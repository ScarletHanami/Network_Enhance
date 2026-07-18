#!/system/bin/sh
# network_info.sh — 网络增强 网络状态采集工具
#
# 多策略采集 WiFi/移动网络/5G 信号质量及延迟数据,
# 优先使用 cmd wifi status (Android 14+ 更稳定),
# 失败时自动降级 dumpsys wifi 多模式解析,
# 支持 JSON / full / brief 等多种输出格式供 WebUI 使用

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
# WiFi SSID: cmd wifi status 优先 (Android 14+), 失败时降级 dumpsys wifi 多模式解析
# ----------------------------------------------------------------------
get_wifi_ssid() {
    local ssid=""

    # 优先使用 cmd wifi status (Android 14+)
    if se_is_android_14_plus; then
        ssid=$(cmd wifi status 2>/dev/null | grep 'SSID' 2>/dev/null | head -1 | sed 's/.*SSID \([^,]*\).*/\1/' 2>/dev/null | tr -d '"' | tr -d ' ')
        if [ -n "$ssid" ] && [ "$ssid" != "null" ] && [ "$ssid" != "unknown" ]; then
            # 验证不是原文
            if ! echo "$ssid" | grep -q 'SSID\|wifi'; then
                echo "$ssid"
                return 0
            fi
        fi
        ssid=""
    fi

    # 降级: dumpsys wifi 多模式解析
    local dump
    dump=$(dumpsys wifi 2>/dev/null)

    # 模式 1: mWifiInfo 行内 SSID:"xxx" (带引号)
    ssid=$(echo "$dump" | grep 'mWifiInfo' 2>/dev/null | head -1 | sed 's/.*SSID:"\([^"]*\)".*/\1/' 2>/dev/null)
    if [ -n "$ssid" ] && echo "$ssid" | grep -q 'mWifiInfo\|WifiInfo\|SSID'; then
        ssid=""
    fi
    [ -n "$ssid" ] && { echo "$ssid"; return 0; }

    # 模式 2: SSID:"ChinaNet-C9D3-5G" (Android 14/15 真实格式)
    ssid=$(echo "$dump" | grep -oE 'SSID:"[^"]+"' 2>/dev/null | head -1 | sed 's/SSID:"//;s/"$//')
    [ -n "$ssid" ] && { echo "$ssid"; return 0; }

    # 模式 3: "ChinaNet-C9D3-5G" 直接带引号的 SSID
    ssid=$(echo "$dump" | grep -oE '"[A-Za-z0-9][A-Za-z0-9._-]*-[A-Za-z0-9]+"' 2>/dev/null | head -1 | tr -d '"')
    [ -n "$ssid" ] && { echo "$ssid"; return 0; }

    # 模式 4: mWifiInfo 行内 SSID:xxx (无引号)
    ssid=$(echo "$dump" | grep 'mWifiInfo' 2>/dev/null | head -1 | sed 's/.*SSID:\([^,]*\).*/\1/' 2>/dev/null | tr -d '"' | tr -d ' ')
    if [ -n "$ssid" ] && echo "$ssid" | grep -q 'mWifiInfo\|WifiInfo'; then
        ssid=""
    fi
    [ -n "$ssid" ] && { echo "$ssid"; return 0; }

    # 模式 5: cmd wifi status (兜底)
    ssid=$(cmd wifi status 2>/dev/null | grep 'SSID' 2>/dev/null | head -1 | sed 's/.*SSID \([^,]*\).*/\1/' 2>/dev/null | tr -d '"' | tr -d ' ')
    [ -n "$ssid" ] && { echo "$ssid"; return 0; }

    echo "未知"
}

# ----------------------------------------------------------------------
# WiFi RSSI: 包装 common.sh 的 se_get_wifi_rssi
# ----------------------------------------------------------------------
get_wifi_rssi() {
    local rssi
    rssi=$(se_get_wifi_rssi)
    [ -z "$rssi" ] && rssi="?"
    echo "$rssi"
}

