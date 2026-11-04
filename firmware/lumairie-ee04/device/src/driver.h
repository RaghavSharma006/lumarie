#pragma once
// Seeed_GFX reads this header when selecting its compiled ePaper driver.
// ID 509: 7.3 inch 800x480 Spectra 6 (ED2208).
#ifndef BOARD_SCREEN_COMBO
#define BOARD_SCREEN_COMBO 509
#endif
#ifndef USE_XIAO_EPAPER_DISPLAY_BOARD_EE04
#define USE_XIAO_EPAPER_DISPLAY_BOARD_EE04
#endif
#if BOARD_SCREEN_COMBO != 509
#error "LUMAIRIE EE04 diagnostic requires Spectra 6 setup 509 (ED2208)"
#endif
