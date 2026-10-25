# Development and validation

The package uses JavaScript LuCI, UCI, `rpcd-mod-file`, `cgi-io` and a shell RPC plugin. No Lua controller or package-manager-specific runtime logic is required. The SDK chooses the package format.

## SDK builds

Use the stable SDK's own pinned feeds, including `base` and `packages`. Replacing those feeds with LuCI alone omits libraries needed by the SDK. The build helper pins Argon 2.4.8 as the standalone theme dependency and builds all six supplied translations with LuCI's standard translation rules.

```sh
mkdir -p bin
docker run --rm --user root -e FORCE_UNSAFE_CONFIGURE=1 \
  -v "$PWD:/src:ro" -v "$PWD/bin:/builder/bin" \
  openwrt/sdk:x86-64-25.12.6 /bin/sh /src/.github/workflows/build.sh
```

For IPK use `openwrt/sdk:x86-64-24.10.8` with a separate output directory. Packages use architecture `all`; the SDK still determines the dependency metadata and package format. Build artifacts are written below `bin/packages/`; compiler logs are archived as `bin/logs.tar.xz` even on failure.

## Regression tests

```sh
node --test tests/*.test.js
docker run --rm -v "$PWD:/src:ro" \
  openwrt/rootfs:x86-64-25.12.6 sh /src/tests/openwrt.sh
```

The Node tests exercise the view's RPC/error handling and button wiring. Container tests use real OpenWrt BusyBox, jshn and UCI for file operations, malformed names, symlinks, upload collisions, partial-copy cleanup and upgrade migrations. Run the shell test only in a disposable container; it changes that container's Argon configuration.

Validate translation catalogs with `msgfmt --check -o /dev/null po/<language>/argon-config-app.po`.

## Browser integration

`tests/browser.cjs` tests the actual LuCI form and HTTP upload against an expendable, running OpenWrt instance with the app installed. It changes the primary color to `#123abc`, uploads and deletes a small PNG, and applies the configuration. It expects English LuCI and a root login, and defaults to `http://127.0.0.1:18080` with an empty password. Set `LUCI_URL`, `LUCI_PASSWORD` and `CHROME_BIN` as needed. Do not point this test at a production router.

```sh
npm install --prefix /tmp/argon-browser playwright-core
NODE_PATH=/tmp/argon-browser/node_modules node tests/browser.cjs
```

The following optional checks use the same Playwright setup. They require the corresponding disposable instance and should run sequentially on each instance because some change its configuration.

| Script | Prerequisites and coverage |
| --- | --- |
| `wallpaper-browser.cjs` | English standalone page, default port 18082; validates filter edits, apply/reload, reset, keys, resolution and source switching |
| `package-upgrade.sh old-app new-app old-language new-language` | Run inside OpenWrt with a compatible Argon 2.x theme; pass four actual APK or IPK paths, using the Chinese language packages; verifies upgrade preservation and installed files/RPC |
| `integrated-browser.cjs` | English Argon 3 instance, default port 18084; set `EXPECT_PRIMARY` to its existing primary color (default `#345def`); checks native settings and hidden standalone route |
| `readonly-browser.cjs` | English standalone instance, default port 18082; provision a login with read ACL groups and no write groups; set `LUCI_USERNAME` (default `argon-viewer`) and `LUCI_PASSWORD`; at least one background file must exist |
| `login-background-browser.cjs` | An unauthenticated Argon 2.x login page; configure the source in the disposable instance first and set `EXPECT_BACKGROUND` (URL regex), `EXPECT_WIDTH` and `EXPECT_HEIGHT`; checks the image actually decoded by Chromium |

`package-upgrade.sh` seeds custom settings and a file before upgrading, then compares their complete contents. It needs the old and new packages downloaded beforehand. It does not fetch releases or install the theme. The provider query test in `wallpaper-provider.sh` simulates HTTP; the login-image check can use a live source or a local fallback. Live provider checks are optional and do not run in CI.

## Configuration ownership and migration

Argon 3.x owns `/etc/config/argon`, `view/argon-config.js`, `luci.argon`, and the original menu, ACL and translation names. This package uses separate names and does not ship the shared configuration file. Its pre-install script saves the existing configuration before upgrading from the old package. A UCI defaults script restores it and initializes only missing options on standalone installations. Explicit wallpaper choices take precedence over the legacy `bing_background` switch.

The standalone menu depends on the absence of `/usr/share/argon/config-integrated`, the marker shipped by the integrated theme. Installing both packages therefore does not create duplicate settings menus. Existing Argon 3 settings are left to the theme's own initialization.

Write RPC methods are granted only in the write ACL. Uploads use separate temporary paths, are copied to a hidden file on the destination filesystem, and are published without overwriting an existing background. All operations report a result code; the view reports failures and refreshes only the background list, preserving unsaved form values.

## Publishing

Push a tag matching `PKG_VERSION` and `PKG_RELEASE`, such as `v2.1.0`, `v2.1.0-r1` or `release-2.1.0-r1`, or run the Release workflow manually with a matching tag name. The selected workflow ref is the source of the binaries. Both stable SDK builds and tests must succeed before the public release is created.

The publisher requires both main package formats, attaches the translations and generates `SHA256SUMS` using asset basenames. A rerun can complete an existing release, but a tag pointing to another commit is rejected so that manual dispatches cannot replace its binaries with builds from another revision. Existing release notes are preserved on reruns.
