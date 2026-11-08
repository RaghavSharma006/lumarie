import { ESPLoader, Transport } from './vendor/esptool-js.js';

const button = document.getElementById('probeBtn');
const status = document.getElementById('probeStatus');
const result = document.getElementById('probeResult');

button.addEventListener('click', async () => {
  if (!window.isSecureContext || !navigator.serial) {
    status.textContent = 'Use desktop Chrome or Edge over HTTPS to test the USB board.';
    return;
  }

  button.disabled = true;
  result.hidden = true;
  status.textContent = 'Choose the board’s USB serial port. The board may restart during identification.';
  let transport;
  try {
    const port = await navigator.serial.requestPort();
    transport = new Transport(port);
    const loader = new ESPLoader({ transport, baudrate: 115200 });
    status.textContent = 'Connecting to the Espressif bootloader…';
    const chip = await loader.main();
    const flashSize = await loader.detectFlashSize();
    const isC3 = /ESP32-C3/i.test(chip);
    result.hidden = false;
    result.textContent = `Chip: ${chip}. Flash: ${flashSize}. ${isC3
      ? 'ESP32-C3 detected. Save these details for firmware compatibility.'
      : 'This is not an ESP32-C3. Do not use C3 firmware on this board.'}`;
    status.textContent = 'Board identification complete. No firmware was erased or written.';
  } catch (error) {
    status.textContent = error.name === 'NotFoundError'
      ? 'No port selected. Check the USB data cable and try again.'
      : `Could not identify the board: ${error.message || String(error)}. If needed, hold BOOT while pressing RESET, then retry.`;
  } finally {
    if (transport) {
      try { await transport.disconnect(); } catch (_) { /* The port may already be closed. */ }
    }
    button.disabled = false;
  }
});
