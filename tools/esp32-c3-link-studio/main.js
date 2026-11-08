import { ESPLoader, Transport } from 'esptool-js';

const el = (id) => document.getElementById(id);
const $connect = el('connect');
const $disconnect = el('disconnect');
const $flash = el('flash');
const $firmware = el('firmware');
const $monitor = el('monitor');
const $ping = el('ping');
const $stop = el('stop-monitor');
let transport = null;
let loader = null;
let detectedChip = '';
let monitorPort = null;
let monitorReader = null;
let monitorRunning = false;
let busy = false;
let received = '';

function log(message, kind = '') {
  const line = document.createElement('div');
  if (kind) line.className = kind;
  line.textContent = `[${new Date().toLocaleTimeString()}] ${String(message)}`;
  el('logs').appendChild(line);
  el('logs').scrollTop = el('logs').scrollHeight;
}
function status(id, message, type = '') {
  el(id + '-status').textContent = message;
  el(id + '-dot').className = 'dot ' + type;
}
function updateButtons() {
  const connected = !!loader;
  $connect.disabled = busy || connected || monitorRunning;
  $disconnect.disabled = busy || !connected;
  $flash.disabled = busy || !connected || !$firmware.files?.length || !detectedChip.toUpperCase().includes('ESP32-C3');
  $monitor.disabled = busy || connected || monitorRunning;
  $ping.disabled = busy || !monitorRunning;
  $stop.disabled = busy || !monitorRunning;
}
function setBusy(value) { busy = value; updateButtons(); }
function friendlyError(error) {
  return error?.message || String(error);
}
const terminal = {
  clean() {},
  writeLine(text) { if (text.trim()) log(text.trim()); },
  write(text) { if (text.trim()) log(text.trim()); }
};

if (!('serial' in navigator) || !window.isSecureContext) {
  status('browser', 'USB serial unsupported here', 'bad');
  log('Open this HTTPS app in desktop Google Chrome or Microsoft Edge.', 'error');
  $connect.disabled = true;
  $monitor.disabled = true;
} else {
  status('browser', 'Web Serial supported', 'active');
  log('Ready. Connect ESP32-C3 with a USB data cable.');
}

async function dropLoader(reset = false) {
  const oldLoader = loader;
  const oldTransport = transport;
  loader = null;
  transport = null;
  detectedChip = '';
  el('chip-detail').textContent = 'Detected chip: —';
  status('device', 'No ESP32 connected');
  try { if (reset && oldLoader) await oldLoader.after('hard_reset'); }
  catch (err) { log(`Reset note: ${friendlyError(err)}`); }
  try { if (oldTransport) await oldTransport.disconnect(); }
  catch (err) { log(`Disconnect note: ${friendlyError(err)}`); }
  updateButtons();
}

$connect.addEventListener('click', async () => {
  if (busy || !navigator.serial) return;
  setBusy(true);
  try {
    // A direct button click is required for the browser port picker.
    const port = await navigator.serial.requestPort();
    transport = new Transport(port, true);
    loader = new ESPLoader({ transport, baudrate: 115200, terminal, debugLogging: false });
    log('Connecting to ROM bootloader…');
    detectedChip = String(await loader.main());
    if (!detectedChip.toUpperCase().includes('ESP32-C3')) {
      log(`Detected ${detectedChip}. Only ESP32-C3 flashing is enabled here.`, 'error');
      await dropLoader(true);
      return;
    }
    status('device', 'ESP32-C3 connected', 'active');
    el('chip-detail').textContent = `Detected chip: ${detectedChip}`;
    log(`PASS: USB ↔ ${detectedChip} ROM bootloader`, 'ok');
  } catch (err) {
    log(`Connection failed: ${friendlyError(err)}`, 'error');
    await dropLoader();
  } finally { setBusy(false); }
});

$disconnect.addEventListener('click', async () => {
  setBusy(true);
  await dropLoader(true);
  setBusy(false);
  log('Device disconnected.');
});

$firmware.addEventListener('change', () => {
  const file = $firmware.files?.[0];
  el('selected-file').textContent = file ? `${file.name} · ${(file.size / 1024).toFixed(1)} KB` : 'Choose a firmware .bin';
  updateButtons();
});

