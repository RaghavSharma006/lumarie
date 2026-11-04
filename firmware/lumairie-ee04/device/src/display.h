#pragma once
#include "provisioning.h"
void display_init();
void display_state(FrameState state, const char *device_name, const char *qr_uri);

// Decode the existing high-nibble-first six-color packed format, and wait
// for the ED2208 full hardware refresh before reporting DISPLAYED.
bool display_photo(const uint8_t *pixels, uint16_t width, uint16_t height);
