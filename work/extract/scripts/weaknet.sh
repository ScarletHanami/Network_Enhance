#!/system/bin/sh
# weaknet.sh — 卫星地球 Pro v6.3.0 弱网自救脚本

SE_BOOTSTRAP_PWD="$(pwd 2>/dev/null)"

_se_find_common() {
    if [ -n "$SE_BOOTSTRAP_PWD" ] && [ -f "$SE_BOOTSTRAP_PWD/scripts/common.sh" ] 2>/dev/null; then
        echo "$SE_BOOTSTRAP_PWD/scripts/common.sh"; return 0
    fi
    if [ -n "${AXERONDIR:-}" ] && [ -f "$AXERONDIR/plugins/Satellite_Earth/scripts/common.sh" ] 2>/dev/null; then
        echo "$AXERONDIR/plugins/Satellite_Earth/scripts/common.sh"; return 0
    fi
    local raw_zero="${0:-}"
    if [ -n "$raw_zero" ] && [ "$raw_zero" != "${raw_zero#/}" ]; then
        local d="${raw_zero%/*}"
        [ -f "$d/scripts/common.sh" ] 2>/dev/null && { echo "$d/scripts/common.sh"; return 0; }
        [ -f "$d/../scripts/common.sh" ] 2>/dev/null && { echo "$d/../scripts/common.sh"; return 0; }
    fi
    for _p in \
        /data/user_de/0/com.android.shell/axeron/plugins/Satellite_Earth \
        /data/user_de/0/android/axeron/plugins/Satellite_Earth \
        /data/adb/modules/Satellite_Earth; do
        [ -f "$_p/scripts/common.sh" ] 2>/dev/null && { echo "$_p/scripts/common.sh"; return 0; }
    done
    return 1
}
_se_common=$(_se_find_common) || { echo "[SE] common.sh 未找到" >&2; exit 0; }
. "$_se_common"
unset _se_common _se_find_common

set_weaknet_active() {
    touch "$WEAKNET_ACTIVE_FLAG" 2>/dev/null
    log_msg "weaknet 模式激活 ($1)" "[weaknet]"
    return 0
}

clear_weaknet_active() {
    rm -f "$WEAKNET_ACTIVE_FLAG" 2>/dev/null
    log_msg "weaknet 模式退出" "[weaknet]"
    return 0
}

dns_prefetch() {
    local tag="$1"
    shift
    if ! wait_network_ready 3; then
        log_msg "DNS 预热跳过 (网络未就绪): $tag" "[weaknet]"
        return 0
    fi
    if [ -f "$DNS_PREFETCH_PID" ]; then
        local old_pid
        old_pid=$(cat "$DNS_PREFETCH_PID" 2>/dev/null)
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            if [ -r "/proc/$old_pid/cmdline" ]; then
                if tr '\0' ' ' < "/proc/$old_pid/cmdline" 2>/dev/null | grep -q "ping"; then
                    log_msg "DNS 预热已在运行 (PID=$old_pid)" "[weaknet]"
                    return 0
                fi
            else
                log_msg "DNS 预热可能已在运行 (PID=$old_pid)" "[weaknet]"
                return 0
            fi
        fi
        rm -f "$DNS_PREFETCH_PID" 2>/dev/null
    fi
    (
        for domain in "$@"; do
            ping -c 1 -W 1 "$domain" >/dev/null 2>&1
        done
        rm -f "$DNS_PREFETCH_PID" 2>/dev/null
    ) &
    echo $! > "$DNS_PREFETCH_PID" 2>/dev/null
    log_msg "DNS 预热已启动 (PID=$!): $tag" "[weaknet]"
    return 0
}

silent_reset() {
    if [ -f "$MODDIR/scripts/wifi.sh" ]; then
        sh "$MODDIR/scripts/wifi.sh" apply >/dev/null 2>&1
    fi
    if [ -f "$MODDIR/scripts/carrier.sh" ]; then
        sh "$MODDIR/scripts/carrier.sh" apply >/dev/null 2>&1
    fi
    se_put global low_power_mode 0
    se_put global low_power_sticky 0
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
    return 0
}

