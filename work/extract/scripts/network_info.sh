#!/system/bin/sh
# network_info.sh — 卫星地球 Pro v6.3.0 网络状态采集工具
# v6.3.0: 强化 dumpsys 解析的多 ROM 兼容性

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

# ----------------------------------------------------------------------
# v6.3.1: WiFi SSID 读取（多 ROM 兼容，覆盖 Android 14/15）
# ----------------------------------------------------------------------
get_wifi_ssid() {
    local ssid=""
    local dump
    dump=$(dumpsys wifi 2>/dev/null)

    # 模式 1: mWifiInfo 行内 SSID:"xxx" (带引号)
    ssid=$(echo "$dump" | grep 'mWifiInfo' 2>/dev/null | head -1 | sed 's/.*SSID:"\([^"]*\)".*/\1/' 2>/dev/null)
    # 验证 sed 是否真的匹配到了（避免返回原文）
    if [ -n "$ssid" ] && echo "$ssid" | grep -q 'mWifiInfo\|WifiInfo\|SSID'; then
        ssid=""
    fi
    [ -n "$ssid" ] && { echo "$ssid"; return 0; }

    # 模式 2: SSID:"ChinaNet-C9D3-5G" (Android 14/15 真实格式，截图中确认)
    ssid=$(echo "$dump" | grep -oE 'SSID:"[^"]+"' 2>/dev/null | head -1 | sed 's/SSID:"//;s/"$//')
    [ -n "$ssid" ] && { echo "$ssid"; return 0; }

    # 模式 3: "ChinaNet-C9D3-5G" 直接带引号的 SSID（截图中确认这种格式）
    ssid=$(echo "$dump" | grep -oE '"[A-Za-z0-9][A-Za-z0-9._-]*-[A-Za-z0-9]+"' 2>/dev/null | head -1 | tr -d '"')
    [ -n "$ssid" ] && { echo "$ssid"; return 0; }

    # 模式 4: mWifiInfo 行内 SSID:xxx (无引号)
    ssid=$(echo "$dump" | grep 'mWifiInfo' 2>/dev/null | head -1 | sed 's/.*SSID:\([^,]*\).*/\1/' 2>/dev/null | tr -d '"' | tr -d ' ')
    if [ -n "$ssid" ] && echo "$ssid" | grep -q 'mWifiInfo\|WifiInfo'; then
        ssid=""
    fi
    [ -n "$ssid" ] && { echo "$ssid"; return 0; }

    # 模式 5: cmd wifi status (Android 11+)
    ssid=$(cmd wifi status 2>/dev/null | grep 'SSID' 2>/dev/null | head -1 | sed 's/.*SSID \([^,]*\).*/\1/' 2>/dev/null | tr -d '"' | tr -d ' ')
    [ -n "$ssid" ] && { echo "$ssid"; return 0; }

    echo "未知"
}

get_wifi_rssi() {
    local rssi
    rssi=$(se_get_wifi_rssi)
    [ -z "$rssi" ] && rssi="?"
    echo "$rssi"
}

