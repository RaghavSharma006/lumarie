#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "esp_err.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_app_desc.h"
#include "esp_partition.h"
#include "esp_sleep.h"
#include "esp_timer.h"
#include "esp_mac.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"
#include "nvs.h"
#include "protocomm.h"
#include "protocomm_ble.h"
#include "protocomm_security2.h"

// The BLE service exposes only authenticated protocomm endpoints.
// No panel GPIO, waveform, voltage or controller command is assumed here.
static const char *TAG = "lumairie";
static const uint32_t MAX_FRAME_BYTES = 512 * 1024;
static const uint16_t MAX_CHUNK_BYTES = 256;
static const uint32_t PROTOCOL_VERSION = 1;
static const uint8_t SERVICE_UUID[16] = {0x2a,0x3f,0x17,0xc9,0x72,0x85,0x40,0x42,0x8d,0x55,0x30,0x1a,0x40,0x61,0x19,0x10};
static const esp_partition_t *staging_partition;
static uint32_t expected_length, expected_crc, next_offset;
static bool receiving, verified;
static esp_ota_handle_t ota_handle;
static const esp_partition_t *ota_partition;
static uint32_t ota_length, ota_received;
static bool ota_active;
static int64_t last_activity;

typedef enum { POWER_AWAKE, POWER_ADVERTISING, POWER_TRANSFERRING, POWER_REFRESHING, POWER_SLEEPING, POWER_ERROR } power_state_t;
static power_state_t power_state = POWER_AWAKE;

static uint32_t read32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static void write32(uint8_t *p, uint32_t v) {
    for (int i = 0; i < 4; i++) p[i] = (uint8_t)(v >> (i * 8));
}
static uint32_t crc_step(uint32_t crc, const uint8_t *data, size_t length) {
    for (size_t i = 0; i < length; i++) {
        crc ^= data[i];
        for (int bit = 0; bit < 8; bit++) crc = (crc & 1) ? (crc >> 1) ^ 0xEDB88320u : crc >> 1;
    }
    return crc;
}

static bool newer_version(const char *candidate, const char *current) {
    unsigned a[3], b[3];
    if (sscanf(candidate, "%u.%u.%u", &a[0], &a[1], &a[2]) != 3 ||
        sscanf(current, "%u.%u.%u", &b[0], &b[1], &b[2]) != 3) return false;
    for (int i = 0; i < 3; i++) {
        if (a[i] > b[i]) return true;
        if (a[i] < b[i]) return false;
    }
    return false;
}

static void reboot_callback(void *arg) { (void)arg; esp_restart(); }

static esp_err_t schedule_reboot(void) {
    esp_timer_handle_t timer;
    const esp_timer_create_args_t config = { .callback = reboot_callback, .name = "ota_reboot" };
    esp_err_t err = esp_timer_create(&config, &timer);
    if (err == ESP_OK) err = esp_timer_start_once(timer, 1500000);
    return err;
}

static esp_err_t mock_display_refresh(void) {
    // A real adapter must power the verified driver, read only committed
    // staging bytes, wait for BUSY/refresh completion, then power it down.
    // Until its documentation exists this reports no physical display.
    ESP_LOGW(TAG, "mock display received verified frame; no physical refresh");
    return ESP_ERR_NOT_SUPPORTED;
}

