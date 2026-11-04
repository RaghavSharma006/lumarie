#include "identity.h"
#include <string.h>
#include <stdio.h>
#include "esp_mac.h"
#include "nvs.h"
static bool valid_qr(const char *uri, char *name) {
  static constexpr char prefix[] = "lumairie://pair?id=";
  if (strncmp(uri, prefix, sizeof(prefix)-1) || strlen(uri)>200) return false;
  const char *id = uri + sizeof(prefix)-1;
  const char *name_param = strstr(id,"&name=");
  if (!name_param) return false;
  size_t n = name_param-id;
  if (n<8 || n>64) return false;
  for (size_t i=0;i<n;++i) {
    char c=id[i];
    if (!((c>='A'&&c<='Z')||(c>='a'&&c<='z')||
          (c>='0'&&c<='9')||c=='_'||c=='-')) return false;
  }
  const char *value = name_param + 6;
  const char *end=strchr(value,'&');
  if (!end || end-value!=14 || strncmp(value,"LUMAIRE-",8)) return false;
  for(int i=8;i<14;i++) {
    char c=value[i];
    if(!((c>='0'&&c<='9')||(c>='A'&&c<='F')||
         (c>='a'&&c<='f'))) return false;
  }
  memcpy(name,value,14);
  name[14]=0;
  if(strncmp(end,"&user=",6)) return false;
  const char *user=end+6;
  const char *secret=strstr(user,"&secret=");
  if(!secret || secret-user<1 || secret-user>64) return false;
  secret+=8;
  size_t m=strlen(secret);
  if(m<16 || m>128 || strchr(secret,'&')) return false;
  uint8_t mac[6];
  if(esp_read_mac(mac,ESP_MAC_BT)!=ESP_OK) return false;
  char expected[20];
  snprintf(expected,sizeof(expected),"LUMAIRE-%02X%02X%02X",mac[3],mac[4],mac[5]);
  return strcmp(expected,name)==0;
}
extern bool factory_create_identity();
bool factory_identity_load(FactoryIdentity *out) {
  if(!out) return false;
  memset(out,0,sizeof(*out));
  nvs_handle_t nvs;
  esp_err_t opened = nvs_open("factory", NVS_READONLY, &nvs);
  bool fresh = opened == ESP_ERR_NVS_NOT_FOUND;
  esp_err_t qr_status = opened;
  if (opened == ESP_OK) {
    size_t len = sizeof(out->qr_uri);
    qr_status = nvs_get_str(nvs, "qr_uri", out->qr_uri, &len);
    if (qr_status == ESP_ERR_NVS_NOT_FOUND) {
      size_t bytes = 0;
      bool has_salt = nvs_get_blob(nvs, "srp_salt", nullptr, &bytes) == ESP_OK;
      bool has_verifier = nvs_get_blob(nvs, "srp_verifier", nullptr, &bytes) == ESP_OK;
      fresh = !has_salt && !has_verifier;
    }
    nvs_close(nvs);
  }
  // Never rotate or overwrite a partly configured factory record.
  if (fresh && factory_create_identity()) {
    opened = nvs_open("factory", NVS_READONLY, &nvs);
    if (opened == ESP_OK) {
      size_t length = sizeof(out->qr_uri);
      qr_status = nvs_get_str(nvs, "qr_uri", out->qr_uri, &length);
      nvs_close(nvs);
    }
  }
  bool ok = qr_status == ESP_OK && valid_qr(out->qr_uri, out->ble_name);
  if (!ok) memset(out, 0, sizeof(*out));
  return ok;
}
