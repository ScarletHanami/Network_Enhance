#!/system/bin/sh
# carrier.sh — 卫星地球 Pro v6.3.0 运营商识别 + 网络模式优化

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

apply_carrier_settings() {
    [ "$ENABLE_MOBILE_OPTIMIZE" = "true" ] || {
        echo "移动网络优化已禁用 (config.sh: ENABLE_MOBILE_OPTIMIZE=false)"
        return 0
    }

    local carrier="$1"
    [ -z "$carrier" ] && carrier="$CARRIER"
    [ "$carrier" = "auto" ] && carrier=$(se_detect_carrier)

    if [ "$carrier" = "auto" ] || [ -z "$carrier" ] || [ "$carrier" = "off" ]; then
        echo "未应用运营商优化 (carrier=$carrier)"
        echo "可在 config.sh 中手动指定 CARRIER=telecom|mobile|unicom|ctn"
        return 1
    fi

    echo "=== 应用运营商优化: $carrier (v6.3.0 OEM 兼容版) ==="

    se_put global mobile_data_always_on 1
    echo "  [OK] mobile_data_always_on = 1"

    se_put global mobile_data_preferred 1
    echo "  [OK] mobile_data_preferred = 1"

    se_put global mobile_data_auto_handover 1
    echo "  [OK] mobile_data_auto_handover = 1"

    se_put global volte_vt_enabled 1
    se_put global vonr_enabled 1
    se_put global vt_enabled 1
    echo "  [OK] VoLTE / VoNR / VT 启用"

    se_put global enable_nr_dc 1
    se_put global endc_capability 1
    se_put global nr_handover_enabled 1
    echo "  [OK] 5G DC + ENDC + Handover 启用"

    case "$carrier" in
        telecom)
            se_put global preferred_network_mode1 26
            se_put global preferred_network_mode 26
            echo "  [OK] 中国电信: NR/LTE/CDMA/EvDo/GSM/WCDMA"
            ;;
        mobile)
            se_put global preferred_network_mode1 23
            se_put global preferred_network_mode 23
            if [ "$ENABLE_5G_SA" = "true" ]; then
                se_put global nr_sa_mode 1
                echo "  [OK] 中国移动: NR/LTE/TDSCDMA + VoLTE + 5G SA"
            else
                echo "  [OK] 中国移动: NR/LTE/TDSCDMA + VoLTE (5G SA 关)"
            fi
            ;;
        unicom)
            se_put global preferred_network_mode1 23
            se_put global preferred_network_mode 23
            echo "  [OK] 中国联通: NR/LTE/TDSCDMA + VoLTE"
            ;;
        ctn)
            se_put global preferred_network_mode1 26
            se_put global preferred_network_mode 26
            if [ "$ENABLE_5G_SA" = "true" ]; then
                se_put global nr_sa_mode 1
                echo "  [OK] 中国广电: NR/LTE + VoLTE + 5G SA"
            else
                echo "  [OK] 中国广电: NR/LTE + VoLTE (5G SA 关)"
            fi
            ;;
        *)
            echo "未知运营商: $carrier"
            return 1
            ;;
    esac

    log_msg "运营商优化已应用: $carrier | 5G_SA=$ENABLE_5G_SA | brand=${SE_BRAND}" "[mobile]"
    return 0
}

show_carrier_status() {
    local detected
    detected=$(se_detect_carrier)
    local mccmnc carrier_name
    mccmnc=$(getprop gsm.sim.operator.numeric 2>/dev/null | head -1)
    carrier_name=$(getprop gsm.sim.operator.alpha 2>/dev/null | head -1)

    echo "=== 运营商状态 ==="
    echo "  SIM 卡运营商 : ${carrier_name:-未知}"
    echo "  MCC-MNC      : ${mccmnc:-未知}"
    echo "  自动识别     : $detected"
    echo "  配置选择     : ${CARRIER:-auto}"
    echo "  5G SA 启用   : ${ENABLE_5G_SA:-true}"
    echo "  OEM 兼容     : ${ENABLE_OEM_COMPAT:-true}"
    echo "  设备品牌     : ${SE_BRAND:-未探测}"
    echo ""
    echo "  当前设置:"
    echo "    mobile_data_always_on      : $(se_get global mobile_data_always_on)"
    echo "    mobile_data_preferred      : $(se_get global mobile_data_preferred)"
    echo "    mobile_data_auto_handover  : $(se_get global mobile_data_auto_handover)"
    echo "    preferred_network_mode     : $(se_get global preferred_network_mode)"
    echo "    volte_vt_enabled           : $(se_get global volte_vt_enabled)"
    echo "    vonr_enabled               : $(se_get global vonr_enabled)"
    echo "    nr_sa_mode                 : $(se_get global nr_sa_mode)"
    echo "    enable_nr_dc               : $(se_get global enable_nr_dc)"
    echo "    endc_capability            : $(se_get global endc_capability)"
    echo "    nr_handover_enabled        : $(se_get global nr_handover_enabled)"
    return 0
}

reset_carrier() {
    echo "=== 还原运营商设置 ==="
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
    se_del global vt_enabled
    se_put global volte_vt_enabled 1
    echo "[OK] 运营商设置已还原"
    log_msg "运营商设置已还原" "[mobile]"
    return 0
}

case "$1" in
    apply)   apply_carrier_settings "$2" ;;
    detect)  se_detect_carrier ;;
    status)  show_carrier_status ;;
    reset)   reset_carrier ;;
    *)
        echo "用法: sh carrier.sh <apply|detect|status|reset>"
        echo "  apply [carrier]  应用运营商优化"
        echo "  detect           仅识别当前运营商"
        echo "  status           查看当前状态"
        echo "  reset            还原系统默认"
        ;;
esac
exit 0
