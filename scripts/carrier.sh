#!/system/bin/sh
# carrier.sh — 运营商识别 & 网络制式优化 v1.0
#
# preferred_network_mode 默认值 (AOSP RILConstants):
#   电信(telecom): 27 (NR/LTE/CDMA/EvDo/GSM/WCDMA)
#   移动(mobile):  32 (NR/LTE/TD-SCDMA/GSM/WCDMA)
#   联通(unicom):  26 (NR/LTE/GSM/WCDMA)
#   广电(ctn):     33 (NR/LTE/TD-SCDMA/CDMA/EvDo/GSM/WCDMA)
#
# LTE 锁定: mode=11, 5G→4G 降级: mode=9

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
# se_verify_network_type_changed — 验证 PNM 写入后网络制式是否实际切换
# 三星等 ROM 可能写入成功但未生效，通过 dumpsys telephony.registry 检查
# 参数: $1 = 期望制式 (LTE/NR), $2 = 等待秒数 (默认 5)
# 返回: 0 = 已切换, 1 = 未切换
# ----------------------------------------------------------------------
se_verify_network_type_changed() {
    local expected="$1"
    local wait_sec="${2:-5}"
    # 防御: 非数值入参回退到默认等待时间
    case "$wait_sec" in
        ''|*[!0-9]*) wait_sec=5 ;;
    esac

    # 多次轮询检测（最多 5 次）, 应对网络注册延迟
    local i
    for i in 1 2 3 4 5; do
        sleep "$wait_sec" 2>/dev/null
        local reg
        reg=$(dumpsys telephony.registry 2>/dev/null)

        # 从 mServiceState 提取 voice/data 网络制式
        # 输出格式: ... CMCC CMCC 46000 ... LTE LTE ...
        #          ^ first match  = voice, second match = data
        local mstate_line
        mstate_line=$(echo "$reg" | grep 'mServiceState=' | head -1)

        if [ -n "$mstate_line" ]; then
            # 提取 voice 和 data 网络制式
            local voice_tech data_tech
            voice_tech=$(echo "$mstate_line" | grep -oE '(LTE|NR|WCDMA|GSM|CDMA|EvDo|TDSCDMA|HSPA|UMTS|EDGE|GPRS)' | head -1)
            data_tech=$(echo "$mstate_line" | grep -oE '(LTE|NR|WCDMA|GSM|CDMA|EvDo|TDSCDMA|HSPA|UMTS|EDGE|GPRS)' | sed -n '2p' 2>/dev/null)
            # 部分 ROM 输出仅包含 voice tech, data 行缺失时复用 voice 值
            [ -z "$data_tech" ] && data_tech="$voice_tech"

            # $expected 支持通配匹配: "LTE" 或 "NR/LTE" 均可, 灵活应对多制式场景
            case "$expected" in
                *LTE*)
                    if [ "$voice_tech" = "LTE" ] || [ "$data_tech" = "LTE" ]; then
                        log_msg "[verify-net] 网络制式已切换: voice=$voice_tech data=$data_tech (期望含 $expected)" "[carrier]"
                        return 0
                    fi
                    ;;
                *NR*)
                    if [ "$voice_tech" = "NR" ] || [ "$data_tech" = "NR" ]; then
                        log_msg "[verify-net] 网络制式已切换: voice=$voice_tech data=$data_tech (期望含 $expected)" "[carrier]"
                        return 0
                    fi
                    ;;
                *)
                    if [ -n "$voice_tech" ] || [ -n "$data_tech" ]; then
                        log_msg "[verify-net] 当前网络制式: voice=$voice_tech data=$data_tech (期望 $expected)" "[carrier]"
                        return 0
                    fi
                    ;;
            esac
        fi
    done

    log_msg "[verify-net] 网络制式未切换到 $expected (5次检测均未匹配)" "[warn]"
    return 1
}