# ----------------------------------------------------------------------
# v6.3.1: WiFi 链路速率（多 ROM 兼容，覆盖 Android 14/15）
# ----------------------------------------------------------------------
get_wifi_link_speed() {
    local dump speed
    dump=$(dumpsys wifi 2>/dev/null)

    # 模式 1: mLinkSpeed: 433 (旧 AOSP)
    speed=$(echo "$dump" | grep 'mLinkSpeed' 2>/dev/null | head -1 | grep -oE '[0-9]+' 2>/dev/null | head -1)
    [ -n "$speed" ] && { echo "$speed"; return 0; }

    # 模式 2: linkSpeed=433
    speed=$(echo "$dump" | grep -oE 'linkSpeed=[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$speed" ] && { echo "$speed"; return 0; }

    # 模式 3: Link speed: 1297Mbps (Android 14/15 真实格式，截图中确认)
    speed=$(echo "$dump" | grep -oE 'Link speed: [0-9]+Mbps' 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
    [ -n "$speed" ] && { echo "$speed"; return 0; }

    # 模式 4: Link speed: 1297 (无 Mbps 后缀)
    speed=$(echo "$dump" | grep -oE 'Link speed: [0-9]+' 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
    [ -n "$speed" ] && { echo "$speed"; return 0; }

    # 模式 5: Tx Link speed: 1297Mbps
    speed=$(echo "$dump" | grep -oE 'Tx Link speed: [0-9]+Mbps' 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
    [ -n "$speed" ] && { echo "$speed"; return 0; }

    # 模式 6: cmd wifi status
    speed=$(cmd wifi status 2>/dev/null | grep -i 'speed' 2>/dev/null | grep -oE '[0-9]+' | head -1)
    [ -n "$speed" ] && { echo "$speed"; return 0; }

    echo "?"
}

# ----------------------------------------------------------------------
# v6.3.1: WiFi 频段（多 ROM 兼容，覆盖 Android 14/15）
# ----------------------------------------------------------------------
get_wifi_frequency() {
    local dump freq
    dump=$(dumpsys wifi 2>/dev/null)

    # 模式 1: mFrequency: 5180 (旧 AOSP)
    freq=$(echo "$dump" | grep 'mFrequency' 2>/dev/null | head -1 | grep -oE '[0-9]+' 2>/dev/null | head -1)
    if [ -n "$freq" ]; then
        if [ "$freq" -gt 4000 ] 2>/dev/null; then
            echo "5G"
        else
            echo "2.4G"
        fi
        return 0
    fi

    # 模式 2: frequency=5180
    freq=$(echo "$dump" | grep -oE 'frequency=[0-9]+' 2>/dev/null | head -1 | cut -d= -f2)
    if [ -n "$freq" ]; then
        if [ "$freq" -gt 4000 ] 2>/dev/null; then
            echo "5G"
        else
            echo "2.4G"
        fi
        return 0
    fi

    # 模式 3: Frequency: 5180MHz (Android 14/15 真实格式，截图中确认)
    freq=$(echo "$dump" | grep -oE 'Frequency: [0-9]+MHz' 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
    if [ -n "$freq" ]; then
        if [ "$freq" -gt 4000 ] 2>/dev/null; then
            echo "5G"
        else
            echo "2.4G"
        fi
        return 0
    fi

    # 模式 4: Frequency: 5180 (无 MHz 后缀)
    freq=$(echo "$dump" | grep -oE 'Frequency: [0-9]+' 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
    if [ -n "$freq" ]; then
        if [ "$freq" -gt 4000 ] 2>/dev/null; then
            echo "5G"
        else
            echo "2.4G"
        fi
        return 0
    fi

    # 模式 5: cmd wifi status (Android 11+)
    freq=$(cmd wifi status 2>/dev/null | grep -i 'frequency' 2>/dev/null | grep -oE '[0-9]+' | head -1)
    if [ -n "$freq" ]; then
        if [ "$freq" -gt 4000 ] 2>/dev/null; then
            echo "5G"
        else
            echo "2.4G"
        fi
        return 0
    fi

    echo "?"
}

get_carrier_name() {
    local name
    name=$(getprop gsm.sim.operator.alpha 2>/dev/null | head -1)
    # v6.3.1: 无 SIM 卡时返回"无SIM"而非"?"
    if [ -z "$name" ] || [ "$name" = "Unknown" ] || [ "$name" = "unknown" ]; then
        # 尝试其他属性
        name=$(getprop gsm.operator.alpha 2>/dev/null | head -1)
        if [ -z "$name" ] || [ "$name" = "Unknown" ] || [ "$name" = "unknown" ]; then
            echo "无SIM"
            return 0
        fi
    fi
    echo "$name"
}

get_network_type_name() {
    local rat
    rat=$(getprop gsm.network.type 2>/dev/null | head -1)
    # v6.3.1: 无 SIM 卡或异常值时返回"无"而非"?"
    if [ -z "$rat" ] || [ "$rat" = "Unknown" ] || [ "$rat" = "unknown" ] || [ "$rat" = "NR_SA,Unknown" ]; then
        # 尝试其他属性
        rat=$(getprop gsm.network.type 2>/dev/null | tr ',' '\n' | head -1)
        case "$rat" in
            NR|nr)      echo "5G NR"; return 0 ;;
            LTE|lte)    echo "4G LTE"; return 0 ;;
            *)          ;;
        esac
        echo "无"
        return 0
    fi
    # 处理 "NR_SA,Unknown" 这种逗号分隔的多值
    rat=$(echo "$rat" | cut -d',' -f1)
    case "$rat" in
        NR|nr)                  echo "5G NR" ;;
        LTE|lte)                echo "4G LTE" ;;
        HSDPA|HSUPA|HSPA|HSPA+) echo "3G HSPA" ;;
        UMTS)                   echo "3G UMTS" ;;
        EDGE)                   echo "2G EDGE" ;;
        GPRS)                   echo "2G GPRS" ;;
        *)                      echo "${rat:-无}" ;;
    esac
}

