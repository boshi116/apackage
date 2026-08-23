#!/bin/sh
set -eu

REPO="${REPO:-hxzlplp7/luci-app-dashboard}"
VERSION="${VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-}"
CORE_BIN="/usr/bin/dashboard-core"
CORE_SERVICE="/etc/init.d/dashboard-core"
CORE_LISTEN="${CORE_LISTEN:-127.0.0.1:19090}"

if [ "$(id -u)" != "0" ]; then
    echo "This installer must run as root." >&2
    exit 1
fi

if [ "$VERSION" = "latest" ]; then
    BASE_URL="https://github.com/${REPO}/releases/latest/download"
else
    BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
fi

# 检测系统包管理器：25.12+ 用 apk，旧版用 opkg
if command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    PKG_EXT="apk"
elif command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
    PKG_EXT="ipk"
else
    echo "Missing package manager: install apk or opkg." >&2
    exit 1
fi

download() {
    url="$1"
    dest="$2"
    allow_fail="${3:-0}"
    rm -f "$dest"

    if command -v curl >/dev/null 2>&1; then
        if ! curl -fL --connect-timeout 15 --retry 2 -o "$dest" "$url"; then
            rm -f "$dest"
            [ "$allow_fail" = "1" ] && return 1
            echo "Download failed: $url" >&2
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -T 30 -O "$dest" "$url"; then
            rm -f "$dest"
            [ "$allow_fail" = "1" ] && return 1
            echo "Download failed: $url" >&2
            exit 1
        fi
    elif command -v uclient-fetch >/dev/null 2>&1; then
        if ! uclient-fetch -O "$dest" "$url"; then
            rm -f "$dest"
            [ "$allow_fail" = "1" ] && return 1
            echo "Download failed: $url" >&2
            exit 1
        fi
    else
        echo "Missing downloader: install curl, wget, or uclient-fetch." >&2
        exit 1
    fi

    if [ ! -s "$dest" ]; then
        rm -f "$dest"
        [ "$allow_fail" = "1" ] && return 1
        echo "Download failed or empty file: $url" >&2
        exit 1
    fi
}

pkg_install() {
    if [ "$PKG_MGR" = "apk" ]; then
        apk add --force-overwrite --force-non-repository "$@"
    else
        if ! opkg install --force-reinstall "$@"; then
            opkg install "$@"
        fi
    fi
}

