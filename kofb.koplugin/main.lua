--[[--
kofb.koplugin — 「网页文件管理器 2」的 KOReader 快捷方式（v1.0.6）

UI 文案按系统语言显示：系统为简体中文时显示中文，其它（含英文）显示英文。
判定依据为 KOReader 启动时已加载的 locale（require("gettext").current_lang，
中文为 "zh_CN" 等，英文/未设为 "C"/"en" 等）。

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
local GetText = require("gettext")
local logger = require("logger")

-- 按系统语言返回中文或英文：KOReader 启动时已据系统语言加载对应 locale，
-- GetText.current_lang 为 "zh_CN" 等（中文）或 "C"/"en" 等（英文/其它）。
-- 每次调用都重新判定，可随 KOReader 运行时切换语言即时生效。
local function T(en, cn)
    local l = GetText.current_lang
        or os.getenv("LANG") or os.getenv("LC_ALL") or os.getenv("LANGUAGE") or ""
    return l:match("zh") and cn or en
end

-- 长文本（依赖项目地址 + 当前状态）用可滚动的 TextViewer 展示；
-- 老版本 KOReader 无该模块时自动回退到 InfoMessage，不影响插件加载。
local ok_tv, tv_module = pcall(require, "ui/widget/textviewer")
local TextViewer = (ok_tv and type(tv_module) == "table") and tv_module or nil

local PLUGIN_VERSION = "1.0.6"

-- 依赖项目开源地址：KUAL 扩展包「网页文件管理器 2」（提供核心程序）
local URL_KUAL_EXT = "https://github.com/Gh9518/kindle-filebrowser-optimized"

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
        title = T("Web File Browser: Start", "网页文件管理器：启动"), general = true,
    })
    Dispatcher:registerAction("kofb_stop", {
        category = "none", event = "KOFBStop",
        title = T("Web File Browser: Stop", "网页文件管理器：关闭"), general = true,
    })
    Dispatcher:registerAction("kofb_ip", {
        category = "none", event = "KOFBShowIP",
        title = T("Web File Browser: Status / IP", "网页文件管理器：状态 / IP"), general = true,
    })
end