# ----------------------------------------------------------------------
# lock_lte — 锁定 LTE only (mode=11), 用于游戏模式/4G+ 跳频防护
# ----------------------------------------------------------------------
lock_lte() {
    echo "=== 锁定 LTE only (mode=11) ==="

    # 检查 PNM 受限标记
    if se_is_pnm_restricted; then
        echo "  [SKIP] 当前品牌(${SE_BRAND:-?}) PNM 已标记受限, 跳过写入"
        echo "  提示: 可通过 action.sh 菜单 32 清除标记后重试"
        log_msg "[lock_lte] 跳过: PNM 已标记受限 (brand=${SE_BRAND:-?})" "[carrier]"
        return 1
    fi

    # 保存当前 PNM 值（用于后续 unlock_lte 恢复）
    local current_mode
    current_mode=$(se_get global preferred_network_mode 2>/dev/null)
    if [ -n "$current_mode" ] && [ "$current_mode" != "null" ]; then
        echo "$current_mode" > "$SE_5G_BACKUP_FILE" 2>/dev/null
        echo "  [OK] 已备份当前 PNM 值: $current_mode"
        log_msg "[lock_lte] 已备份 PNM=$current_mode 到 $SE_5G_BACKUP_FILE" "[carrier]"
    else
        # 没有当前值则备份运营商默认值
        local carrier default_mode
        carrier=$(se_detect_carrier)
        default_mode=$(se_get_carrier_default_mode "$carrier")
        echo "$default_mode" > "$SE_5G_BACKUP_FILE" 2>/dev/null
        echo "  [OK] 当前无 PNM 值, 备份运营商默认值: $default_mode ($carrier)"
        log_msg "[lock_lte] 备份运营商默认值 mode=$default_mode ($carrier)" "[carrier]"
    fi

    # 使用 se_put_safe_verify 写入 LTE only（自动验证，华为/荣耀/三星兼容）
    local lte_only_mode
    lte_only_mode=$(se_get_lte_only_mode)
    echo "  [..] 写入 preferred_network_mode=$lte_only_mode (LTE only)..."
    # 同时写入 _mode1（SIM2）, 确保双卡场景下主副卡均锁定
    se_put_safe_verify global preferred_network_mode "$lte_only_mode"
    se_put_safe_verify global preferred_network_mode1 "$lte_only_mode"

    # 关闭 ENDC（减少 4G+ 载波聚合跳频）
    # 注意: 只关闭 ENDC 不关闭 enable_nr_dc, 后续 unlock 恢复 ENDC 即可回到 5G
    echo "  [..] 关闭 ENDC (减少 4G+ 载波聚合跳频)..."
    se_put global endc_capability 0

    # 功能性验证: 检查网络制式是否实际切换到 LTE
    echo "  [..] 功能性验证: 等待网络制式切换..."
    if se_verify_network_type_changed "LTE" 5; then
        echo "  [OK] 已锁定 LTE only, 网络制式已切换"
        log_msg "[lock_lte] 锁定 LTE 成功, 网络制式已切换" "[carrier]"
        return 0
    else
        echo "  [WARN] PNM 写入完成但网络制式未切换"
        echo "  可能原因: 当前品牌 ROM 忽略 PNM 切换, 或所在区域无 LTE 信号"
        # 标记 PNM 受限（避免后续反复尝试写入）
        # se_should_verify_write 过滤: 仅华为/荣耀/三星等支持写入验证的品牌才标记,
        # 其他品牌直接写入成功但系统忽略 PNM 的情况极少, 无需标记
        if se_should_verify_write; then
            touch "/data/local/tmp/network_enhance_pnm_restricted_${SE_BRAND:-unknown}" 2>/dev/null
            echo "  [INFO] 已标记 ${SE_BRAND:-?} PNM 受限, 后续将跳过 PNM 切换"
        fi
        log_msg "[lock_lte] PNM 写入但网络制式未切换, 标记 PNM 受限 (brand=${SE_BRAND:-?})" "[warn]"
        return 1
    fi
}

