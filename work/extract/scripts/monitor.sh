#!/system/bin/sh
# monitor.sh — 卫星地球 Pro v6.3.0 动态自适应调度器

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

get_level_display_name() {
    case "$1" in
        strong)    echo "强信号 (省电)" ;;
        normal)    echo "正常" ;;
        weak)      echo "弱信号自救" ;;
        critical)  echo "极限自救" ;;
        no_network) echo "无网络" ;;
        *)         echo "未知" ;;
    esac
}

get_level_description() {
    case "$1" in
        strong)    echo "允许休眠+扫描慢+省电" ;;
        normal)    echo "标准优化+扫描中" ;;
        weak)      echo "极限容忍+移动数据兜底" ;;
        critical)  echo "全力保活+扫描激进+ping反馈" ;;
        no_network) echo "等待网络恢复" ;;
        *)         echo "" ;;
    esac
}

compute_overall_level_v2() {
    local net_type="$1" wifi_rssi="$2" mobile_dbm="$3" ping_ms="$4"

    # v6.3.1: 无网络时直接返回 no_network（避免空值导致后续比较崩溃）
    if [ -z "$net_type" ] || [ "$net_type" = "none" ]; then
        echo "no_network"
        return 0
    fi

    local wifi_lvl="unknown"
    local mobile_lvl="unknown"

    # WiFi 等级计算（v6.3.1: 空值容错）
    if [ -n "$wifi_rssi" ] && [ "$wifi_rssi" != "?" ]; then
        local abs_r=""
        if [ "$wifi_rssi" -lt 0 ] 2>/dev/null; then
            abs_r=$((-wifi_rssi))
        elif [ "$wifi_rssi" -gt 0 ] 2>/dev/null; then
            abs_r="$wifi_rssi"
        fi
        if [ -n "$abs_r" ] && [ "$abs_r" -gt 0 ] 2>/dev/null; then
            if [ "$abs_r" -lt "$WIFI_STRONG_RSSI" ] 2>/dev/null; then
                wifi_lvl="strong"
            elif [ "$abs_r" -lt "$WIFI_WEAK_RSSI" ] 2>/dev/null; then
                wifi_lvl="normal"
            else
                wifi_lvl="weak"
            fi
        fi
    fi

    # 移动等级计算（v6.3.1: 空值容错，无 SIM 卡时 mobile_lvl 保持 unknown）
    local mlevel=""
    mlevel=$(se_get_mobile_level 2>/dev/null)
    if [ -n "$mlevel" ]; then
        case "$mlevel" in
            4)         mobile_lvl="strong" ;;
            2|3)       mobile_lvl="normal" ;;
            0|1)       mobile_lvl="weak" ;;
            *)         mobile_lvl="normal" ;;
        esac
    elif [ -n "$mobile_dbm" ] && [ "$mobile_dbm" != "?" ] && [ "$mobile_dbm" != "" ]; then
        local abs_d=""
        if [ "$mobile_dbm" -lt 0 ] 2>/dev/null; then
            abs_d=$((-mobile_dbm))
        elif [ "$mobile_dbm" -gt 0 ] 2>/dev/null; then
            abs_d="$mobile_dbm"
        fi
        if [ -n "$abs_d" ] && [ "$abs_d" -gt 0 ] 2>/dev/null; then
            if [ "$abs_d" -lt "$MOBILE_STRONG_DBM" ] 2>/dev/null; then
                mobile_lvl="strong"
            elif [ "$abs_d" -le "$MOBILE_WEAK_DBM" ] 2>/dev/null; then
                mobile_lvl="normal"
            else
                mobile_lvl="weak"
            fi
        fi
    fi

    # 基础等级判定（v6.3.1: 按 net_type 决策，unknown 降级到 normal）
    local base_level="normal"
    case "$net_type" in
        wifi)
            case "$wifi_lvl" in
                strong|normal|weak) base_level="$wifi_lvl" ;;
                *)                  base_level="normal" ;;
            esac
            ;;
        mobile)
            case "$mobile_lvl" in
                strong|normal|weak) base_level="$mobile_lvl" ;;
                *)                  base_level="normal" ;;
            esac
            ;;
        dual)
            if [ "$wifi_lvl" = "weak" ] || [ "$mobile_lvl" = "weak" ]; then
                base_level="weak"
            elif [ "$wifi_lvl" = "strong" ] && [ "$mobile_lvl" = "strong" ]; then
                base_level="strong"
            else
                base_level="normal"
            fi
            ;;
        *)      base_level="normal" ;;
    esac

    # ping 反馈调节（v6.3.1: 空值容错）
    local ping_critical=0 ping_bad=0
    if [ "$ENABLE_PING_FEEDBACK" = "true" ] && [ "$ping_ms" != "?" ] && [ -n "$ping_ms" ]; then
        case "$ping_ms" in
            ''|*[!0-9]*) ;;
            *)
                if [ "$ping_ms" -ge "$PING_BAD_MS" ] 2>/dev/null; then
                    ping_critical=1
                elif [ "$ping_ms" -ge "$PING_GOOD_MS" ] 2>/dev/null && [ "$ping_ms" -lt "$PING_BAD_MS" ] 2>/dev/null; then
                    ping_bad=1
                fi
                ;;
        esac
    fi

    if [ "$ping_critical" = "1" ]; then
        if [ "$base_level" = "weak" ]; then
            echo "critical"
        else
            echo "weak"
        fi
        return 0
    fi
    if [ "$ping_bad" = "1" ] && [ "$base_level" = "strong" ]; then
        echo "normal"
        return 0
    fi
    echo "$base_level"
    return 0
}

