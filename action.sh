#!/system/bin/sh
# action.sh — 网络增强 用户主动触发脚本
# 提供状态检测、弱网自救、DNS/WiFi/运营商管理、智能调度器、5G/LTE 制式管理
# 支持交互菜单（无参数）和 CLI 参数模式（sh action.sh <数字>）

SE_BOOTSTRAP_PWD="$(pwd 2>/dev/null)"

_se_find_common() {
    # 策略 1: pwd（最可靠，CWD = 模块根目录）
    if [ -n "$SE_BOOTSTRAP_PWD" ] && [ -f "$SE_BOOTSTRAP_PWD/scripts/common.sh" ] 2>/dev/null; then
        echo "$SE_BOOTSTRAP_PWD/scripts/common.sh"
        return 0
    fi
    # 策略 2: $AXERONDIR/plugins/Network_Enhance（官方环境变量）
    if [ -n "${AXERONDIR:-}" ] && [ -f "$AXERONDIR/plugins/Network_Enhance/scripts/common.sh" ] 2>/dev/null; then
        echo "$AXERONDIR/plugins/Network_Enhance/scripts/common.sh"
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
        /data/user_de/0/com.android.shell/axeron/plugins/Network_Enhance \
        /data/user_de/0/android/axeron/plugins/Network_Enhance \
        /data/adb/modules/Network_Enhance; do
        [ -f "$_p/scripts/common.sh" ] 2>/dev/null && { echo "$_p/scripts/common.sh"; return 0; }
    done
    return 1
}

_se_common=$(_se_find_common)
if [ -z "$_se_common" ]; then
    echo "[NE] common.sh 未找到"
    echo "  pwd=$SE_BOOTSTRAP_PWD"
    echo "  AXERONDIR=${AXERONDIR:-未设置}"
    echo "  \$0=${0:-空}"
    exit 0
fi
. "$_se_common"
unset _se_common
unset -f _se_find_common 2>/dev/null || true

