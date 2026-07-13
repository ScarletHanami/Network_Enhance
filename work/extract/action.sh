#!/system/bin/sh
# action.sh — 卫星地球 Pro v6.3.0 用户主动触发脚本
#
# v6.3.0 关键修复:
#   - AxManager 调用 action.sh 时执行 cd "<pluginPath>"; sh ./action.sh
#   - 所以 $0 = "./action.sh"，${0%/*} = "."，不可靠
#   - 修复：脚本顶部立即用 pwd 锁定 MODDIR，后续 cd 不影响
#   - 所有子脚本调用使用绝对路径 $MODDIR/scripts/xxx.sh

# ===============================
# v6.3.0 Bootstrap: 立即锁定 MODDIR（在任何 cd 之前）
# ===============================
# AxManager 调用 action.sh 时 CWD = 模块根目录
# 必须在脚本顶部立即抓取，否则后续 cd 会失效
SE_BOOTSTRAP_PWD="$(pwd 2>/dev/null)"

_se_find_common() {
    # 策略 1: pwd（最可靠，CWD = 模块根目录）
    if [ -n "$SE_BOOTSTRAP_PWD" ] && [ -f "$SE_BOOTSTRAP_PWD/scripts/common.sh" ] 2>/dev/null; then
        echo "$SE_BOOTSTRAP_PWD/scripts/common.sh"
        return 0
    fi
    # 策略 2: $AXERONDIR/plugins/Satellite_Earth（官方环境变量）
    if [ -n "${AXERONDIR:-}" ] && [ -f "$AXERONDIR/plugins/Satellite_Earth/scripts/common.sh" ] 2>/dev/null; then
        echo "$AXERONDIR/plugins/Satellite_Earth/scripts/common.sh"
        return 0
    fi
    # 策略 3: $0 推导（绝对路径场景）
    local raw_zero="${0:-}"
    if [ -n "$raw_zero" ] && [ "$raw_zero" != "${raw_zero#/}" ]; then
        local d="${raw_zero%/*}"
        [ -f "$d/scripts/common.sh" ] 2>/dev/null && { echo "$d/scripts/common.sh"; return 0; }
        [ -f "$d/../scripts/common.sh" ] 2>/dev/null && {
            local parent
            parent=$(cd "$d/.." 2>/dev/null && pwd) && [ -n "$parent" ] && echo "$parent/scripts/common.sh" && return 0
        }
    fi
    # 策略 4: 已知安装路径硬探测
    for _p in \
        /data/user_de/0/com.android.shell/axeron/plugins/Satellite_Earth \
        /data/user_de/0/android/axeron/plugins/Satellite_Earth \
        /data/adb/modules/Satellite_Earth; do
        [ -f "$_p/scripts/common.sh" ] 2>/dev/null && { echo "$_p/scripts/common.sh"; return 0; }
    done
    return 1
}

_se_common=$(_se_find_common)
if [ -z "$_se_common" ]; then
    echo "[SE] common.sh 未找到"
    echo "  pwd=$SE_BOOTSTRAP_PWD"
    echo "  AXERONDIR=${AXERONDIR:-未设置}"
    echo "  \$0=${0:-空}"
    exit 0
fi
. "$_se_common"
unset _se_common _se_find_common

# ui_print 兼容
if command -v ui_print >/dev/null 2>&1; then
    HAS_UI=1
else
    HAS_UI=0
fi

print_msg() {
    if [ "$HAS_UI" = "1" ]; then
        ui_print "$1"
    else
        echo "$1"
    fi
}