# ----------------------------------------------------------------------
# unlock_lte — 解锁 LTE 恢复 5G, 从备份文件还原 PNM 值
# ----------------------------------------------------------------------
unlock_lte() {
    echo "=== 解锁 LTE, 恢复 5G ==="

    # 读取备份的 PNM 值
    local backup_mode=""
    if [ -f "$SE_5G_BACKUP_FILE" ]; then
        backup_mode=$(cat "$SE_5G_BACKUP_FILE" 2>/dev/null)
    fi

    # 无备份则使用运营商默认值
    if [ -z "$backup_mode" ] || [ "$backup_mode" = "null" ]; then
        local carrier
        carrier=$(se_detect_carrier)
        backup_mode=$(se_get_carrier_default_mode "$carrier")
        echo "  [INFO] 无备份, 使用运营商默认值: $backup_mode ($carrier)"
        log_msg "[unlock_lte] 无备份, 使用运营商默认值 mode=$backup_mode ($carrier)" "[carrier]"
    else
        echo "  [OK] 读取备份 PNM 值: $backup_mode"
        log_msg "[unlock_lte] 读取备份 PNM=$backup_mode" "[carrier]"
    fi

    # 清除 PNM 受限标记（解锁后允许重新尝试 PNM 切换）
    if se_is_pnm_restricted; then
        se_clear_pnm_restricted
        echo "  [OK] 已清除 PNM 受限标记"
    fi

    # 写入备份值（同时写入 _mode1 确保双卡都恢复）
    echo "  [..] 写入 preferred_network_mode=$backup_mode..."
    se_put_safe_verify global preferred_network_mode "$backup_mode"
    se_put_safe_verify global preferred_network_mode1 "$backup_mode"

    # 恢复 ENDC（与 lock_lte 中的关闭操作对称）
    echo "  [..] 恢复 ENDC..."
    se_put global endc_capability 1

    # 清理备份文件（确保下次 lock-lte 重新备份最新值）
    rm -f "$SE_5G_BACKUP_FILE" 2>/dev/null

    # 验证网络制式是否恢复到 5G
    echo "  [..] 功能性验证: 等待网络制式切换..."
    if se_verify_network_type_changed "NR" 5; then
        echo "  [OK] 已恢复 5G, 网络制式已切换"
        log_msg "[unlock_lte] 恢复 5G 成功" "[carrier]"
    else
        echo "  [INFO] 已写入 PNM=$backup_mode, 但网络制式未切换到 5G"
        echo "  可能原因: 当前区域无 5G 信号, 或 ROM 限制"
        log_msg "[unlock_lte] PNM 已写入但未切换到 5G (可能无 5G 信号)" "[carrier]"
    fi
    return 0
}

# ----------------------------------------------------------------------
# degrade_5g_to_4g — 5G 降级到 4G (mode=9), 用于假满格自救
# 与 lock_lte 区别: mode=9 允许 3G 回退, mode=11 严格锁定 LTE
# ----------------------------------------------------------------------
degrade_5g_to_4g() {
    echo "=== 5G 降级到 4G (mode=9) ==="

    # 检查 PNM 受限标记
    if se_is_pnm_restricted; then
        log_msg "[degrade] 跳过: PNM 已标记受限 (brand=${SE_BRAND:-?})" "[carrier]"
        return 1
    fi

    # 保存当前 PNM 值（如未保存过）
    # 与 lock_lte 共用 $SE_5G_BACKUP_FILE, 先 lock 后 degrade 不会覆盖已有备份
    if [ ! -f "$SE_5G_BACKUP_FILE" ]; then
        local current_mode
        current_mode=$(se_get global preferred_network_mode 2>/dev/null)
        if [ -n "$current_mode" ] && [ "$current_mode" != "null" ]; then
            echo "$current_mode" > "$SE_5G_BACKUP_FILE" 2>/dev/null
        else
            local carrier default_mode
            carrier=$(se_detect_carrier)
            default_mode=$(se_get_carrier_default_mode "$carrier")
            echo "$default_mode" > "$SE_5G_BACKUP_FILE" 2>/dev/null
        fi
    fi

    # 写入 LTE/GSM/WCDMA（mode=9）, 保留 ENDC 便于快速恢复 5G
    local lte_preferred_mode
    lte_preferred_mode=$(se_get_lte_preferred_mode)
    se_put_safe_verify global preferred_network_mode "$lte_preferred_mode"
    se_put_safe_verify global preferred_network_mode1 "$lte_preferred_mode"

    log_msg "[degrade] 已降级 5G→4G (mode=$lte_preferred_mode)" "[carrier]"
    return 0
}

