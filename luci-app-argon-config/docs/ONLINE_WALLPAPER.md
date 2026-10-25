# 在线壁纸筛选

2.1.0 为独立插件页面增加筛选设置，使用 Argon 2.4.8 已有的壁纸 RPC 协议。Argon 3 带内置设置时仍隐藏独立插件入口。

| 设置 | 用法 |
| --- | --- |
| Unsplash 合集 ID | 可填写一个或多个公开合集 ID，用逗号分隔，支持字母、数字、下划线和短横线；不要填写合集网址 |
| Unsplash Access Key | 必填，使用 Unsplash 应用的 Access Key |
| Wallhaven 标签 ID | 一个正整数，例如 `37`；不是 `yqg6r7` 这样的壁纸 ID |
| Wallhaven API 密钥 | 设置标签后可选；与 Unsplash 共用主题的 `use_api_key` 配置项，切换服务时请填写对应服务的密钥 |
| Wallhaven 精确分辨率 | 设置标签后可用；开启为精确 1920×1080，关闭为至少 1920×1080 |

留空合集／标签会恢复该来源的随机模式。主题的普通 Wallhaven 随机模式固定使用精确 1920×1080，不读取 API Key 或最低分辨率选项，因此这两个控件仅在填写数字标签后显示。当前主题接口没有实现多个标签 ID 的组合搜索，界面不接受逗号分隔的 Wallhaven 标签。

配置保存为主题原本支持的 `online_wallpaper=unsplash_317099` 或 `wallhaven_37`，并在独立的辅助配置项里记住另一来源的筛选值。解析按实际 UCI 匿名节读取；保存时即使只改筛选值、不改来源，也会更新主题读取的编码设置。

在线图片获取、失败回退和缓存仍由主题处理。修改密钥或分辨率不会强制清除主题已有的缓存 URL，已有缓存可能继续使用，直到主题下一次请求新图片。该插件不会修改主题文件。

开发验证使用真实 LuCI、UCI 和 Argon 2.4.8 的 RPC，外部 HTTP 响应使用模拟数据，不需要真实密钥或访问外部壁纸服务。可用 `tests/wallpaper-browser.cjs` 验证表单保存和重载，用 `tests/wallpaper-provider.sh` 验证主题生成的查询参数；只在可丢弃的测试实例上执行。

接口参考：[Unsplash 随机图片](https://unsplash.com/documentation#get-a-random-photo)、[Argon 2.4.8 壁纸 RPC](https://github.com/jerrykuku/luci-theme-argon/blob/v2.4.8/root/usr/libexec/rpcd/luci.argon_wallpaper)。