# CI 日志入口
se_ci_log "action.sh" "action.sh 启动 | choice=${1:-交互菜单}"

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
    print_msg "  网络增强 v${SE_VERSION} — 状态检测"
    print_msg "=========================================="
    print_msg ""

    print_msg "[运行环境]"
    print_msg "  → 引擎       : $(detect_env)"
    print_msg "  → AXERON     : ${AXERON:-未设置}"
    print_msg "  → AXERONVER  : ${AXERONVER:-未知}"
    print_msg "  → AXERONDIR  : ${AXERONDIR:-未设置}"
    print_msg "  → Android API: $(se_get_api)"
    if se_is_android_14_plus; then
        print_msg "  → 兼容性     : OK Android 14+"
    else
        print_msg "  → 兼容性     : WARN 低于 Android 14"
    fi
    print_msg "  → MODDIR_ROOT: ${MODDIR_ROOT:-未解析}"
    print_msg ""

    print_msg "[运营商]"
    local mccmnc carrier_name
    mccmnc=$(getprop gsm.sim.operator.numeric 2>/dev/null | head -1)
    carrier_name=$(getprop gsm.sim.operator.alpha 2>/dev/null | head -1)
    print_msg "  → SIM 运营商 : ${carrier_name:-无}"
    print_msg "  → MCC-MNC    : ${mccmnc:-未知}"
    print_msg "  → 配置选择   : ${CARRIER:-auto}"
    if se_is_pnm_restricted; then
        print_msg "  → PNM 受限   : WARN 已标记 (切换可能无效)"
    elif se_should_verify_write; then
        print_msg "  → PNM 受限   : OK 未受限 (启用写入验证)"
    else
        print_msg "  → PNM 受限   : OK 未受限"
    fi
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
    print_msg "  → 网络制式   : $(se_get global preferred_network_mode) (11=LTE only, 9=LTE/3G, 26/27/32/33=5G)"
    print_msg "  → 5G SA      : $(se_get global nr_sa_mode)"
    print_msg "  → ENDC       : $(se_get global endc_capability) (0=关闭)"
    print_msg "  → VoLTE      : $(se_get global volte_vt_enabled)"
    print_msg "  → VoNR       : $(se_get global vonr_enabled)"
    print_msg ""

    print_msg "[5G 信号质量]"
    print_msg "  → NR RSRP    : $(se_get_nr_rsrp) dBm"
    print_msg "  → NR RSRQ    : $(se_get_nr_rsrq) dB"
    print_msg "  → NR SINR    : $(se_get_nr_sinr) dB"
    if se_detect_fake_5g; then
        print_msg "  → 假满格判定 : WARN 检测到 5G 假满格"
    else
        print_msg "  → 假满格判定 : OK 正常"
    fi
    print_msg ""

    print_msg "[Data Saver]"
    local ds_status
    ds_status=$(cmd netpolicy get restrict-background 2>/dev/null)
    if [ "$ds_status" = "1" ] || echo "$ds_status" | grep -qiE "enabled|true"; then
        print_msg "  → 状态       : WARN 已启用 (后台数据受限)"
    else
        print_msg "  → 状态       : OK 已禁用"
    fi
    print_msg ""

    print_msg "[智能调度器]"
    if se_monitor_running; then
        print_msg "  → 状态    : 运行中 (PID=$(se_monitor_pid))"
        if [ -f "$SE_STATE_FILE" ]; then
            print_msg "  → 当前等级: $(grep '^LEVEL=' "$SE_STATE_FILE" 2>/dev/null | cut -d= -f2)"
            print_msg "  → 网络类型: $(grep '^NET_TYPE=' "$SE_STATE_FILE" 2>/dev/null | cut -d= -f2)"
            print_msg "  → WiFi RSSI: $(grep '^WIFI_RSSI=' "$SE_STATE_FILE" 2>/dev/null | cut -d= -f2)"
            print_msg "  → 移动 dBm: $(grep '^MOBILE_DBM=' "$SE_STATE_FILE" 2>/dev/null | cut -d= -f2)"
            print_msg "  → NR RSRP : $(grep '^NR_RSRP=' "$SE_STATE_FILE" 2>/dev/null | cut -d= -f2)"
            print_msg "  → NR SINR : $(grep '^NR_SINR=' "$SE_STATE_FILE" 2>/dev/null | cut -d= -f2)"
            print_msg "  → 公网延迟: $(grep '^PING_MS=' "$SE_STATE_FILE" 2>/dev/null | cut -d= -f2) ms"
            print_msg "  → 5G降级  : $(grep '^FAKE_5G_ACTIVE=' "$SE_STATE_FILE" 2>/dev/null | cut -d= -f2) (1=已降级)"
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
    print_msg "  1. 视频模式   (弱网预加载优化)"
    print_msg "  2. 游戏模式   (锁定4G LTE+禁后台)"
    print_msg "  3. 社交模式   (微信/QQ 消息延迟)"
    print_msg "  4. 下载模式   (大文件下载)"
    print_msg "  5. 恢复默认优化"
    print_msg " 33. 代理稳定模式 (锁定4G+移动数据保活+后台压制)"
    print_msg " 34. 加入代理白名单 (需包名参数)"
    print_msg " 35. 移出代理白名单 (需包名参数)"
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
    print_msg "  -- 5G/LTE 制式管理 --"
    print_msg " 30. 5G 假满格自检 (显示RSRP/SINR/Ping)"
    print_msg " 31. 锁定 LTE Only (游戏模式同款, 注意语音副作用)"
    print_msg " 32. 解锁 LTE (恢复运营商默认 5G)"
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
        printf "请选择操作 [1-35]: "
        read choice
    else
        print_msg ""
        print_msg "(非交互模式，请直接执行: sh action.sh <数字>)"
        exit 0
    fi
else
    choice="$1"
fi

# 确认 MODDIR 有效
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

cd "$MODDIR" 2>/dev/null

