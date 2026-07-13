#!/system/bin/sh
# uninstall.sh — 卫星地球 Pro v6.3.0 卸载清理脚本

SE_BOOTSTRAP_PWD="$(pwd 2>/dev/null)"

_se_find_common() {
    if [ -n "$SE_BOOTSTRAP_PWD" ] && [ -f "$SE_BOOTSTRAP_PWD/scripts/common.sh" ] 2>/dev/null; then
        echo "$SE_BOOTSTRAP_PWD/scripts/common.sh"; return 0
    fi
    if [ -n "${AXERONDIR:-}" ] && [ -f "$AXERONDIR/plugins/Satellite_Earth/scripts/common.sh" ] 2>/dev/null; then
        echo "$AXERONDIR/plugins/Satellite_Earth/scripts/common.sh"; return 0
    fi
    if [ -n "${MODPATH:-}" ] && [ -f "$MODPATH/scripts/common.sh" ] 2>/dev/null; then
        echo "$MODPATH/scripts/common.sh"; return 0
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

log_msg "开始卸载清理..." "[uninstall]"

# 停止调度器
if [ -f "$SE_PID_FILE" ]; then
    mon_pid=$(cat "$SE_PID_FILE" 2>/dev/null)
    if [ -n "$mon_pid" ] && kill -0 "$mon_pid" 2>/dev/null; then
        kill "$mon_pid" 2>/dev/null
        sleep 1
        kill -9 "$mon_pid" 2>/dev/null
        log_msg "调度器进程已停止 (PID=$mon_pid)" "[uninstall]"
    fi
    rm -f "$SE_PID_FILE" "$SE_STATE_FILE"
fi
rm -f "$WEAKNET_ACTIVE_FLAG" "$DNS_PREFETCH_PID" 2>/dev/null

# Private DNS 恢复默认
se_del global private_dns_mode
se_del global private_dns_spec
se_put global private_dns_mode "opportunistic"

# WiFi 设置还原
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
se_del global wifi_batched_scan_results_ms
se_del global wifi_recovery_state

# 移动网络设置还原
se_put global mobile_data_always_on 0
se_del global mobile_data_preferred
se_del global mobile_data_auto_handover
se_del global preferred_network_mode1
se_del global preferred_network_mode
se_del global nr_sa_mode
se_del global vonr_enabled
se_del global enable_nr_dc
se_del global endc_capability
se_del global nr_handover_enabled
se_del global data_stall_alarm_aggressive
se_del global data_stall_alarm_non_aggressive
se_del global vt_enabled
se_put global volte_vt_enabled 1

# weaknet 额外项
se_put global low_power_mode 0
se_put global low_power_sticky 0

se_notify_cancel

log_msg "卫星地球 Pro v${SE_VERSION} 已卸载" "[uninstall]"
exit 0
