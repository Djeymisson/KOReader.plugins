#!/bin/sh
# fb_bridge.sh — KOReader 快捷方式插件与「网页文件管理器 2」KUAL 包之间的桥接
# 用法: sh fb_bridge.sh start | stop | status | ip | dir | quiet
#
# 【为什么不直接调用 KUAL 包的 start.sh / stop.sh】
# KOReader 在前台时，那两个脚本有三个天然冲突：
#   1. 结尾都发 com.lab126.hal powerButtonPressed「返回桌面」，会把 KOReader 切走 / 锁屏；
#   2. 全程用 eips 直接写 framebuffer 显示 IP 和提示，而 KOReader 正占着 framebuffer，
#      直写会花屏或被重绘覆盖；idle.sh 守护更会持续写屏；
#   3. start.sh 会开无线、stop.sh 会按 WIFI_STATE 还原飞行模式，KOReader 前台时
#      网络归 KOReader 的 NetworkMgr 管，两边会互相打架，甚至关掉正在用的 WiFi。
# 此外 stop.sh 里有 sleep 5，同步调用会阻塞 UI 五秒。
#
# 【本脚本的取舍】
#   三不：不回桌面、不写 eips、不碰无线开关；也不拉起 idle.sh（自动退出守护会写屏）。
#   IP 改由 KOReader 自己的 InfoMessage 弹出，天然避开帧缓冲冲突。
#   只依赖 KUAL 包目录里的 filebrowser 二进制与 filebrowser.db，
#   不 source / 不调用它的任何 .sh —— 因此 KUAL 包后续升级不会破坏本插件（双向解耦）。
#   自动退出、无网 2 分钟退出、飞行模式还原等完整功能仍由 KUAL 入口负责；
#   KOReader 入口定位为「快捷方式」：手动启动、手动关闭、随时查看 IP。

EXT_ID='<id>filebrowser</id>'
PIDFILE=/tmp/fb_koreader.pid
LOGFILE=/tmp/fb_koreader.log

# 定位 KUAL 扩展目录：显式指定 → 按 config.xml 的 id 精确识别（兼容目录改名）→ 默认路径
# 注意：定位只判断「目录」，不要求核心二进制已存在 —— 首次使用时核心尚未下载，
# 目录是合法的，应由 start 分支单独报 "no core"，而不是误报 "extension not found"。
find_ext() {
    if [ -n "$FB_HOME" ] && [ -d "$FB_HOME" ]; then
        echo "$FB_HOME"; return 0
    fi
    for d in /mnt/us/extensions/* /mnt/base-us/extensions/*; do
        [ -f "$d/config.xml" ] || continue
        grep -q "$EXT_ID" "$d/config.xml" 2>/dev/null && { echo "$d"; return 0; }
    done
    for d in /mnt/us/extensions/filebrowser /mnt/base-us/extensions/filebrowser; do
        [ -d "$d" ] && { echo "$d"; return 0; }
    done
    return 1
}
DIR=$(find_ext)

# 目录缺失时给可判定的输出，避免 Lua 侧拿到空串误判
if [ -z "$DIR" ]; then
    case "$1" in
        ip)     echo "FB_ERR"; exit 1 ;;
        status) echo "off";    exit 1 ;;
        dir)    echo "";       exit 1 ;;
        *)      echo "FB_ERR: extension not found"; exit 1 ;;
    esac
fi

cd "$DIR" || { echo "FB_ERR: cannot cd $DIR"; exit 1; }

# 端口 80 = 0x0050，状态 0A = LISTEN；-a 0.0.0.0 时 Go 可能落在 tcp6 表
listening() {
    for tbl in /proc/net/tcp /proc/net/tcp6; do
        awk 'NR>1 && $2 ~ /:0050$/ && $4=="0A"{f=1} END{exit !f}' "$tbl" 2>/dev/null && return 0
    done
    return 1
}

get_ip() {
    addr=""
    for ifc in wlan0 eth0 mlan0 tiwlan0; do
        addr=$(ifconfig "$ifc" 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p' | head -1)
        [ -n "$addr" ] && break
    done
    if [ -z "$addr" ]; then echo "FB_ERR"; else echo "$addr"; fi
}

# 只杀本服务进程：优先 pid 文件，再按命令行精确兜底。
# 不能用裸 grep filebrowser —— 会误伤路径里恰好含该字样的其它进程。
kill_service() {
    if [ -f "$PIDFILE" ]; then
        p=$(cat "$PIDFILE" 2>/dev/null)
        case "$p" in ''|*[!0-9]*) : ;; *) kill "$p" 2>/dev/null ;; esac
        rm -f "$PIDFILE"
    fi
    for p in $(ps aux 2>/dev/null | grep '[f]ilebrowser --noauth' | awk '{print $2}'); do
        kill "$p" 2>/dev/null
    done
}

# 停掉 KUAL 入口遗留的写屏守护（idle.sh 持续 eips 写屏，KOReader 前台会花屏）
quiet_guard() {
    for p in $(ps aux 2>/dev/null | grep -E '[i]dle.sh|[a]utoclose.sh' | awk '{print $2}'); do
        kill "$p" 2>/dev/null
    done
}

case "$1" in

start)
    # 幂等：80 端口已监听就不重复拉起，兼容「服务其实由 KUAL 入口启动」的情形
    if listening; then
        quiet_guard
        echo on
        exit 0
    fi
    [ -x ./filebrowser ] || { echo "FB_ERR: no core (run KUAL once)"; exit 1; }

    # 防休眠：Kindle 休眠会关 WiFi，服务期间保持唤醒（best-effort，不改动无线开关）
    lipc-set-prop -i com.lab126.powerd preventScreenSaver 1 2>/dev/null

    # 放行 80 入站（部分固件默认拦截）；只在规则不存在时插入，避免重复堆积
    if ! iptables -L INPUT -n 2>/dev/null | grep -q 'dpt:80'; then
        iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || \
            /sbin/iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null
    fi

    : > "$LOGFILE"
    # v2.63.23 无 serve 子命令；--noauth 免登录；-d 显式指定数据库
    if command -v setsid >/dev/null 2>&1; then
        setsid ./filebrowser --noauth -a 0.0.0.0 -p 80 -r /mnt/us \
            -d ./filebrowser.db >"$LOGFILE" 2>&1 </dev/null &
    else
        nohup ./filebrowser --noauth -a 0.0.0.0 -p 80 -r /mnt/us \
            -d ./filebrowser.db >"$LOGFILE" 2>&1 </dev/null &
    fi
    echo $! > "$PIDFILE"

    # 等端口就绪，0.2 秒粒度；不支持小数 sleep 的老固件自动退化为 1 秒
    i=0
    while [ "$i" -lt 40 ]; do
        listening && break
        sleep 0.2 2>/dev/null || sleep 1
        i=$(( i + 1 ))
    done
    if listening; then
        echo on
    else
        err=$(tail -n 1 "$LOGFILE" 2>/dev/null | cut -c1-60)
        echo "FB_ERR: not listening ($err)"
        exit 1
    fi
    ;;

stop)
    kill_service
    quiet_guard
    lipc-set-prop -i com.lab126.powerd preventScreenSaver 0 2>/dev/null
    echo stopped
    ;;

status)
    listening && echo on || echo off
    ;;

ip)
    get_ip
    ;;

dir)
    echo "$DIR"
    ;;

quiet)
    quiet_guard
    echo quieted
    ;;

*)
    echo "usage: fb_bridge.sh start|stop|status|ip|dir|quiet"
    exit 1
    ;;
esac