$flash.addEventListener('click', async () => {
  if (busy || !loader || !detectedChip.toUpperCase().includes('ESP32-C3')) return;
  const file = $firmware.files?.[0];
  if (!file || !file.name.toLowerCase().endsWith('.bin') || !file.size || file.size > 16 * 1024 * 1024) {
    log('Choose a nonempty .bin firmware file no larger than 16 MB.', 'error');
    return;
  }
  const address = Number(el('flash-offset').value);
  if (!confirm(`Flash ${file.name} to ESP32-C3 at 0x${address.toString(16)}?\n\nThis will overwrite existing firmware in those flash sectors. Continue only if the image is correct for this board.`)) return;
  setBusy(true);
  el('progressbox').classList.add('show');
  el('progress').style.width = '0%';
  el('progresslabel').textContent = 'Starting transfer…';
  try {
    const data = new Uint8Array(await file.arrayBuffer());
    log(`Flashing ${file.name} at 0x${address.toString(16)} · ${data.length} bytes…`);
    await loader.writeFlash({
      fileArray: [{ data, address }],
      flashMode: 'dio', flashFreq: '40m', flashSize: 'detect',
      eraseAll: false, compress: true,
      reportProgress: (_index, written, total) => {
        const pct = total ? Math.min(100, Math.round(100 * written / total)) : 0;
        el('progress').style.width = `${pct}%`;
        el('progresslabel').textContent = `Flashing… ${pct}% (${written}/${total} bytes)`;
      }
    });
    el('progress').style.width = '100%';
    el('progresslabel').textContent = 'Flashing complete. Reconnect serial monitor to test PING.';
    log('PASS: Firmware written. Resetting board.', 'ok');
    await dropLoader(true);
  } catch (err) {
    el('progresslabel').textContent = 'Flash failed—see log.';
    log(`Flash failed: ${friendlyError(err)}`, 'error');
    await dropLoader();
  } finally { setBusy(false); }
});

// Serial monitor runs on a fresh Web Serial port, not an active ROM-loader transport.
async function readMonitor(port) {
  const decoder = new TextDecoder();
  try {
    while (monitorRunning && port.readable) {
      const reader = port.readable.getReader();
      monitorReader = reader;
      try {
        while (monitorRunning) {
          const { value, done } = await reader.read();
          if (done) break;
          if (!value?.length) continue;
          const chunk = decoder.decode(value, { stream: true });
          received = (received + chunk).slice(-4096);
          const output = chunk.trim();
          if (output) log('RX: ' + output, received.includes('PONG LUMAIRIE ESP32-C3') ? 'ok' : '');
          if (received.includes('PONG LUMAIRIE ESP32-C3')) {
            status('ping', 'PONG received · two-way link verified', 'active');
          }
        }
      } finally { reader.releaseLock(); monitorReader = null; }
      break;
    }
  } catch (err) { if (monitorRunning) log(`Monitor read stopped: ${friendlyError(err)}`, 'error'); }
  if (monitorRunning) await stopMonitor();
}

async function stopMonitor() {
  if (!monitorPort) return;
  monitorRunning = false;
  try { if (monitorReader) await monitorReader.cancel(); }
  catch (_) {}
  const p = monitorPort;
  monitorPort = null;
  try { await p.close(); }
  catch (err) { log(`Port close note: ${friendlyError(err)}`); }
  el('monitor-status').textContent = 'Serial monitor is closed';
  updateButtons();
}

$monitor.addEventListener('click', async () => {
  if (!navigator.serial || busy || loader || monitorRunning) return;
  setBusy(true);
  try {
    const port = await navigator.serial.requestPort();
    await port.open({ baudRate: 115200 });
    monitorPort = port;
    monitorRunning = true;
    received = '';
    el('monitor-status').textContent = 'Serial monitor active · 115200 baud';
    log('Serial monitor open. Send PING or reset ESP32 to see READY.', 'ok');
    void readMonitor(port);
  } catch (err) { log(`Monitor open failed: ${friendlyError(err)}`, 'error'); await stopMonitor(); }
  finally { setBusy(false); }
});

$ping.addEventListener('click', async () => {
  if (!monitorPort?.writable || !monitorRunning) return;
  try {
    received = '';
    status('ping', 'Waiting for PONG…');
    const writer = monitorPort.writable.getWriter();
    try { await writer.write(new TextEncoder().encode('PING\n')); }
    finally { writer.releaseLock(); }
    log('TX: PING', 'ok');
  } catch (err) { log(`PING send failed: ${friendlyError(err)}`, 'error'); }
});
$stop.addEventListener('click', async () => { await stopMonitor(); log('Serial monitor closed.'); });
el('clear').addEventListener('click', () => { el('logs').replaceChildren(); log('Log cleared.'); });
updateButtons();
