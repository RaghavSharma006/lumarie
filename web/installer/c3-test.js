import { ESPLoader, Transport } from './vendor/esptool-js.js';

const probeBtn = document.getElementById('probeBtn');
const probeStatus = document.getElementById('probeStatus');
const probeResult = document.getElementById('probeResult');
const flashBtn = document.getElementById('flashBtn');
const flashAck = document.getElementById('flashAck');
const flashStatus = document.getElementById('flashStatus');
const progress = document.getElementById('flashProgress');

// ESP-IDF v5.5.6 ESP32-C3 build with mock display and 8 MB partitions.
const images = [
  ['bootloader.bin', 0x0, '04d599cf6d7f3edc6d1f31d8d76624a06b5061ad010a415a29e2e4169d420ee8'],
  ['partition-table.bin', 0x8000, '6432a29e7ff4239c439d04813f3d4b568a9ba8847248cfad9f2d18d7e80e79d1'],
  ['ota_data_initial.bin', 0xf000, '7d2c7ac4888bfd75cd5f56e8d61f69595121183afc81556c876732fd3782c62f'],
  ['lumairie_frame.bin', 0x20000, '8be688e374af935ffe54cf54a9ae54c2ddbc49a14ca52d0c99a83bf46e11ae13'],
];

flashAck.addEventListener('change', () => { flashBtn.disabled = !flashAck.checked; });

async function connect() {
  if (!window.isSecureContext || !navigator.serial) throw new Error('Use desktop Chrome or Edge over HTTPS.');
  const port = await navigator.serial.requestPort();
  const transport = new Transport(port);
  try {
    const loader = new ESPLoader({ transport, baudrate: 115200 });
    const chip = await loader.main();
    const flashSize = await loader.detectFlashSize();
    return { loader, transport, chip, flashSize };
  } catch (error) {
    await transport.disconnect().catch(() => {});
    throw error;
  }
}

function bytesOf(size) {
  const m = /^([0-9]+)\s*(MB|KB)$/i.exec(size.trim());
  return m ? Number(m[1]) * (m[2].toUpperCase() === 'MB' ? 1048576 : 1024) : 0;
}

async function hash(data) {
  const digest = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
}

async function getImages() {
  const files = [];
  for (const [name, address, expected] of images) {
    const response = await fetch(`./firmware/esp32c3-mock/${name}`, { cache: 'no-store' });
    if (!response.ok) throw new Error(`Firmware download failed: ${name}.`);
    const data = new Uint8Array(await response.arrayBuffer());
    if (await hash(data) !== expected) throw new Error(`Firmware integrity check failed: ${name}.`);
    files.push({ name, address, data });
  }
  return files;
}

async function readRegion(loader, address, size, onProgress) {
  const chunks = [];
  let read = 0;
  while (read < size) {
    const length = Math.min(65536, size - read);
    chunks.push(await loader.readFlash(address + read, length));
    read += length;
    onProgress(read, size);
  }
  return new Blob(chunks, { type: 'application/octet-stream' });
}

function download(blob) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `lumairie-c3-full-backup-${new Date().toISOString().replace(/[:.]/g, '-')}.bin`;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}

probeBtn.addEventListener('click', async () => {
  probeBtn.disabled = true;
  probeResult.hidden = true;
  probeStatus.textContent = 'Choose the USB port. The board may restart.';
  let connection;
  try {
    connection = await connect();
    probeResult.hidden = false;
    probeResult.textContent = `Chip: ${connection.chip}. Flash: ${connection.flashSize}. ${/ESP32-C3/i.test(connection.chip) ? 'ESP32-C3 detected.' : 'Do not install C3 firmware on this chip.'}`;
    probeStatus.textContent = 'Board identified. Flash was not changed.';
  } catch (error) {
    probeStatus.textContent = error.name === 'NotFoundError' ? 'No port selected.' : `Board test failed: ${error.message || error}`;
  } finally {
    if (connection) await connection.transport.disconnect().catch(() => {});
    probeBtn.disabled = false;
  }
});

flashBtn.addEventListener('click', async () => {
  if (!flashAck.checked) return;
  flashBtn.disabled = probeBtn.disabled = true;
  progress.hidden = false;
  progress.value = 0;
  let connection;
  try {
    flashStatus.textContent = 'Choose the ESP32-C3 USB port.';
    connection = await connect();
    const { loader, chip, flashSize } = connection;
    if (!/ESP32-C3/i.test(chip)) throw new Error(`Detected ${chip}; only ESP32-C3 is supported.`);
    const capacity = bytesOf(flashSize);
    if (capacity < 8 * 1048576) throw new Error(`Detected ${flashSize}; this image needs at least 8 MB flash.`);
    flashStatus.textContent = 'Checking firmware integrity…';
    const files = await getImages();
    if (files.some(f => f.address + f.data.length > capacity)) throw new Error('Firmware exceeds flash capacity.');

    flashStatus.textContent = 'Reading full factory backup. This can take several minutes…';
    const backup = await readRegion(loader, 0, capacity, (read, total) => { progress.value = Math.round(35 * read / total); });
    download(backup);
    if (!window.confirm('Save the downloaded full-flash backup. Install mock-display firmware now? It will not connect to the app or refresh the panel.')) {
      flashStatus.textContent = 'Stopped after backup. No flash was written.';
      return;
    }

    flashStatus.textContent = 'Writing C3 firmware. Keep USB connected…';
    await loader.writeFlash({
      fileArray: files.map(({ data, address }) => ({ data, address })),
      flashMode: 'keep', flashFreq: 'keep', flashSize: 'keep',
      eraseAll: false, compress: true,
      reportProgress: (i, written, total) => { progress.value = 35 + Math.round(45 * (i + written / total) / files.length); },
    });
    flashStatus.textContent = 'Reading back each firmware image…';
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const readback = await readRegion(loader, file.address, file.data.length, (read, total) => {
        progress.value = 80 + Math.round(20 * (i + read / total) / files.length);
      });
      if (await hash(await readback.arrayBuffer()) !== images[i][2]) throw new Error(`Readback mismatch: ${file.name}. Restore the downloaded backup.`);
    }
    await loader.after('hard_reset');
    progress.value = 100;
    flashStatus.textContent = 'C3 candidate flashed and verified. This build has no app pairing or panel output.';
  } catch (error) {
    flashStatus.textContent = error.name === 'NotFoundError' ? 'No port selected. Nothing was flashed.' : `Flash stopped: ${error.message || error}`;
  } finally {
    if (connection) await connection.transport.disconnect().catch(() => {});
    flashBtn.disabled = !flashAck.checked;
    probeBtn.disabled = false;
  }
});
