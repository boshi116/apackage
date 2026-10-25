#!/bin/sh
# Manual test: install real packages in a disposable OpenWrt instance with Argon 2.x.
set -eu
[ -e /etc/openwrt_release ] || { echo 'Use an expendable OpenWrt container.' >&2; exit 1; }
[ "$#" -eq 4 ] || { echo "Usage: $0 old-app new-app old-language new-language" >&2; exit 2; }
for package in "$@"; do [ -f "$package" ] || exit 1; done
install_packages() {
	case "$1" in
		*.apk) apk add --allow-untrusted "$@" ;;
		*.ipk) opkg install "$@" ;;
		*) return 1 ;;
	esac
}
install_packages "$1" "$3"
uci set 'argon.@global[0].primary=#12ab34'
uci set 'argon.@global[0].dark_primary=#567abc'
uci set 'argon.@global[0].blur=0'
uci set 'argon.@global[0].transparency=0'
uci set 'argon.@global[0].mode=dark'
uci set 'argon.@global[0].online_wallpaper=unsplash_317099,a_b-C'
uci set 'argon.@global[0].unsplash_collection=317099,a_b-C'
uci set 'argon.@global[0].wallhaven_tag=37'
uci set 'argon.@global[0].use_api_key=upgrade-test-access-key'
uci set 'argon.@global[0].use_exact_resolution=0'
uci set 'argon.@global[0].custom_option=retained'
uci commit argon
uci export argon > /tmp/argon-before-upgrade
background='/www/luci-static/argon/background/upgrade retained #1.png'
mkdir -p /www/luci-static/argon/background
# Rendering a real PNG is covered by browser.cjs; this checks file preservation.
printf 'background bytes retained during upgrade\n' > "$background"
cp "$background" /tmp/argon-background-before-upgrade
install_packages "$2" "$4"
uci export argon > /tmp/argon-after-upgrade
cmp /tmp/argon-before-upgrade /tmp/argon-after-upgrade
cmp /tmp/argon-background-before-upgrade "$background"
[ ! -e /etc/argon-config-app-migration/argon ]
[ -s /usr/lib/lua/luci/i18n/argon-config-app.zh-cn.lmo ]
grep -Fq unsplash_collection /www/luci-static/resources/view/argon-config-app.js
grep -Fq use_exact_resolution /www/luci-static/resources/view/argon-config-app.js
[ "$(sh /usr/libexec/rpcd/luci.argon_config call avail | jsonfilter -e @.avail)" -ge 0 ]
echo 'PASS: actual package upgrade preserves all UCI options and background bytes; new view, Chinese catalog and RPC are installed.'
