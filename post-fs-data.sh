#!/system/bin/sh
# post-fs-data.sh — 网络增强
# AxManager BOOT_COMPLETED first sync 阶段（一次性静态优化）
# 此阶段仅执行 settings 写入，不启动后台进程

SE_BOOTSTRAP_PWD="$(pwd 2>/dev/null)"

_se_find_common() {
    if [ -n "$SE_BOOTSTRAP_PWD" ] && [ -f "$SE_BOOTSTRAP_PWD/scripts/common.sh" ] 2>/dev/null; then
        echo "$SE_BOOTSTRAP_PWD/scripts/common.sh"; return 0
    fi
    if [ -n "${AXERONDIR:-}" ] && [ -f "$AXERONDIR/plugins/Network_Enhance/scripts/common.sh" ] 2>/dev/null; then
        echo "$AXERONDIR/plugins/Network_Enhance/scripts/common.sh"; return 0
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

log_msg "网络增强 v${SE_VERSION} 启动 (post-fs-data)" "[boot]"
log_msg "环境=$(detect_env) brand=${SE_BRAND:-?} api=${SE_API:-?} pwd=$(pwd)" "[boot]"

# ===============================
# Android 版本检测
# ===============================
if ! se_is_android_14_plus; then
    log_msg "[WARN] 当前 Android API=$(se_get_api) 低于 34, 部分功能可能受限" "[boot]"
fi

# ===============================
# 迁移 system.prop 功能到 settings global
# ===============================
# 原 system.prop 内容:
#   persist.sys.satellite_earth.version=1.0
#   persist.sys.satellite_earth.activated=1
# 迁移为 settings put global（自定义键, 免Root可写, 仅作状态标记）
se_put global network_enhance_version "$SE_VERSION"
se_put global network_enhance_activated 1
log_msg "已迁移 system.prop 功能到 settings global" "[boot]"

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
# 移动网络优化（修正运营商默认值）
# ===============================
# AOSP RILConstants.java 权威数值表:
#   电信: 26 → 27 (NR/LTE/CDMA/EvDo/GSM/WCDMA, 原26不含CDMA致电信失语音)
#   移动: 23 → 32 (NR/LTE/TD-SCDMA/GSM/WCDMA, 原23是NR only致丢失4G回退)
#   联通: 26   (原模块正确, NR/LTE/GSM/WCDMA)
#   广电: 26 → 33 (NR/LTE/TD-SCDMA/CDMA/EvDo/GSM/WCDMA, 全制式)
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

    # 使用 se_put_safe_verify 确保华为/荣耀/三星写入可靠性
    case "$carrier" in
        telecom)
            # 电信: 27（修正值，原26不含CDMA致电信失语音）
            se_put_safe_verify global preferred_network_mode1 27
            se_put_safe_verify global preferred_network_mode 27
            ;;
        mobile)
            # 移动: 32（修正值，原23是NR only致丢失4G回退）
            se_put_safe_verify global preferred_network_mode1 32
            se_put_safe_verify global preferred_network_mode 32
            [ "$ENABLE_5G_SA" = "true" ] && se_put global nr_sa_mode 1
            ;;
        unicom)
            # 联通: 26 (原模块正确)
            se_put_safe_verify global preferred_network_mode1 26
            se_put_safe_verify global preferred_network_mode 26
            ;;
        ctn)
            # 广电: 33（修正值，全制式含5G）
            se_put_safe_verify global preferred_network_mode1 33
            se_put_safe_verify global preferred_network_mode 33
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

# ===============================
# 主流程（此阶段不启动 monitor.sh）
# ===============================
# 此阶段仅执行一次性静态 settings 写入
# monitor.sh 主循环在 service.sh (late_start 阶段) 启动
apply_wifi_optimize
apply_mobile_optimize
apply_persistent_group

log_msg "post-fs-data 阶段优化完成 (monitor.sh 不在此启动)" "[boot]"
exit 0
