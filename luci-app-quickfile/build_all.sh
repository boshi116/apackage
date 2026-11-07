#!/bin/bash
# ==============================================================================
# quickfile 2.0.9 统一打包脚本 —— 同时产出 ipk (opkg) 与 apk (apk v3)
#
# 用法:
#   ./build_all.sh <quickfile二进制> <输出目录> <架构名> [架构名...]
#
# 例:
#   ./build_all.sh ./quickfile ./out aarch64_cortex-a53 aarch64_generic x86_64
#
# 依赖:
#   - ipk: 无外部依赖(手工构造 ar/tar 格式)
#   - apk: 需要 apk-tools 的 `apk mkpkg` (通过环境变量 APK_MKPKG 指定, 默认 /tmp/apk-tools/build/src/apk)
#   - 语言包 lmo: 需要 luci 官方 po2lmo (环境变量 PO2LMO), 若未指定则跳过语言包
# ==============================================================================
set -e

BIN_SRC="${1:?需要指定 quickfile 二进制}"
OUT_DIR="${2:?需要指定输出目录}"
shift 2
ARCHES=("$@")
[ ${#ARCHES[@]} -eq 0 ] && { echo "需要至少指定一个架构名"; exit 1; }

PKG_NAME="quickfile"
PKG_VER="2.0.9"
PKG_REL="1"
I18N_VER="26.143.10947"
I18N_REL="r1"

APK_MKPKG="${APK_MKPKG:-/tmp/apk-tools/build/src/apk}"
PO2LMO="${PO2LMO:-/tmp/luci-src/modules/luci-base/src/po2lmo}"
PO_FILE="${PO_FILE:-/tmp/qf.po}"

mkdir -p "$OUT_DIR"

# ------------------------------------------------------------------------------
# 公共文件: 所有包共用这些内容, 抽到函数里生成到指定根目录
# ------------------------------------------------------------------------------

# ---- init.d 脚本 ----
gen_init_d() {
	mkdir -p "$1/etc/init.d"
	cat > "$1/etc/init.d/quickfile" <<'INITEOF'
#!/bin/sh /etc/rc.common
# quickfile - 轻量级 Web 文件管理器 (Rust/Axum + Vue3)
# 由 sbwml/luci-app-quickfile 上游源码自行编译, musl 静态链接
#
# 鉴权说明:
#   quickfile 通过本地 `ubus call session get` 校验 LuCI 的 sysauth cookie,
#   不依赖 nginx。但 LuCI cookie 的 Path 固定为 /cgi-bin/luci/,
#   因此 API 前缀必须保持在 /cgi-bin/luci/quickfile/ 下, cookie 才会被送达。
#
# 部署模式 (由 /etc/config/quickfile 的 mode 决定, 默认 auto):
#   auto    - 存在 nginx 则用 unix socket + nginx 反代(同源 443, 兼容性最好);
#             否则用独立 TCP 端口 (默认 8090) 直连, 适用于 uhttpd 设备。
#   nginx   - 强制 unix socket + nginx 反代
#   direct  - 强制独立 TCP 端口直连 (适用于 uhttpd 设备)

START=90
USE_PROCD=1
PROG=/usr/bin/quickfile
QF_SOCK=/tmp/run/quickfile/quickfile.sock
QF_API=/cgi-bin/luci/quickfile/api/
QF_STATIC=/cgi-bin/luci/quickfile-static/
QF_DIR=/

# 直接用 uci 读取, 避免依赖 rc.common 的 config_* 上下文
qf_get() {
	local v
	v="$(uci -q get "quickfile.main.$1" 2>/dev/null)"
	[ -z "$v" ] && v="$2"
	echo "$v"
}

qf_has_nginx() {
	[ -x /usr/sbin/nginx ] && [ -f /etc/nginx/conf.d/quickfile.locations ]
}

start_service() {
	local mode port
	mode="$(qf_get mode auto)"
	port="$(qf_get port 8090)"

	[ "$mode" = "auto" ] && {
		if qf_has_nginx; then mode=nginx; else mode=direct; fi
	}

	[ -d /tmp/run/quickfile ] || mkdir -p /tmp/run/quickfile

	procd_open_instance quickfile
	procd_set_param command $PROG
	procd_append_param command -dir $QF_DIR
	procd_append_param command -api $QF_API
	procd_append_param command -static $QF_STATIC

	if [ "$mode" = "nginx" ]; then
		procd_append_param command -sock $QF_SOCK
	else
		procd_append_param command -port $port
	fi

	procd_set_param stdout 0
	procd_set_param stderr 0
	procd_set_param respawn
	procd_set_param limits core="unlimited"
	procd_set_param limits nofile="200000 200000"
	procd_close_instance quickfile
}

stop_service() {
	rm -f "$QF_SOCK" 2>/dev/null
}

reload_service() {
	stop
	start
}
INITEOF
	chmod 755 "$1/etc/init.d/quickfile"
}

# ---- UCI 默认配置 ----
gen_config() {
	mkdir -p "$1/etc/config"
	cat > "$1/etc/config/quickfile" <<'CFGEOF'
config quickfile 'main'
	option mode 'auto'
	option port '8090'
	option enabled '1'
CFGEOF
	chmod 644 "$1/etc/config/quickfile"
}

# ---- nginx 反代配置 ----
gen_nginx() {
	mkdir -p "$1/etc/nginx/conf.d"
	cat > "$1/etc/nginx/conf.d/quickfile.locations" <<'NGXEOF'
# quickfile 2.0.9 反向代理
# 2.0.9 原生支持自定义 API/Static 前缀, 无需 rewrite
# 同源(443)访问以便复用 LuCI 的 sysauth cookie(带 secure 属性)

client_max_body_size 0;
client_body_buffer_size 128k;

location /cgi-bin/luci/quickfile/api/ {
	proxy_cache off;
	proxy_redirect off;
	proxy_buffering off;
	proxy_request_buffering off;
	proxy_http_version 1.1;
	proxy_connect_timeout 300;
	proxy_read_timeout 300;
	proxy_send_timeout 300;
	proxy_set_header Host $host;
	proxy_set_header Upgrade $http_upgrade;
	proxy_set_header Connection "upgrade";
	proxy_set_header X-Real-IP $remote_addr;
	proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	proxy_pass http://unix:/tmp/run/quickfile/quickfile.sock;
}

location /cgi-bin/luci/quickfile-static/ {
	proxy_cache off;
	proxy_redirect off;
	proxy_buffering off;
	proxy_http_version 1.1;
	proxy_set_header Host $host;
	proxy_set_header X-Real-IP $remote_addr;
	proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	proxy_pass http://unix:/tmp/run/quickfile/quickfile.sock;
}

location /cgi-bin/luci/quickfile {
	proxy_cache off;
	proxy_redirect off;
	proxy_buffering off;
	proxy_http_version 1.1;
	proxy_connect_timeout 300;
	proxy_read_timeout 300;
	proxy_send_timeout 300;
	proxy_set_header Host $host;
	proxy_set_header Upgrade $http_upgrade;
	proxy_set_header Connection "upgrade";
	proxy_set_header X-Real-IP $remote_addr;
	proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	proxy_pass http://unix:/tmp/run/quickfile/quickfile.sock;
}
NGXEOF
	chmod 644 "$1/etc/nginx/conf.d/quickfile.locations"
}

# ---- LuCI 菜单 ----
gen_menu() {
	mkdir -p "$1/usr/share/luci/menu.d"
	cat > "$1/usr/share/luci/menu.d/luci-app-quickfile.json" <<'MENUEOF'
{
	"admin/system/quickfile": {
		"title": "Quick File Manager",
		"order": 80,
		"action": {
			"type": "view",
			"path": "system/quickfile"
		}
	}
}
MENUEOF
	chmod 644 "$1/usr/share/luci/menu.d/luci-app-quickfile.json"
}

# ---- rpcd ACL ----
gen_acl() {
	mkdir -p "$1/usr/share/rpcd/acl.d"
	cat > "$1/usr/share/rpcd/acl.d/luci-app-quickfile.json" <<'ACLEOF'
{
	"luci-app-quickfile": {
		"description": "Grant UCI access for luci-app-quickfile",
		"read": {
			"file": {
				"/usr/bin/quickfile": [ "exec" ]
			},
			"uci": [ "quickfile" ]
		},
		"write": {
			"uci": [ "quickfile" ]
		}
	}
}
ACLEOF
	chmod 644 "$1/usr/share/rpcd/acl.d/luci-app-quickfile.json"
}

# ---- LuCI 视图 (XHR 探测同源, 404/401 都回退直连端口) ----
gen_view() {
	mkdir -p "$1/www/luci-static/resources/view/system"
	cat > "$1/www/luci-static/resources/view/system/quickfile.js" <<'VIEWEOF'
'use strict';
'require form';
'require view';
'require ui';
'require uci';

return view.extend({
	render: function () {
		const m = new form.Map('system', '');
		const s = m.section(form.NamedSection, 'iframe_section', 'settings');
		s.anonymous = true;

		s.render = function () {
			/*
			 * 访问地址的确定:
			 *
			 *  - nginx 模式: quickfile 走 unix socket, 由 nginx 在 443/80 同源反代,
			 *    因此直接用同源路径 /cgi-bin/luci/quickfile/ 。
			 *    同源是必须的 —— LuCI 的 sysauth_https cookie 带 secure 属性。
			 *
			 *  - direct 模式 (uhttpd 设备): quickfile 监听独立 TCP 端口 (默认 8090)。
			 *    此时 LuCI 的 sysauth_http cookie 没有 secure 属性, 且 cookie 作用域
			 *    只按 (domain, path) 匹配、与端口无关, 所以只要路径仍以
			 *    /cgi-bin/luci/ 开头, 跨端口也能带上 cookie, 鉴权可通过。
			 *
			 * 因此: 优先同源; 若同源探测失败(404/401/网络错误), 自动回退到直连端口。
			 */
			const cfg = uci.get('quickfile', 'main');
			const port = (cfg && cfg['port']) || '8090';
			const host = window.location.hostname;
			const origin = window.location.protocol + '//' + window.location.host;
			const PREFIX = '/cgi-bin/luci/quickfile/';
			const directUrl = 'http://' + host + ':' + port + PREFIX;

			const iframe = E('iframe', {
				'id': 'quickfile-frame',
				'style': `
					width: 100%;
					height: 100%;
					border: none;
					border-radius: 10px;
				`
			});

			const iframeContainer = E('div', {
				'class': 'iframe-container',
				'style': `
					display: flex;
					flex-direction: column;
					width: 100%;
					max-width: 1600px;
					height: calc(100vh - 180px);
					min-height: 800px;
					overflow: hidden;
					border-radius: 10px;
				`
			}, [ iframe ]);

			/*
			 * 同源探测。
			 *
			 * 用 XHR 探测同源路径的 HTTP 状态码, 而不是读 iframe 内容:
			 *   - uhttpd 设备: 同源路径由 LuCI 处理, 返回 404 (No page is registered)
			 *   - nginx 反代但会话失效: 返回 401
			 * 两种情况都需要回退到直连端口。
			 *
			 * 直接用 fetch 会被 CORS 拦(mixed-content / 跨端口), 因此改用 XHR,
			 * 失败一律按"需要回退"处理。
			 */
			const probe = new XMLHttpRequest();
			probe.open('GET', origin + PREFIX, true);
			probe.onload = function () {
				if (probe.status >= 200 && probe.status < 400) {
					iframe.src = origin + PREFIX;
				} else {
					iframe.src = directUrl;
				}
			};
			probe.onerror = function () {
				iframe.src = directUrl;
			};
			probe.send();

			return iframeContainer;
		};

		return m.render();
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
VIEWEOF
	chmod 644 "$1/www/luci-static/resources/view/system/quickfile.js"
}

# ---- ipk 的 postinst / prerm ----
gen_ipk_scripts() {
	mkdir -p "$1"

	cat > "$1/postinst" <<'POSTEOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0

[ -s /lib/functions.sh ] && . /lib/functions.sh
config_load quickfile
config_get_bool enabled quickfile main enabled 0

[ "$enabled" = "1" ] || exit 0

/etc/init.d/quickfile enable 2>/dev/null
/etc/init.d/quickfile restart 2>/dev/null

# 清理 LuCI 菜单索引缓存, 让新菜单项生效
rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload 2>/dev/null

exit 0
POSTEOF
	chmod 755 "$1/postinst"

	cat > "$1/prerm" <<'PRERMEOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0

/etc/init.d/quickfile stop 2>/dev/null
/etc/init.d/quickfile disable 2>/dev/null

# 清理 LuCI 菜单索引缓存
rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload 2>/dev/null

exit 0
PRERMEOF
	chmod 755 "$1/prerm"
}

# ---- apk 的 post-install / pre-deinstall (对齐官方 luci 包格式) ----
gen_apk_scripts() {
	mkdir -p "$1"

	cat > "$1/post-install.sh" <<'APKPOSTEOF'
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="quickfile"

default_postinst

[ -n "${IPKG_INSTROOT}" ] || {
	# 清理 LuCI 菜单索引缓存, 让新菜单项生效
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null

	# 启用开机自启并立即启动服务
	/etc/init.d/quickfile enable 2>/dev/null
	/etc/init.d/quickfile restart 2>/dev/null

	exit 0
}
APKPOSTEOF
	chmod 755 "$1/post-install.sh"

	cat > "$1/pre-deinstall.sh" <<'APKPREEOF'
#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="quickfile"

default_prerm

[ -n "${IPKG_INSTROOT}" ] || {
	/etc/init.d/quickfile stop 2>/dev/null
	/etc/init.d/quickfile disable 2>/dev/null

	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null

	exit 0
}
APKPREEOF
	chmod 755 "$1/pre-deinstall.sh"
}

# ---- 填充一个包根目录 (共用文件) ----
gen_payload() {
	ROOT="$1"
	mkdir -p "$ROOT/usr/bin"
	install -Dm755 "$BIN_SRC" "$ROOT/usr/bin/quickfile"
	gen_init_d    "$ROOT"
	gen_config    "$ROOT"
	gen_nginx     "$ROOT"
	gen_menu      "$ROOT"
	gen_acl       "$ROOT"
	gen_view      "$ROOT"
}

# ------------------------------------------------------------------------------
# ipk 打包
# ------------------------------------------------------------------------------
build_ipk() {
	ARCH="$1"
	WORK="$(mktemp -d)"
	DATA="$WORK/data"
	CTRL="$WORK/control"
	mkdir -p "$DATA" "$CTRL"

	gen_payload "$DATA"
	gen_ipk_scripts "$CTRL"

	# ---- control ----
	cat > "$CTRL/control" <<CONTROLEOF
Package: $PKG_NAME
Version: $PKG_VER-$PKG_REL
Depends: libc
Source: package/$PKG_NAME
SourceName: $PKG_NAME
License: Apache-2.0
Section: net
SourceDateEpoch: 1780000000
Maintainer: sbwml <admin@cooluc.com>
Architecture: $ARCH
Installed-Size: 40960
Description:  Lightweight web-based file manager built with Rust (Axum) and Vue 3,
 featuring an integrated terminal and multimedia preview, tailored for embedded
 systems and the OpenWrt ecosystem.
CONTROLEOF

	# ---- 打包 data/control ----
	( cd "$DATA" && tar czf "$WORK/data.tar.gz" . )
	( cd "$CTRL" && tar czf "$WORK/control.tar.gz" . )

	# opkg 格式必需的 debian-binary 标记文件 (内容固定为 "2.0\n")
	printf '2.0\n' > "$WORK/debian-binary"

	OUT="$OUT_DIR/${PKG_NAME}_${PKG_VER}-${PKG_REL}_${ARCH}.ipk"
	rm -f "$OUT"
	tar czf "$OUT" -C "$WORK" ./debian-binary ./data.tar.gz ./control.tar.gz
	rm -rf "$WORK"
	echo "  ipk: $(basename "$OUT")  ($(stat -c%s "$OUT") bytes)"
}

# ---- 语言包 ipk (arch = all) ----
build_i18n_ipk() {
	if [ ! -x "$PO2LMO" ] || [ ! -f "$PO_FILE" ]; then
		echo "  跳过 ipk 语言包 (缺 po2lmo 或 po 文件)"
		return 0
	fi
	WORK="$(mktemp -d)"
	DATA="$WORK/data"
	CTRL="$WORK/control"
	mkdir -p "$DATA/usr/lib/lua/luci/i18n" "$CTRL"

	"$PO2LMO" "$PO_FILE" "$DATA/usr/lib/lua/luci/i18n/quickfile.zh-cn.lmo"
	chmod 644 "$DATA/usr/lib/lua/luci/i18n/quickfile.zh-cn.lmo"

	cat > "$CTRL/control" <<CONTROLEOF
Package: luci-i18n-quickfile-zh-cn
Version: $I18N_VER-$I18N_REL
Depends: libc, $PKG_NAME
Source: package/luci-i18n-quickfile-zh-cn
SourceName: luci-i18n-quickfile-zh-cn
License: Apache-2.0
Section: luci
SourceDateEpoch: 1780000000
Maintainer: sbwml <admin@cooluc.com>
Architecture: all
Installed-Size: 64
Description:  Chinese translation for luci-app-quickfile.
CONTROLEOF

	( cd "$DATA" && tar czf "$WORK/data.tar.gz" . )
	( cd "$CTRL" && tar czf "$WORK/control.tar.gz" . )

	printf '2.0\n' > "$WORK/debian-binary"

	OUT="$OUT_DIR/luci-i18n-quickfile-zh-cn_${I18N_VER}_all.ipk"
	rm -f "$OUT"
	tar czf "$OUT" -C "$WORK" ./debian-binary ./data.tar.gz ./control.tar.gz
	rm -rf "$WORK"
	echo "  ipk: $(basename "$OUT")  ($(stat -c%s "$OUT") bytes)"
}

# ------------------------------------------------------------------------------
# apk v3 打包
# ------------------------------------------------------------------------------
build_apk() {
	ARCH="$1"
	if [ ! -x "$APK_MKPKG" ]; then
		echo "  跳过 apk (缺 apk-tools: $APK_MKPKG)"
		return 0
	fi

	WORK="$(mktemp -d)"
	ROOT="$WORK/root"
	mkdir -p "$ROOT"

	gen_payload "$ROOT"
	gen_apk_scripts "$WORK"

	# 属主必须是 root, 否则 mkpkg 会记成 nobody
	chown -R root:root "$ROOT"
	find "$ROOT" -type d -exec chmod 755 {} \;
	chmod 755 "$ROOT/usr/bin/quickfile" "$ROOT/etc/init.d/quickfile"
	chmod 644 "$ROOT/etc/config/quickfile" \
	          "$ROOT/usr/share/luci/menu.d/luci-app-quickfile.json" \
	          "$ROOT/usr/share/rpcd/acl.d/luci-app-quickfile.json" \
	          "$ROOT/www/luci-static/resources/view/system/quickfile.js" \
	          "$ROOT/etc/nginx/conf.d/quickfile.locations"

	OUT="$OUT_DIR/${PKG_NAME}-${PKG_VER}-r${PKG_REL}-${ARCH}.apk"
	rm -f "$OUT"
	(
		cd "$ROOT"
		"$APK_MKPKG" --root=. mkpkg --no-xattrs \
			-I name:"$PKG_NAME" \
			-I version:"${PKG_VER}-r${PKG_REL}" \
			-I description:"Lightweight web-based file manager for OpenWrt, built with Rust and Vue3" \
			-I arch:"$ARCH" \
			-I license:Apache-2.0 \
			-I origin:"package/$PKG_NAME" \
			-I maintainer:"sbwml <admin@cooluc.com>" \
			-I url:https://github.com/sbwml/luci-app-quickfile \
			-I depends:libc \
			-s post-install:"$WORK/post-install.sh" \
			-s pre-deinstall:"$WORK/pre-deinstall.sh" \
			-F . \
			-o "$OUT"
	)
	rm -rf "$WORK"
	echo "  apk: $(basename "$OUT")  ($(stat -c%s "$OUT") bytes)"
}

# ---- 语言包 apk (arch = noarch) ----
build_i18n_apk() {
	if [ ! -x "$APK_MKPKG" ] || [ ! -x "$PO2LMO" ] || [ ! -f "$PO_FILE" ]; then
		echo "  跳过 apk 语言包 (缺 apk-tools / po2lmo / po)"
		return 0
	fi

	WORK="$(mktemp -d)"
	ROOT="$WORK/root"
	mkdir -p "$ROOT/usr/lib/lua/luci/i18n"

	"$PO2LMO" "$PO_FILE" "$ROOT/usr/lib/lua/luci/i18n/quickfile.zh-cn.lmo"
	chown -R root:root "$ROOT"
	find "$ROOT" -type d -exec chmod 755 {} \;
	chmod 644 "$ROOT/usr/lib/lua/luci/i18n/quickfile.zh-cn.lmo"

	OUT="$OUT_DIR/luci-i18n-quickfile-zh-cn-${I18N_VER}-${I18N_REL}.apk"
	rm -f "$OUT"
	(
		cd "$ROOT"
		"$APK_MKPKG" --root=. mkpkg --no-xattrs \
			-I name:luci-i18n-quickfile-zh-cn \
			-I version:"${I18N_VER}-${I18N_REL}" \
			-I description:"Chinese translation for luci-app-quickfile" \
			-I arch:noarch \
			-I license:Apache-2.0 \
			-I origin:package/luci-i18n-quickfile-zh-cn \
			-I maintainer:"sbwml <admin@cooluc.com>" \
			-I depends:"$PKG_NAME" \
			-F . \
			-o "$OUT"
	)
	rm -rf "$WORK"
	echo "  apk: $(basename "$OUT")  ($(stat -c%s "$OUT") bytes)"
}

# ------------------------------------------------------------------------------
# 主流程
# ------------------------------------------------------------------------------
echo "=============================================================="
echo " quickfile $PKG_VER 打包"
echo " 二进制: $BIN_SRC"
echo " 输出  : $OUT_DIR"
echo " 架构  : ${ARCHES[*]}"
echo "=============================================================="

for A in "${ARCHES[@]}"; do
	echo ""
	echo ">>> 架构: $A"
	build_ipk "$A"
	build_apk "$A"
done

echo ""
echo ">>> 语言包 (arch=all / noarch, 与架构无关, 只出一份)"
build_i18n_ipk
build_i18n_apk

echo ""
echo "=============================================================="
echo " 完成, 产物:"
ls -la "$OUT_DIR"
echo "=============================================================="
