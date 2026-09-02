# luci-app-tcpdump

一个运行在 OpenWrt 上的 LuCI 抓包工具，底层调用 tcpdump，在 Web 页面中完成启动、停止、状态查看和 pcap 下载。

## 功能

- 选择抓包接口，支持 `any`
- 输入 BPF 过滤条件
- 可选包数量上限和 snaplen
- 支持开启或关闭混杂模式
- 后台抓包并下载生成的 pcap 文件
- 支持中文和英文界面文案

## 语言支持

- English: default fallback language
- 中文: follows the LuCI language setting or browser language when it is Chinese

独立打包产物已经内置双语文案，不依赖额外的 LuCI 翻译编译步骤。

## 目录结构

- `Makefile`: OpenWrt/LuCI 包定义
- `luasrc/controller/tcpdump.lua`: LuCI 控制器与接口
- `luasrc/view/tcpdump/index.htm`: LuCI 页面模板
- `root/usr/bin/luci-tcpdump`: 后台抓包脚本

## 使用方式

1. 将本目录放入 OpenWrt SDK 或源码树中的 LuCI 包路径。
2. 选择并编译 `luci-app-tcpdump`。
3. 安装 ipk 后，在 LuCI 的 `Services -> Tcpdump` 中使用。

如果当前目录不是完整的 OpenWrt 构建树，也可以直接运行 `./build_ipk.sh` 在本地生成 ipk。

## 注意事项

- 运行依赖 `tcpdump`。
- 抓包文件默认输出到 `/tmp/luci-tcpdump.pcap`。
- 后台进程 pid 默认记录在 `/var/run/luci-tcpdump.pid`。

## 独立打包

运行以下命令会在 `dist/` 下生成一个通用架构的 ipk：

```sh
./build_ipk.sh
```