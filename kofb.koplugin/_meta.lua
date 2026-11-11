local _ = require("gettext")

-- 网页文件管理器 2 · KOReader 快捷方式
-- 安装：把整个 kofb.koplugin 目录放进 koreader/plugins/，重启 KOReader。
-- 卸载：删除该目录并重启即可，不改动 KOReader 本体，也不改动 KUAL 插件包。
-- 依赖：本插件只是快捷方式，需先安装 KUAL 扩展包「网页文件管理器 2」提供核心程序；
--       依附项目开源地址与当前状态见插件菜单「状态 / IP / 关于」。
return {
    name = "kofb",
    fullname = _("网页文件管理器 2（快捷方式）"),
    description = _([[在 KOReader 菜单里直接启动 / 关闭 Kindle 网页文件管理器，并把本机 IP 显示在「启动」后面。启动时 KOReader 保持在前台，不返回桌面、不改写屏幕帧缓冲。
注意：本插件仅为快捷方式，不含核心程序，需先安装 KUAL 扩展包「网页文件管理器 2」；依附项目开源地址与当前状态见菜单「状态 / IP / 关于」。]]),
    version = "1.0.5",
}
