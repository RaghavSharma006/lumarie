#pragma once
#include <stddef.h>
#include <stdint.h>
struct FactoryIdentity {
  char qr_uri[225];
  char ble_name[20];
};
// Reads unique factory QR and validates same BLE name as ESP32's MAC.
// Never generates a shared/population-wide password or prints the secret.
bool factory_identity_load(FactoryIdentity *out);
