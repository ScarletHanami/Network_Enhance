#!/system/bin/sh
# wifi.sh — 网络增强 WiFi 优化工具
# 用法: sh wifi.sh <apply|status|reset>

SE_BOOTSTRAP_PWD="$(pwd 2>/dev/null)"

_se_find_common() {
    if [ -n "$SE_BOOTSTRAP_PWD" ] && [ -f "$SE_BOOTSTRAP_PWD/scripts/common.sh" ] 2>/dev/null; then
        echo "$SE_BOOTSTRAP_PWD/scripts/common.sh"; return 0
    fi
    if [ -n "${AXERONDIR:-}" ] && [ -f "$AXERONDIR/plugins/Network_Enhance/scripts/common.sh" ] 2>/dev/null; then
        echo "$AXERONDIR/plugins/Network_Enhance/scripts/common.sh"; return 0
    fi
    local raw_zero="${0:-}"
    if [ -n "$raw_zero" ] && [ "$raw_zero" != "${raw_zero#/}" ]; then
        local d="${raw_zero%/*}"
        [ -f "$d/scripts/common.sh" ] 2>/dev/null && { echo "$d/scripts/common.sh"; return 0; }
        [ -f "$d/../scripts/common.sh" ] 2>/dev/null && { echo "$d/../scripts/common.sh"; return 0; }
    fi
    for _p in \
        /data/user_de/0/com.android.shell/axeron/plugins/Network_Enhance \
        /data/user_de/0/android/axeron/plugins/Network_Enhance \
        /data/adb/modules/Network_Enhance; do
        [ -f "$_p/scripts/common.sh" ] 2>/dev/null && { echo "$_p/scripts/common.sh"; return 0; }
    done
    return 1
}
_se_common=$(_se_find_common) || { echo "[NE] common.sh 未找到" >&2; exit 0; }
. "$_se_common"
unset _se_common _se_find_common

# ----------------------------------------------------------------------
# 应用 WiFi 优化（OEM 兼容性由 oem_compat.sh 过滤）
# ----------------------------------------------------------------------
apply_wifi() {
    [ "$ENABLE_WIFI_OPTIMIZE" = "true" ] || {
        echo "WiFi 优化已禁用 (config.sh: ENABLE_WIFI_OPTIMIZE=false)"
        return 0
    }

    echo "=== 应用 WiFi 优化 (OEM 兼容版) ==="

    # 扫描与漫游
    se_put global wifi_scan_throttle_enabled 0
    echo "  [OK] wifi_scan_throttle_enabled = 0"

    se_put global wifi_framework_scan_interval_ms 15000
    echo "  [OK] wifi_framework_scan_interval_ms = 15000"

    se_put global wifi_suspend_optimizations_enabled 0
    echo "  [OK] wifi_suspend_optimizations_enabled = 0"

    se_put global wifi_idle_ms "$WIFI_IDLE_MS"
    echo "  [OK] wifi_idle_ms = $WIFI_IDLE_MS"

    # 信号阈值
    se_put global wifi_bad_rssi_threshold "-$WIFI_BAD_RSSI"
    se_put global wifi_bad_rssi_threshold_2g "-$WIFI_BAD_RSSI"
    se_put global wifi_bad_rssi_threshold_5g "-$WIFI_BAD_RSSI"
    echo "  [OK] wifi_bad_rssi_threshold = -$WIFI_BAD_RSSI dBm"

    # 网络评分
    se_put global wifi_networks_score_enabled 0
    echo "  [OK] wifi_networks_score_enabled = 0"

    # 驻留时间
    se_put global wifi_max_dwell_time_ms 60000
    echo "  [OK] wifi_max_dwell_time_ms = 60000"

    # MAC 随机化（OEM 兼容性过滤后, 部分 OEM/API 会跳过）
    se_put global wifi_enhanced_mac_randomization_enabled 1
    se_put global wifi_connected_mac_randomization_enabled 1
    echo "  [OK] MAC 随机化启用 (如设备/OEM 支持)"

    # PNO 频率阈值（小米会跳过）
    se_put global wifi_pno_frequency_threshold 2
    echo "  [OK] wifi_pno_frequency_threshold = 2"

    # 持久化组延迟（华为/荣耀会跳过）
    se_put global wifi_persistent_group_remove_delay_ms 30000
    echo "  [OK] wifi_persistent_group_remove_delay_ms = 30000"

    log_msg "WiFi 优化已应用" "[wifi]"
    return 0
}

