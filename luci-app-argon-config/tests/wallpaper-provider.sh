#!/bin/sh
# Manual integration test for a compatible theme RPC inside disposable OpenWrt.
set -eu
[ -e /etc/openwrt_release ] || { echo 'Use an expendable OpenWrt container.' >&2; exit 1; }
export ARGON_TEST_RPC="${1:-/usr/libexec/rpcd/luci.argon_wallpaper}"
export ARGON_TEST_LOG=/tmp/argon-provider-requests
[ -f "$ARGON_TEST_RPC" ] || exit 1
mkdir -p /var/run /var/lock
sh /src/root/etc/uci-defaults/luci-argon-config-app
cat > /tmp/argon-provider-wrapper <<'WRAPPER'
#!/bin/sh
wget() {
	printf '%s\n' "$*" >> "$ARGON_TEST_LOG"
	case "$*" in
		*api.unsplash.com*) printf '{"urls":{"regular":"https://example.test/test.jpg"}}\n' ;;
		*wallhaven.cc/api*) printf '{"data":[{"path":"https://example.test/test.jpg"}]}\n' ;;
	esac
}
flock() { return 0; }
set -- call get_url
. "$ARGON_TEST_RPC"
WRAPPER
request() {
	rm -f /var/run/argon_unsplash_317099,a_b-C.url /var/run/argon_wallhaven_37.url
	: > "$ARGON_TEST_LOG"
	printf '{}\n' | sh /tmp/argon-provider-wrapper > /tmp/argon-provider-result
	[ "$(jsonfilter -i /tmp/argon-provider-result -e @.url)" = 'https://example.test/test.jpg' ]
}
uci set 'argon.@global[0].online_wallpaper=unsplash_317099,a_b-C'
uci set 'argon.@global[0].use_api_key=test-access-key'
uci commit argon
request
grep -Fq 'client_id=test-access-key&collections=317099,a_b-C' "$ARGON_TEST_LOG"
uci set 'argon.@global[0].online_wallpaper=wallhaven_37'
uci set 'argon.@global[0].use_api_key=test-wallhaven-key'
uci set 'argon.@global[0].use_exact_resolution=1'
uci commit argon
request
grep -Fq 'apikey=test-wallhaven-key&q=id%3A37&resolutions=1920x1080' "$ARGON_TEST_LOG"
uci set 'argon.@global[0].use_exact_resolution=0'
uci -q delete 'argon.@global[0].use_api_key'
uci commit argon
request
grep -Fq 'q=id%3A37&atleast=1920x1080' "$ARGON_TEST_LOG"
! grep -Fq 'apikey=' "$ARGON_TEST_LOG"
echo 'PASS: real theme RPC builds Unsplash collection and Wallhaven tag/key/resolution queries; HTTP responses are simulated.'