apply_dynamic_params() {
    local level="$1"
    local rssi_abs="$2"

    case "$level" in
        strong|normal|weak|critical|no_network) ;;
        *) level="normal" ;;
    esac

    case "$level" in
        strong|normal)
            se_put global data_stall_alarm_aggressive 0
            se_put global data_stall_alarm_non_aggressive 0
            se_del global enable_nr_dc
            se_del global endc_capability
            se_del global nr_handover_enabled
            se_del global vonr_enabled
            ;;
        weak)
            se_put global data_stall_alarm_non_aggressive 0
            ;;
    esac

    local params interval scan_ms bad_rssi mobile_ka ping_chk
    params=$(se_compute_dynamic_params "$level" "$rssi_abs" 2>/dev/null)
    # v6.3.3: 确保 params 非空
    [ -z "$params" ] && params="600 15000 -88 1 1"
    interval=$(echo "$params" | awk '{print $1}')
    scan_ms=$(echo "$params" | awk '{print $2}')
    bad_rssi=$(echo "$params" | awk '{print $3}')
    mobile_ka=$(echo "$params" | awk '{print $4}')
    ping_chk=$(echo "$params" | awk '{print $5}')
    # v6.3.3: 兜底
    [ -z "$interval" ] && interval=600
    [ -z "$scan_ms" ] && scan_ms=15000
    [ -z "$bad_rssi" ] && bad_rssi=-88

    case "$level" in
        strong)
            se_put global wifi_suspend_optimizations_enabled 1
            se_put global wifi_framework_scan_interval_ms "$scan_ms"
            se_put global wifi_bad_rssi_threshold "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_2g "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_5g "$bad_rssi"
            ;;
        normal)
            se_put global wifi_suspend_optimizations_enabled 0
            se_put global wifi_framework_scan_interval_ms "$scan_ms"
            se_put global wifi_bad_rssi_threshold "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_2g "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_5g "$bad_rssi"
            se_put global mobile_data_always_on "$mobile_ka"
            ;;
        weak)
            se_put global wifi_suspend_optimizations_enabled 0
            se_put global wifi_framework_scan_interval_ms "$scan_ms"
            se_put global wifi_bad_rssi_threshold "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_2g "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_5g "$bad_rssi"
            se_put global mobile_data_always_on 1
            se_put global mobile_data_preferred 1
            se_put global mobile_data_auto_handover 1
            se_put global data_stall_alarm_aggressive 1
            ;;
        critical)
            se_put global wifi_suspend_optimizations_enabled 0
            se_put global wifi_framework_scan_interval_ms "$scan_ms"
            se_put global wifi_bad_rssi_threshold "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_2g "$bad_rssi"
            se_put global wifi_bad_rssi_threshold_5g "$bad_rssi"
            se_put global mobile_data_always_on 1
            se_put global mobile_data_preferred 1
            se_put global mobile_data_auto_handover 1
            se_put global data_stall_alarm_aggressive 1
            se_put global data_stall_alarm_non_aggressive 1
            se_put global enable_nr_dc 1
            se_put global endc_capability 1
            se_put global nr_handover_enabled 1
            se_put global volte_vt_enabled 1
            se_put global vonr_enabled 1
            ;;
        no_network)
            :
            ;;
    esac

    # v6.3.3: 确保输出非空
    [ -z "$interval" ] && interval=600
    [ -z "$scan_ms" ] && scan_ms=15000
    [ -z "$bad_rssi" ] && bad_rssi=-88
    echo "${interval} ${scan_ms} ${bad_rssi}"
    return 0
}

