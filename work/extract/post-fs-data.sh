#!/system/bin/sh
# post-fs-data.sh — 卫星地球 Pro v6.3.0
# BOOT_COMPLETED 首次同步阶段，应用一次性静态优化

# v6.3.0 Bootstrap: 立即锁定 MODDIR
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

log_msg "卫星地球 Pro v${SE_VERSION} 启动 (post-fs-data)" "[boot]"
log_msg "环境=$(detect_env) brand=${SE_BRAND:-?} api=${SE_API:-?} pwd=$(pwd)" "[boot]"

# ===============================
# WiFi 优化
# ===============================
apply_wifi_optimize() {
    [ "$ENABLE_WIFI_OPTIMIZE" = "true" ] || { log_msg "WiFi 优化已禁用" "[wifi]"; return 0; }

    se_put global wifi_scan_throttle_enabled 0
    se_put global wifi_framework_scan_interval_ms 15000
    se_put global wifi_suspend_optimizations_enabled 0
    se_put global wifi_idle_ms "$WIFI_IDLE_MS"
    se_put global wifi_bad_rssi_threshold "-$WIFI_BAD_RSSI"
    se_put global wifi_bad_rssi_threshold_2g "-$WIFI_BAD_RSSI"
    se_put global wifi_bad_rssi_threshold_5g "-$WIFI_BAD_RSSI"
    se_put global wifi_networks_score_enabled 0
    se_put global wifi_max_dwell_time_ms 60000
    se_put global wifi_enhanced_mac_randomization_enabled 1
    se_put global wifi_connected_mac_randomization_enabled 1
    se_put global wifi_pno_frequency_threshold 2
    log_msg "WiFi 优化已应用 (OEM 兼容过滤后)" "[wifi]"
    return 0
}

# ===============================
# 移动网络优化
# ===============================
apply_mobile_optimize() {
    [ "$ENABLE_MOBILE_OPTIMIZE" = "true" ] || { log_msg "移动网络优化已禁用" "[mobile]"; return 0; }

    se_put global mobile_data_always_on 1
    se_put global mobile_data_preferred 1
    se_put global mobile_data_auto_handover 1
    se_put global volte_vt_enabled 1
    se_put global vonr_enabled 1
    se_put global vt_enabled 1
    se_put global enable_nr_dc 1
    se_put global endc_capability 1
    se_put global nr_handover_enabled 1

    local carrier="$CARRIER"
    [ "$carrier" = "auto" ] && carrier=$(se_detect_carrier)

    case "$carrier" in
        telecom)
            se_put global preferred_network_mode1 26
            se_put global preferred_network_mode 26
            ;;
        mobile)
            se_put global preferred_network_mode1 23
            se_put global preferred_network_mode 23
            [ "$ENABLE_5G_SA" = "true" ] && se_put global nr_sa_mode 1
            ;;
        unicom)
            se_put global preferred_network_mode1 23
            se_put global preferred_network_mode 23
            ;;
        ctn)
            se_put global preferred_network_mode1 26
            se_put global preferred_network_mode 26
            [ "$ENABLE_5G_SA" = "true" ] && se_put global nr_sa_mode 1
            ;;
        off)
            log_msg "运营商优化已禁用 (CARRIER=off)" "[mobile]"
            return 0
            ;;
        *)
            log_msg "运营商未识别，跳过网络制式优化" "[mobile]"
            ;;
    esac

    log_msg "移动网络优化已应用 | 运营商=${carrier} | 5G_SA=${ENABLE_5G_SA}" "[mobile]"
    return 0
}

apply_persistent_group() {
    se_put global wifi_persistent_group_remove_delay_ms 30000
    log_msg "WiFi 持久化组延迟已应用 (30000ms)" "[wifi]"
    return 0
}

# 主流程
apply_wifi_optimize
apply_mobile_optimize
apply_persistent_group

log_msg "post-fs-data 阶段优化完成" "[boot]"
exit 0
