#!/system/bin/sh
# oem_compat.sh — 卫星地球 Pro v6.3.0 OEM 兼容性数据库
#
# v6.3.0: 沿用 v6.2.0 的厂商矩阵，强化 se_put_safe 错误吞没

# ----------------------------------------------------------------------
# 厂商探测
# ----------------------------------------------------------------------
se_detect_brand() {
    local brand
    brand=$(getprop ro.product.brand 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')
    [ -z "$brand" ] && brand=$(getprop ro.product.vendor.brand 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')
    [ -z "$brand" ] && brand=$(getprop ro.build.product 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')

    case "$brand" in
        redmi|poco|xiaomi)         echo "xiaomi" ;;
        oppo|oneplus|realme)        echo "oppo" ;;
        vivo|iqoo|bbk)              echo "vivo" ;;
        samsung)                    echo "samsung" ;;
        honor)                      echo "honor" ;;
        huawei|emui)                echo "huawei" ;;
        meizu)                      echo "meizu" ;;
        asus)                       echo "asus" ;;
        *)                          echo "${brand:-unknown}" ;;
    esac
}

se_detect_api() {
    local api
    api=$(getprop ro.build.version.sdk 2>/dev/null | head -1)
    [ -z "$api" ] && api=30
    echo "$api"
}

se_detect_soc() {
    local hw
    hw=$(getprop ro.hardware 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')
    case "$hw" in
        *qcom*|*msm*|*sm*)      echo "qualcomm" ;;
        *mt*|*mediatek*|*mtk*)  echo "mediatek" ;;
        *kirin*|*hi*)           echo "hisilicon" ;;
        *exynos*)               echo "exynos" ;;
        *)                      echo "unknown" ;;
    esac
}

# ----------------------------------------------------------------------
# 厂商 × 键 兼容性矩阵
# ----------------------------------------------------------------------
# 返回值: 0=可写, 1=跳过, 2=替换
se_key_supported() {
    local key="$1"
    local brand="${SE_BRAND:-$(se_detect_brand)}"
    local api="${SE_API:-$(se_detect_api)}"
    local soc="${SE_SOC:-$(se_detect_soc)}"

    # 全局规则: API < 30 不支持 MAC 随机化
    case "$key" in
        wifi_enhanced_mac_randomization_enabled|wifi_connected_mac_randomization_enabled)
            [ "$api" -lt 30 ] 2>/dev/null && return 1
            ;;
    esac

    case "$brand" in
        xiaomi)
            case "$key" in
                nr_sa_mode)                 return 2 ;;
                data_stall_alarm_aggressive|data_stall_alarm_non_aggressive)
                                            return 2 ;;
                mobile_data_auto_handover)  return 2 ;;
                wifi_pno_frequency_threshold) return 1 ;;
                wifi_recovery_state)        return 1 ;;
            esac
            ;;
        vivo|bbk)
            case "$key" in
                nr_sa_mode)                 return 1 ;;
                enable_nr_dc)               return 1 ;;
                wifi_enhanced_mac_randomization_enabled) return 1 ;;
                data_stall_alarm_aggressive|data_stall_alarm_non_aggressive)
                                            return 1 ;;
            esac
            ;;
        samsung)
            case "$key" in
                nr_sa_mode|enable_nr_dc|endc_capability|nr_handover_enabled)
                                            return 1 ;;
                wifi_max_dwell_time_ms)     return 1 ;;
            esac
            ;;
        huawei|honor)
            case "$key" in
                nr_sa_mode|enable_nr_dc|endc_capability|nr_handover_enabled|vonr_enabled)
                                            return 1 ;;
                wifi_persistent_group_remove_delay_ms) return 1 ;;
            esac
            ;;
        oppo|oneplus|realme)
            : # 全部支持
            ;;
    esac

    case "$soc" in
        mediatek)
            case "$key" in
                endc_capability)            return 1 ;;
            esac
            ;;
        hisilicon|exynos)
            case "$key" in
                enable_nr_dc|endc_capability|nr_handover_enabled) return 1 ;;
            esac
            ;;
    esac

    return 0
}