write_state() {
    local net_type="$1"
    local level="$2"
    local rssi="$3"
    local dbm="$4"
    local ping_ms="$5"
    local params="$6"
    cat > "${SE_STATE_FILE}.tmp" <<EOF
PID=$$
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
NET_TYPE=$net_type
LEVEL=$level
WIFI_RSSI=$rssi
MOBILE_DBM=$dbm
PING_MS=$ping_ms
PARAMS=$params
EOF
    mv "${SE_STATE_FILE}.tmp" "$SE_STATE_FILE" 2>/dev/null
    return 0
}

send_switch_notification() {
    [ "$ENABLE_SWITCH_NOTIFY" = "true" ] || return 0
    local level="$1" rssi="$2" dbm="$3" ping_ms="$4" net_type="$5"
    local display_name desc
    display_name=$(get_level_display_name "$level")
    desc=$(get_level_description "$level")

    # v6.3.3: 通知发送时如果 ping_ms 为空或"?",重新实时获取一次
    # 原因: 调度器后台 nohup 进程的 ping 可能在等级切换瞬间失败,但通知时网络已恢复
    if [ -z "$ping_ms" ] || [ "$ping_ms" = "?" ]; then
        ping_ms=$(se_get_ping_ms 2>/dev/null)
        [ -z "$ping_ms" ] && ping_ms="?"
    fi

    local title="卫星地球 → ${display_name}"
    local body="策略: ${desc}
网络: ${net_type:-unknown}
延迟: ${ping_ms} ms"
    se_notify "$title" "$body"
    log_msg "[通知] $title | ping=${ping_ms}ms" "[monitor]"
    return 0
}