get_mobile_level() {
    local level
    level=$(se_get_mobile_level)
    # v6.3.1: 无 SIM 卡时返回"无"
    [ -z "$level" ] && level="无"
    echo "$level"
}

get_mobile_dbm() {
    local dbm
    dbm=$(se_get_mobile_dbm)
    # v6.3.1: 无 SIM 卡时返回"无"
    [ -z "$dbm" ] && dbm="无"
    echo "$dbm"
}

get_ping_ms() {
    se_get_ping_ms
}

get_realtime_speed() {
    local iface="$1"

    if [ -z "$iface" ] || ! grep -q "^ *${iface}:" /proc/net/dev 2>/dev/null; then
        iface=""
        for candidate in wlan0 rmnet_data0 rmnet0 ccmni0 eth0; do
            if grep -q "^ *${candidate}:" /proc/net/dev 2>/dev/null; then
                local rx_test
                rx_test=$(grep "^ *${candidate}:" /proc/net/dev 2>/dev/null | awk '{print $2}')
                if [ -n "$rx_test" ] && [ "$rx_test" -gt 0 ] 2>/dev/null; then
                    iface="$candidate"
                    break
                fi
            fi
        done
    fi

    [ -z "$iface" ] && { echo "0 0 unknown"; return 0; }

    local rx1 tx1
    rx1=$(grep "^ *${iface}:" /proc/net/dev 2>/dev/null | awk '{print $2}')
    tx1=$(grep "^ *${iface}:" /proc/net/dev 2>/dev/null | awk '{print $10}')
    [ -z "$rx1" ] && { echo "0 0 $iface"; return 0; }

    sleep 1

    local rx2 tx2
    rx2=$(grep "^ *${iface}:" /proc/net/dev 2>/dev/null | awk '{print $2}')
    tx2=$(grep "^ *${iface}:" /proc/net/dev 2>/dev/null | awk '{print $10}')

    local rx_bps tx_bps
    rx_bps=$((rx2 - rx1))
    tx_bps=$((tx2 - tx1))
    [ "$rx_bps" -lt 0 ] 2>/dev/null && rx_bps=0
    [ "$tx_bps" -lt 0 ] 2>/dev/null && tx_bps=0

    echo "$((rx_bps / 1024)) $((tx_bps / 1024)) $iface"
}

format_speed() {
    local kbps="$1"
    [ -z "$kbps" ] && kbps=0
    if [ "$kbps" -lt 1024 ] 2>/dev/null; then
        echo "${kbps} KB/s"
    else
        local mbps=$((kbps / 1024))
        local mbps_dec=$((kbps % 1024 * 10 / 1024))
        echo "${mbps}.${mbps_dec} MB/s"
    fi
}

show_full_status() {
    local net_type
    net_type=$(se_detect_network_type)

    echo "=== 网络状态 (完整) ==="
    echo "  网络类型: $net_type"
    echo ""

    case "$net_type" in
        wifi|dual)
            echo "[WiFi]"
            echo "  SSID     : $(get_wifi_ssid)"
            echo "  RSSI     : $(get_wifi_rssi) dBm"
            echo "  链路速率 : $(get_wifi_link_speed) Mbps"
            echo "  频段     : $(get_wifi_frequency)"
            echo ""
            ;;
    esac

    case "$net_type" in
        mobile|dual)
            echo "[移动网络]"
            echo "  运营商   : $(get_carrier_name)"
            echo "  网络制式 : $(get_network_type_name)"
            echo "  Level    : $(get_mobile_level)/4"
            echo "  dBm      : $(get_mobile_dbm) dBm"
            echo ""
            ;;
    esac

    if [ "$net_type" != "none" ]; then
        echo "[实时速率]"
        local speed_info rx_kbps tx_kbps iface
        speed_info=$(get_realtime_speed)
        rx_kbps=$(echo "$speed_info" | awk '{print $1}')
        tx_kbps=$(echo "$speed_info" | awk '{print $2}')
        iface=$(echo "$speed_info" | awk '{print $3}')
        echo "  接口     : $iface"
        echo "  下行     : $(format_speed "$rx_kbps")"
        echo "  上行     : $(format_speed "$tx_kbps")"
        echo ""
        echo "[公网延迟]"
        echo "  Ping     : $(get_ping_ms) ms"
    else
        echo "[!] 当前无网络连接"
    fi
}

