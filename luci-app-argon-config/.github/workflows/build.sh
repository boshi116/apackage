#!/bin/sh
set -eu

cd /builder
[ -d scripts ] || ./setup.sh

# Keep the exact feed revisions supplied with the stable SDK, including base
# libraries required by LuCI. Use GitHub mirrors for the Git repositories.
sed -e 's|https://git.openwrt.org/openwrt/openwrt.git|https://github.com/openwrt/openwrt.git|' \
	-e 's|https://git.openwrt.org/feed/packages.git|https://github.com/openwrt/packages.git|' \
	-e 's|https://git.openwrt.org/project/luci.git|https://github.com/openwrt/luci.git|' \
	feeds.conf.default > feeds.conf
for feed in base packages luci; do
	# Stable SDKs may pin a tag, which cannot be updated with git pull.
	[ -s "feeds/$feed.index" ] || ./scripts/feeds update "$feed"
done
./scripts/feeds install -a -p base
./scripts/feeds install -a -p luci

rm -rf package/luci-app-argon-config
mkdir -p package/luci-app-argon-config
cp -R /src/htdocs /src/po /src/root /src/Makefile package/luci-app-argon-config/
# Argon is not in the official LuCI feed. Pin the last 2.x release for the
# standalone app build; 3.x ships its own settings and migration recipe.
[ -d package/luci-theme-argon ] ||
	git clone --depth 1 --branch v2.4.8 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon

# The SDK ships CONFIG_ALL=y. Keep its target selection, then select only
# this app and its languages instead of packaging every optional subpackage.
[ -f .config ] || make defconfig
sed -n '/^CONFIG_TARGET_/p; /^CONFIG_SDK[=_]/p' .config > .config.argon
mv .config.argon .config
cat >> .config <<'CONFIG'
# CONFIG_ALL is not set
# CONFIG_ALL_KMODS is not set
# CONFIG_ALL_NONSHARED is not set
CONFIG_PACKAGE_luci-app-argon-config=m
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_LUCI_LANG_zh_Hant=y
CONFIG_LUCI_LANG_es=y
CONFIG_LUCI_LANG_pl=y
CONFIG_LUCI_LANG_pt_BR=y
CONFIG_LUCI_LANG_ru=y
CONFIG
make defconfig
# Preserve the compiler's exit status even when collecting logs.
trap 'tar -cJf /builder/bin/logs.tar.xz logs 2>/dev/null || true' EXIT
make package/luci-app-argon-config/compile V=s -j2 BUILD_LOG=1
