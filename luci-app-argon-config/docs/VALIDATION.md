# Validation

## 2.1.0 wallpaper filters

Validated on 2026-10-22 using the actual APK/IPK artifacts from [Actions run 39777520294](https://github.com/AimeeAngelia/luci-app-argon-config/actions/runs/39777520294), application revision `ae1959f27217ef295f971ddef106b4e2806014c4`. Both SDK jobs pass and each format contains the main package plus six translations. Subsequent validation commits change tests and documentation only.

| Check | Result |
| --- | --- |
| Node behavior and release tests | All 20 pass, including anonymous UCI sections, legacy encoded IDs, filter-only edits, clearing filters, provider switching and validation |
| Actual 2.0.0 → 2.1.0 upgrade on OpenWrt 25.12.6 (APK) and 24.10.8 (IPK), with official Argon 2.4.8 | Main and Chinese packages upgrade; all UCI options and background bytes are preserved, including zero opacity/blur and custom options |
| Chromium against both upgraded installations | Collection save/reload, Reset, required Unsplash key, optional Wallhaven key, tag validation, exact/minimum resolution, clearing filters and remembered filters pass |
| Existing browser regression on both installations | Upload, real PNG preview, duplicate/format rejection, delete/cancel, refresh, unsaved values, Reset, Save and Save & Apply pass |
| Live Bing and Wallhaven through the actual theme RPC on both installations | Each returns a real image URL for Bing, exact Wallhaven tag searches and minimum-resolution searches |
| Live Wallhaven API responses | Exact search returns 1920×1080 results; minimum search returns 1920×1080 and larger sizes |
| Actual login page on OpenWrt 24.10.8 | Chromium loads and decodes a real 1920×1080 Wallhaven image; missing Unsplash key falls back to a local PNG |
| Read-only LuCI session | Source/upload/delete controls disabled; direct file deletion and UCI writes denied by RPC permissions |
| Argon 3.0.0-r2 installed before the app | Main/Chinese packages install without conflicts; existing theme configuration preserved |
| Argon 2.4.8 → 3.0.0-r2 with app 2.1.0 installed | Every existing UCI setting preserved |
| Browser for both Argon 3 installation orders | Native page opens with preserved color, exactly one menu entry, standalone route returns 404 and no JavaScript errors |
| Translations | Simplified Chinese covers all 59 messages; all six catalogs compile |

The live RPC checks cleared only their disposable containers' wallpaper caches before each scenario. Normal key/resolution edits do not clear theme caches automatically; see [ONLINE_WALLPAPER.md](ONLINE_WALLPAPER.md). Unsplash collection/key query generation was verified with the actual theme RPC and simulated HTTP responses; authenticated Unsplash image retrieval was not tested because no valid Access Key was provided. Live provider results describe this test run, not future service availability.

All browser checks use real HTTP, RPC and UCI against disposable OpenWrt containers with the generated packages installed. The containers share the host kernel; physical router hardware was not covered. Reproduction scripts and prerequisites are described in [DEVELOPMENT.md](DEVELOPMENT.md).

## 2.0.0

Tested with the actual stable SDKs and root filesystems for OpenWrt 25.12.6 and 24.10.8.

| Check | Result |
| --- | --- |
| Node view behavior and ACL assertions | 9 tests passed |
| Real BusyBox, jshn and UCI | 18 RPC scenarios and configuration migrations passed on both versions |
| OpenWrt 25.12.6 SDK | Main APK and six translation APKs built |
| OpenWrt 24.10.8 SDK | Main IPK and six translation IPKs built |
| APK installation with Argon 2.4.8 | Passed |
| IPK installation with Argon 2.4.8 | Passed |
| APK installation alongside official Argon 3.0.0-r2 | Passed without file conflicts; custom primary color preserved |
| Upgrade from the original 1.0 APK | Both unchanged and modified configurations preserved; old app files removed |
| Browser against actual LuCI, including Argon 2.4.8 | Upload, PNG preview, duplicate rejection, invalid format, delete/cancel, refresh, unsaved values, Reset, Save and Save & Apply passed |
| Browser against Argon 3.0 | Integrated settings opened; standalone entry hidden; exactly one settings menu entry |
| Actual rpcd read-only session | Space query allowed; install/remove denied |
| Simplified Chinese catalog | All current strings translated |

The browser tests used Chromium and real HTTP uploads, RPC calls and UCI commits. The initial form tests also ran under the Bootstrap theme. Integration containers use the host kernel; physical router hardware, browser video codecs and online wallpaper providers were not covered.

The original repository's master branch at the start of this change was `3e099a37c3f71d0de677f1b6b0f4bffd57d91dac`. No separate DeepSeek changes were present in its published branches.