apply_video_mode() {
    echo "=== 应用视频模式 (v6.3.0 16 项) ==="
    silent_reset

    se_put global wifi_bad_rssi_threshold_2g "-95"
    se_put global wifi_bad_rssi_threshold_5g "-92"
    se_put global wifi_bad_rssi_threshold "-95"
    se_put global wifi_suspend_optimizations_enabled 0
    se_put global wifi_idle_ms 14400000
    se_put global wifi_framework_scan_interval_ms 10000
    se_put global wifi_persistent_group_remove_delay_ms 60000
    se_put global mobile_data_always_on 1
    se_put global mobile_data_auto_handover 1
    se_put global data_stall_alarm_aggressive 1
    se_put global low_power_mode 0
    se_put global low_power_sticky 0
    se_put global wifi_scan_throttle_enabled 0
    se_put global wifi_networks_score_enabled 0
    se_put global wifi_batched_scan_results_ms 5000
    se_put global wifi_recovery_state 1
    se_put global mobile_data_preferred 0
    se_put global data_stall_alarm_non_aggressive 1
    se_put global volte_vt_enabled 1
    se_put global vonr_enabled 1
    echo "  [OK] 视频模式 16 项优化已应用"

    dns_prefetch "video" \
        www.douyin.com www.bilibili.com www.kuaishou.com www.ixigua.com \
        www.iqiyi.com www.youku.com \
        v.douyin.com api.bilibili.com dns.alidns.com dot.pub

    set_weaknet_active "video"
    log_msg "视频模式已应用" "[weaknet]"
    echo "[OK] 视频模式已生效"
    return 0
}

apply_game_mode() {
    echo "=== 应用游戏模式 (v6.3.0 15 项) ==="
    silent_reset

    se_put global mobile_data_always_on 1
    se_put global mobile_data_preferred 1
    se_put global mobile_data_auto_handover 1
    se_put global low_power_mode 0
    se_put global low_power_sticky 0
    se_put global nr_sa_mode 1
    se_put global enable_nr_dc 1
    se_put global endc_capability 1
    se_put global nr_handover_enabled 1
    se_put global data_stall_alarm_aggressive 1
    se_put global wifi_framework_scan_interval_ms 10000
    se_put global wifi_suspend_optimizations_enabled 0
    se_put global wifi_scan_throttle_enabled 0
    se_put global wifi_bad_rssi_threshold "-90"
    se_put global wifi_bad_rssi_threshold_2g "-90"
    se_put global wifi_bad_rssi_threshold_5g "-88"
    se_put global wifi_networks_score_enabled 0
    se_put global volte_vt_enabled 1
    se_put global vonr_enabled 1
    se_put global wifi_persistent_group_remove_delay_ms 60000
    se_put global data_stall_alarm_non_aggressive 1
    se_put global wifi_idle_ms 21600000
    se_put global wifi_batched_scan_results_ms 5000
    se_put global wifi_recovery_state 1
    echo "  [OK] 游戏模式 15 项优化已应用"

    dns_prefetch "game" \
        dns.alidns.com dot.pub www.tencent.com \
        www.netease.com www.mihoyo.com \
        api.tencentcloudapi.com

    set_weaknet_active "game"
    log_msg "游戏模式已应用" "[weaknet]"
    echo "[OK] 游戏模式已生效"
    return 0
}

apply_social_mode() {
    echo "=== 应用社交模式 ==="
    silent_reset

    se_put global mobile_data_always_on 1
    se_put global mobile_data_auto_handover 1
    se_put global mobile_data_preferred 0
    se_put global wifi_suspend_optimizations_enabled 0
    se_put global wifi_idle_ms 14400000
    se_put global wifi_scan_throttle_enabled 0
    se_put global low_power_mode 0
    se_put global low_power_sticky 0
    se_put global wifi_bad_rssi_threshold "-90"
    se_put global wifi_bad_rssi_threshold_2g "-90"
    se_put global wifi_bad_rssi_threshold_5g "-88"
    se_put global wifi_networks_score_enabled 0
    se_put global data_stall_alarm_aggressive 1
    se_put global wifi_persistent_group_remove_delay_ms 60000
    se_put global wifi_recovery_state 1
    se_put global volte_vt_enabled 1
    echo "  [OK] 社交模式已应用"

    dns_prefetch "social" \
        dns.alidns.com dot.pub \
        www.weixin.qq.com wx.qq.com \
        www.qq.com mobile.qq.com \
        im.qq.com dns.pub

    set_weaknet_active "social"
    log_msg "社交模式已应用" "[weaknet]"
    echo "[OK] 社交模式已生效"
    return 0
}