# ----------------------------------------------------------------------
# apply_carrier_settings — 按运营商应用网络制式优化
# ----------------------------------------------------------------------
apply_carrier_settings() {
    [ "$ENABLE_MOBILE_OPTIMIZE" = "true" ] || {
        echo "移动网络优化已禁用 (config.sh: ENABLE_MOBILE_OPTIMIZE=false)"
        return 0
    }

    local carrier="$1"
    # 运营商解析链: 函数参数 → 全局 $CARRIER → 自动识别
    # 三种方式优先级递减, 确保无论何种调用方式都能正确识别
    [ -z "$carrier" ] && carrier="$CARRIER"
    [ "$carrier" = "auto" ] && carrier=$(se_detect_carrier)

    if [ "$carrier" = "auto" ] || [ -z "$carrier" ] || [ "$carrier" = "off" ]; then
        echo "未应用运营商优化 (carrier=$carrier)"
        echo "可在 config.sh 中手动指定 CARRIER=telecom|mobile|unicom|ctn"
        return 1
    fi

    echo "=== 应用运营商优化: $carrier (v1.0 OEM 兼容版) ==="

    # --- 基础数据设置 ---
    # 保持移动数据常开、优先切换到数据网络、自动切换
    se_put global mobile_data_always_on 1
    echo "  [OK] mobile_data_always_on = 1"

    se_put global mobile_data_preferred 1
    echo "  [OK] mobile_data_preferred = 1"

    se_put global mobile_data_auto_handover 1
    echo "  [OK] mobile_data_auto_handover = 1"

    # --- 语音与视频通话增强（VoLTE / VoNR / VT）---
    se_put global volte_vt_enabled 1
    se_put global vonr_enabled 1
    se_put global vt_enabled 1
    echo "  [OK] VoLTE / VoNR / VT 启用"

    # --- 5G 载波聚合与切换 ---
    # enable_nr_dc + endc_capability + nr_handover_enabled 协同工作
    # 关闭任意一个都可能影响 5G 连接稳定性和切换性能
    se_put global enable_nr_dc 1
    se_put global endc_capability 1
    se_put global nr_handover_enabled 1
    echo "  [OK] 5G DC + ENDC + Handover 启用"

    # 运营商默认值修正 (AOSP RILConstants 权威值)
    # 先写 _mode1 再写 _mode: 部分 ROM 在 mode1 写入后会自动同步到 mode
    case "$carrier" in
        telecom)
            # 电信: 27 (NR/LTE/CDMA/EvDo/GSM/WCDMA)
            se_put_safe_verify global preferred_network_mode1 27
            se_put_safe_verify global preferred_network_mode 27
            echo "  [OK] 中国电信: NR/LTE/CDMA/EvDo/GSM/WCDMA (mode=27)"
            ;;
        mobile)
            # 移动: 32 (NR/LTE/TD-SCDMA/GSM/WCDMA)
            se_put_safe_verify global preferred_network_mode1 32
            se_put_safe_verify global preferred_network_mode 32
            # 移动/广电支持 SA（ENABLE_5G_SA 控制）, 电信/联通仅 NSA 在国内更稳定
            if [ "$ENABLE_5G_SA" = "true" ]; then
                se_put global nr_sa_mode 1
                echo "  [OK] 中国移动: NR/LTE/TD-SCDMA/GSM/WCDMA + VoLTE + 5G SA (mode=32)"
            else
                echo "  [OK] 中国移动: NR/LTE/TD-SCDMA/GSM/WCDMA + VoLTE (mode=32, 5G SA 关)"
            fi
            ;;
        unicom)
            # 联通: 26 (NR/LTE/GSM/WCDMA)
            se_put_safe_verify global preferred_network_mode1 26
            se_put_safe_verify global preferred_network_mode 26
            echo "  [OK] 中国联通: NR/LTE/GSM/WCDMA + VoLTE (mode=26)"
            ;;
        ctn)
            # 广电: 33 (NR/LTE/TD-SCDMA/CDMA/EvDo/GSM/WCDMA)
            se_put_safe_verify global preferred_network_mode1 33
            se_put_safe_verify global preferred_network_mode 33
            if [ "$ENABLE_5G_SA" = "true" ]; then
                se_put global nr_sa_mode 1
                echo "  [OK] 中国广电: NR/LTE/TD-SCDMA/CDMA/EvDo/GSM/WCDMA + VoLTE + 5G SA (mode=33)"
            else
                echo "  [OK] 中国广电: 全制式 + VoLTE (mode=33, 5G SA 关)"
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
    # getprop 读取的是 SIM 卡上报的运营商信息（MCC-MNC + 名称）
    # se_detect_carrier 是算法级识别（综合 MCC-MNC + PLMN + 广播判断）
    # 两者可能不一致（如漫游场景）, 同时展示便于排查
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

    # 显示 PNM 受限状态
    if se_is_pnm_restricted; then
        echo "  PNM 受限     : WARN 已标记 (PNM 切换可能无效)"
    elif se_should_verify_write; then
        echo "  PNM 受限     : OK 未受限 (启用写入验证)"
    else
        echo "  PNM 受限     : OK 未受限"
    fi
    echo ""

    echo "  当前设置:"
    echo "    preferred_network_mode     : $(se_get global preferred_network_mode)"
    echo "    preferred_network_mode1    : $(se_get global preferred_network_mode1)"
    echo "    mobile_data_always_on      : $(se_get global mobile_data_always_on)"
    echo "    mobile_data_preferred      : $(se_get global mobile_data_preferred)"
    echo "    mobile_data_auto_handover  : $(se_get global mobile_data_auto_handover)"
    echo "    volte_vt_enabled           : $(se_get global volte_vt_enabled)"
    echo "    vonr_enabled               : $(se_get global vonr_enabled)"
    echo "    nr_sa_mode                 : $(se_get global nr_sa_mode)"
    echo "    enable_nr_dc               : $(se_get global enable_nr_dc)"
    echo "    endc_capability            : $(se_get global endc_capability)"
    echo "    nr_handover_enabled        : $(se_get global nr_handover_enabled)"
    echo ""

    # 显示备份的 PNM 值
    if [ -f "$SE_5G_BACKUP_FILE" ]; then
        echo "  5G 备份值    : $(cat "$SE_5G_BACKUP_FILE" 2>/dev/null)"
    fi
    return 0
}

