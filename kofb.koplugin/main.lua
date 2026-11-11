--[[--
kofb.koplugin — 「网页文件管理器 2」的 KOReader 快捷方式（v1.0.5）

为什么自带桥接脚本，而不是直接调用 KUAL 包的 start.sh / stop.sh：
  * 那两个脚本结尾都会发 com.lab126.hal powerButtonPressed 事件「返回 Kindle 桌面」，
    并用 eips 直接写帧缓冲显示 IP。KOReader 在前台时，前者会把 KOReader 踢到后台，
    后者会被 KOReader 的界面重绘覆盖（甚至反过来破坏 KOReader 画面）。
  * 因此本插件改由自带的 fb_bridge.sh 完成启停：只做 防休眠 / 放行 80 端口 /
    后台拉起 filebrowser 二进制，绝不回桌面、绝不写 eips、不拉起会写屏的 idle.sh。
  * IP 用 KOReader 自己的菜单右侧值 / 弹窗显示，天然避开帧缓冲冲突。
  * 桥接脚本只依赖 Kindle 系统接口与现有包里的 filebrowser 二进制 / filebrowser.db，
    不 source lib.sh、不调用 start.sh，因此 KUAL 插件包后续升级不会破坏本插件。

本插件只是「快捷方式」，不含核心程序：依附项目开源地址与当前状态见菜单
「状态 / IP / 关于」，仅安装本插件的人员可据此补全依赖。

「快捷方式」体现在 Dispatcher：注册了 3 个动作，可在
  设置 → 手势 / 物理按键 / 快捷面板 里绑定到任意触发方式。
--]]--

local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")

-- 长文本（依附项目地址 + 当前状态）用可滚动的 TextViewer 展示；
-- 老版本 KOReader 无该模块时自动回退到 InfoMessage，不影响插件加载。
local ok_tv, tv_module = pcall(require, "ui/widget/textviewer")
local TextViewer = (ok_tv and type(tv_module) == "table") and tv_module or nil

local PLUGIN_VERSION = "1.0.5"

-- 依附项目开源地址：仅安装本插件的人员按此处补全依赖
local URL_KUAL_EXT = "https://github.com/Gh9518/kindle-filebrowser-optimized"
local URL_CORE     = "https://github.com/filebrowser/filebrowser"
local URL_KUAL     = "https://github.com/NiLuJe/KUAL"
local URL_KOREADER = "https://github.com/koreader/koreader"
local URL_TUTORIAL = "https://bookfere.com/post/823.html"

local KOFileBrowser = WidgetContainer:extend{
    name = "kofb",
    is_doc_only = false,   -- 文件管理器与阅读器界面都可用
}

