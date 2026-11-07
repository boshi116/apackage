# quickfile 2.0.9 — OpenWrt 轻量级 Web 文件管理器

基于上游 [sbwml/luci-app-quickfile](https://github.com/sbwml/luci-app-quickfile) 源码自行编译的
aarch64-musl 静态二进制 + 可直接安装的安装包（**ipk / apk 两种格式**）。

## 安装包

### opkg 格式（OpenWrt ≤ 24.10 / 第三方固件）—— `ipk/` 目录

| 文件 | 架构 | 说明 |
|---|---|---|
| `quickfile_2.0.9-1_aarch64_cortex-a53.ipk` | aarch64_cortex-a53 | 主包：二进制 + init 脚本 + LuCI 菜单/视图/ACL + nginx 反代配置 |
| `quickfile_2.0.9-1_aarch64_generic.ipk` | aarch64_generic | 同上（架构元数据不同） |
| `quickfile_2.0.9-1_x86_64.ipk` | x86_64 | 同上 |
| `luci-i18n-quickfile-zh-cn_26.143.10947_all.ipk` | all | 中文语言包（可选） |

```sh
opkg install quickfile_2.0.9-1_aarch64_cortex-a53.ipk
opkg install luci-i18n-quickfile-zh-cn_26.143.10947_all.ipk
```

### apk 格式（OpenWrt 25.12+ 官方版）—— `apk/` 目录

| 文件 | 架构 | 说明 |
|---|---|---|
| `quickfile-2.0.9-r1-aarch64_cortex-a53.apk` | aarch64_cortex-a53 | 主包（含 post-install 自动启动脚本） |
| `quickfile-2.0.9-r1-aarch64_generic.apk` | aarch64_generic | 同上 |
| `quickfile-2.0.9-r1-x86_64.apk` | x86_64 | 同上 |
| `luci-i18n-quickfile-zh-cn-26.143.10947-r1.apk` | noarch | 中文语言包 |

```sh
apk add --allow-untrusted quickfile-2.0.9-r1-aarch64_generic.apk
apk add --allow-untrusted luci-i18n-quickfile-zh-cn-26.143.10947-r1.apk
```

> `--allow-untrusted` 是因为包未用 OpenWrt 官方私钥签名。若要放进官方源分发，需自行签名。

### 架构与二进制的对应关系

| 架构 | Rust target | 二进制大小 | 说明 |
|---|---|---|---|
| aarch64_cortex-a53 | `aarch64-unknown-linux-musl` | 20.3 MB | 静态链接，真静态（0 NEEDED / 0 INTERP） |
| aarch64_generic | `aarch64-unknown-linux-musl` | 20.3 MB | **与上者共用同一二进制**，仅包元数据 arch 不同 |
| x86_64 | `x86_64-unknown-linux-musl` | 21.1 MB | static-pie 链接（0 NEEDED / 0 INTERP） |

> `aarch64_cortex-a53` 与 `aarch64_generic` 的**二进制完全相同**（ARMv8 指令集兼容），
> 区别只在 ipk/apk 的 `Architecture` 字段，用来匹配各自的软件源。

### 其它文件

| 文件 | 说明 |
|---|---|
| `build_all.sh` | **统一打包脚本**，一次产出 ipk + apk × 任意架构 |
| `quickfile.zh_Hans.po` | 上游中文翻译源文件 |
| `po2lmo` | LuCI 官方 lmo 生成器（x86_64 Linux 可执行文件） |

装完即可用：LuCI 侧边栏 **系统选项 → 文件管理**。

> **装了语言包菜单还是英文？** 见下方「语言包不生效的原因」——必须用 `po2lmo` 生成 lmo，
> 不能用系统的 `msgfmt`。

## 已验证设备

| 设备 | 固件 | 包管理器 | 安装格式 | 结果 |
|---|---|---|---|---|
| Huasifei WH3000 Pro (MT7986) | Padavanonly Immortalwrt 24.10 | opkg | ipk (cortex-a53) | ✅ 自动启动、nginx 同源模式、菜单中文 |
| **mu300 (展锐 UMS9620)** | **OpenWrt 25.12.5 官方版** | **apk 3.0.5** | apk (aarch64_generic) | ✅ 自动启动、direct 直连模式、菜单中文 |

两台设备的差异（包管理器、架构名、Web 服务、LuCI 版本）都已适配：

- **apk vs opkg**：OpenWrt 25.12 官方改用 apk v3（ADB 格式），**完全不认 ipk**
  （报 `v2 package format error`）。需用 apk-tools 的 `apk mkpkg` 重新打包。
- **架构名**：`aarch64_cortex-a53` → `aarch64_generic`（包元数据需改）。
- **uhttpd 设备**：无 nginx，init 脚本的 `auto` 模式自动切到 `direct`（独立端口 8090）。
- **LuCI 视图回退**：uhttpd 上同源路径返回 404（不是 401），视图改用 XHR 探测状态码，
  404/401/网络错误都回退到直连端口。

## 语言包不生效的原因（重要）

**症状**：语言包装上了，文件也到位了，但 LuCI 侧边栏菜单仍显示英文 `Quick File Manager`，
而其它菜单（系统选项、服务选项）正常显示中文。

**根因**：LuCI 25.x（>= 24.x）**不再使用标准 GNU gettext 的 .mo 格式**，而是用自研的
紧凑 lmo 格式，**msgid 以 8 位十六进制哈希字符串存储**，而不是明文。

对比三个文件的头部就能看出来：

| 文件 | 格式 | msgid 部分 |
|---|---|---|
| 官方 `luci-i18n-quickfile-zh-cn` 的 lmo（32 B） | LuCI 紧凑格式 | `6f0e3340` |
| `luci-i18n-base-zh-cn` 的 lmo（128 KB） | LuCI 紧凑格式 | 同上机制 |
| `msgfmt` 生成的 lmo（154 B） | GNU gettext 明文 | `Quick File Manager` |

而 `6f0e3340` 正是 `hash("Quick File Manager")` 的值（LuCI 的 `sfh_hash` 算法，
实现在 `modules/luci-base/src/lib/lmo.c`）。

前端查表逻辑（`/www/luci-static/resources/cbi.js`）：

```js
function _(s, c) {
    var k = (c != null ? trimws(c) + '\u0001' : '') + trimws(s);
    return (window.TR && TR[sfh(k)]) || s;   // ← 用哈希查，不是明文
}
```

翻译字典由服务端端点 `/cgi-bin/luci/admin/translations/<lang>` 下发，
key 同样全是 `6f0e3340` 这种哈希串。所以用 `msgfmt` 生成的明文 lmo
LuCI 根本查不到，表现就是"装了但没反应"。

**正确做法**：用 LuCI 官方生成器 `po2lmo` 编译 .po：

```sh
# 1. 拿到 LuCI 源码里的官方生成器
git clone --depth 1 https://github.com/openwrt/luci.git
cd luci/modules/luci-base/src
make po2lmo          # 需要 lemon（Makefile 里会自动编）

# 2. 编译 .po → lmo
./po2lmo quickfile.zh_Hans.po quickfile.zh-cn.lmo

# 3. 装到设备
#    /usr/lib/lua/luci/i18n/quickfile.zh-cn.lmo
```

本包内的 `po2lmo` 就是官方源码编译出来的产物（x86_64 Linux 可执行）。
用它生成的 lmo 与官方发布的 lmo **逐字节一致**（md5 `ceb7c40b729b94ceec981dc2f3f5bece`）。

**装完还要重启 LuCI 让 catalog 重新加载**（lmo 是进程启动时扫描目录载入的）：

```sh
/etc/init.d/uwsgi restart      # 或 /etc/init.d/uhttpd restart
rm -f /tmp/luci-indexcache*    # 清 LuCI 菜单索引缓存
```

> 顺带说明：LuCI 界面语言由浏览器 `Accept-Language` 决定，请求的是
> `/cgi-bin/luci/admin/translations/<lang>`。若浏览器发的是 `en-US`，
> 端点就返回英文（内容为空 `window.TR={};`），菜单自然是英文 —— 这跟语言包无关。

## 两种运行模式（自动选择）

配置文件：`/etc/config/quickfile`

```
config quickfile 'main'
	option mode 'auto'      # auto | nginx | direct
	option port '8090'
```

| 模式 | 场景 | 工作方式 |
|---|---|---|
| `auto`（默认） | 自动判断 | 装了 nginx 就走 nginx 同源反代；否则走独立端口 |
| `nginx` | 有 nginx | unix socket + nginx 反代（同源 443） |
| `direct` | **uhttpd 设备** | 独立 TCP 端口（默认 8090）直连，**不需要 nginx** |

切换方式：`uci set quickfile.main.mode='direct' && uci commit quickfile && /etc/init.d/quickfile restart`

## 为什么 uhttpd 设备也能用

关键在 LuCI 会话 cookie 的作用域规则：

- cookie 名 `sysauth_http`（LuCI 走 HTTP 时）**没有 `secure` 属性**
- cookie 的 `Path` 是 `/cgi-bin/luci/`
- **cookie 作用域只按 (domain, path) 匹配，与端口无关**

所以只要 quickfile 的访问路径仍以 `/cgi-bin/luci/` 开头，即使跑在另一个 TCP 端口上，
浏览器也会把 `sysauth_http` 一并送达，鉴权照样通过。

而 `sysauth_https`（LuCI 走 HTTPS 时）带 `secure` 属性，只会发往 HTTPS —— 这种场景
必须用 `nginx` 模式（443 同源）。LuCI 视图已内置自动回退逻辑：**用 XHR 探测同源路径的
HTTP 状态码**，404（uhttpd 未反代）/ 401（会话失效）/ 网络错误，三种情况都自动切到直连端口。

> 注意：早期版本只匹配 iframe 内的「invalid session」文本，但 uhttpd 上同源路径返回的是
> LuCI 的 404 页面（"No page is registered"），导致回退不触发。已改为 XHR 状态码探测。

## 架构说明

quickfile 后端通过本地 `ubus call session get` 校验 LuCI token，**不依赖 nginx**。
但 API 前缀必须保持在 `/cgi-bin/luci/quickfile/api/` 下，才能匹配 LuCI cookie 的 Path。

2.0.9 原生支持自定义 API/Static 前缀（同时注册 `/api/` 与自定义前缀），所以 nginx 配置
不需要任何 `rewrite`。

## 已验证功能

- 文件浏览（列表/网格）、排序、分页流式加载
- 上传（拖拽/粘贴）、下载、重命名、删除、复制/剪切/粘贴
- 新建目录/文件、chmod 权限修改、属性查看、MD5/SHA-256 校验
- 内置代码编辑器（CodeMirror 6，40+ 语言高亮、UCI/ucode 语法）
- 内置终端（xterm.js + WebSocket）
- 压缩/解压（zip/tar/tar.gz/tar.xz/tar.zst/ipk/apk/img/ext4/squashfs，ZIP AES-256）
- 图片/音视频/PDF/Markdown 预览
- IPK/APK 在线安装、`ipk2apk` 转换（Rust 独立实现，无需 apk-tools）

## 重新编译

在 Linux 环境（**不要在 Windows 上编**，`std::path::MAIN_SEPARATOR` 会导致路径处理出 bug）：

```sh
# 1. 源码
curl -LO https://r2.cooluc.com/source/quickfile-src-2.0.9.tar.xz
tar xf quickfile-src-2.0.9.tar.xz && cd quickfile-src-2.0.9

# 2. 工具链
rustup toolchain install 1.95.0
rustup target add --toolchain 1.95.0 aarch64-unknown-linux-musl
# musl 交叉编译器
curl -LO https://musl.cc/aarch64-linux-musl-cross.tgz && tar xzf aarch64-linux-musl-cross.tgz

# 3. 编译
export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=/tmp/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc
export CC_aarch64_unknown_linux_musl=/tmp/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc
export AR_aarch64_unknown_linux_musl=/tmp/aarch64-linux-musl-cross/bin/aarch64-linux-musl-ar
export RANLIB_aarch64_unknown_linux_musl=/tmp/aarch64-linux-musl-cross/bin/aarch64-linux-musl-ranlib
cargo build --release --target aarch64-unknown-linux-musl

# 4. 打包
bash build_ipk.sh target/aarch64-unknown-linux-musl/release/quickfile ./out
```

> **依赖注意**：`shuck-*` 0.2.3 要求 rustc ≥ 1.94.1，需用 1.95.0 并
> `cargo update shuck-ast shuck-formatter shuck-indexer shuck-parser --precise 0.2.3`。

### 编译 x86_64

x86_64 是宿主架构时**不能直接用系统的 `musl-gcc`** —— 它默认动态链接，产物会带
`INTERP /lib/ld-musl-x86_64.so.1`，在 OpenWrt 上因缺少 musl 运行时而无法启动。
必须用 musl.cc 的交叉工具链（默认静态）：

```sh
rustup target add x86_64-unknown-linux-musl
curl -LO https://musl.cc/x86_64-linux-musl-cross.tgz
tar xzf x86_64-linux-musl-cross.tgz

export PATH="$HOME/.cargo/bin:$PATH"
TC=/path/to/x86_64-linux-musl-cross/bin
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=$TC/x86_64-linux-musl-gcc
export CC_x86_64_unknown_linux_musl=$TC/x86_64-linux-musl-gcc
export CXX_x86_64_unknown_linux_musl=$TC/x86_64-linux-musl-g++
export AR_x86_64_unknown_linux_musl=$TC/x86_64-linux-musl-ar
export RANLIB_x86_64_unknown_linux_musl=$TC/x86_64-linux-musl-ranlib
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_RUSTFLAGS="-C target-feature=+crt-static"
cargo build --release --target x86_64-unknown-linux-musl

# 验证: 0 个 NEEDED + 0 个 INTERP 才是真静态
readelf -d target/x86_64-unknown-linux-musl/release/quickfile | grep -c NEEDED
readelf -l target/x86_64-unknown-linux-musl/release/quickfile | grep -c INTERP
```

aarch64 的交叉工具链同样来自 musl.cc（`aarch64-linux-musl-cross.tgz`），
配置变量名把 `X86_64` 换成 `AARCH64` 即可。

## 换架构

改 `build_ipk.sh` 里的 `ARCH` 变量，并在对应架构的 Linux 上重新编译即可。
二进制是静态链接的，不依赖目标机任何库。

## 打包成 apk（OpenWrt 25.12+）

OpenWrt 25.12 官方改用 **apk v3（ADB 格式）**，**不认 ipk**：

```
$ apk add --allow-untrusted quickfile.ipk
ERROR: quickfile.ipk: v2 package format error
```

### 用统一脚本（推荐）

`build_all.sh` 一次产出 ipk + apk × 任意架构：

```sh
# 依赖(环境变量可覆盖):
#   APK_MKPKG  apk-tools 的 apk 二��� (含 mkpkg 子命令)
#   PO2LMO    luci 官方 po2lmo 生成器
#   PO_FILE   中文翻译 .po 文件
export APK_MKPKG=/tmp/apk-tools/build/src/apk
export PO2LMO=/tmp/luci-src/modules/luci-base/src/po2lmo
export PO_FILE=/tmp/qf.po

bash build_all.sh \
  /tmp/quickfile-src-2.0.9/target/aarch64-unknown-linux-musl/release/quickfile \
  ./out \
  aarch64_cortex-a53 aarch64_generic x86_64
```

输出：

```
out/quickfile_2.0.9-1_aarch64_cortex-a53.ipk
out/quickfile_2.0.9-1_aarch64_generic.ipk
out/quickfile_2.0.9-1_x86_64.ipk
out/quickfile-2.0.9-r1-aarch64_cortex-a53.apk
out/quickfile-2.0.9-r1-aarch64_generic.apk
out/quickfile-2.0.9-r1-x86_64.apk
out/luci-i18n-quickfile-zh-cn_26.143.10947_all.ipk
out/luci-i18n-quickfile-zh-cn-26.143.10947-r1.apk
```

### 手动打 apk

```sh
# 1. 编译 apk-tools（需要 meson >= 0.64、ninja）
git clone --depth 1 https://github.com/alpinelinux/apk-tools.git
cd apk-tools && meson setup build && ninja -C build
# 产物: build/src/apk （内含 mkpkg 子命令）

# 2. 准备打包根目录（目录结构即包内路径）
mkdir -p apkroot/{etc/config,etc/init.d,etc/nginx/conf.d,usr/bin,usr/share/luci/menu.d,\
usr/share/rpcd/acl.d,www/luci-static/resources/view/system}
cp target/aarch64-unknown-linux-musl/release/quickfile apkroot/usr/bin/
cp etc/init.d/quickfile apkroot/etc/init.d/
cp etc/config/quickfile apkroot/etc/config/
cp etc/nginx/conf.d/quickfile.locations apkroot/etc/nginx/conf.d/
cp usr/share/luci/menu.d/luci-app-quickfile.json apkroot/usr/share/luci/menu.d/
cp usr/share/rpcd/acl.d/luci-app-quickfile.json apkroot/usr/share/rpcd/acl.d/
cp www/luci-static/resources/view/system/quickfile.js apkroot/www/luci-static/resources/view/system/

# 3. 关键：属主必须是 root，且权限正确
chown -R root:root apkroot
find apkroot -type d -exec chmod 755 {} \;
chmod 755 apkroot/usr/bin/quickfile apkroot/etc/init.d/quickfile
chmod 644 apkroot/etc/config/quickfile apkroot/usr/share/luci/menu.d/*.json \
          apkroot/usr/share/rpcd/acl.d/*.json \
          apkroot/www/luci-static/resources/view/system/quickfile.js \
          apkroot/etc/nginx/conf.d/quickfile.locations

# 4. 打包（-I 的值不能含 ':'，description 里也不能有冒号）
cd apkroot
../apk-tools/build/src/apk --root=. mkpkg --no-xattrs \
  -I name:quickfile \
  -I version:2.0.9-r1 \
  -I description:"Lightweight web-based file manager for OpenWrt, built with Rust and Vue3" \
  -I arch:aarch64_generic \
  -I license:Apache-2.0 \
  -I origin:package/quickfile \
  -I maintainer:"sbwml <admin@cooluc.com>" \
  -I url:https://github.com/sbwml/luci-app-quickfile \
  -I depends:libc \
  -s post-install:/path/to/post-install.sh \
  -s pre-deinstall:/path/to/pre-deinstall.sh \
  -F . -o ../quickfile-2.0.9-r1-aarch64_generic.apk
```

**几个 apk v3 的坑**：

| 问题 | 说明 |
|---|---|
| `installed-size` 不能手动设 | 由 mkpkg 自动计算，设了会报 `invalid info field` |
| `-I` 的值不能含 `:` | `apk_blob_split` 用 `:` 切 key/value，description 里有冒号会被误解析 |
| 版本号格式 | apk 必须用 `2.0.9-r1`（`x.y.z-rN`）；`2.0.9-1` 会被判 `package version is invalid`（opkg 的 ipk 用 `-1` 即可） |
| 属主必须是 root | 打包机若非 root 用户，mkpkg 会记成 nobody（用 `--root=.` 跑在 root 下可避免） |
| 需 install script | apk v3 不像 ipk 有 postinst，**必须用 `-s post-install:xxx.sh` 显式附加** |

`post-install` 脚本模板（与官方 luci 包一致）：

```sh
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="quickfile"
default_postinst
[ -n "${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
	/etc/init.d/quickfile enable 2>/dev/null
	/etc/init.d/quickfile restart 2>/dev/null
	exit 0
}
```

校验包内容：`apk adbdump quickfile-2.0.9-r1-aarch64_generic.apk`

## 卸载

opkg 设备：

```sh
opkg remove luci-i18n-quickfile-zh-cn
opkg remove quickfile
```

apk 设备：

```sh
apk del luci-i18n-quickfile-zh-cn
apk del quickfile
```

pre-deinstall 脚本会自动停服务、关自启、清除 LuCI 菜单缓存。
ipk 版本的 postrm 会额外清理 nginx 的 `quickfile.locations` 并 reload nginx。