static esp_err_t handle_frame(uint32_t session_id, const uint8_t *in, ssize_t length,
                              uint8_t **out, ssize_t *out_length, void *private_data) {
    (void)session_id; (void)private_data;
    if (!in || length < 1 || !out || !out_length) return ESP_ERR_INVALID_ARG;
    if (length == 4 && memcmp(in, "PING", 4) == 0) {
        static const char reply[] = "{\"protocol\":1}";
        *out = malloc(sizeof(reply) - 1);
        if (!*out) return ESP_ERR_NO_MEM;
        memcpy(*out, reply, sizeof(reply) - 1);
        *out_length = sizeof(reply) - 1;
        last_activity = esp_timer_get_time();
        return ESP_OK;
    }
    uint8_t *response = malloc(9);
    if (!response) return ESP_ERR_NO_MEM;
    memset(response, 0, 9);
    response[0] = in[0];
    esp_err_t status = ESP_ERR_INVALID_ARG;
    switch (in[0]) {
        case 0x01: // CAPABILITIES
            if (length == 1) { write32(response + 1, PROTOCOL_VERSION); write32(response + 5, MAX_CHUNK_BYTES); status = ESP_OK; }
            break;
        case 0x02: { // BEGIN: version, width, height, byte length, CRC32
            if (length != 17 || !staging_partition) break;
            uint32_t version = read32(in + 1);
            uint16_t width = (uint16_t)(in[5] | (in[6] << 8));
            uint16_t height = (uint16_t)(in[7] | (in[8] << 8));
            uint32_t total = read32(in + 9);
            uint32_t crc = read32(in + 13);
            if (version != PROTOCOL_VERSION || !((width == 800 && height == 480) || (width == 480 && height == 800)) ||
                total != ((uint32_t)width * height + 1) / 2 || total > MAX_FRAME_BYTES || total > staging_partition->size) break;
            receiving = false; verified = false; next_offset = 0;
            status = esp_partition_erase_range(staging_partition, 0, staging_partition->size);
            if (status == ESP_OK) { expected_length = total; expected_crc = crc; receiving = true; power_state = POWER_TRANSFERRING; }
            break;
        }
        case 0x03: { // CHUNK: offset, up to 256 bytes. Reply next expected offset.
            if (!receiving || length < 6 || length > 5 + MAX_CHUNK_BYTES) break;
            uint32_t offset = read32(in + 1);
            uint32_t count = (uint32_t)length - 5;
            if (offset == next_offset && count <= expected_length - next_offset) {
                status = esp_partition_write(staging_partition, offset, in + 5, count);
                if (status == ESP_OK) next_offset += count;
            } else if (offset < next_offset && offset + count <= next_offset) {
                // Idempotent acknowledgement for a lost ACK. A mismatched
                // duplicate must still fail, preventing ambiguous resume.
                uint8_t previous[MAX_CHUNK_BYTES];
                if (esp_partition_read(staging_partition, offset, previous, count) == ESP_OK && memcmp(previous, in + 5, count) == 0) status = ESP_OK;
            }
            write32(response + 1, next_offset);
            break;
        }
        case 0x04: { // END: verify complete staged image before display call.
            if (!receiving || length != 1 || next_offset != expected_length) break;
            uint8_t block[256]; uint32_t crc = 0xFFFFFFFFu;
            status = ESP_OK;
            for (uint32_t offset = 0; offset < expected_length; offset += sizeof(block)) {
                size_t count = expected_length - offset < sizeof(block) ? expected_length - offset : sizeof(block);
                status = esp_partition_read(staging_partition, offset, block, count);
                if (status != ESP_OK) break;
                crc = crc_step(crc, block, count);
            }
            receiving = false;
            if (status != ESP_OK || (crc ^ 0xFFFFFFFFu) != expected_crc) { status = ESP_ERR_INVALID_CRC; break; }
            verified = true;
            power_state = POWER_REFRESHING;
            status = mock_display_refresh();
            power_state = POWER_AWAKE;
            response[5] = status == ESP_OK ? 2 : 1; // 1=DELIVERED, 2=DISPLAYED
            status = ESP_OK;
            break;
        }
        case 0x05: // ABORT
            receiving = false; verified = false; next_offset = 0;
            power_state = POWER_AWAKE; status = ESP_OK; break;
        case 0x10: { // OTA_BEGIN: signed app image length
#if defined(CONFIG_SECURE_BOOT) || (defined(CONFIG_SECURE_SIGNED_APPS_NO_SECURE_BOOT) && defined(CONFIG_SECURE_SIGNED_ON_UPDATE_NO_SECURE_BOOT))
            if (length != 5 || receiving || ota_active) break;
            ota_partition = esp_ota_get_next_update_partition(NULL);
            ota_length = read32(in + 1);
            if (!ota_partition || ota_length < 4096 || ota_length > ota_partition->size) break;
            status = esp_ota_begin(ota_partition, ota_length, &ota_handle);
            if (status == ESP_OK) { ota_received = 0; ota_active = true; power_state = POWER_TRANSFERRING; }
#endif
            break;
        }
        case 0x11: { // OTA_CHUNK: offset, up to 256 bytes
            if (!ota_active || length < 6 || length > 5 + MAX_CHUNK_BYTES) break;
            uint32_t offset = read32(in + 1);
            uint32_t count = (uint32_t)length - 5;
            if (offset != ota_received || count > ota_length - ota_received) break;
            status = esp_ota_write(ota_handle, in + 5, count);
            if (status == ESP_OK) ota_received += count;
            write32(response + 1, ota_received);
            break;
        }
        case 0x12: { // OTA_END: signature/image verification, version check, A/B switch
            if (!ota_active || length != 1 || ota_received != ota_length) break;
            ota_active = false;
            status = esp_ota_end(ota_handle);
            power_state = POWER_AWAKE;
            if (status != ESP_OK) break;
            esp_app_desc_t candidate;
            const esp_app_desc_t *current = esp_app_get_description();
            status = esp_ota_get_partition_description(ota_partition, &candidate);
            if (status != ESP_OK) break;
            if (!newer_version(candidate.version, current->version) || candidate.secure_version < current->secure_version) {
                status = ESP_ERR_INVALID_VERSION; break;
            }
            status = esp_ota_set_boot_partition(ota_partition);
            if (status == ESP_OK) status = schedule_reboot();
            break;
        }
        case 0x13: // OTA_ABORT
            if (ota_active) esp_ota_abort(ota_handle);
            ota_active = false; ota_received = 0; power_state = POWER_AWAKE; status = ESP_OK; break;
        default: break;
    }
    response[8] = status == ESP_OK ? 0 : 1;
    *out = response; *out_length = 9;
    last_activity = esp_timer_get_time();
    return ESP_OK;
}