-- 取插件自身目录：优先 debug 得到的真实路径，再按候选目录校验 fb_bridge.sh 是否存在
local function plugin_dir()
    local candidates = {}
    local ok, src = pcall(function() return debug.getinfo(1, "S").source end)
    if ok and src and src:sub(1, 1) == "@" then
        local d = src:match("^@(.*/)")
        if d then candidates[#candidates + 1] = d end
    end
    candidates[#candidates + 1] = "/mnt/us/koreader/plugins/kofb.koplugin/"
    candidates[#candidates + 1] = "/mnt/base-us/koreader/plugins/kofb.koplugin/"
    for _, d in ipairs(candidates) do
        local f = io.open(d .. "fb_bridge.sh", "r")
        if f then
            f:close()
            return d
        end
    end
    return candidates[1] or "/mnt/us/koreader/plugins/kofb.koplugin/"
end

local BRIDGE = plugin_dir() .. "fb_bridge.sh"

local function shquote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- 同步执行并取回 stdout（status / ip / dir / stop 这类快速命令）
local function capture(args)
    local cmd = "sh " .. shquote(BRIDGE) .. " " .. args .. " 2>/dev/null"
    local h = io.popen(cmd)
    if not h then return "" end
    local out = h:read("*a") or ""
    h:close()
    return (out:gsub("%s+$", ""))
end

-- 后台执行（start 内部有短轮询等端口就绪，放后台避免阻塞 KOReader 的 UI 线程）
local function spawn(args)
    os.execute("sh " .. shquote(BRIDGE) .. " " .. args .. " >/dev/null 2>&1 &")
end

function KOFileBrowser:onDispatcherRegisterActions()
    Dispatcher:registerAction("kofb_start", {
        category = "none", event = "KOFBStart",
        title = _("网页文件管理器：启动"), general = true,
    })
    Dispatcher:registerAction("kofb_stop", {
        category = "none", event = "KOFBStop",
        title = _("网页文件管理器：关闭"), general = true,
    })
    Dispatcher:registerAction("kofb_ip", {
        category = "none", event = "KOFBShowIP",
        title = _("网页文件管理器：状态 / IP"), general = true,
    })
end

function KOFileBrowser:init()
    logger.dbg("kofb: bridge =", BRIDGE)
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function KOFileBrowser:addToMainMenu(menu_items)
    menu_items.kofb_filebrowser = {
        text = _("网页文件管理器 2"),
        -- 一级菜单：tools 是「工具」标签页本身（阅读器 / 文件管理器都存在）。
        -- 官方 menusorter.lua 会给该 tab 打 id="tools" 并把本项 insert 到其一级列表；
        -- 旧值 more_tools 是工具页下的「更多工具」子菜单，需多点一层；
        -- 不带 sorting_hint 则会被当成 orphan 丢进第一个标签页并加 "NEW: " 前缀。
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("启动"),
                -- 把 IP 直接显示在「启动」后面（菜单右侧值），无需再点任何子项。
                -- KOReader 每次展开菜单会调用 mandatory_func 取一次状态与 IP。
                mandatory_func = function()
                    if capture("status") ~= "on" then return _("未启动") end
                    local ip = capture("ip")
                    if ip == "" or ip == "Offline" or ip:find("FB_ERR") then
                        return _("未联网")
                    end
                    return ip
                end,
                callback = function() self:onFBStart() end,
            },
            {
                text = _("关闭"),
                callback = function() self:onFBStop() end,
            },
            {
                -- 合并项：当前状态 + 依附项目开源地址，一次点开看全。
                text = _("状态 / IP / 关于"),
                -- 右侧显示版本号，便于在设备上直接确认装的是哪一版（防旧包缓存）
                mandatory = "v" .. PLUGIN_VERSION,
                callback = function() self:showAbout() end,
            },
        },
    }
end

function KOFileBrowser:onFBStart()
    if capture("status") == "on" then
        -- 服务已在跑（例如先在 KUAL 里启动过）：只接管，停掉会写 eips 的守护，
        -- 然后居中提示当前 IP 即可（默认 80 端口，不显示端口号）。
        spawn("quiet")
        local ip = capture("ip")
        local text = (ip == "" or ip == "Offline" or ip:find("FB_ERR"))
            and _("服务已在运行，但当前未联网。")
            or  _("当前 IP：http://") .. ip
        self:showMessage(text, 5)
        return
    end
    spawn("start")
    local start_msg = InfoMessage:new{
        text = _("正在后台启动网页文件管理器…\nKOReader 保持在当前页面。"),
        align = "center",
    }
    UIManager:show(start_msg)
    -- 桥接脚本内部会等 80 端口就绪（最长约 8 秒），这里轮询到就绪或超时再弹结果，
    -- 避免「正在启动」还没结束就误报失败；每 2 秒查一次，最多约 10 秒。
    self:_pollStart(start_msg, 0)
end

-- 轮询启动结果：就绪则弹成功/未联网提示（5 秒自动关闭），超时则弹安装依赖提示（5 秒）
function KOFileBrowser:_pollStart(start_msg, n)
    if capture("status") == "on" then
        UIManager:close(start_msg)
        self:showStartResult()
        return
    end
    if n >= 5 then
        UIManager:close(start_msg)
        self:showStartResult()
        return
    end
    UIManager:scheduleIn(2, function()
        self:_pollStart(start_msg, n + 1)
    end)
end

function KOFileBrowser:showStartResult()
    local st = capture("status")
    local text
    if st ~= "on" then
        text = _("启动失败：未能启动「网页文件管理器 2」核心程序。\n\n")
            .. _("请先安装 KUAL 扩展包「网页文件管理器 2」并让核心程序就位，\n再回来点「启动」；依赖项目开源地址见菜单「状态 / IP / 关于」。")
    else
        local ip = capture("ip")
        if ip == "" or ip == "Offline" or ip:find("FB_ERR") then
            text = _("网页文件管理器已启动，但当前未联网。\n连上 WiFi 后，菜单「启动」右侧会显示本机 IP。")
        else
            -- 默认访问就是 80 端口，URL 不写端口号，整段居中显示
            text = _("网页文件管理器已启动\n\n请在浏览器访问：\n\nhttp://") .. ip
        end
    end
    -- 成功与失败都只显示 5 秒后自动关闭，不再多弹窗
    self:showMessage(text, 5)
end

function KOFileBrowser:onFBStop()
    local r = capture("stop")
    local ok = (r == "stopped")
    -- 关闭只提示是否成功：成功 2 秒后自动关闭，失败提示重试（5 秒）
    self:showMessage(ok and _("网页文件管理器已关闭。") or _("关闭失败，请稍后重试。"), ok and 2 or 5)
end

-- 自动关闭的简短弹窗（timeout 秒后由 KOReader 自动关闭），用于启动结果 / 关闭结果；文字居中
function KOFileBrowser:showMessage(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, show_icon = false, timeout = timeout, align = "center" })
end