reset_carrier() {
    echo "=== 还原运营商设置 ==="
    # mobile_data_always_on / volte_vt_enabled 需显式重置为系统默认值
    # 其余 se_del 删除即可让系统使用内置默认值，避免残留自定义项
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

    # 清理 5G 备份文件
    rm -f "$SE_5G_BACKUP_FILE" 2>/dev/null

    # 清除 PNM 受限标记
    se_clear_pnm_restricted 2>/dev/null

    echo "[OK] 运营商设置已还原"
    log_msg "运营商设置已还原" "[mobile]"
    return 0
}

case "$1" in
    # 简单命令: 单行内联调用, 参数透传
    apply)   apply_carrier_settings "$2" ;;
    detect)  se_detect_carrier ;;
    status)  show_carrier_status ;;
    reset)   reset_carrier ;;
    # 复杂命令: 多行格式, 调用独立封装的函数
    lock-lte)
        lock_lte
        ;;
    unlock-lte)
        unlock_lte
        ;;
    degrade)
        degrade_5g_to_4g
        ;;
    verify-net)
        se_verify_network_type_changed "$2" 5
        ;;
    *)
        echo "运营商识别 + 网络制式优化 v${SE_VERSION}"
        echo ""
        echo "用法: sh carrier.sh <命令>"
        echo ""
        echo "命令:"
        echo "  apply [carrier]   应用运营商优化"
        echo "  detect            仅识别当前运营商"
        echo "  status            查看当前状态"
        echo "  reset             还原系统默认"
        echo "  lock-lte          锁定 LTE only (mode=11, 游戏模式用)"
        echo "  unlock-lte        解锁 LTE, 恢复运营商默认 5G 模式"
        echo "  degrade           5G 降级到 4G (mode=9, 假满格自救用)"
        echo "  verify-net <key>  功能性验证: 检查网络制式是否为 <key> (LTE/NR)"
        echo ""
        echo "运营商默认 preferred_network_mode 值:"
        echo "  电信 (telecom) : 27 (NR/LTE/CDMA/EvDo/GSM/WCDMA)"
        echo "  移动 (mobile)  : 32 (NR/LTE/TD-SCDMA/GSM/WCDMA)"
        echo "  联通 (unicom)  : 26 (NR/LTE/GSM/WCDMA)"
        echo "  广电 (ctn)     : 33 (NR/LTE/TD-SCDMA/CDMA/EvDo/GSM/WCDMA)"
        ;;
esac
exit 0