case "$choice" in
    # 弱网自救
    1|video)        se_ci_log "action.sh" "menu: video mode"; sh "$MODDIR/scripts/weaknet.sh" video ;;
    2|game)         se_ci_log "action.sh" "menu: game mode"; sh "$MODDIR/scripts/weaknet.sh" game ;;
    3|social)       se_ci_log "action.sh" "menu: social mode"; sh "$MODDIR/scripts/weaknet.sh" social ;;
    4|download)     se_ci_log "action.sh" "menu: download mode"; sh "$MODDIR/scripts/weaknet.sh" download ;;
    5|normal)       se_ci_log "action.sh" "menu: normal mode"; sh "$MODDIR/scripts/weaknet.sh" normal ;;
    # 代理稳定模式与白名单管理
    33|vpn-mode)    se_ci_log "action.sh" "menu: vpn mode"; sh "$MODDIR/scripts/weaknet.sh" vpn ;;
    34|add-vpn-wl)  se_ci_log "action.sh" "menu: add vpn wl | pkg=$2"; sh "$MODDIR/scripts/weaknet.sh" add-wl "$2" ;;
    35|rm-vpn-wl)   se_ci_log "action.sh" "menu: rm vpn wl | pkg=$2"; sh "$MODDIR/scripts/weaknet.sh" rm-wl "$2" ;;
    # Private DNS
    6)  se_ci_log "action.sh" "menu: dns status"; sh "$MODDIR/scripts/dns.sh" status ;;
    7)  se_ci_log "action.sh" "menu: dns list"; sh "$MODDIR/scripts/dns.sh" list ;;
    8)  se_ci_log "action.sh" "menu: dns check"; sh "$MODDIR/scripts/dns.sh" check ;;
    9)  se_ci_log "action.sh" "menu: dns on ali"; sh "$MODDIR/scripts/dns.sh" on ali ;;
    10) se_ci_log "action.sh" "menu: dns on tencent"; sh "$MODDIR/scripts/dns.sh" on tencent ;;
    11) se_ci_log "action.sh" "menu: dns on adguard"; sh "$MODDIR/scripts/dns.sh" on adguard ;;
    12) se_ci_log "action.sh" "menu: dns off"; sh "$MODDIR/scripts/dns.sh" off ;;
    13) se_ci_log "action.sh" "menu: dns reset"; sh "$MODDIR/scripts/dns.sh" reset ;;
    # WiFi / 运营商
    14) se_ci_log "action.sh" "menu: wifi apply"; sh "$MODDIR/scripts/wifi.sh" apply ;;
    15) se_ci_log "action.sh" "menu: wifi status"; sh "$MODDIR/scripts/wifi.sh" status ;;
    16) se_ci_log "action.sh" "menu: wifi reset"; sh "$MODDIR/scripts/wifi.sh" reset ;;
    17) se_ci_log "action.sh" "menu: carrier apply"; sh "$MODDIR/scripts/carrier.sh" apply ;;
    18) se_ci_log "action.sh" "menu: carrier status"; sh "$MODDIR/scripts/carrier.sh" status ;;
    # 智能调度器
    19) se_ci_log "action.sh" "menu: monitor start"; sh "$MODDIR/scripts/monitor.sh" start ;;
    20) se_ci_log "action.sh" "menu: monitor stop"; sh "$MODDIR/scripts/monitor.sh" stop ;;
    21) se_ci_log "action.sh" "menu: monitor restart"; sh "$MODDIR/scripts/monitor.sh" restart ;;
    22) se_ci_log "action.sh" "menu: monitor status"; sh "$MODDIR/scripts/monitor.sh" status ;;
    23) se_ci_log "action.sh" "menu: monitor detect"; sh "$MODDIR/scripts/monitor.sh" detect ;;
    24) se_ci_log "action.sh" "menu: monitor notify"; sh "$MODDIR/scripts/monitor.sh" notify "$2" ;;
    25) se_ci_log "action.sh" "menu: monitor cancel"; sh "$MODDIR/scripts/monitor.sh" cancel ;;
    # 5G/LTE 制式管理
    30|fake5g-check)
        se_ci_log "action.sh" "menu: fake5g check"
        echo "=== 5G 假满格自检 ==="
        echo ""
        echo "[5G 信号质量]"
        echo "  NR RSRP : $(se_get_nr_rsrp) dBm (强≥-85, 弱≤-110)"
        echo "  NR RSRQ : $(se_get_nr_rsrq) dB (强≥-10, 弱≤-15)"
        echo "  NR SINR : $(se_get_nr_sinr) dB (强≥10, 弱≤0)"
        echo "  公网延迟: $(se_get_ping_ms) ms"
        echo ""
        echo "[假满格判定]"
        echo "  RSRP 阈值: $FAKE_5G_RSRP_THRESHOLD dBm"
        echo "  SINR 阈值: $FAKE_5G_SINR_THRESHOLD dB"
        echo "  Ping 阈值: $FAKE_5G_PING_THRESHOLD ms"
        echo ""
        if se_detect_fake_5g; then
            echo "  判定结果: WARN 检测到 5G 假满格"
            echo "  建议    : 等待调度器自动降级, 或手动执行菜单 31 锁定 LTE"
        else
            echo "  判定结果: OK 正常"
        fi
        echo ""
        echo "[调度器状态]"
        if se_monitor_running; then
            echo "  调度器运行中, 将自动处理假满格"
        else
            echo "  调度器未运行, 建议执行菜单 19 启动"
        fi
        ;;
    31|lock-lte)
        # 锁定 LTE 并发送语音副作用提醒
        se_ci_log "action.sh" "menu: lock-lte"
        echo "=== 手动锁定 LTE Only ==="
        echo ""
        sh "$MODDIR/scripts/carrier.sh" lock-lte
        if [ -f "$MODDIR/scripts/weaknet.sh" ]; then
            # 直接发送通知（避免 source 整个 weaknet.sh）
            se_notify "网络增强 → LTE Only 已锁定" "已锁定 LTE Only 模式