se_key_replacement() {
    local key="$1"
    local brand="${SE_BRAND:-$(se_detect_brand)}"

    case "$brand" in
        xiaomi)
            case "$key" in
                nr_sa_mode)                         echo "nr_mode" ;;
                data_stall_alarm_aggressive)        echo "data_stall_alarm_interval" ;;
                data_stall_alarm_non_aggressive)    echo "data_stall_alarm_interval_long" ;;
                mobile_data_auto_handover)          echo "mobile_data_auto_switch" ;;
            esac
            ;;
    esac
}

# ----------------------------------------------------------------------
# 安全写入封装（v6.3.0: 强化错误吞没，确保永不非零退出）
# ----------------------------------------------------------------------
se_put_safe() {
    local namespace="$1"
    local key="$2"
    local value="$3"

    se_key_supported "$key" 2>/dev/null
    local support=$?

    case "$support" in
        0)
            # 可安全写入
            if settings put "$namespace" "$key" "$value" 2>/dev/null; then
                :
            else
                log_msg "[oem] 写入失败: $namespace.$key=$value" "[warn]"
            fi
            return 0
            ;;
        1)
            # 跳过
            log_msg "[oem] 跳过 $namespace.$key (brand=${SE_BRAND:-?} 不支持)" "[oem]"
            return 0
            ;;
        2)
            # 替换键名
            local new_key
            new_key=$(se_key_replacement "$key" 2>/dev/null)
            if [ -n "$new_key" ]; then
                log_msg "[oem] 替换 $key → $new_key (brand=${SE_BRAND:-?})" "[oem]"
                if settings put "$namespace" "$new_key" "$value" 2>/dev/null; then
                    :
                else
                    log_msg "[oem] 替换键写入失败: $namespace.$new_key=$value" "[warn]"
                fi
            else
                log_msg "[oem] 替换键名为空: $key" "[warn]"
            fi
            return 0
            ;;
    esac
    return 0
}

# ----------------------------------------------------------------------
# 厂商信息一次性探测
# ----------------------------------------------------------------------
se_probe_oem_env() {
    SE_BRAND=$(se_detect_brand 2>/dev/null)
    SE_API=$(se_detect_api 2>/dev/null)
    SE_SOC=$(se_detect_soc 2>/dev/null)
    SE_MODEL=$(getprop ro.product.model 2>/dev/null | head -1)
    SE_ROM_VER=$(getprop ro.build.version.release 2>/dev/null | head -1)
    SE_ROM_NAME=$(getprop ro.build.display.id 2>/dev/null | head -1)

    export SE_BRAND SE_API SE_SOC SE_MODEL SE_ROM_VER SE_ROM_NAME

    log_msg "[oem] brand=${SE_BRAND} model=${SE_MODEL} api=${SE_API} soc=${SE_SOC} rom=${SE_ROM_NAME}" "[oem]"
    return 0
}

# ----------------------------------------------------------------------
# 厂商信息展示
# ----------------------------------------------------------------------
se_show_oem_info() {
    echo "[OEM 兼容性信息]"
    echo "  品牌        : ${SE_BRAND:-未探测}"
    echo "  型号        : ${SE_MODEL:-未知}"
    echo "  Android 版本: ${SE_ROM_VER:-?} (API ${SE_API:-?})"
    echo "  芯片平台    : ${SE_SOC:-未知}"
    echo "  ROM 标识    : ${SE_ROM_NAME:-未知}"
    echo ""
    echo "[本机型已知不兼容键]"
    local skipped=0
    for key in nr_sa_mode enable_nr_dc endc_capability nr_handover_enabled \
               wifi_enhanced_mac_randomization_enabled wifi_pno_frequency_threshold \
               wifi_recovery_state data_stall_alarm_aggressive \
               data_stall_alarm_non_aggressive mobile_data_auto_handover \
               wifi_max_dwell_time_ms wifi_persistent_group_remove_delay_ms \
               vonr_enabled; do
        se_key_supported "$key" 2>/dev/null
        case $? in
            1) echo "  [跳过] $key"; skipped=$((skipped + 1)) ;;
            2) echo "  [替换] $key → $(se_key_replacement "$key" 2>/dev/null)"; skipped=$((skipped + 1)) ;;
        esac
    done
    [ "$skipped" = "0" ] && echo "  (本机型全部键可安全写入)"
    return 0
}
