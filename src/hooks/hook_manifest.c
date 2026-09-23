// Manifest request code via opensteamtool API
#include "hooks.h"
#include "../config/config.h"
#include "../util/log.h"
#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CFNetwork/CFNetwork.h>

#define MANIFEST_API_FMT "http://gmrc.wudrm.com/manifest/%llu"
#define MANIFEST_UA      "OpenSteamTool/1.0"

static void *orig_GetManifestRequestCode = NULL;

typedef uint32_t (*fn_GetManifestRequestCode)(void *self, uint32_t app_id,
                                                uint32_t depot_id, uint64_t manifest_id,
                                                const char *branch, uint64_t *pRequestCode);

// Fetch manifest request code from the remote API. Returns 0 on success.
static int fetch_manifest_code(uint64_t manifest_id, uint64_t *out_code) {
    char url_buf[128];
    snprintf(url_buf, sizeof(url_buf), MANIFEST_API_FMT, (unsigned long long)manifest_id);

    CFURLRef url = CFURLCreateWithBytes(NULL, (const UInt8 *)url_buf,
                                        (CFIndex)strlen(url_buf),
                                        kCFStringEncodingUTF8, NULL);
    if (!url) return -1;

    CFHTTPMessageRef req = CFHTTPMessageCreateRequest(NULL, CFSTR("GET"), url, kCFHTTPVersion1_1);
    CFRelease(url);
    if (!req) return -1;

    CFHTTPMessageSetHeaderFieldValue(req, CFSTR("User-Agent"), CFSTR(MANIFEST_UA));

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CFReadStreamRef stream = CFReadStreamCreateForHTTPRequest(NULL, req);
#pragma clang diagnostic pop
    CFRelease(req);
    if (!stream) return -1;

    if (!CFReadStreamOpen(stream)) {
        CFRelease(stream);
        return -1;
    }

    UInt8 buf[64];
    CFIndex total = 0;
    while (total < (CFIndex)(sizeof(buf) - 1)) {
        CFIndex n = CFReadStreamRead(stream, buf + total, (CFIndex)(sizeof(buf) - 1) - total);
        if (n <= 0) break;
        total += n;
    }
    CFReadStreamClose(stream);
    CFRelease(stream);

    if (total <= 0) return -1;

    buf[total] = '\0';
    char *end = NULL;
    unsigned long long code = strtoull((const char *)buf, &end, 10);
    if (end == (char *)buf || code == 0) return -1;

    *out_code = (uint64_t)code;
    return 0;
}

static uint32_t hook_GetManifestRequestCode(void *self, uint32_t app_id,
                                              uint32_t depot_id, uint64_t manifest_id,
                                              const char *branch, uint64_t *pRequestCode) {
    sx_config_t *g_cfg = sx_config_current;
    fn_GetManifestRequestCode orig =
        (fn_GetManifestRequestCode)orig_GetManifestRequestCode;

    if (g_cfg && sx_config_has_app(g_cfg, (int)app_id)) {
        uint64_t code = 0;
        if (fetch_manifest_code(manifest_id, &code) == 0 && pRequestCode) {
            *pRequestCode = code;
            SX_LOG_ONCE_KEY(depot_id,
                    "GetManifestRequestCode: app=%u depot=%u manifest=0x%llx -> opensteamtool code=0x%llx",
                    app_id, depot_id, (unsigned long long)manifest_id,
                    (unsigned long long)code);
            return 1;
        }
        // API failed, fall through to original
        SX_LOG_ONCE_KEY(depot_id,
                "GetManifestRequestCode: app=%u depot=%u manifest=0x%llx -> opensteamtool FAILED, passthrough",
                app_id, depot_id, (unsigned long long)manifest_id);
    }

    return orig(self, app_id, depot_id, manifest_id, branch, pRequestCode);
}


static sx_hook_def_t g_hooks[] = {
    {
        .name     = "GetManifestRequestCode",
        .sig_name = "CAppInfo::GetManifestRequestCode",
        .hook_fn  = (void *)hook_GetManifestRequestCode,
        .orig_fn  = &orig_GetManifestRequestCode,
        .optional = 1,
    },
};

int sx_hooks_manifest_count(void) {
    return (int)(sizeof(g_hooks) / sizeof(g_hooks[0]));
}

sx_hook_def_t *sx_hooks_manifest_defs(void) {
    return g_hooks;
}