show_brief() {
    local net_type
    net_type=$(se_detect_network_type)
    case "$net_type" in
        wifi)
            echo "WiFi $(get_wifi_ssid) | $(get_wifi_rssi)dBm | $(get_wifi_link_speed)Mbps | 延迟$(get_ping_ms)ms"
            ;;
        mobile)
            echo "$(get_carrier_name) $(get_network_type_name) | Lv$(get_mobile_level)/4 $(get_mobile_dbm)dBm | 延迟$(get_ping_ms)ms"
            ;;
        dual)
            echo "双通道 WiFi $(get_wifi_rssi)dBm + 移动 Lv$(get_mobile_level)/4 | 延迟$(get_ping_ms)ms"
            ;;
        none)
            echo "无网络连接"
            ;;
    esac
}

show_multiline() {
    local net_type
    net_type=$(se_detect_network_type)
    case "$net_type" in
        wifi)
            echo "WiFi: $(get_wifi_ssid) ($(get_wifi_frequency))"
            echo "信号: $(get_wifi_rssi) dBm | 链路: $(get_wifi_link_speed) Mbps"
            echo "延迟: $(get_ping_ms) ms"
            ;;
        mobile)
            echo "$(get_carrier_name) $(get_network_type_name)"
            echo "信号: Lv$(get_mobile_level)/4 | $(get_mobile_dbm) dBm"
            echo "延迟: $(get_ping_ms) ms"
            ;;
        dual)
            echo "WiFi: $(get_wifi_ssid) $(get_wifi_rssi)dBm $(get_wifi_link_speed)Mbps"
            echo "移动: $(get_carrier_name) $(get_network_type_name) Lv$(get_mobile_level)/4 $(get_mobile_dbm)dBm"
            echo "延迟: $(get_ping_ms) ms"
            ;;
        none)
            echo "无网络连接"
            echo "等待网络恢复..."
            ;;
    esac
}

json_escape() {
    local s="$1"
    s=$(printf '%s' "$s" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e 's/\r/\\r/g' | tr '\n' '\f' | sed 's/\f/\\n/g')
    printf '%s' "$s"
}

show_json() {
    # v6.3.2: 每个字段独立采集 + 空值兜底,确保 JSON 始终有效
    local net_type ssid rssi speed freq carrier rat level dbm ping_ms

    net_type=$(se_detect_network_type 2>/dev/null)
    [ -z "$net_type" ] && net_type="none"

    ssid=$(get_wifi_ssid 2>/dev/null)
    [ -z "$ssid" ] && ssid="未知"

    rssi=$(get_wifi_rssi 2>/dev/null)
    [ -z "$rssi" ] && rssi="?"

    speed=$(get_wifi_link_speed 2>/dev/null)
    [ -z "$speed" ] && speed="?"

    freq=$(get_wifi_frequency 2>/dev/null)
    [ -z "$freq" ] && freq="?"

    carrier=$(get_carrier_name 2>/dev/null)
    [ -z "$carrier" ] && carrier="无SIM"

    rat=$(get_network_type_name 2>/dev/null)
    [ -z "$rat" ] && rat="无"

    level=$(get_mobile_level 2>/dev/null)
    [ -z "$level" ] && level="无"

    dbm=$(get_mobile_dbm 2>/dev/null)
    [ -z "$dbm" ] && dbm="无"

    ping_ms=$(se_get_ping_ms 2>/dev/null)
    [ -z "$ping_ms" ] && ping_ms="?"

    echo "{"
    echo "  \"net_type\": \"$(json_escape "$net_type")\","
    echo "  \"wifi\": {"
    echo "    \"ssid\": \"$(json_escape "$ssid")\","
    echo "    \"rssi\": \"$(json_escape "$rssi")\","
    echo "    \"link_speed\": \"$(json_escape "$speed")\","
    echo "    \"frequency\": \"$(json_escape "$freq")\""
    echo "  },"
    echo "  \"mobile\": {"
    echo "    \"carrier\": \"$(json_escape "$carrier")\","
    echo "    \"rat\": \"$(json_escape "$rat")\","
    echo "    \"level\": \"$(json_escape "$level")\","
    echo "    \"dbm\": \"$(json_escape "$dbm")\""
    echo "  },"
    echo "  \"ping_ms\": \"$(json_escape "$ping_ms")\","
    echo "  \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)\""
    echo "}"
}