# ----------------------------------------------------------------------
# WiFi 链路速率: 精确匹配 "Link speed: 1297Mbps" (排除 Tx/Rx/Max 前缀),
# 降级匹配 mLinkSpeed= / linkSpeed= 等旧格式,
# 先限定包含 Mbps 的精确片段再提取数字, 避免匹配到 MAC 地址碎片
# ----------------------------------------------------------------------
get_wifi_link_speed() {
    local speed=""

    # 阶段 1: cmd wifi status 精确截取 "Link speed: 1297Mbps"
    # 先用 grep -oE 限定完整片段(含 Mbps), 再提取纯数字
    speed=$(cmd wifi status 2>/dev/null | grep -oE 'Link speed: [0-9]+Mbps' 2>/dev/null | head -1 | grep -oE '[0-9]+')
    [ -n "$speed" ] && { echo "$speed"; return 0; }

    # 阶段 2: dumpsys wifi 精确截取 "Link speed: 1297Mbps"
    local dump
    dump=$(dumpsys wifi 2>/dev/null)
    speed=$(echo "$dump" | grep -oE 'Link speed: [0-9]+Mbps' 2>/dev/null | head -1 | grep -oE '[0-9]+')
    [ -n "$speed" ] && { echo "$speed"; return 0; }

    # 阶段 3: 无 Mbps 后缀的 "Link speed: 1297"
    speed=$(echo "$dump" | grep -oE 'Link speed: [0-9]+' 2>/dev/null | head -1 | grep -oE '[0-9]+')
    [ -n "$speed" ] && { echo "$speed"; return 0; }

    # 阶段 4: 旧 AOSP 格式降级
    # 4a: mLinkSpeed: 433 (旧 AOSP)
    speed=$(echo "$dump" | grep -oE 'mLinkSpeed: [0-9]+' 2>/dev/null | head -1 | grep -oE '[0-9]+')
    [ -n "$speed" ] && { echo "$speed"; return 0; }

    # 4b: linkSpeed=433
    speed=$(echo "$dump" | grep -oE 'linkSpeed=[0-9]+' 2>/dev/null | head -1 | grep -oE '[0-9]+')
    [ -n "$speed" ] && { echo "$speed"; return 0; }

    # 阶段 5: 兜底 - Tx Link speed (有 Tx 前缀但聊胜于无)
    speed=$(echo "$dump" | grep -oE 'Tx Link speed: [0-9]+Mbps' 2>/dev/null | head -1 | grep -oE '[0-9]+')
    [ -n "$speed" ] && { echo "$speed"; return 0; }

    echo "?"
}

# ----------------------------------------------------------------------
# WiFi 频段: 精确匹配 "Frequency: 5180MHz", 判定 >4000=5G, 2000-3000=2.4G,
# 降级支持 mFrequency/frequency= 等旧格式
# ----------------------------------------------------------------------
get_wifi_frequency() {
    local freq=""
    local result=""

    _judge_freq() {
        local f="$1"
        [ -z "$f" ] && return 1
        case "$f" in
            [0-9][0-9][0-9][0-9]) ;;
            *) return 1 ;;
        esac
        if [ "$f" -gt 4000 ] 2>/dev/null; then
            echo "5G"; return 0
        elif [ "$f" -ge 2000 ] && [ "$f" -le 3000 ] 2>/dev/null; then
            echo "2.4G"; return 0
        fi
        return 1
    }

    local dump
    dump=$(dumpsys wifi 2>/dev/null)

    # 阶段 1: dumpsys wifi 精确匹配 "Frequency: 5180MHz" 
    freq=$(echo "$dump" | grep -oE 'Frequency:\s*[0-9]{4}MHz' 2>/dev/null | head -1 | grep -oE '[0-9]{4}')
    result=$(_judge_freq "$freq")
    [ -n "$result" ] && { echo "$result"; return 0; }

    # 阶段 1b: "Frequency: 5180" (无 MHz 后缀)
    freq=$(echo "$dump" | grep -oE 'Frequency:\s*[0-9]{4}' 2>/dev/null | head -1 | grep -oE '[0-9]{4}')
    result=$(_judge_freq "$freq")
    [ -n "$result" ] && { echo "$result"; return 0; }

    # 阶段 2: cmd wifi status 匹配 frequency
    if se_is_android_14_plus; then
        freq=$(cmd wifi status 2>/dev/null | grep -iE 'frequency' | grep -oE '[0-9]{4}' | head -1)
        result=$(_judge_freq "$freq")
        [ -n "$result" ] && { echo "$result"; return 0; }
    fi

    # 阶段 3: 旧 AOSP 格式降级
    # 3a: mFrequency: 5180 或 mFrequency=5180
    freq=$(echo "$dump" | grep -oE 'mFrequency[=:]\s*[0-9]{4}' 2>/dev/null | head -1 | grep -oE '[0-9]{4}')
    result=$(_judge_freq "$freq")
    [ -n "$result" ] && { echo "$result"; return 0; }

    # 3b: frequency=5180 (小写等号)
    freq=$(echo "$dump" | grep -oE 'frequency=[0-9]{4}' 2>/dev/null | head -1 | grep -oE '[0-9]{4}')
    result=$(_judge_freq "$freq")
    [ -n "$result" ] && { echo "$result"; return 0; }

    # 阶段 4: WifiInfo 行内 frequency=5180
    freq=$(echo "$dump" | grep 'WifiInfo' 2>/dev/null | grep -oE 'frequency=[0-9]{4}' 2>/dev/null | head -1 | grep -oE '[0-9]{4}')
    result=$(_judge_freq "$freq")
    [ -n "$result" ] && { echo "$result"; return 0; }

    # 全部失败
    echo "?"
}