static bool load_factory_credentials(uint8_t **salt, size_t *salt_size, uint8_t **verifier, size_t *verifier_size) {
    nvs_handle_t nvs;
    if (nvs_open("factory", NVS_READONLY, &nvs) != ESP_OK) return false;
    bool okay = nvs_get_blob(nvs, "srp_salt", NULL, salt_size) == ESP_OK && *salt_size >= 16 && *salt_size <= 64 &&
                nvs_get_blob(nvs, "srp_verifier", NULL, verifier_size) == ESP_OK && *verifier_size >= 128 && *verifier_size <= 512;
    if (okay) {
        *salt = malloc(*salt_size); *verifier = malloc(*verifier_size);
        okay = *salt && *verifier && nvs_get_blob(nvs, "srp_salt", *salt, salt_size) == ESP_OK &&
               nvs_get_blob(nvs, "srp_verifier", *verifier, verifier_size) == ESP_OK;
    }
    nvs_close(nvs);
    if (!okay) { free(*salt); free(*verifier); *salt = NULL; *verifier = NULL; }
    return okay;
}

static bool physical_pairing_authorized(void) {
#if CONFIG_LUMAIRIE_PAIR_GPIO >= 0
    // The chosen pin must first be validated against the actual board circuit.
    gpio_config_t config = { .pin_bit_mask = 1ULL << CONFIG_LUMAIRIE_PAIR_GPIO, .mode = GPIO_MODE_INPUT,
                             .pull_up_en = GPIO_PULLUP_ENABLE, .pull_down_en = GPIO_PULLDOWN_DISABLE };
    if (gpio_config(&config) != ESP_OK) return false;
    int64_t start = esp_timer_get_time();
    while (esp_timer_get_time() - start < 3000000) {
        if (gpio_get_level(CONFIG_LUMAIRIE_PAIR_GPIO) != 0) return false;
        vTaskDelay(pdMS_TO_TICKS(50));
    }
    return true;
#else
    return false;
#endif
}

