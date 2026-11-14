local GetText = require("gettext")

-- 按系统语言返回中文或英文（与 main.lua 同一判定逻辑）
local function T(en, cn)
    local l = GetText.current_lang
        or os.getenv("LANG") or os.getenv("LC_ALL") or os.getenv("LANGUAGE") or ""
    return l:match("zh") and cn or en
end

-- 网页文件管理器 2 · KOReader 快捷方式
-- 安装：把整个 kofb.koplugin 目录放进 koreader/plugins/，重启 KOReader。
-- 卸载：删除该目录并重启即可，不改动 KOReader 本体，也不改动 KUAL 插件包。
-- 依赖：本插件只是快捷方式，需先安装 KUAL 扩展包「网页文件管理器 2」提供核心程序；
--       依附项目开源地址与当前状态见插件菜单「状态 / IP / 关于」。
return {
    name = "kofb",
    fullname = T("Web File Browser 2 (Shortcut)", "网页文件管理器 2（快捷方式）"),
    description = T(
        "Start or stop Kindle's Web File Browser directly from the KOReader menu, with the device IP shown next to \"Start\". "
        .. "KOReader stays in the foreground — no return to the home screen, no framebuffer writes.\n"
        .. "Note: this plugin is only a shortcut with no core program; install the KUAL extension \"Web File Browser 2\" first. "
        .. "Upstream links and current status are in the \"Status / IP / About\" menu.",
        "在 KOReader 菜单里直接启动 / 关闭 Kindle 网页文件管理器，并把本机 IP 显示在「启动」后面。启动时 KOReader 保持在前台，不返回桌面、不改写屏幕帧缓冲。\n"
        .. "注意：本插件仅为快捷方式，不含核心程序，需先安装 KUAL 扩展包「网页文件管理器 2」；依附项目开源地址与当前状态见菜单「状态 / IP / 关于」。"),
    version = "1.0.7",
}
