#!/system/bin/sh
# oem_compat.sh — 网络增强 OEM 兼容性数据库

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
# 品牌是否需要写入验证
# ----------------------------------------------------------------------
# 华为/荣耀: PNM 写入可能受限, 须用 se_put_verify 验证
# 三星: 部分版本会忽略写入, 也纳入验证
# 其他品牌: 已知 PNM 可用, 直接写入
# 返回值: 0 = 需要写入验证, 1 = 不需要
se_should_verify_write() {
    local brand="${SE_BRAND:-$(se_detect_brand)}"
    case "$brand" in
        huawei|honor)
            return 0  # 需要写入验证（部分版本受限）
            ;;
        samsung)
            return 0  # 三星部分版本会忽略写入
            ;;
        *)
            return 1  # 已知可用
            ;;
    esac
}

# ----------------------------------------------------------------------
# 品牌是否支持 preferred_network_mode 切换
# ----------------------------------------------------------------------
# OPPO/小米: 完全支持; 三星: 可用但部分版本会忽略;
# 华为/荣耀: PNM 可用, 但 5G NR 私有键跳过; 未知: 保守可用
# 返回值: 0 = 支持, 1 = 不支持
se_is_brand_supports_pnm() {
    local brand="${SE_BRAND:-$(se_detect_brand)}"
    case "$brand" in
        oppo|oneplus|realme|xiaomi|redmi|poco)
            return 0  # 完全支持
            ;;
        vivo|iqoo|bbk)
            return 0  # 基础键可用
            ;;
        samsung)
            return 0  # 可用但部分版本会忽略
            ;;
        huawei|honor)
            return 0  # PNM 可用, 5G NR 键跳过
            ;;
        meizu|asus|unknown)
            return 0  # 保守可用
            ;;
        *)
            return 0  # 默认保守可用
            ;;
    esac
}

# ----------------------------------------------------------------------
# 厂商 × 键 兼容性矩阵
# ----------------------------------------------------------------------
# 返回值: 0=可写, 1=跳过, 2=替换
# 关键: 华为/荣耀的 preferred_network_mode 不跳过（S3 修正）,
#   但 5G NR 私有键仍跳过（避免崩溃）
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

    # preferred_network_mode 全品牌不跳过（S3 修正: PNM 仍可用）
    case "$key" in
        preferred_network_mode|preferred_network_mode1)
            # 全品牌支持
            se_is_brand_supports_pnm && return 0 || return 1
            ;;
    esac

    case "$brand" in
        xiaomi)
            case "$key" in
                nr_sa_mode)                 return 2 ;;  # 替换为 nr_mode
                data_stall_alarm_aggressive|data_stall_alarm_non_aggressive)
                                            return 2 ;;  # 替换为 MIUI 私有键
                mobile_data_auto_handover)  return 2 ;;  # 替换为 mobile_data_auto_switch
                wifi_pno_frequency_threshold) return 1 ;;  # MIUI 不支持
                wifi_recovery_state)        return 1 ;;  # MIUI 私有实现不同
            esac
            ;;
        vivo|bbk)
            case "$key" in
                nr_sa_mode)                 return 1 ;;  # 会导致 telephony 崩溃
                enable_nr_dc)               return 1 ;;  # 部分机型 modem 重启
                wifi_enhanced_mac_randomization_enabled) return 1 ;;  # OriginOS 6 移除
                data_stall_alarm_aggressive|data_stall_alarm_non_aggressive)
                                            return 1 ;;  # OriginOS 私有实现
            esac
            ;;
        samsung)
            case "$key" in
                nr_sa_mode|enable_nr_dc|endc_capability|nr_handover_enabled)
                                            return 1 ;;  # OneUI 跳过
                wifi_max_dwell_time_ms)     return 1 ;;
            esac
            ;;
        huawei|honor)
            # 5G NR 私有键跳过, 但 PNM 不跳过（已在上方处理）
            case "$key" in
                nr_sa_mode|enable_nr_dc|endc_capability|nr_handover_enabled|vonr_enabled)
                                            return 1 ;;  # HarmonyOS 跳过避免崩溃
                wifi_persistent_group_remove_delay_ms) return 1 ;;  # HarmonyOS 私有实现
            esac
            ;;
        oppo|oneplus|realme)
            : # 全部支持
            ;;
    esac

    case "$soc" in
        mediatek)
            case "$key" in
                endc_capability)            return 1 ;;  # MTK 芯片跳过
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
# 安全写入封装（含 OEM 兼容性过滤 + 键名替换）
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
# 带验证的安全写入封装（华为/荣耀/三星专用）
# ----------------------------------------------------------------------
# 封装 OEM 兼容性过滤 + 写入验证完整流程:
#   - 华为/荣耀/三星: 写入后循环验证 (se_put_verify)
#   - 其他品牌: 走标准 OEM 过滤写入 (se_put)
# 用法: se_put_safe_verify global preferred_network_mode 11
se_put_safe_verify() {
    local namespace="$1"
    local key="$2"
    local value="$3"

    se_key_supported "$key" 2>/dev/null
    local support=$?

    case "$support" in
        0)
            # 可安全写入
            if se_should_verify_write; then
                # 华为/荣耀/三星: 写入并循环验证
                if se_put_verify "$namespace" "$key" "$value"; then
                    log_msg "[oem-verify] $namespace.$key=$value 写入验证成功 (brand=${SE_BRAND:-?})" "[oem]"
                else
                    log_msg "[oem-verify] $namespace.$key=$value 写入验证失败 (brand=${SE_BRAND:-?}, 标记 PNM 受限)" "[warn]"
                    # 标记该品牌 PNM 受限, 避免后续反复尝试无效写入
                    touch "/data/local/tmp/network_enhance_pnm_restricted_${SE_BRAND:-unknown}" 2>/dev/null
                fi
            else
                # 其他品牌走标准 OEM 过滤写入（保留 nr_sa_mode→nr_mode 等替换逻辑）
                se_put "$namespace" "$key" "$value"
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
# 检测当前品牌是否已被标记为 PNM 受限
# ----------------------------------------------------------------------
# 返回值: 0 = PNM 受限, 1 = 正常
se_is_pnm_restricted() {
    local brand="${SE_BRAND:-$(se_detect_brand)}"
    [ -f "/data/local/tmp/network_enhance_pnm_restricted_${brand}" ] 2>/dev/null
}

