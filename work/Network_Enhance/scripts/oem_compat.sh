#!/system/bin/sh
# oem_compat.sh — 网络增强 v1.0 OEM 兼容性数据库
#
# ⚠️ 修改点 1: 厂商矩阵保留并扩展（S1 原 6 厂商 + S3 国产差异表）
# ⚠️ 修改点 2: 华为/荣耀 PNM 写入支持（用户补充要求 + S3 第5节）
#   - 5G NR 私有键跳过（避免崩溃）
#   - 但 preferred_network_mode 不跳过（S3 Reddit 反馈可用）
# ⚠️ 修改点 3: 新增 se_should_verify_write() 品牌标记函数（用户细节提醒 3）
#   - 华为/荣耀返回 0（需要写入验证）
#   - 其他品牌返回 1（已知可用）
# ⚠️ 修改点 4: se_show_oem_info() 显示 PNM 支持情况
# ⚠️ 修改点 5: 版本号与命名统一为 v1.0 / network_enhance
#
# 来源:
#   S1 第一步: 原模块 v6.3.0 OEM 矩阵
#   S3 第三步: 国产手机 Android 14/15 网络设置差异表
#     - 小米 HyperOS: https://www.reddit.com/r/HyperOS/
#     - vivo OriginOS: https://www.reddit.com/r/Vivo/
#     - 华为 HarmonyOS: https://www.reddit.com/r/Huawei/
#     - 荣耀 MagicOS: https://www.reddit.com/r/Honor/

# ----------------------------------------------------------------------
# 厂商探测（保留 S1 原逻辑）
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
# 修改点 3: 品牌标记函数 - 是否需要写入验证（用户细节提醒 3）
# ----------------------------------------------------------------------
# 来源: S3 第5节国产差异表 + 用户补充要求 4
#   华为/荣耀: PNM 写入可能受限, 必须用 se_put_verify 验证
#   小米/vivo/三星/OPPO: 已知 PNM 可用, 用 se_put 即可
# 返回值: 0 = 需要写入验证, 1 = 不需要
se_should_verify_write() {
    local brand="${SE_BRAND:-$(se_detect_brand)}"
    case "$brand" in
        huawei|honor)
            return 0  # 需要写入验证（S3 Reddit 反馈部分版本受限）
            ;;
        samsung)
            return 0  # 修改点: 三星纳入验证（S3 "部分版本会忽略" 更隐蔽）
            ;;
        *)
            return 1  # 已知可用
            ;;
    esac
}

# ----------------------------------------------------------------------
# 修改点 2: 品牌是否支持 preferred_network_mode 切换（S3 关键修正）
# ----------------------------------------------------------------------
# 来源: S3 第5节 国产手机 Android 14/15 网络设置差异表
#   - OPPO/小米/vivo: 完全支持
#   - 三星 OneUI: 可用但部分版本会忽略
#   - 华为/荣耀: 可用但 5G NR 键跳过（用户补充要求 5）
#   - 未知品牌: 保守可用
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
# 厂商 × 键 兼容性矩阵（保留 S1 原逻辑 + S3 修正）
# ----------------------------------------------------------------------
# 返回值: 0=可写, 1=跳过, 2=替换
# 关键修正（修改点 2）:
#   - 华为/荣耀: preferred_network_mode 不再跳过（S3 + 用户补充要求）
#   - 5G NR 私有键仍跳过（避免崩溃）
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

    # 修改点 2: preferred_network_mode 全品牌不跳过（S3 修正）
    # 原 S1 中华为/荣耀跳过此键, 但 S3 Reddit 反馈 PNM 仍可用
    case "$key" in
        preferred_network_mode|preferred_network_mode1)
            # 全品牌支持（S3 修正）
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
            # 修改点 2: 5G NR 私有键跳过, 但 PNM 不跳过（已在上方处理）
            case "$key" in
                nr_sa_mode|enable_nr_dc|endc_capability|nr_handover_enabled|vonr_enabled)
                                            return 1 ;;  # HarmonyOS 跳过避免崩溃
                wifi_persistent_group_remove_delay_ms) return 1 ;;  # HarmonyOS 私有实现
            esac
            ;;
        oppo|oneplus|realme)
            : # 全部支持（主测试环境, S1）
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
# 安全写入封装（保留 S1 v6.3.0 强化错误吞没）
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
# 修改点 3: 带验证的安全写入封装（华为/荣耀/三星专用）
# ----------------------------------------------------------------------
# 用户细节提醒 1: se_put_verify 改为循环验证 3 次
# 用户细节提醒 3: 华为/荣耀/三星品牌必须调用 se_put_verify 而非 se_put
# 用户细节问题 1: 其他品牌必须走 se_put (保留 OEM 过滤), 不能直接 settings put
# 此函数封装了 OEM 兼容性过滤 + 写入验证的完整流程
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
                # 修改点: 其他品牌走标准 OEM 过滤写入（保留 nr_sa_mode→nr_mode 等替换逻辑）
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
# 来源: 用户细节提醒 3 + se_put_safe_verify 标记机制
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
# 厂商信息一次性探测（保留 S1 原逻辑 + 修改点 5 命名更新）
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
# 修改点 4: 厂商信息展示（增加 PNM 支持情况显示）
# ----------------------------------------------------------------------
se_show_oem_info() {
    echo "[OEM 兼容性信息]"
    echo "  品牌        : ${SE_BRAND:-未探测}"
    echo "  型号        : ${SE_MODEL:-未知}"
    echo "  Android 版本: ${SE_ROM_VER:-?} (API ${SE_API:-?})"
    echo "  芯片平台    : ${SE_SOC:-未知}"
    echo "  ROM 标识    : ${SE_ROM_NAME:-未知}"
    echo ""

    # 修改点 4: PNM 支持情况（S3 新增）
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

    # 运营商默认值显示（S3 修正后的正确值）
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