case "$1" in
    brief)     show_brief ;;
    multiline) show_multiline ;;
    full|"")   show_full_status ;;
    wifi)
        echo "SSID: $(get_wifi_ssid)"
        echo "RSSI: $(get_wifi_rssi) dBm"
        echo "LinkSpeed: $(get_wifi_link_speed) Mbps"
        echo "Freq: $(get_wifi_frequency)"
        ;;
    mobile)
        echo "Carrier: $(get_carrier_name)"
        echo "RAT: $(get_network_type_name)"
        echo "Level: $(get_mobile_level)/4"
        echo "dBm: $(get_mobile_dbm)"
        ;;
    speed)
        local_speed=$(get_realtime_speed "$2")
        rx_kbps=$(echo "$local_speed" | awk '{print $1}')
        tx_kbps=$(echo "$local_speed" | awk '{print $2}')
        iface=$(echo "$local_speed" | awk '{print $3}')
        echo "Interface: $iface"
        echo "下行: $(format_speed "$rx_kbps")"
        echo "上行: $(format_speed "$tx_kbps")"
        ;;
    json)  show_json ;;
    type)  se_detect_network_type ;;
    ping)  echo "$(se_get_ping_ms) ms" ;;
    dynamic)
        net_type=$(se_detect_network_type)
        rssi=$(se_get_wifi_rssi)
        dbm=$(se_get_mobile_dbm)
        ping_ms=$(se_get_ping_ms)
        wifi_lvl=$(se_wifi_level)
        mobile_lvl=$(se_mobile_level)
        overall=$(se_overall_level "$net_type" "$wifi_lvl" "$mobile_lvl" "$ping_ms")
        rssi_abs=0
        if [ -n "$rssi" ]; then
            if [ "$rssi" -lt 0 ] 2>/dev/null; then
                rssi_abs=$((-rssi))
            else
                rssi_abs="$rssi"
            fi
        fi
        params=$(se_compute_dynamic_params "$overall" "$rssi_abs")
        echo "NET_TYPE=$net_type"
        echo "WIFI_RSSI=$rssi"
        echo "WIFI_LEVEL=$wifi_lvl"
        echo "MOBILE_DBM=$dbm"
        echo "MOBILE_LEVEL=$mobile_lvl"
        echo "PING_MS=$ping_ms"
        echo "OVERALL_LEVEL=$overall"
        echo "PARAMS=$params"
        ;;
    quality)
        net_type=$(se_detect_network_type)
        rssi=$(se_get_wifi_rssi)
        dbm=$(se_get_mobile_dbm)
        ping_ms=$(se_get_ping_ms)
        wifi_score=0
        if [ -n "$rssi" ] && [ "$rssi" != "?" ]; then
            abs_r=$rssi
            [ "$rssi" -lt 0 ] 2>/dev/null && abs_r=$((-rssi))
            wifi_score=$(awk -v a="$abs_r" 'BEGIN { s = 100 - (a - 40) * 100 / 60; if (s < 0) s = 0; if (s > 100) s = 100; printf "%d", s }')
        fi
        mobile_score=0
        if [ -n "$dbm" ] && [ "$dbm" != "?" ]; then
            abs_d=$dbm
            [ "$dbm" -lt 0 ] 2>/dev/null && abs_d=$((-dbm))
            mobile_score=$(awk -v a="$abs_d" 'BEGIN { s = 100 - (a - 70) * 100 / 50; if (s < 0) s = 0; if (s > 100) s = 100; printf "%d", s }')
        fi
        ping_score=0
        if [ "$ping_ms" != "?" ] && [ -n "$ping_ms" ]; then
            ping_score=$(awk -v p="$ping_ms" 'BEGIN { s = 100 - (p - 20) * 100 / 480; if (s < 0) s = 0; if (s > 100) s = 100; printf "%d", s }')
        fi
        echo "WIFI_SCORE=$wifi_score"
        echo "MOBILE_SCORE=$mobile_score"
        echo "PING_SCORE=$ping_score"
        case "$net_type" in
            wifi)   overall_score="$wifi_score" ;;
            mobile) overall_score="$mobile_score" ;;
            dual)   overall_score=$(awk -v w="$wifi_score" -v m="$mobile_score" 'BEGIN { printf "%d", (w + m) / 2 }') ;;
            *)      overall_score=0 ;;
        esac
        if [ "$ping_score" -gt 0 ] 2>/dev/null; then
            overall_score=$(awk -v o="$overall_score" -v p="$ping_score" 'BEGIN { printf "%d", (o * 0.6 + p * 0.4) }')
        fi
        echo "OVERALL_SCORE=$overall_score"
        ;;
    *)
        echo "网络状态采集工具 v${SE_VERSION}"
        echo "用法: sh network_info.sh <命令>"
        echo "命令: full | brief | multiline | json | dynamic | quality | wifi | mobile | speed | type | ping"
        ;;
esac
exit 0