# ----------------------------------------------------------------------
# 运营商信息
# ----------------------------------------------------------------------
get_carrier_name() {
    local name
    name=$(getprop gsm.sim.operator.alpha 2>/dev/null | head -1)
    # 去逗号后判断空/Unknown（不插卡或无效卡时返回 "," 或 "")
    name=$(echo "$name" | sed 's/,[[:space:]]*$//;s/^[[:space:],]*//')
    if [ -z "$name" ] || [ "$name" = "Unknown" ] || [ "$name" = "unknown" ]; then
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
    if [ -z "$rat" ] || [ "$rat" = "Unknown" ] || [ "$rat" = "unknown" ] || [ "$rat" = "NR_SA,Unknown" ]; then
        rat=$(getprop gsm.network.type 2>/dev/null | tr ',' '\n' | head -1)
        case "$rat" in
            NR|nr)      echo "5G NR"; return 0 ;;
            LTE|lte)    echo "4G LTE"; return 0 ;;
            *)          ;;
        esac
        echo "无"
        return 0
    fi
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
    [ -z "$level" ] && level="无"
    echo "$level"
}

get_mobile_dbm() {
    local dbm
    dbm=$(se_get_mobile_dbm)
    [ -z "$dbm" ] && dbm="无"
    echo "$dbm"
}

get_ping_ms() {
    se_get_ping_ms
}

# ----------------------------------------------------------------------
# 5G 信号质量采集（包装 common.sh 函数）
# ----------------------------------------------------------------------
get_nr_rsrp() {
    local rsrp
    rsrp=$(se_get_nr_rsrp)
    [ -z "$rsrp" ] && rsrp="无"
    echo "$rsrp"
}

get_nr_sinr() {
    local sinr
    sinr=$(se_get_nr_sinr)
    [ -z "$sinr" ] && sinr="无"
    echo "$sinr"
}

get_nr_rsrq() {
    local rsrq
    rsrq=$(se_get_nr_rsrq)
    [ -z "$rsrq" ] && rsrq="无"
    echo "$rsrq"
}

# 5G 假满格判定（包装 common.sh 函数）
get_fake_5g_status() {
    if se_detect_fake_5g; then
        echo "true"
    else
        echo "false"
    fi
}

# ----------------------------------------------------------------------
# 实时速率采集
# ----------------------------------------------------------------------
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

# ----------------------------------------------------------------------
# 完整状态显示
# ----------------------------------------------------------------------
show_full_status() {
    local net_type
    net_type=$(se_detect_network_type)

    echo "=== 网络状态 (完整) v${SE_VERSION} ==="
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

    echo "[5G 信号质量]"
    echo "  NR RSRP  : $(get_nr_rsrp) dBm"
    echo "  NR RSRQ  : $(get_nr_rsrq) dB"
    echo "  NR SINR  : $(get_nr_sinr) dB"
    if [ "$(get_fake_5g_status)" = "true" ]; then
        echo "  假满格   : WARN 检测到 5G 假满格"
    else
        echo "  假满格   : OK 正常"
    fi
    echo ""

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
            echo "$(get_carrier_name) $(get_network_type_name) | Lv$(get_mobile_level)/4 $(get_mobile_dbm)dBm | RSRP$(get_nr_rsrp) | 延迟$(get_ping_ms)ms"
            ;;
        dual)
            echo "双通道 WiFi $(get_wifi_rssi)dBm + 移动 Lv$(get_mobile_level)/4 | RSRP$(get_nr_rsrp) | 延迟$(get_ping_ms)ms"
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
            echo "5G : RSRP $(get_nr_rsrp) | SINR $(get_nr_sinr) dB"
            echo "延迟: $(get_ping_ms) ms"
            ;;
        dual)
            echo "WiFi: $(get_wifi_ssid) $(get_wifi_rssi)dBm $(get_wifi_link_speed)Mbps"
            echo "移动: $(get_carrier_name) $(get_network_type_name) Lv$(get_mobile_level)/4 $(get_mobile_dbm)dBm"
            echo "5G : RSRP $(get_nr_rsrp) | SINR $(get_nr_sinr) dB"
            echo "延迟: $(get_ping_ms) ms"
            ;;
        none)
            echo "无网络连接"
            echo "等待网络恢复..."
            ;;
    esac
}