run_monitor_loop() {
    local current_level="init"
    local loop_count=0

    trap 'rm -f "$SE_PID_FILE" "$SE_STATE_FILE" 2>/dev/null; log_msg "调度器退出 (信号)" "[monitor]"; exit 0' INT TERM
    trap 'rm -f "$SE_PID_FILE" "$SE_STATE_FILE" 2>/dev/null; log_msg "调度器退出 (EXIT)" "[monitor]"' EXIT

    echo $$ > "$SE_PID_FILE" 2>/dev/null

    log_msg "调度器启动 v${SE_VERSION} (PID=$$)" "[monitor]"
    log_msg "动态参数=${ENABLE_DYNAMIC_PARAMS} | ping反馈=${ENABLE_PING_FEEDBACK} | OEM兼容=${ENABLE_OEM_COMPAT}" "[monitor]"
    write_state "init" "init" "?" "?" "?" "0 0 0"

    # v6.3.3: 首轮立即做一次检测并写状态，避免 WebUI 长时间看到 init
    # 关键修复: 不依赖 apply_dynamic_params 的返回值(它内部 fork 大量 settings 子进程可能超时)
    # 改为: 先用 se_compute_dynamic_params 算参数写状态, 再后台 apply_dynamic_params 写 settings
    sleep 2
    local _net_type _wifi_rssi _mobile_dbm _ping_ms _target_level _rssi_abs _applied_params
    _net_type=$(se_detect_network_type 2>/dev/null)
    _wifi_rssi=$(se_get_wifi_rssi 2>/dev/null)
    _mobile_dbm=$(se_get_mobile_dbm 2>/dev/null)
    _ping_ms=$(se_get_ping_ms 2>/dev/null)
    [ -z "$_net_type" ] && _net_type="none"
    [ -z "$_ping_ms" ] && _ping_ms="?"

    _target_level=$(compute_overall_level_v2 "$_net_type" "$_wifi_rssi" "$_mobile_dbm" "$_ping_ms" 2>/dev/null)
    [ -z "$_target_level" ] && _target_level="normal"

    _rssi_abs=0
    if [ -n "$_wifi_rssi" ] && [ "$_wifi_rssi" != "?" ]; then
        case "$_wifi_rssi" in
            ''|*[!0-9-]*) ;;
            *)
                if [ "$_wifi_rssi" -lt 0 ] 2>/dev/null; then
                    _rssi_abs=$((-_wifi_rssi))
                elif [ "$_wifi_rssi" -gt 0 ] 2>/dev/null; then
                    _rssi_abs="$_wifi_rssi"
                fi
                ;;
        esac
    fi

    # v6.3.3: 直接用 se_compute_dynamic_params 算参数(纯计算无副作用,不会超时)
    _applied_params=$(se_compute_dynamic_params "$_target_level" "$_rssi_abs" 2>/dev/null)
    [ -z "$_applied_params" ] && _applied_params="600 15000 -88 1 1"

    current_level="$_target_level"
    write_state "$_net_type" "$_target_level" "${_wifi_rssi:-?}" "${_mobile_dbm:-无}" "$_ping_ms" "$_applied_params"
    log_msg "[首轮] 等级=$current_level net=$_net_type rssi=$_wifi_rssi dbm=$_mobile_dbm ping=${_ping_ms}ms params=$_applied_params" "[monitor]"

    # v6.3.3: settings 写入放到后台,不阻塞主循环
    apply_dynamic_params "$_target_level" "$_rssi_abs" >/dev/null 2>&1 &

    while true; do
        loop_count=$((loop_count + 1))

        if [ -f "$WEAKNET_ACTIVE_FLAG" ]; then
            if [ $((loop_count % 4)) -eq 0 ]; then
                log_msg "[让位] weaknet 激活，跳过本轮" "[monitor]"
            fi
            sleep "$MONITOR_NORMAL_INTERVAL" 2>/dev/null
            continue
        fi

        local net_type wifi_rssi mobile_dbm ping_ms
        net_type=$(se_detect_network_type 2>/dev/null)
        wifi_rssi=$(se_get_wifi_rssi 2>/dev/null)
        mobile_dbm=$(se_get_mobile_dbm 2>/dev/null)
        ping_ms=$(se_get_ping_ms 2>/dev/null)

        # v6.3.3: 空值防御
        [ -z "$net_type" ] && net_type="none"
        [ -z "$ping_ms" ] && ping_ms="?"

        local target_level
        target_level=$(compute_overall_level_v2 "$net_type" "$wifi_rssi" "$mobile_dbm" "$ping_ms" 2>/dev/null)
        [ -z "$target_level" ] && target_level="normal"

        local rssi_abs=0
        if [ -n "$wifi_rssi" ] && [ "$wifi_rssi" != "?" ]; then
            case "$wifi_rssi" in
                ''|*[!0-9-]*) ;;
                *)
                    if [ "$wifi_rssi" -lt 0 ] 2>/dev/null; then
                        rssi_abs=$((-wifi_rssi))
                    elif [ "$wifi_rssi" -gt 0 ] 2>/dev/null; then
                        rssi_abs="$wifi_rssi"
                    fi
                    ;;
            esac
        fi

        if [ "$target_level" != "$current_level" ]; then
            log_msg "[切换] $current_level → $target_level | net=$net_type rssi=$wifi_rssi dbm=$mobile_dbm ping=${ping_ms}ms" "[monitor]"

            # v6.3.3: 用 se_compute_dynamic_params 算参数(纯计算不超时),不依赖 apply_dynamic_params 返回值
            local applied_params
            applied_params=$(se_compute_dynamic_params "$target_level" "$rssi_abs" 2>/dev/null)
            [ -z "$applied_params" ] && applied_params="600 15000 -88 1 1"

            current_level="$target_level"
            write_state "$net_type" "$target_level" "${wifi_rssi:-?}" "${mobile_dbm:-无}" "$ping_ms" "$applied_params"
            send_switch_notification "$current_level" "${wifi_rssi:-?}" "${mobile_dbm:-无}" "$ping_ms" "$net_type"

            # v6.3.3: settings 写入放后台,不阻塞主循环
            apply_dynamic_params "$target_level" "$rssi_abs" >/dev/null 2>&1 &
        fi

        local next_interval
        case "$current_level" in
            strong)    next_interval="$MONITOR_MAX_INTERVAL" ;;
            normal)    next_interval="$MONITOR_NORMAL_INTERVAL" ;;
            weak)      next_interval="$MONITOR_MIN_INTERVAL" ;;
            critical)  next_interval="$MONITOR_MIN_INTERVAL" ;;
            no_network) next_interval="$MONITOR_NORMAL_INTERVAL" ;;
            *)         next_interval="$MONITOR_NORMAL_INTERVAL" ;;
        esac

        if [ $((loop_count % 30)) -eq 0 ]; then
            log_msg "[监控#$loop_count] 等级=$current_level net=$net_type rssi=$wifi_rssi dbm=$mobile_dbm ping=${ping_ms}ms" "[monitor]"
        fi

        sleep "$next_interval" 2>/dev/null
    done
}

