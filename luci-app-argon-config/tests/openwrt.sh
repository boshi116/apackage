#!/bin/sh
# Run only inside an expendable OpenWrt container: this uses its real UCI and jshn.
set -eu
[ -e /etc/openwrt_release ] || { echo 'Run this test in an OpenWrt container.' >&2; exit 1; }
app=/src/root/usr/libexec/rpcd/luci.argon_config
bg=/www/luci-static/argon/background
upload=/tmp/argon-config-upload-0123456789abcdef
mkdir -p "$bg"
count=0
expect() {
	method="$1"; input="$2"; expected="$3"
	actual="$(printf '%s\n' "$input" | sh "$app" call "$method" | jsonfilter -e '@.result')"
	[ "$actual" = "$expected" ] || { echo "FAIL $method: expected $expected, got $actual ($input)" >&2; exit 1; }
	count=$((count + 1))
}

sh -n "$app"
sh "$app" list | jsonfilter -e '@.install.filename' | grep -qx String
[ "$(sh "$app" call avail | jsonfilter -e '@.avail')" -ge 0 ]
printf 'image bytes' > "$upload"
expect install '{"tmpfile":"/tmp/argon-config-upload-0123456789abcdef","filename":"日落 & sky.JPG"}' 0
[ "$(ls -l "$bg/日落 & sky.JPG" | awk '{print $1}')" = '-rw-r--r--' ]
[ ! -e "$upload" ]
printf 'replacement' > "$upload"
expect install '{"tmpfile":"/tmp/argon-config-upload-0123456789abcdef","filename":"日落 & sky.JPG"}' 4
grep -qx 'image bytes' "$bg/日落 & sky.JPG"
expect install '{"tmpfile":"/tmp/argon-config-upload-0123456789abcdef","filename":"bad.html"}' 2
expect install '{"tmpfile":"/etc/passwd","filename":"password.png"}' 3
expect install '{"tmpfile":"/tmp/argon-config-upload-../../etc/passwd","filename":"x.png"}' 3
expect install '{"tmpfile":"/tmp/argon-config-upload-0123456789abcdef","filename":"../outside.png"}' 1
expect remove '{"filename":".."}' 1
expect remove '{"filename":""}' 1
expect remove '{"filename":"a\\b.png"}' 1
expect remove '{"filename":"bad\nname.png"}' 1
expect remove '{"filename":"x.html"}' 2
expect remove '{"filename":"missing.png"}' 5
ln -s /etc/passwd "$bg/link.png"
expect remove '{"filename":"link.png"}' 1
expect install '{"tmpfile":"/tmp/argon-config-upload-0123456789abcdef","filename":"link.png"}' 1
rm "$upload"
ln -s /etc/passwd "$upload"
expect install '{"tmpfile":"/tmp/argon-config-upload-0123456789abcdef","filename":"x.png"}' 3
rm "$upload"
: > "$upload"
expect install '{"tmpfile":"/tmp/argon-config-upload-0123456789abcdef","filename":"x.png"}' 3
expect remove '{"filename":"日落 & sky.JPG"}' 0
[ ! -e "$bg/日落 & sky.JPG" ]
# A failed copy must not publish a partial file or remove the source.
printf data > "$upload"
mkdir -p /tmp/argon-test-bin
printf '#!/bin/sh\nexit 1\n' > /tmp/argon-test-bin/cp
chmod +x /tmp/argon-test-bin/cp
PATH="/tmp/argon-test-bin:$PATH" expect install '{"tmpfile":"/tmp/argon-config-upload-0123456789abcdef","filename":"failed.png"}' 5
[ ! -e "$bg/failed.png" ] && [ -f "$upload" ]
[ -z "$(find "$bg" -name '.argon-config-upload-*')" ]
rm "$upload"

# Exercise migrations with OpenWrt UCI, including a conffile released on upgrade.
init=/src/root/etc/uci-defaults/luci-argon-config-app
rm -f /etc/config/argon
sh "$init"
[ "$(uci get 'argon.@global[0].online_wallpaper')" = none ]
uci set 'argon.@global[0].primary=#abcdef'
uci set 'argon.@global[0].blur=0'
uci set 'argon.@global[0].bing_background=1'
uci delete 'argon.@global[0].online_wallpaper'
uci commit argon
sh "$init"
[ "$(uci get 'argon.@global[0].primary')" = '#abcdef' ]
[ "$(uci get 'argon.@global[0].blur')" = 0 ]
[ "$(uci get 'argon.@global[0].online_wallpaper')" = bing ]
! uci -q get 'argon.@global[0].bing_background'
uci set 'argon.@global[0].online_wallpaper=none'
uci set 'argon.@global[0].bing_background=1'
uci commit argon
sh "$init"
[ "$(uci get 'argon.@global[0].online_wallpaper')" = none ]
before="$(uci show argon)"
sh "$init"
[ "$(uci show argon)" = "$before" ]
sed -n '/^define Package.*\/preinst$/,/^endef$/p' /src/Makefile | sed '1d;$d;s/\$\$/\$/g' > /tmp/argon-preinst
IPKG_INSTROOT='' sh /tmp/argon-preinst
rm /etc/config/argon
sh "$init"
[ "$(uci show argon)" = "$before" ]
[ ! -d /etc/argon-config-app-migration ]
mkdir -p /usr/share/argon
touch /usr/share/argon/config-integrated
uci delete 'argon.@global[0].blur'
uci commit argon
before="$(uci show argon)"
sh "$init"
[ "$(uci show argon)" = "$before" ]
echo "PASS: $count RPC scenarios; fresh install, legacy migration, idempotence, upgrade preservation and integrated-theme handoff"