注意: 非 VoLTE 来电可能无法接通
游戏结束请及时解锁 (菜单 32)"
            log_msg "[action-31] LTE Only 已手动锁定, 语音通知已发送" "[action]"
        fi
        echo ""
        echo "  注意: 已锁定 LTE Only, 非 VoLTE 来电可能无法接通"
        echo "  游戏结束请执行菜单 32 解锁"
        ;;
    32|unlock-lte)
        # 解锁 LTE，恢复 5G
        se_ci_log "action.sh" "menu: unlock-lte"
        echo "=== 手动解锁 LTE, 恢复 5G ==="
        echo ""
        sh "$MODDIR/scripts/carrier.sh" unlock-lte
        log_msg "[action-32] LTE 已手动解锁, 恢复 5G" "[action]"
        ;;
    # 维护
    26|check)
        se_ci_log "action.sh" "menu: self-check"
        se_self_check
        ;;
    27|reset-all)
        se_ci_log "action.sh" "menu: reset-all"
        echo "=== 一键还原所有设置 ==="
        rm -f "$WEAKNET_ACTIVE_FLAG" 2>/dev/null
        rm -f "$DNS_PREFETCH_PID" 2>/dev/null
        # 关闭 Data Saver（确保还原）
        cmd netpolicy set restrict-background false 2>/dev/null
        sh "$MODDIR/scripts/monitor.sh" stop 2>/dev/null
        # 恢复网络制式
        sh "$MODDIR/scripts/carrier.sh" unlock-lte 2>/dev/null
        sh "$MODDIR/scripts/wifi.sh" reset 2>/dev/null
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
        # 清理自定义键
        se_del global network_enhance_version
        se_del global network_enhance_activated
        se_notify_cancel
        echo "[OK] 所有设置已还原为系统默认"
        log_msg "用户执行一键还原 (v${SE_VERSION})" "[action]"
        if [ "$ENABLE_MONITOR" = "true" ]; then
            echo "[INFO] 重启调度器..."
            sh "$MODDIR/scripts/monitor.sh" start 2>/dev/null
        fi
        ;;
    28)
        se_ci_log "action.sh" "menu: view log"
        [ -f "$SE_LOG_FILE" ] && tail -50 "$SE_LOG_FILE" 2>/dev/null || echo "日志不存在: $SE_LOG_FILE"
        ;;
    29)
        se_ci_log "action.sh" "menu: clear log"
        rm -f "$SE_LOG_FILE" "${SE_LOG_FILE}".* 2>/dev/null
        echo "日志已清空"
        ;;
    *)
        se_ci_log "action.sh" "menu: cancelled (choice=$choice)"
        echo "已取消"
        ;;
esac

exit 0
