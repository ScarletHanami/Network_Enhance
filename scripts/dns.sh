#!/system/bin/sh
# dns.sh — 网络增强 Private DNS (DoT) 工具

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
# DoT 提供商列表
# ----------------------------------------------------------------------
# 格式: 简称 主机名 说明
PROVIDERS="ali dns.alidns.com 阿里DNS(国内推荐)
tencent dot.pub 腾讯DNS(注意是dot.pub)
360 dns.360.cn 360DNS(注意是dns不是doh)
adguard dns.adguard.com AdGuard(国际_去广告)
dnspod dns.pub DNSPod
mopo dnshand.suning.com 苏宁DNS
"

get_provider_host() {
    case "$1" in
        ali|alidns|阿里)         echo "dns.alidns.com" ;;
        tencent|腾讯|qq)         echo "dot.pub" ;;
        360|qihoo)               echo "dns.360.cn" ;;
        adguard|adg)             echo "dns.adguard.com" ;;
        dnspod|pod)              echo "dns.pub" ;;
        mopo|mopohmt|suning)     echo "dnshand.suning.com" ;;
        "")                      echo "$PRIVATE_DNS_HOST" ;;
        *)                       echo "$1" ;;
    esac
}

# ----------------------------------------------------------------------
# 智能 DNS 选择 — 对 6 家 DoT 提供商做 ping 测试, 选延迟最低的
# ----------------------------------------------------------------------
# 返回: 最优提供商的主机名
select_best_dot() {
    echo "=== 智能 DNS 选择 (测试 6 家提供商延迟) ===" >&2

    if ! wait_network_ready 10; then
        echo "[FAIL] 网络未就绪, 使用默认 $PRIVATE_DNS_HOST" >&2
        echo "$PRIVATE_DNS_HOST"
        return 0
    fi

    local best_host=""
    local best_latency=99999
    local providers_list="dns.alidns.com dot.pub dns.360.cn dns.adguard.com dns.pub dnshand.suning.com"

    for host in $providers_list; do
        local latency
        latency=$(ping -c 2 -W 2 "$host" 2>/dev/null | grep 'time=' | tail -1 | sed 's/.*time=\([0-9.]*\).*/\1/' | cut -d. -f1)
        if [ -n "$latency" ]; then
            echo "  $host : ${latency}ms" >&2
            if [ "$latency" -lt "$best_latency" ] 2>/dev/null; then
                best_latency="$latency"
                best_host="$host"
            fi
        else
            echo "  $host : 不可达" >&2
        fi
    done

    if [ -z "$best_host" ]; then
        echo "[WARN] 所有提供商均不可达, 使用默认 $PRIVATE_DNS_HOST" >&2
        echo "$PRIVATE_DNS_HOST"
    else
        echo "[OK] 最优: $best_host (${best_latency}ms)" >&2
        echo "$best_host"
    fi
    return 0
}

# ----------------------------------------------------------------------
# DoT 端口可达性检查
# ----------------------------------------------------------------------
check_dot_reachable() {
    local host="$1"
    [ -z "$host" ] && host="$PRIVATE_DNS_HOST"

    echo "自检: $host:853 (DoT 端口) ..."

    if command -v nc >/dev/null 2>&1; then
        if nc -w 3 -z "$host" 853 2>/dev/null; then
            echo "  [OK] nc 测试通过: $host:853 可达"
            return 0
        else
            echo "  [--] nc 测试失败，尝试 ping 兜底"
        fi
    fi

    if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
        echo "  [WARN] 主机 ping 可达，但 853 端口未确认"
        return 0
    else
        echo "  [FAIL] 主机不可达: $host"
        return 1
    fi
}