# 清除 PNM 受限标记（用户手动重新尝试时使用）
se_clear_pnm_restricted() {
    local brand="${SE_BRAND:-$(se_detect_brand)}"
    rm -f "/data/local/tmp/network_enhance_pnm_restricted_${brand}" 2>/dev/null
    log_msg "[oem] 已清除 ${brand} PNM 受限标记" "[oem]"
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
# 厂商信息展示（含 PNM 支持情况）
# ----------------------------------------------------------------------
se_show_oem_info() {
    echo "[OEM 兼容性信息]"
    echo "  品牌        : ${SE_BRAND:-未探测}"
    echo "  型号        : ${SE_MODEL:-未知}"
    echo "  Android 版本: ${SE_ROM_VER:-?} (API ${SE_API:-?})"
    echo "  芯片平台    : ${SE_SOC:-未知}"
    echo "  ROM 标识    : ${SE_ROM_NAME:-未知}"
    echo ""

    # PNM 支持情况
    echo "[preferred_network_mode 支持情况]"
    if se_is_brand_supports_pnm; then
        if se_is_pnm_restricted; then
            echo "  状态        : WARN PNM 写入受限（验证失败, 已标记）"
            echo "  建议        : 可通过 action.sh 菜单 32（解锁LTE）清除标记重试"
        else
            echo "  状态        : OK 当前品牌支持 PNM 切换"
        fi
    else
        echo "  状态        : FAIL 当前品牌不支持 PNM 切换"
    fi

    # 是否需要写入验证
    if se_should_verify_write; then
        echo "  写入验证    : ON 华为/荣耀/三星品牌, 启用写入验证"
    else
        echo "  写入验证    : OFF 已知可用品牌, 直接写入"
    fi
    echo ""

    echo "[运营商默认 preferred_network_mode 值]"
    echo "  电信 (telecom) : 27 (NR/LTE/CDMA/EvDo/GSM/WCDMA)"
    echo "  移动 (mobile)  : 32 (NR/LTE/TD-SCDMA/GSM/WCDMA)"
    echo "  联通 (unicom)  : 26 (NR/LTE/GSM/WCDMA)"
    echo "  广电 (ctn)     : 33 (NR/LTE/TD-SCDMA/CDMA/EvDo/GSM/WCDMA)"
    local current_carrier
    current_carrier=$(se_detect_carrier 2>/dev/null)
    if [ -n "$current_carrier" ] && [ "$current_carrier" != "auto" ]; then
        local default_mode
        default_mode=$(se_get_carrier_default_mode "$current_carrier")
        echo "  当前运营商    : $current_carrier (默认值 $default_mode)"
    fi
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
    echo ""
    return 0
}