function KOFileBrowser:init()
    logger.dbg("kofb: bridge =", BRIDGE)
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function KOFileBrowser:addToMainMenu(menu_items)
    menu_items.kofb_filebrowser = {
        text = T("Web File Browser 2", "网页文件管理器 2"),
        -- 一级菜单：tools 是「工具」标签页本身（阅读器 / 文件管理器都存在）。
        -- 官方 menusorter.lua 会给该 tab 打 id="tools" 并把本项 insert 到其一级列表；
        -- 旧值 more_tools 是工具页下的「更多工具」子菜单，需多点一层；
        -- 不带 sorting_hint 则会被当成 orphan 丢进第一个标签页并加 "NEW: " 前缀。
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = T("Start", "启动"),
                -- 把 IP 直接显示在「启动」后面（菜单右侧值），无需再点任何子项。
                -- KOReader 每次展开菜单会调用 mandatory_func 取一次状态与 IP。
                mandatory_func = function()
                    if capture("status") ~= "on" then return T("Not started", "未启动") end
                    local ip = capture("ip")
                    if ip == "" or ip == "Offline" or ip:find("FB_ERR") then
                        return T("No network", "未联网")
                    end
                    return ip
                end,
                callback = function() self:onFBStart() end,
            },
            {
                text = T("Stop", "关闭"),
                callback = function() self:onFBStop() end,
            },
            {
                -- 合并项：当前状态 + 依赖项目开源地址，一次点开看全。
                text = T("Status / IP / About", "状态 / IP / 关于"),
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
            and T("Service is already running, but currently no network.", "服务已在运行，但当前未联网。")
            or  T("Current IP: http://", "当前 IP：http://") .. ip
        self:showMessage(text, 5)
        return
    end
    spawn("start")
    local start_msg = InfoMessage:new{
        text = T("Starting Web File Browser in the background…\nKOReader stays on the current page.",
                  "正在后台启动网页文件管理器…\nKOReader 保持在当前页面。"),
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
        text = T("Failed to start: could not launch the \"Web File Browser 2\" core program.\n\n",
                 "启动失败：未能启动「网页文件管理器 2」核心程序。\n\n")
            .. T("Please install the KUAL extension \"Web File Browser 2\" and have its core program in place first, "
                  .. "then come back and tap Start; see the menu \"Status / IP / About\" for the dependency's open-source address.",
                 "请先安装 KUAL 扩展包「网页文件管理器 2」并让核心程序就位，\n再回来点「启动」；依赖项目开源地址见菜单「状态 / IP / 关于」。")
    else
        local ip = capture("ip")
        if ip == "" or ip == "Offline" or ip:find("FB_ERR") then
            text = T("Web File Browser has started, but there is no network connection now.\n"
                      .. "After connecting to Wi-Fi, the device IP will appear on the right of the Start menu item.",
                     "网页文件管理器已启动，但当前未联网。\n连上 WiFi 后，菜单「启动」右侧会显示本机 IP。")
        else
            -- 简洁：仅「启动成功，当前IP」，默认 80 端口，不写端口号
            text = T("Started. Current IP: http://", "启动成功，当前IP：http://") .. ip
        end
    end
    -- 成功与失败都只显示 5 秒后自动关闭，不再多弹窗
    self:showMessage(text, 5)
end

function KOFileBrowser:onFBStop()
    local r = capture("stop")
    local ok = (r == "stopped")
    -- 关闭只提示是否成功：成功 2 秒后自动关闭，失败提示重试（5 秒）
    self:showMessage(ok and T("Web File Browser has been stopped.", "网页文件管理器已关闭。")
                          or T("Failed to stop. Please try again later.", "关闭失败，请稍后重试。"),
                     ok and 2 or 5)
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
        text = T("The service is not ready or not started.\n\n"
                  .. "Please install the KUAL extension and have its core program in place first, "
                  .. "then come back and tap Start; see \"Status / IP / About\" for the dependency address and current status.",
                 "服务尚未就绪或未启动。\n\n请先安装 KUAL 扩展包并让核心程序就位，\n再回来点「启动」；依附项目地址与当前状态见「状态 / IP / 关于」。")
    elseif ip == "" or ip == "Offline" or ip:find("FB_ERR") then
        text = T("Web File Browser has started, but there is no network connection now.\n"
                  .. "After connecting to Wi-Fi, the device IP will appear on the right of the Start menu item.",
                 "网页文件管理器已启动，但当前未联网。\n连上 WiFi 后，菜单「启动」右侧会显示本机 IP。")
    else
        text = T("Web File Browser has started\n\nCurrent IP: http://", "网页文件管理器已启动\n\n当前IP：http://") .. ip
    end
    if prefix then
        text = prefix .. "\n\n" .. text
    end
    UIManager:show(InfoMessage:new{ text = text, show_icon = false })
end

-- 合并后的「状态 / IP / 关于」：当前状态 + 依赖项目开源地址
function KOFileBrowser:showAbout()
    local st = capture("status")
    local ip = capture("ip")
    local d = capture("dir")
    local state_line
    if st ~= "on" then
        state_line = T("Service: not started", "服务：未启动")
    elseif ip == "" or ip == "Offline" or ip:find("FB_ERR") then
        state_line = T("Service: running, but no network", "服务：运行中，但当前未联网")
    else
        state_line = T("Service: running · Current IP: http://", "服务：运行中　当前IP：http://") .. ip
    end

    local text = table.concat({
        T("Web File Browser 2 · KOReader Shortcut v", "网页文件管理器 2 · KOReader 快捷方式 v") .. PLUGIN_VERSION,
        "",
        T("Current Status", "当前状态"),
        state_line,
        T("KUAL extension dir: ", "KUAL 扩展目录：")
            .. (d ~= "" and d or T("not found (set FB_HOME at the top of fb_bridge.sh)",
                                   "未找到（可在 fb_bridge.sh 顶部设 FB_HOME）")),
        "",
        T("Dependency", "依赖项目"),
        T("Install the KUAL extension \"Web File Browser 2\" first (it provides the core program)",
          "需先安装 KUAL 扩展包「网页文件管理器 2」（提供核心程序）"),
        "   " .. URL_KUAL_EXT,
    }, "\n")

    if TextViewer then
        UIManager:show(TextViewer:new{
            title = T("Web File Browser 2 · Status / IP / About", "网页文件管理器 2 · 状态 / IP / 关于"),
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