static void enter_sleep_if_wake_is_configured(void) {
#if CONFIG_LUMAIRIE_PAIR_GPIO >= 0
    gpio_num_t pin = (gpio_num_t)CONFIG_LUMAIRIE_PAIR_GPIO;
    if (!esp_sleep_is_valid_wakeup_gpio(pin)) {
        ESP_LOGE(TAG, "configured button cannot wake from deep sleep; staying awake");
        return;
    }
    for (int attempt = 0; attempt < 100 && gpio_get_level(pin) == 0; attempt++) {
        vTaskDelay(pdMS_TO_TICKS(50));
    }
    if (gpio_get_level(pin) == 0) {
        ESP_LOGW(TAG, "button held; avoiding immediate deep-sleep wake loop");
        return;
    }
    if (esp_deep_sleep_enable_gpio_wakeup(1ULL << CONFIG_LUMAIRIE_PAIR_GPIO, ESP_GPIO_WAKEUP_GPIO_LOW) != ESP_OK) {
        ESP_LOGE(TAG, "could not enable GPIO wake; staying awake");
        return;
    }
    power_state = POWER_SLEEPING;
    esp_deep_sleep_start();
#else
    ESP_LOGW(TAG, "wake GPIO unconfigured; remaining awake until board integration");
#endif
}

void app_main(void) {
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        // Do not silently erase factory credentials on production devices.
        ESP_LOGE(TAG, "NVS requires service; refusing automatic erase"); return;
    }
    ESP_ERROR_CHECK(err);
    staging_partition = esp_partition_find_first(ESP_PARTITION_TYPE_DATA, 0x40, "frame_tmp");
    if (!staging_partition) { ESP_LOGE(TAG, "staging partition missing"); return; }
    uint8_t *salt = NULL, *verifier = NULL; size_t salt_size = 0, verifier_size = 0;
    if (!load_factory_credentials(&salt, &salt_size, &verifier, &verifier_size)) {
        ESP_LOGE(TAG, "factory security material absent; BLE disabled"); return;
    }
    esp_ota_img_states_t ota_state;
    const esp_partition_t *running = esp_ota_get_running_partition();
    if (esp_ota_get_state_partition(running, &ota_state) == ESP_OK && ota_state == ESP_OTA_IMG_PENDING_VERIFY) {
        // Validate core boot dependencies before accepting the new slot.
        // Panel self-test needs the verified board driver and remains pending.
        ESP_ERROR_CHECK(esp_ota_mark_app_valid_cancel_rollback());
    }
    if (!physical_pairing_authorized()) {
        ESP_LOGI(TAG, "physical pairing window closed; BLE disabled");
        free(salt); free(verifier);
        enter_sleep_if_wake_is_configured();
        return;
    }
    protocomm_t *pc = protocomm_new();
    if (!pc) goto fail;
    protocomm_ble_name_uuid_t endpoints[] = {{"security_endpoint", 0xFF51}, {"frame", 0xFF52}};
    protocomm_ble_config_t ble = {0};
    memcpy(ble.service_uuid, SERVICE_UUID, sizeof(SERVICE_UUID));
    uint8_t mac[6];
    if (esp_read_mac(mac, ESP_MAC_BT) != ESP_OK) goto fail_pc;
    snprintf(ble.device_name, sizeof(ble.device_name), "LUMAIRE-%02X%02X%02X", mac[3], mac[4], mac[5]);
    ble.nu_lookup = endpoints; ble.nu_lookup_count = 2;
    if (protocomm_ble_start(pc, &ble) != ESP_OK) goto fail_pc;
    protocomm_security2_params_t sec = {.salt = (const char *)salt, .salt_len = salt_size,
                                         .verifier = (const char *)verifier, .verifier_len = verifier_size};
    if (protocomm_set_security(pc, "security_endpoint", &protocomm_security2, &sec) != ESP_OK) goto fail_ble;
    if (protocomm_add_endpoint(pc, "frame", handle_frame, NULL) != ESP_OK) goto fail_security;
    power_state = POWER_ADVERTISING;
    last_activity = esp_timer_get_time();
    while (esp_timer_get_time() - last_activity < (int64_t)CONFIG_LUMAIRIE_ADVERTISE_SECONDS * 1000000LL) {
        vTaskDelay(pdMS_TO_TICKS(250));
    }
    protocomm_remove_endpoint(pc, "frame");
fail_security:
    protocomm_unset_security(pc, "security_endpoint");
fail_ble:
    protocomm_ble_stop(pc);
fail_pc:
    protocomm_delete(pc);
fail:
    free(salt); free(verifier);
    ESP_LOGI(TAG, "BLE window closed; sleeping if a verified wake input exists");
    enter_sleep_if_wake_is_configured();
}