# ===============================
# 状态检测
# ===============================
show_status() {
    print_msg "=========================================="
    print_msg "  卫星地球 Pro v${SE_VERSION} — 状态检测"
    print_msg "=========================================="
    print_msg ""

    print_msg "[运行环境]"
    print_msg "  → 引擎       : $(detect_env)"
    print_msg "  → AXERON     : ${AXERON:-未设置}"
    print_msg "  → AXERONVER  : ${AXERONVER:-未知}"
    print_msg "  → AXERONDIR  : ${AXERONDIR:-未设置}"
    print_msg "  → API        : $(getprop ro.build.version.sdk 2>/dev/null | head -1)"
    print_msg "  → MODDIR_ROOT: ${MODDIR_ROOT:-未解析}"
    print_msg ""

    print_msg "[运营商]"
    local mccmnc carrier_name
    mccmnc=$(getprop gsm.sim.operator.numeric 2>/dev/null | head -1)
    carrier_name=$(getprop gsm.sim.operator.alpha 2>/dev/null | head -1)
    print_msg "  → SIM 运营商 : ${carrier_name:-无}"
    print_msg "  → MCC-MNC    : ${mccmnc:-未知}"
    print_msg "  → 配置选择   : ${CARRIER:-auto}"
    print_msg ""

    print_msg "[Private DNS]"
    print_msg "  → 模式 : $(se_get global private_dns_mode)"
    print_msg "  → 主机 : $(se_get global private_dns_spec)"
    print_msg ""

    print_msg "[WiFi 优化]"
    print_msg "  → 扫描节流   : $(se_get global wifi_scan_throttle_enabled) (0=关闭)"
    print_msg "  → 扫描间隔   : $(se_get global wifi_framework_scan_interval_ms) ms"
    print_msg "  → 休眠优化   : $(se_get global wifi_suspend_optimizations_enabled) (0=关闭)"
    print_msg "  → 空闲超时   : $(se_get global wifi_idle_ms) ms"
    print_msg "  → 弱信号阈值 : $(se_get global wifi_bad_rssi_threshold) dBm"
    local rssi
    rssi=$(se_get_wifi_rssi)
    print_msg "  → 当前 RSSI  : ${rssi:-未连接} dBm"
    print_msg ""

    print_msg "[移动网络]"
    print_msg "  → 数据保活   : $(se_get global mobile_data_always_on) (1=启用)"
    print_msg "  → 自动切换   : $(se_get global mobile_data_auto_handover)"
    print_msg "  → 网络制式   : $(se_get global preferred_network_mode)"
    print_msg "  → 5G SA      : $(se_get global nr_sa_mode)"
    print_msg "  → VoLTE      : $(se_get global volte_vt_enabled)"
    print_msg "  → VoNR       : $(se_get global vonr_enabled)"
    print_msg ""

    print_msg "[智能调度器]"
    if se_monitor_running; then
        print_msg "  → 状态    : 运行中 (PID=$(se_monitor_pid))"
        if [ -f "$SE_STATE_FILE" ]; then
            print_msg "  → 当前等级: $(grep '^LEVEL=' "$SE_STATE_FILE" 2>/dev/null | cut -d= -f2)"
            print_msg "  → 网络类型: $(grep '^NET_TYPE=' "$SE_STATE_FILE" 2>/dev/null | cut -d= -f2)"
            print_msg "  → WiFi RSSI: $(grep '^WIFI_RSSI=' "$SE_STATE_FILE" 2>/dev/null | cut -d= -f2)"
            print_msg "  → 移动 dBm: $(grep '^MOBILE_DBM=' "$SE_STATE_FILE" 2>/dev/null | cut -d= -f2)"
            print_msg "  → 公网延迟: $(grep '^PING_MS=' "$SE_STATE_FILE" 2>/dev/null | cut -d= -f2) ms"
        fi
    else
        print_msg "  → 状态    : 未运行"
    fi
    if [ -f "$WEAKNET_ACTIVE_FLAG" ]; then
        print_msg "  → weaknet : 激活中 (调度器已让位)"
    fi
    print_msg ""
}

# ===============================
# 操作菜单
# ===============================
show_menu() {
    print_msg "=========================================="
    print_msg "  可用操作"
    print_msg "=========================================="
    print_msg ""
    print_msg "  -- 弱网自救 --"
    print_msg "  1. 视频模式   (抖音/B站卡顿)"
    print_msg "  2. 游戏模式   (打游戏延迟高)"
    print_msg "  3. 社交模式   (微信/QQ 消息延迟)"
    print_msg "  4. 下载模式   (大文件下载)"
    print_msg "  5. 恢复默认优化"
    print_msg ""
    print_msg "  -- Private DNS --"
    print_msg "  6. 查看状态"
    print_msg "  7. 列出提供商 (6 家)"
    print_msg "  8. 自检 853 端口"
    print_msg "  9. 启用 (阿里)"
    print_msg " 10. 启用 (腾讯)"
    print_msg " 11. 启用 (AdGuard)"
    print_msg " 12. 禁用"
    print_msg " 13. 恢复系统默认"
    print_msg ""
    print_msg "  -- WiFi / 运营商 --"
    print_msg " 14. 重新应用 WiFi 优化"
    print_msg " 15. 查看 WiFi 设置"
    print_msg " 16. 还原 WiFi 设置"
    print_msg " 17. 重新应用运营商优化"
    print_msg " 18. 查看运营商状态"
    print_msg ""
    print_msg "  -- 智能调度器 --"
    print_msg " 19. 启动智能调度器"
    print_msg " 20. 停止智能调度器"
    print_msg " 21. 重启智能调度器"
    print_msg " 22. 查看调度器状态"
    print_msg " 23. 单次检测网络 (调试)"
    print_msg " 24. 发送测试通知"
    print_msg " 25. 撤销调度器通知"
    print_msg ""
    print_msg "  -- 维护 --"
    print_msg " 26. 模块自检 (含 OEM 兼容性信息)"
    print_msg " 27. 一键还原所有设置"
    print_msg " 28. 查看最近 50 行日志"
    print_msg " 29. 清空日志"
    print_msg ""
}

# AxManager 安装环境只显示状态
if [ "$HAS_UI" = "1" ] && [ -z "$AXERON" ]; then
    show_status
    print_msg "(安装环境，仅显示状态)"
    exit 0
fi

if [ -z "$1" ]; then
    show_status
    show_menu
    if [ -t 0 ]; then
        echo ""
        echo -n "请选择操作 [1-29]: "
        read choice
    else
        print_msg ""
        print_msg "(非交互模式，请直接执行: sh action.sh <数字>)"
        exit 0
    fi
else
    choice="$1"
fi