# ----------------------------------------------------------------------
# 启用 Private DNS（支持 auto 参数触发智能选择）
# ----------------------------------------------------------------------
enable_private_dns() {
    local host

    # auto 参数触发智能选择
    if [ "$1" = "auto" ] || [ "$1" = "best" ]; then
        echo "=== 启用 Private DNS (智能选择模式) ==="
        host=$(select_best_dot)
        echo "  智能选择结果: $host"
    else
        host=$(get_provider_host "$1")
        echo "=== 启用 Private DNS ==="
    fi

    echo "  目标主机: $host"
    echo ""

    if ! wait_network_ready 10; then
        echo "[FAIL] 网络未就绪"
        log_msg "启用失败: 网络未就绪" "[dns]"
        return 1
    fi

    if ! check_dot_reachable "$host"; then
        echo "[FAIL] 自检未通过，未启用 Private DNS"
        log_msg "启用失败: $host 自检未通过" "[dns]"
        return 1
    fi

    echo ""

    local old_mode old_spec
    old_mode=$(se_get global private_dns_mode)
    old_spec=$(se_get global private_dns_spec)
    echo "  旧设置: mode=${old_mode:-无} spec=${old_spec:-无}"

    # 免 Root 可用: settings put global private_dns_mode hostname / private_dns_spec
    se_put global private_dns_mode "hostname"
    se_put global private_dns_spec "$host"

    sleep 2
    local new_mode new_spec
    new_mode=$(se_get global private_dns_mode)
    new_spec=$(se_get global private_dns_spec)

    if [ "$new_mode" = "hostname" ] && [ "$new_spec" = "$host" ]; then
        echo "[OK] Private DNS 已启用"
        echo "  模式: $new_mode"
        echo "  主机: $new_spec"
        log_msg "已启用: $host" "[dns]"
        return 0
    else
        echo "[FAIL] 写入验证失败，回滚..."
        if [ -n "$old_mode" ] && [ "$old_mode" != "null" ]; then
            se_put global private_dns_mode "$old_mode"
        else
            se_del global private_dns_mode
        fi
        if [ -n "$old_spec" ] && [ "$old_spec" != "null" ]; then
            se_put global private_dns_spec "$old_spec"
        else
            se_del global private_dns_spec
        fi
        log_msg "启用失败: $host 写入验证失败，已回滚" "[dns]"
        return 1
    fi
}

# ----------------------------------------------------------------------
# 禁用 / 恢复默认
# ----------------------------------------------------------------------
disable_private_dns() {
    echo "=== 禁用 Private DNS ==="
    se_put global private_dns_mode "off"
    se_del global private_dns_spec
    echo "[OK] Private DNS 已禁用"
    log_msg "已禁用" "[dns]"
    return 0
}

reset_private_dns() {
    echo "=== 恢复系统默认 ==="
    se_del global private_dns_mode
    se_del global private_dns_spec
    se_put global private_dns_mode "opportunistic"
    echo "[OK] Private DNS 已恢复为系统默认 (opportunistic)"
    log_msg "已恢复默认" "[dns]"
    return 0
}

# ----------------------------------------------------------------------
# 状态显示（含空值容错）
# ----------------------------------------------------------------------
show_status() {
    local mode spec
    mode=$(se_get global private_dns_mode)
    spec=$(se_get global private_dns_spec)

    [ -z "$mode" ] || [ "$mode" = "null" ] && mode="未设置"
    [ -z "$spec" ] || [ "$spec" = "null" ] && spec="未设置"

    echo "=== Private DNS 状态 v${SE_VERSION} ==="
    echo "  模式: $mode"
    case "$mode" in
        hostname)      echo "  含义: 使用指定主机 (DoT)" ;;
        opportunistic) echo "  含义: 自动尝试加密 DNS" ;;
        off)           echo "  含义: 已关闭" ;;
        未设置)        echo "  含义: 未配置" ;;
        *)             echo "  含义: 未知" ;;
    esac
    echo "  主机: ${spec}"
    echo ""
    echo "  配置文件值: ENABLE_PRIVATE_DNS=${ENABLE_PRIVATE_DNS:-false}"
    echo "  配置主机名: ${PRIVATE_DNS_HOST:-dns.alidns.com}"
    return 0
}

list_providers() {
    echo "=== 可用 DoT 提供商 (6 家) ==="
    echo ""
    printf "%-10s %-25s %s\n" "名称" "主机" "说明"
    printf "%-10s %-25s %s\n" "----" "----" "----"
    echo "$PROVIDERS" | while read name host desc; do
        [ -z "$name" ] && continue
        printf "%-10s %-25s %s\n" "$name" "$host" "$desc"
    done
    return 0
}

case "$1" in
    on|enable)  enable_private_dns "$2" ;;
    off|disable) disable_private_dns ;;
    reset|default) reset_private_dns ;;
    check|test) check_dot_reachable "$2" ;;
    list|providers) list_providers ;;
    auto|best)  # 智能选择模式
        enable_private_dns "auto"
        ;;
    status) show_status ;;
    *)
        echo "Private DNS (DoT) 工具 v${SE_VERSION}"
        echo ""
        echo "=== 可用命令 ==="
        echo "  status              查看当前状态"
        echo "  list                列出可用提供商 (6 家)"
        echo "  check [host]        自检 853 端口可达性"
        echo "  on [provider]       启用 Private DNS"
        echo "  auto                智能选择最优 DoT (ping 测试选延迟最低)"
        echo "  off                 禁用 Private DNS"
        echo "  reset               恢复系统默认"
        echo ""
        echo "提供商简称: ali | tencent | 360 | adguard | dnspod | mopo"
        ;;
esac
exit 0