apply_download_mode() {
    echo "=== 应用下载模式 ==="
    silent_reset

    se_put global wifi_suspend_optimizations_enabled 0
    se_put global wifi_scan_throttle_enabled 0
    se_put global wifi_idle_ms 21600000
    se_put global wifi_bad_rssi_threshold "-92"
    se_put global wifi_bad_rssi_threshold_2g "-92"
    se_put global wifi_bad_rssi_threshold_5g "-90"
    se_put global wifi_networks_score_enabled 0
    se_put global wifi_persistent_group_remove_delay_ms 60000
    se_put global low_power_mode 0
    se_put global low_power_sticky 0
    se_put global mobile_data_always_on 1
    se_put global mobile_data_auto_handover 1
    se_put global mobile_data_preferred 0
    se_put global wifi_batched_scan_results_ms 5000
    se_put global wifi_recovery_state 1
    se_put global data_stall_alarm_aggressive 1
    se_put global data_stall_alarm_non_aggressive 1
    se_put global volte_vt_enabled 1
    se_put global vonr_enabled 1
    echo "  [OK] 下载模式已应用"

    dns_prefetch "download" \
        dns.alidns.com dot.pub \
        www.baidu.com www.taobao.com www.jd.com \
        www.aliyun.com cdn.jsdelivr.net \
        pan.baidu.com www.123pan.com

    set_weaknet_active "download"
    log_msg "下载模式已应用" "[weaknet]"
    echo "[OK] 下载模式已生效"
    return 0
}

apply_normal_mode() {
    echo "=== 恢复默认优化模式 ==="
    clear_weaknet_active

    if [ -f "$MODDIR/scripts/wifi.sh" ]; then
        sh "$MODDIR/scripts/wifi.sh" apply
    fi
    if [ -f "$MODDIR/scripts/carrier.sh" ]; then
        sh "$MODDIR/scripts/carrier.sh" apply
    fi

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

    rm -f "$DNS_PREFETCH_PID" 2>/dev/null

    if [ "$ENABLE_MONITOR" = "true" ]; then
        if ! se_monitor_running; then
            sh "$MODDIR/scripts/monitor.sh" start >/dev/null 2>&1
        fi
    fi

    log_msg "已恢复默认优化模式" "[weaknet]"
    echo "[OK] 已恢复默认优化"
    return 0
}

show_status() {
    echo "=== 当前网络优化状态 ==="
    echo ""
    if [ -f "$WEAKNET_ACTIVE_FLAG" ]; then
        echo "  [!] weaknet 模式激活中（调度器已让位）"
        echo ""
    fi
    echo "[WiFi]"
    echo "  scan_throttle         : $(se_get global wifi_scan_throttle_enabled)"
    echo "  scan_interval_ms      : $(se_get global wifi_framework_scan_interval_ms)"
    echo "  suspend_optimizations : $(se_get global wifi_suspend_optimizations_enabled)"
    echo "  idle_ms               : $(se_get global wifi_idle_ms)"
    echo "  bad_rssi_threshold    : $(se_get global wifi_bad_rssi_threshold) dBm"
    echo ""
    echo "[移动网络]"
    echo "  mobile_data_always_on     : $(se_get global mobile_data_always_on)"
    echo "  mobile_data_preferred     : $(se_get global mobile_data_preferred)"
    echo "  mobile_data_auto_handover : $(se_get global mobile_data_auto_handover)"
    echo "  preferred_network_mode    : $(se_get global preferred_network_mode)"
    echo "  nr_sa_mode                : $(se_get global nr_sa_mode)"
    echo "  enable_nr_dc              : $(se_get global enable_nr_dc)"
    echo ""
    echo "[实时网络]"
    echo "  WiFi RSSI : $(se_get_wifi_rssi) dBm"
    echo "  移动 dBm  : $(se_get_mobile_dbm)"
    echo "  公网延迟  : $(se_get_ping_ms) ms"
    return 0
}

case "$1" in
    video)        apply_video_mode ;;
    game)         apply_game_mode ;;
    social)       apply_social_mode ;;
    download)     apply_download_mode ;;
    normal|default) apply_normal_mode ;;
    status)       show_status ;;
    *)
        echo "弱网自救工具 v${SE_VERSION}"
        echo ""
        echo "用法: sh weaknet.sh <模式>"
        echo "可选模式: video | game | social | download | normal | status"
        ;;
esac
exit 0