# v6.3.0: 子脚本调用前确认 MODDIR 有效
if [ -z "$MODDIR" ] || [ ! -d "$MODDIR" ]; then
    print_msg "[!] MODDIR 无效: ${MODDIR:-空}"
    print_msg "  尝试重新解析..."
    MODDIR="$(se_resolve_moddir 2>/dev/null)" || MODDIR=""
    MODDIR_ROOT="$MODDIR"
    if [ -z "$MODDIR" ]; then
        print_msg "[FAIL] 无法定位模块目录，操作中止"
        print_msg "  pwd=$SE_BOOTSTRAP_PWD"
        print_msg "  AXERONDIR=${AXERONDIR:-未设置}"
        exit 0
    fi
    print_msg "[OK] MODDIR 重新解析: $MODDIR"
fi

# v6.3.0: 调用子脚本前切换到模块目录，确保子脚本内 pwd 也正确
cd "$MODDIR" 2>/dev/null

case "$choice" in
    # 弱网自救
    1|video)        sh "$MODDIR/scripts/weaknet.sh" video ;;
    2|game)         sh "$MODDIR/scripts/weaknet.sh" game ;;
    3|social)       sh "$MODDIR/scripts/weaknet.sh" social ;;
    4|download)     sh "$MODDIR/scripts/weaknet.sh" download ;;
    5|normal)       sh "$MODDIR/scripts/weaknet.sh" normal ;;
    # Private DNS
    6)  sh "$MODDIR/scripts/dns.sh" status ;;
    7)  sh "$MODDIR/scripts/dns.sh" list ;;
    8)  sh "$MODDIR/scripts/dns.sh" check ;;
    9)  sh "$MODDIR/scripts/dns.sh" on ali ;;
    10) sh "$MODDIR/scripts/dns.sh" on tencent ;;
    11) sh "$MODDIR/scripts/dns.sh" on adguard ;;
    12) sh "$MODDIR/scripts/dns.sh" off ;;
    13) sh "$MODDIR/scripts/dns.sh" reset ;;
    # WiFi / 运营商
    14) sh "$MODDIR/scripts/wifi.sh" apply ;;
    15) sh "$MODDIR/scripts/wifi.sh" status ;;
    16) sh "$MODDIR/scripts/wifi.sh" reset ;;
    17) sh "$MODDIR/scripts/carrier.sh" apply ;;
    18) sh "$MODDIR/scripts/carrier.sh" status ;;
    # 智能调度器
    19) sh "$MODDIR/scripts/monitor.sh" start ;;
    20) sh "$MODDIR/scripts/monitor.sh" stop ;;
    21) sh "$MODDIR/scripts/monitor.sh" restart ;;
    22) sh "$MODDIR/scripts/monitor.sh" status ;;
    23) sh "$MODDIR/scripts/monitor.sh" detect ;;
    24) sh "$MODDIR/scripts/monitor.sh" notify "$2" ;;
    25) sh "$MODDIR/scripts/monitor.sh" cancel ;;
    # 维护
    26|check)
        se_self_check
        ;;
    27|reset-all)
        echo "=== 一键还原所有设置 ==="
        rm -f "$WEAKNET_ACTIVE_FLAG" 2>/dev/null
        rm -f "$DNS_PREFETCH_PID" 2>/dev/null
        sh "$MODDIR/scripts/monitor.sh" stop 2>/dev/null
        sh "$MODDIR/scripts/wifi.sh" reset 2>/dev/null
        sh "$MODDIR/scripts/carrier.sh" reset 2>/dev/null
        sh "$MODDIR/scripts/dns.sh" reset 2>/dev/null
        se_del global low_power_mode
        se_del global low_power_sticky
        se_put global data_stall_alarm_aggressive 0
        se_put global data_stall_alarm_non_aggressive 0
        se_del global wifi_batched_scan_results_ms
        se_del global wifi_recovery_state
        se_put global mobile_data_preferred 1
        se_put global wifi_idle_ms "$WIFI_IDLE_MS"
        se_put global wifi_persistent_group_remove_delay_ms 30000
        local current_carrier
        current_carrier=$(se_detect_carrier)
        if [ "$current_carrier" != "mobile" ] && [ "$current_carrier" != "ctn" ]; then
            se_del global nr_sa_mode
        elif [ "$ENABLE_5G_SA" != "true" ]; then
            se_del global nr_sa_mode
        fi
        se_notify_cancel
        echo "[OK] 所有设置已还原为系统默认"
        log_msg "用户执行一键还原 (v6.3.0)" "[action]"
        if [ "$ENABLE_MONITOR" = "true" ]; then
            echo "[INFO] 重启调度器..."
            sh "$MODDIR/scripts/monitor.sh" start 2>/dev/null
        fi
        ;;
    28)
        [ -f "$SE_LOG_FILE" ] && tail -50 "$SE_LOG_FILE" || echo "日志不存在: $SE_LOG_FILE"
        ;;
    29)
        rm -f "$SE_LOG_FILE" "${SE_LOG_FILE}".* 2>/dev/null
        echo "日志已清空"
        ;;
    *)
        echo "已取消"
        ;;
esac

exit 0