install_lua_runtime_dependency() {
    if [ "$PKG_MGR" = "apk" ]; then
        if apk info -e luci-lua-runtime >/dev/null 2>&1; then
            echo "Dependency luci-lua-runtime is already installed."
            return 0
        fi
        echo "Installing dependency: luci-lua-runtime..."
        apk update || true
        if apk add luci-lua-runtime; then
            echo "Successfully installed luci-lua-runtime."
            return 0
        fi
        echo "Failed to install luci-lua-runtime via apk." >&2
        exit 1
    fi

    # opkg 路径
    if opkg status luci-lua-runtime 2>/dev/null | grep -q "Status: install ok installed"; then
        echo "Dependency luci-lua-runtime is already installed."
        return 0
    fi

    echo "Updating opkg package database..."
    opkg update || true

    echo "Installing dependency: luci-lua-runtime..."
    if opkg install luci-lua-runtime; then
        echo "Successfully installed luci-lua-runtime."
        return 0
    fi

    echo "opkg install failed. Attempting to locate and download luci-lua-runtime..."

    pkg_file=""
    for list_file in /var/opkg-lists/*; do
        if [ -f "$list_file" ]; then
            pkg_file=$(awk '/Package: luci-lua-runtime/{flag=1;next}/Package:/{flag=0}flag && /Filename:/{print $2;exit}' "$list_file")
            [ -n "$pkg_file" ] && break
        fi
    done

    arch_val="$(detect_arch)"
    version_val="21.02.0"
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        version_val="${DISTRIB_RELEASE:-21.02.0}"
    fi

    download_success=0
    if [ -n "$pkg_file" ] && [ -n "$arch_val" ]; then
        feed_url=""
        if [ -f /etc/opkg/distfeeds.conf ]; then
            feed_url=$(grep -E 'src/gz.*luci' /etc/opkg/distfeeds.conf | head -n 1 | awk '{print $3}')
        fi
        [ -z "$feed_url" ] && feed_url="https://downloads.openwrt.org/releases/${version_val}/packages/${arch_val}/luci"

        for base_url in "$feed_url" "$(echo "$feed_url" | sed 's/downloads.openwrt.org/archive.openwrt.org/g')" "https://mirrors.ustc.edu.cn/openwrt/releases/${version_val}/packages/${arch_val}/luci"; do
            base_url=$(echo "$base_url" | sed 's/\/$//')
            full_url="${base_url}/${pkg_file}"
            echo "Trying to download: $full_url"
            if download "$full_url" "${INSTALL_DIR}/luci-lua-runtime.ipk" 1; then
                echo "Successfully downloaded luci-lua-runtime.ipk"
                if opkg install "${INSTALL_DIR}/luci-lua-runtime.ipk"; then
                    download_success=1
                    break
                fi
            fi
        done
    fi

    if [ "$download_success" = "0" ]; then
        major_ver=$(echo "$version_val" | cut -d. -f1)
        if [ "$major_ver" -ge 21 ] 2>/dev/null || [ "${DISTRIB_RELEASE:-}" = "SNAPSHOT" ]; then
            echo "============================================="
            echo "错误：无法自动安装或下载依赖项 'luci-lua-runtime'！"
            echo "您的 OpenWrt 版本是 ${version_val}，此版本需要该依赖才能运行 LuCI 插件。"
            echo "请尝试以下解决方法："
            echo "1. 确保您的路由器已连接互联网，然后手动执行：opkg update && opkg install luci-lua-runtime"
            echo "2. 如果您的路由器无法联网，请在电脑上访问下载对应版本的 luci-lua-runtime.ipk，"
            echo "   然后将其上传到路由器，并执行：opkg install luci-lua-runtime"
            echo "============================================="
            exit 1
        else
            echo "Warning: Failed to install luci-lua-runtime. Legacy OpenWrt detected, proceeding anyway..."
        fi
    fi
}

detect_arch() {
    if [ -n "${DASHBOARD_CORE_ARCH:-}" ]; then
        printf '%s\n' "$DASHBOARD_CORE_ARCH"
        return
    fi

    if [ "$PKG_MGR" = "opkg" ] && command -v opkg >/dev/null 2>&1; then
        arch="$(opkg print-architecture 2>/dev/null | awk '$2 != "all" { value=$2 } END { print value }')"
        if [ -n "$arch" ]; then
            printf '%s\n' "$arch"
            return
        fi
    fi

    case "$(uname -m 2>/dev/null || true)" in
        aarch64|arm64) printf '%s\n' "aarch64_cortex-a53" ;;
        armv7l) printf '%s\n' "arm_cortex-a7_neon-vfpv4" ;;
        mips) printf '%s\n' "mips_24kc" ;;
        mipsel) printf '%s\n' "mipsel_24kc" ;;
        x86_64) printf '%s\n' "x86_64" ;;
        *)
            echo "Cannot detect backend architecture. Set DASHBOARD_CORE_ARCH and retry." >&2
            exit 1
            ;;
    esac
}

detect_arch_candidates() {
    primary_arch="$(detect_arch)"
    candidates=""

    append_candidate() {
        candidate="$1"
        [ -n "$candidate" ] || return
        case " $candidates " in
            *" $candidate "*) ;;
            *) candidates="${candidates}${candidates:+ }${candidate}" ;;
        esac
    }

    append_candidate "$primary_arch"

    case "$primary_arch" in
        aarch64*|arm64|armv8)
            append_candidate "aarch64_generic"
            append_candidate "aarch64_cortex-a53"
            append_candidate "aarch64"
            append_candidate "armv8"
            ;;
        arm_cortex-a7*|arm_cortex-a8*|arm_cortex-a9*|arm_cortex-a15*|armv7*|armhf)
            append_candidate "arm_cortex-a7_neon-vfpv4"
            append_candidate "arm_cortex-a9_vfpv3-d16"
            append_candidate "armv7"
            ;;
        x86_64|amd64)
            append_candidate "x86_64"
            append_candidate "x86"
            ;;
        i386*|i686*|x86)
            append_candidate "x86"
            append_candidate "i386_pentium4"
            ;;
    esac

    printf '%s\n' "$candidates" | tr ' ' '\n'
}

write_service() {
    cat > "$CORE_SERVICE" <<EOF
#!/bin/sh /etc/rc.common

START=90
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command $CORE_BIN --listen $CORE_LISTEN
    procd_set_param respawn 3600 5 0
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
    chmod 755 "$CORE_SERVICE"
}

cleanup_legacy_kmod() {
    legacy_pkg="kmod-dashboard-monitor"

    if [ "$PKG_MGR" = "apk" ]; then
        if apk info -e "$legacy_pkg" >/dev/null 2>&1; then
            echo "Detected legacy package: ${legacy_pkg}, attempting cleanup."
            apk del "$legacy_pkg" >/dev/null 2>&1 || true
        fi
        return
    fi

    info_dir="/usr/lib/opkg/info"
    postinst="${info_dir}/${legacy_pkg}.postinst"

    if opkg status "$legacy_pkg" >/dev/null 2>&1 || [ -e "$postinst" ]; then
        echo "Detected legacy package: ${legacy_pkg}, attempting cleanup."
        [ -e "$postinst" ] && chmod 755 "$postinst" 2>/dev/null || true
        opkg configure "$legacy_pkg" >/dev/null 2>&1 || true
        opkg remove "$legacy_pkg" >/dev/null 2>&1 || true
    fi
}

ARCH=""
CORE_ASSET=""
CORE_PKG_ASSET=""
CORE_PKG_FILE=""
CORE_MODE=""

echo "Using release: ${VERSION}"
echo "Package manager: ${PKG_MGR} (.${PKG_EXT})"

if [ -z "$INSTALL_DIR" ]; then
    INSTALL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/luci-app-dashboard-install.XXXXXXXXXX") || {
        echo "Failed to create temporary directory" >&2
        exit 1
    }
    trap 'rm -rf "$INSTALL_DIR"' EXIT
else
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
fi

# 下载 LuCI 包：优先当前格式，失败后尝试另一种格式
LUCI_APP_FILE=""
LUCI_I18N_FILE=""

if download "${BASE_URL}/luci-app-dashboard.${PKG_EXT}" "${INSTALL_DIR}/luci-app-dashboard.${PKG_EXT}" 1; then
    LUCI_APP_FILE="${INSTALL_DIR}/luci-app-dashboard.${PKG_EXT}"
elif download "${BASE_URL}/luci-app-dashboard.apk" "${INSTALL_DIR}/luci-app-dashboard.apk" 1; then
    LUCI_APP_FILE="${INSTALL_DIR}/luci-app-dashboard.apk"
elif download "${BASE_URL}/luci-app-dashboard.ipk" "${INSTALL_DIR}/luci-app-dashboard.ipk" 1; then
    LUCI_APP_FILE="${INSTALL_DIR}/luci-app-dashboard.ipk"
else
    echo "Failed to download luci-app-dashboard package." >&2
    exit 1
fi

if download "${BASE_URL}/luci-i18n-dashboard-zh-cn.${PKG_EXT}" "${INSTALL_DIR}/luci-i18n-dashboard-zh-cn.${PKG_EXT}" 1; then
    LUCI_I18N_FILE="${INSTALL_DIR}/luci-i18n-dashboard-zh-cn.${PKG_EXT}"
elif download "${BASE_URL}/luci-i18n-dashboard-zh-cn.apk" "${INSTALL_DIR}/luci-i18n-dashboard-zh-cn.apk" 1; then
    LUCI_I18N_FILE="${INSTALL_DIR}/luci-i18n-dashboard-zh-cn.apk"
elif download "${BASE_URL}/luci-i18n-dashboard-zh-cn.ipk" "${INSTALL_DIR}/luci-i18n-dashboard-zh-cn.ipk" 1; then
    LUCI_I18N_FILE="${INSTALL_DIR}/luci-i18n-dashboard-zh-cn.ipk"
else
    echo "Failed to download luci-i18n-dashboard-zh-cn package." >&2
    exit 1
fi

cleanup_legacy_kmod
install_lua_runtime_dependency

CANDIDATE_ARCHES="$(detect_arch_candidates)"
echo "Backend architecture candidates: $(printf '%s' "$CANDIDATE_ARCHES" | tr '\n' ' ')"

# 尝试下载并安装对应架构的 dashboard-core 包
for candidate in $CANDIDATE_ARCHES; do
    # 优先尝试系统对应格式的包
    candidate_pkg_asset="dashboard-core-${candidate}.${PKG_EXT}"
    candidate_pkg_file="${INSTALL_DIR}/${candidate_pkg_asset}"
    if download "${BASE_URL}/${candidate_pkg_asset}" "${candidate_pkg_file}" 1; then
        echo "Using backend package asset: ${candidate_pkg_asset}"
        if pkg_install "${candidate_pkg_file}"; then
            ARCH="$candidate"
            CORE_PKG_ASSET="$candidate_pkg_asset"
            CORE_PKG_FILE="$candidate_pkg_file"
            CORE_MODE="pkg"
            break
        fi
        echo "Backend package ${candidate_pkg_asset} is not compatible, trying next candidate." >&2
    fi
done

# 如果系统对应格式的包安装失败，尝试另一种格式
if [ -z "$CORE_MODE" ]; then
    alt_ext="ipk"
    [ "$PKG_EXT" = "ipk" ] && alt_ext="apk"
    for candidate in $CANDIDATE_ARCHES; do
        candidate_pkg_asset="dashboard-core-${candidate}.${alt_ext}"
        candidate_pkg_file="${INSTALL_DIR}/${candidate_pkg_asset}"
        if download "${BASE_URL}/${candidate_pkg_asset}" "${candidate_pkg_file}" 1; then
            echo "Using backend package asset (alt format): ${candidate_pkg_asset}"
            # 用对应格式的包管理器安装
            if [ "$alt_ext" = "apk" ] && command -v apk >/dev/null 2>&1; then
                if apk add --force-overwrite --force-non-repository "${candidate_pkg_file}"; then
                    ARCH="$candidate"
                    CORE_PKG_ASSET="$candidate_pkg_asset"
                    CORE_PKG_FILE="$candidate_pkg_file"
                    CORE_MODE="pkg"
                    break
                fi
            elif [ "$alt_ext" = "ipk" ] && command -v opkg >/dev/null 2>&1; then
                if opkg install --force-reinstall "${candidate_pkg_file}" || opkg install "${candidate_pkg_file}"; then
                    ARCH="$candidate"
                    CORE_PKG_ASSET="$candidate_pkg_asset"
                    CORE_PKG_FILE="$candidate_pkg_file"
                    CORE_MODE="pkg"
                    break
                fi
            fi
        fi
    done
fi

# 如果包安装方式都失败，回退到裸二进制模式
if [ -z "$CORE_MODE" ]; then
    for candidate in $CANDIDATE_ARCHES; do
        candidate_asset="dashboard-core-${candidate}"
        if download "${BASE_URL}/${candidate_asset}" "${INSTALL_DIR}/${candidate_asset}" 1; then
            ARCH="$candidate"
            CORE_ASSET="$candidate_asset"
            CORE_MODE="binary"
            break
        fi
    done
fi

if [ "$CORE_MODE" = "binary" ]; then
    echo "Using backend architecture: ${ARCH} (binary mode)"
    cp -f "${INSTALL_DIR}/${CORE_ASSET}" "$CORE_BIN"
    chmod 755 "$CORE_BIN"
elif [ "$CORE_MODE" = "pkg" ]; then
    chmod 755 "$CORE_BIN" 2>/dev/null || true
else
    echo "No compatible dashboard-core asset found for candidates: ${CANDIDATE_ARCHES}" >&2
    echo "Set DASHBOARD_CORE_ARCH explicitly, then rerun installer." >&2
    exit 1
fi

write_service
"$CORE_SERVICE" enable
"$CORE_SERVICE" restart

# 安装 LuCI 包
if [ "$CORE_MODE" = "binary" ]; then
    echo "Installing LuCI packages (binary-mode backend)..."
    if [ "$PKG_MGR" = "apk" ]; then
        apk add --force-overwrite --force-non-repository "$LUCI_APP_FILE" "$LUCI_I18N_FILE" || \
            apk add --force-overwrite "$LUCI_APP_FILE" "$LUCI_I18N_FILE"
    else
        if ! opkg install --force-reinstall --force-depends "$LUCI_APP_FILE" "$LUCI_I18N_FILE"; then
            opkg install --force-depends "$LUCI_APP_FILE" "$LUCI_I18N_FILE"
        fi
    fi
else
    pkg_install "$LUCI_APP_FILE" "$LUCI_I18N_FILE"
fi
"$CORE_SERVICE" restart

rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null || true

echo "luci-app-dashboard installed."
echo "dashboard-core is listening on ${CORE_LISTEN}."