-- 手动查看当前状态 / IP（菜单「状态 / IP / 关于」点击、手势「状态 / IP」、以及「服务已在运行」时使用）
function KOFileBrowser:showInfo(prefix)
    local st = capture("status")
    local ip = capture("ip")
    local text
    if st ~= "on" then
        text = _("服务尚未就绪或未启动。\n\n请先安装 KUAL 扩展包并让核心程序就位，\n再回来点「启动」；依附项目地址与当前状态见「状态 / IP / 关于」。")
    elseif ip == "" or ip == "Offline" or ip:find("FB_ERR") then
        text = _("服务已启动，但当前未联网。\n连上 WiFi 后，菜单「启动」右侧会显示本机 IP。")
    else
        text = _("网页文件管理器已启动\n\n请在浏览器访问：\n\nhttp://")
            .. ip .. ":80\n\n" .. _("注意用 http://，不要用 https://。")
    end
    if prefix then
        text = prefix .. "\n\n" .. text
    end
    UIManager:show(InfoMessage:new{ text = text, show_icon = false })
end

-- 合并后的「状态 / IP / 关于」：当前状态 + 依附项目开源地址
function KOFileBrowser:showAbout()
    local st = capture("status")
    local ip = capture("ip")
    local d = capture("dir")
    local state_line
    if st ~= "on" then
        state_line = _("服务：未启动")
    elseif ip == "" or ip == "Offline" or ip:find("FB_ERR") then
        state_line = _("服务：运行中，但当前未联网")
    else
        state_line = _("服务：运行中　访问：http://") .. ip .. ":80"
    end

    local text = table.concat({
        _("网页文件管理器 2 · KOReader 快捷方式 v") .. PLUGIN_VERSION,
        "",
        _("【当前状态】"),
        state_line,
        _("KUAL 扩展目录：") .. (d ~= "" and d or _("未找到（可在 fb_bridge.sh 顶部设 FB_HOME）")),
        "",
        _("【依赖项目 · 仅装本插件者请先备齐】"),
        _("1) KUAL 扩展包「网页文件管理器 2」（必装，提供核心程序）"),
        "   " .. URL_KUAL_EXT,
        _("2) 核心程序 filebrowser（开源上游项目）"),
        "   " .. URL_CORE,
        _("3) KUAL 启动器"),
        "   " .. URL_KUAL,
        _("4) KOReader 本体"),
        "   " .. URL_KOREADER,
        _("原始教程：") .. URL_TUTORIAL,
    }, "\n")

    if TextViewer then
        UIManager:show(TextViewer:new{
            title = _("网页文件管理器 2 · 状态 / IP / 关于"),
            text = text,
        })
    else
        -- 老版本无 TextViewer：退化为普通弹窗，内容一致（可能需滚动查看）
        UIManager:show(InfoMessage:new{ text = text, show_icon = false })
    end
end

-- Dispatcher 事件入口（可绑到手势 / 物理按键 / 快捷面板）
function KOFileBrowser:onKOFBStart()   self:onFBStart()   end
function KOFileBrowser:onKOFBStop()    self:onFBStop()    end
function KOFileBrowser:onKOFBShowIP()  self:showInfo(nil) end

return KOFileBrowser