# ----------------------------------------------------------------------
# JSON 转义
# ----------------------------------------------------------------------
json_escape() {
    local s="$1"
    s=$(printf '%s' "$s" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e 's/\r/\\r/g' | tr '\n' '\f' | sed 's/\f/\\n/g')
    printf '%s' "$s"
}

# ----------------------------------------------------------------------
# JSON 输出（含 nr / preferred_network_mode / fake_5g 等字段供 WebUI 使用）
# ----------------------------------------------------------------------
show_json() {
    local net_type ssid rssi speed freq carrier rat level dbm ping_ms nr_rsrp nr_sinr nr_rsrq fake_5g pnm_mode

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

    # 5G 信号字段
    nr_rsrp=$(get_nr_rsrp 2>/dev/null)
    [ -z "$nr_rsrp" ] && nr_rsrp="无"

    nr_sinr=$(get_nr_sinr 2>/dev/null)
    [ -z "$nr_sinr" ] && nr_sinr="无"

    nr_rsrq=$(get_nr_rsrq 2>/dev/null)
    [ -z "$nr_rsrq" ] && nr_rsrq="无"

    # 字符串 "0"/"1", 默认 "0" (正常), 兼容前端 JS 字符串比较
    fake_5g="0"
    if se_detect_fake_5g 2>/dev/null; then
        fake_5g="1"
    fi

    # 从状态文件读取 5G 降级状态, 文件不存在或字段缺失时默认 "0"
    local state_fake_5g
    state_fake_5g=$(cat "$SE_STATE_FILE" 2>/dev/null | grep '^FAKE_5G_ACTIVE=' 2>/dev/null | cut -d= -f2)
    case "$state_fake_5g" in
        1) state_fake_5g="1" ;;
        *) state_fake_5g="0" ;;  # 空值/0/异常值统一为 "0"
    esac

    pnm_mode=$(se_get global preferred_network_mode 2>/dev/null)
    [ -z "$pnm_mode" ] && pnm_mode="未知"

    echo "{"
    echo "  \"net_type\": \"$(json_escape "$net_type")\","
    echo "  \"preferred_network_mode\": \"$(json_escape "$pnm_mode")\","
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
    echo "  \"nr\": {"
    echo "    \"rsrp\": \"$(json_escape "$nr_rsrp")\","
    echo "    \"rsrq\": \"$(json_escape "$nr_rsrq")\","
    echo "    \"sinr\": \"$(json_escape "$nr_sinr")\","
    echo "    \"fake_5g\": \"$(json_escape "$fake_5g")\","
    echo "    \"fake_5g_active\": \"$(json_escape "$state_fake_5g")\""
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
    nr)
        echo "NR RSRP: $(get_nr_rsrp) dBm"
        echo "NR RSRQ: $(get_nr_rsrq) dB"
        echo "NR SINR: $(get_nr_sinr) dB"
        echo "Fake5G: $(get_fake_5g_status)"
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
        nr_rsrp=$(se_get_nr_rsrp)
        nr_sinr=$(se_get_nr_sinr)
        wifi_lvl=$(se_wifi_level)
        mobile_lvl=$(se_mobile_level)
        overall=$(se_overall_level "$net_type" "$wifi_lvl" "$mobile_lvl" "$ping_ms" "$nr_sinr")
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
        echo "NR_RSRP=$nr_rsrp"
        echo "NR_SINR=$nr_sinr"
        echo "PING_MS=$ping_ms"
        echo "OVERALL_LEVEL=$overall"
        echo "PARAMS=$params"
        ;;
    quality)
        net_type=$(se_detect_network_type)
        rssi=$(se_get_wifi_rssi)
        dbm=$(se_get_mobile_dbm)
        ping_ms=$(se_get_ping_ms)
        nr_rsrp=$(se_get_nr_rsrp)
        nr_sinr=$(se_get_nr_sinr)
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
        # 5G RSRP 评分
        nr_score=0
        if [ -n "$nr_rsrp" ] && [ "$nr_rsrp" != "无" ] && [ "$nr_rsrp" != "?" ]; then
            abs_nr=$nr_rsrp
            [ "$nr_rsrp" -lt 0 ] 2>/dev/null && abs_nr=$((-nr_rsrp))
            nr_score=$(awk -v a="$abs_nr" 'BEGIN { s = 100 - (a - 85) * 100 / 65; if (s < 0) s = 0; if (s > 100) s = 100; printf "%d", s }')
        fi
        echo "WIFI_SCORE=$wifi_score"
        echo "MOBILE_SCORE=$mobile_score"
        echo "NR_SCORE=$nr_score"
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
        echo "命令: full | brief | multiline | json | dynamic | quality | wifi | mobile | nr | speed | type | ping"
        ;;
esac
exit 0