start_monitor() {
    [ "$ENABLE_MONITOR" = "true" ] || {
        echo "智能调度器已禁用 (ENABLE_MONITOR=false)"
        return 0
    }

    if se_monitor_running; then
        echo "[INFO] 调度器已在运行 (PID=$(se_monitor_pid))"
        return 0
    fi

    rm -f "$SE_PID_FILE" 2>/dev/null

    if command -v nohup >/dev/null 2>&1; then
        nohup sh "$0" _loop >/dev/null 2>&1 &
    else
        sh "$0" _loop >/dev/null 2>&1 &
    fi
    local new_pid=$!
    echo "$new_pid" > "$SE_PID_FILE" 2>/dev/null

    local tried=0
    while [ "$tried" -lt 5 ]; do
        [ -f "$SE_STATE_FILE" ] && break
        sleep 1
        tried=$((tried + 1))
    done

    if [ -f "$SE_STATE_FILE" ]; then
        echo "[OK] 智能调度器已启动 (PID=$new_pid)"
    else
        echo "[WARN] 调度器启动可能失败，请查看日志: $SE_LOG_FILE"
    fi
    log_msg "调度器启动请求 (PID=$new_pid)" "[monitor]"
    return 0
}

stop_monitor() {
    if ! [ -f "$SE_PID_FILE" ]; then
        echo "[INFO] 调度器未运行"
        return 0
    fi

    local pid
    pid=$(cat "$SE_PID_FILE" 2>/dev/null)
    if [ -z "$pid" ]; then
        rm -f "$SE_PID_FILE" "$SE_STATE_FILE" 2>/dev/null
        echo "[INFO] PID 文件为空，已清理"
        return 0
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        echo "[INFO] 进程 $pid 已不存在"
        rm -f "$SE_PID_FILE" "$SE_STATE_FILE" 2>/dev/null
        return 0
    fi

    if [ -r "/proc/$pid/cmdline" ]; then
        if ! tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "monitor.sh"; then
            echo "[WARN] PID $pid 不是调度器进程，跳过 kill"
            rm -f "$SE_PID_FILE" 2>/dev/null
            return 1
        fi
    fi

    kill "$pid" 2>/dev/null
    local waited=0
    while [ "$waited" -lt 5 ]; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
        waited=$((waited + 1))
    done
    kill -9 "$pid" 2>/dev/null

    echo "[OK] 调度器已停止 (PID=$pid)"
    log_msg "调度器停止 (PID=$pid)" "[monitor]"
    rm -f "$SE_PID_FILE" "$SE_STATE_FILE" 2>/dev/null
    return 0
}

