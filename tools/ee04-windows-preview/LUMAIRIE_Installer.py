"""Backup-first USB firmware installer for XIAO ESP32-S3 Plus (Windows).
Developer preview only. No flash erase or eFuse writes. Requires Python 3.11+.
Tested statically; actual Windows USB flow has NOT been hardware tested.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime

ROOT = Path(__file__).resolve().parent
SIZE = 16 * 1024 * 1024
IMAGES = ("bootloader.bin", "partitions.bin", "firmware.bin")
OFFSETS = ("0x0", "0x8000", "0x10000")


def run(args):
    print("\n>", " ".join(str(x) for x in args))
    subprocess.run(list(map(str, args)), check=True)


def capture(args):
    result = subprocess.run(list(map(str, args)), check=True,
                            capture_output=True, text=True)
    print(result.stdout)
    return result.stdout + result.stderr


def esptool(port, *args):
    return [sys.executable, "-m", "esptool", "--chip", "esp32s3",
            "--port", port, "--baud", "115200", *args]


def verify_images():
    manifest = ROOT / "SHA256-FLASH-FILES.txt"
    if not manifest.is_file():
        raise ValueError("No firmware checksum manifest; stop")
    hashes = {}
    for line in manifest.read_text(encoding="ascii").splitlines():
        parts = line.split()
        if len(parts) != 2 or not re.fullmatch("[0-9a-f]{64}", parts[0]) or parts[1] in hashes:
            raise ValueError("Invalid checksum manifest; stop")
        hashes[parts[1]] = parts[0]
    if set(hashes) != set(IMAGES):
        raise ValueError("Missing or unexpected firmware image; stop")
    for name in IMAGES:
        image = ROOT / name
        if not image.exists():
            raise ValueError(f"Missing {name}; stop")
        with image.open("rb") as source:
            if hashlib.file_digest(source, "sha256").hexdigest() != hashes[name]:
                raise ValueError(f"Checksum mismatch: {name}; stop")
    for image in (IMAGES[0], IMAGES[2]):
        if (ROOT / image).open("rb").read(1) != b"\xe9":
            raise ValueError(f"ESP image header invalid: {image}")
    parts = (ROOT / "partitions.bin").read_bytes()
    table = {}
    for pos in range(0, len(parts), 32):
        entry = parts[pos:pos + 32]
        if len(entry) != 32 or entry[:2] != bytes.fromhex("aa50"):
            break
        name = entry[12:28].split(bytes([0]))[0].decode("ascii")
        offset = int.from_bytes(entry[4:8], "little")
        count = int.from_bytes(entry[8:12], "little")
        if offset + count > SIZE:
            raise ValueError("Partition goes past 16 MB flash")
        table[name] = (offset, count)
    if table.get("app0", (0, 0))[0] != 0x10000 or table.get("nvs", (0, 0))[0] != 0x9000:
        raise ValueError("Unexpected partition map; stop")
    if (ROOT / "firmware.bin").stat().st_size > table["app0"][1]:
        raise ValueError("Firmware larger than app partition")


def select_port():
    from serial.tools import list_ports
    ports = list(list_ports.comports())
    print("\nAvailable USB serial ports:")
    for p in ports:
        print(f"  {p.device}: {p.description}")
    port = input("Enter the ESP32-S3 port (example COM5): ").strip().upper()
    if not re.fullmatch(r"COM[1-9][0-9]{0,3}", port):
        raise ValueError("Invalid COM port")
    return port


def inspect(port, backup_dir):
    output = capture(esptool(port, "flash-id"))
    if not re.search("ESP32[- ]S3", output, re.I):
        raise ValueError("ESP32-S3 not verified; refusing to flash")
    if not re.search(r"Detected flash size:\s*16\s*(?:MB|MiB)", output, re.I):
        raise ValueError("16 MB flash not verified; refusing to flash")
    summary = backup_dir / "eFuses.json"
    run([sys.executable, "-m", "espefuse", "--chip", "esp32s3",
         "--port", port, "summary", "--format", "json",
         "--file", str(summary)])
    data = json.loads(summary.read_text(encoding="utf-8"))
    for name in ("SECURE_BOOT_EN", "ENABLE_SECURITY_DOWNLOAD",
                 "DIS_DOWNLOAD_MODE", "SPI_BOOT_CRYPT_CNT"):
        item = data.get(name)
        if not isinstance(item, dict):
            raise ValueError(f"Security status {name} unknown; refusing to flash")
        value = item.get("raw_value")
        if not isinstance(value, str) or not re.fullmatch("0x[0-9a-fA-F]+", value):
            raise ValueError(f"Could not interpret {name}; refusing to flash")
        if int(value, 16):
            raise ValueError(f"Security {name} enabled; refusing plaintext flash")


def main():
    print("LUMAIRIE EE04 — Windows USB photo firmware installer")
    print("DEVELOPER PREVIEW: physical panel/BLE/Wi-Fi behavior not yet verified.")
    print("No 'erase_flash' is used. Writing bootloader and partitions can still")
    print("invalidate existing device firmware, NVS and stored configuration.")
    print("Power OFF before checking EE04 50 PIN jumper and ribbon cable.")
    print("Only use ESP32-S3 Plus, 16 MB, 7.3-inch ED2208 Spectra 6.")
    verify_images()
    try:
        import esptool
        import espefuse
        import serial
    except ImportError:
        print("Installing official Espressif USB tools...")
        run([sys.executable, "-m", "pip", "install", "--user",
             "esptool==5.1.2"])
    port = select_port()
    backup_dir = ROOT / "Backups" / datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir.mkdir(parents=True, exist_ok=False)
    inspect(port, backup_dir)
    out = backup_dir / "FULL-16MB-BACKUP.bin"
    print("Backing up the COMPLETE 16 MB chip before any writes...")
    run(esptool(port, "read-flash", "0x0", hex(SIZE), str(out)))
    if out.stat().st_size != SIZE:
        raise ValueError("Incomplete flash backup; aborting")
    with out.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    (backup_dir / "backup.sha256").write_text(digest + "  FULL-16MB-BACKUP.bin\n")
    print(f"BACKUP VERIFIED at {out}. Keep it private (contains credentials).")
    print("WARNING: the next step overwrites bootloader/partition/app sectors.")
    if input("To install, type exactly FLASH (otherwise no changes): ").strip() != "FLASH":
        print("Cancelled. Backup remains on disk. No firmware was written.")
        return
    inspect(port, backup_dir)
    verify_images()
    run(esptool(port, "write-flash", "--flash-mode", "keep",
                "--flash-size", "keep",
                *[value for pair in zip(OFFSETS,
                   [str(ROOT / name) for name in IMAGES]) for value in pair]))
    print("Flashing command completed. Reset the board and TEST it physically.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"STOPPED: {error}")
        sys.exit(1)