# ----------------------------------------------------------------------
# 状态显示（含 5G 频段识别）
# ----------------------------------------------------------------------
show_wifi_status() {
    echo "=== WiFi 设置状态 v${SE_VERSION} ==="
    echo ""
    echo "[扫描与漫游]"
    echo "  scan_throttle_enabled       : $(se_get global wifi_scan_throttle_enabled) (0=关闭)"
    echo "  scan_interval_ms            : $(se_get global wifi_framework_scan_interval_ms)"
    echo "  pno_frequency_threshold     : $(se_get global wifi_pno_frequency_threshold)"
    echo ""
    echo "[休眠与空闲]"
    echo "  suspend_optimizations       : $(se_get global wifi_suspend_optimizations_enabled) (0=关闭)"
    echo "  idle_ms                     : $(se_get global wifi_idle_ms)"
    echo "  persistent_group_delay      : $(se_get global wifi_persistent_group_remove_delay_ms)"
    echo ""
    echo "[信号与驻留]"
    echo "  bad_rssi_threshold          : $(se_get global wifi_bad_rssi_threshold) dBm"
    echo "  bad_rssi_threshold_2g       : $(se_get global wifi_bad_rssi_threshold_2g) dBm"
    echo "  bad_rssi_threshold_5g       : $(se_get global wifi_bad_rssi_threshold_5g) dBm"
    echo "  networks_score_enabled      : $(se_get global wifi_networks_score_enabled)"
    echo "  max_dwell_time_ms           : $(se_get global wifi_max_dwell_time_ms)"
    echo ""
    echo "[MAC 随机化]"
    echo "  enhanced_mac_randomization  : $(se_get global wifi_enhanced_mac_randomization_enabled)"
    echo "  connected_mac_randomization : $(se_get global wifi_connected_mac_randomization_enabled)"
    echo ""
    echo "[实时状态]"
    local rssi
    rssi=$(se_get_wifi_rssi)
    echo "  当前 WiFi RSSI: ${rssi:-未连接} dBm"

    # 信号等级判定
    if [ -n "$rssi" ] && [ "$rssi" != "?" ]; then
        case "$rssi" in
            ''|*[!0-9-]*) ;;
            *)
                if [ "$rssi" -gt -50 ] 2>/dev/null; then
                    echo "  信号等级      : 极好"
                elif [ "$rssi" -gt -65 ] 2>/dev/null; then
                    echo "  信号等级      : 良好"
                elif [ "$rssi" -gt -75 ] 2>/dev/null; then
                    echo "  信号等级      : 一般"
                elif [ "$rssi" -gt -85 ] 2>/dev/null; then
                    echo "  信号等级      : 较弱"
                else
                    echo "  信号等级      : 极弱"
                fi
                ;;
        esac
    fi

    # 频段与链路速率显示（Android 14+ 支持）
    if se_is_android_14_plus; then
        echo "  当前频段      : $(cmd wifi status 2>/dev/null | grep -i 'frequency' | head -1 | awk '{print $NF}')"
    fi
    return 0
}

# ----------------------------------------------------------------------
# 还原 WiFi 设置
# ----------------------------------------------------------------------
reset_wifi() {
    echo "=== 还原 WiFi 设置 ==="
    se_put global wifi_scan_throttle_enabled 1
    se_put global wifi_framework_scan_interval_ms 30000
    se_put global wifi_suspend_optimizations_enabled 1
    se_del global wifi_idle_ms
    se_del global wifi_bad_rssi_threshold
    se_del global wifi_bad_rssi_threshold_2g
    se_del global wifi_bad_rssi_threshold_5g
    se_put global wifi_networks_score_enabled 1
    se_del global wifi_max_dwell_time_ms
    se_del global wifi_enhanced_mac_randomization_enabled
    se_del global wifi_connected_mac_randomization_enabled
    se_del global wifi_pno_frequency_threshold
    se_del global wifi_persistent_group_remove_delay_ms
    echo "[OK] WiFi 设置已还原为系统默认"
    log_msg "WiFi 设置已还原" "[wifi]"
    return 0
}

case "$1" in
    apply)   apply_wifi ;;
    status)  show_wifi_status ;;
    reset)   reset_wifi ;;
    *)
        echo "WiFi 优化工具 v${SE_VERSION}"
        echo "用法: sh wifi.sh <apply|status|reset>"
        echo "  apply   应用 WiFi 优化"
        echo "  status  查看当前 WiFi 设置"
        echo "  reset   还原系统默认"
        ;;
esac
exit 0