show_status() {
    echo "=== 智能调度器状态 v${SE_VERSION} ==="

    if ! [ -f "$SE_PID_FILE" ]; then
        echo "  状态: 未运行"
        return 0
    fi

    local pid
    pid=$(cat "$SE_PID_FILE" 2>/dev/null)
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        echo "  状态: 进程已退出"
        rm -f "$SE_PID_FILE" "$SE_STATE_FILE" 2>/dev/null
        return 0
    fi

    echo "  状态    : 运行中"
    echo "  PID     : $pid"

    if [ -f "$SE_STATE_FILE" ]; then
        echo ""
        echo "  最近状态:"
        while IFS='=' read -r key value; do
            case "$key" in
                PID)        echo "  PID          : $value" ;;
                TIMESTAMP)  echo "  更新时间     : $value" ;;
                NET_TYPE)   echo "  网络类型     : $value" ;;
                LEVEL)      echo "  当前等级     : $value ($(get_level_display_name "$value"))" ;;
                WIFI_RSSI)  echo "  WiFi RSSI    : $value dBm" ;;
                MOBILE_DBM) echo "  移动 dBm     : $value" ;;
                PING_MS)    echo "  公网延迟     : $value ms" ;;
                PARAMS)     echo "  动态参数     : $value" ;;
            esac
        done < "$SE_STATE_FILE"
    fi

    if [ -f "$WEAKNET_ACTIVE_FLAG" ]; then
        echo ""
        echo "  [!] weaknet 模式激活中，调度器已让位"
    fi
    return 0
}

detect_once() {
    echo "=== 单次网络检测 (动态参数模式) ==="
    local net_type wifi_rssi mobile_dbm ping_ms
    net_type=$(se_detect_network_type)
    wifi_rssi=$(se_get_wifi_rssi)
    mobile_dbm=$(se_get_mobile_dbm)
    ping_ms=$(se_get_ping_ms)

    local target_level
    target_level=$(compute_overall_level_v2 "$net_type" "$wifi_rssi" "$mobile_dbm" "$ping_ms")

    local rssi_abs=0
    if [ -n "$wifi_rssi" ]; then
        if [ "$wifi_rssi" -lt 0 ] 2>/dev/null; then
            rssi_abs=$((-wifi_rssi))
        else
            rssi_abs="$wifi_rssi"
        fi
    fi

    echo "  网络类型     : $net_type"
    echo "  WiFi RSSI    : ${wifi_rssi:-未连接} dBm"
    echo "  移动 dBm     : ${mobile_dbm:-未检测}"
    echo "  公网延迟     : ${ping_ms} ms"
    echo "  综合等级     : $target_level ($(get_level_display_name "$target_level"))"

    if [ -f "$WEAKNET_ACTIVE_FLAG" ]; then
        echo "  [!] weaknet 模式激活中，调度器会跳过参数应用"
    fi
    return 0
}

case "$1" in
    start)   start_monitor ;;
    stop)    stop_monitor ;;
    restart)
        stop_monitor
        local_wait=0
        while se_monitor_running && [ "$local_wait" -lt 5 ]; do
            sleep 1
            local_wait=$((local_wait + 1))
        done
        start_monitor
        ;;
    status)  show_status ;;
    detect)  detect_once ;;
    notify)
        arg_level="${2:-normal}"
        send_switch_notification "$arg_level" "?" "?" "?" "wifi"
        echo "[OK] 通知已发送 (等级=$arg_level)"
        ;;
    cancel)
        se_notify_cancel
        echo "[OK] 已撤销调度器通知"
        ;;
    _loop)   run_monitor_loop ;;
    *)
        echo "卫星地球动态自适应调度器 v${SE_VERSION}"
        echo ""
        echo "用法: sh monitor.sh <命令>"
        echo "命令: start | stop | restart | status | detect | notify | cancel"
        ;;
esac
exit 0
