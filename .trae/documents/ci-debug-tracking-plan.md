# CI 调试埋点实现计划（续）

## 概要

为 `module.prop` 中 `version` 字段以 `ci` 开头时的 CI 调试模式，在所有 shell 脚本和 HTML 中添加大量埋点日志。日志输出到 `/data/local/tmp/Network_Enhance/ci.log`，格式为 `YYYY-MM-DD HH:MM:SS [FILENAME] INFO message`。

## 当前状态

### ✅ 全部完成（2026-07-19）

| 文件 | 计划埋点 | 实际埋点 | 状态 |
|------|---------|---------|------|
| `scripts/common.sh` | ~25 | 32 | ✅ |
| `action.sh` | ~35 | 37 | ✅ |
| `service.sh` | ~8 | 10 | ✅ |
| `post-fs-data.sh` | ~5 | 7 | ✅ |
| `scripts/monitor.sh` | ~18 | 25 | ✅ |
| `scripts/carrier.sh` | ~12 | 16 | ✅ |
| `scripts/weaknet.sh` | ~24 | 33 | ✅ |
| `scripts/wifi.sh` | ~5 | 7 | ✅ |
| `scripts/dns.sh` | ~10 | 16 | ✅ |
| `scripts/network_info.sh` | ~8 | 21 | ✅ |
| `scripts/oem_compat.sh` | ~12 | 12 | ✅ |
| `scripts/diag_dump.sh` | ~5 | 3+ | ✅ |
| `customize.sh` | ~5 | 5 | ✅ |
| `config.sh` | ~1 | 1 | ✅ |
| `uninstall.sh` | ~6 | 7 | ✅ |
| `webroot/index.html` | ~15 | 16 | ✅ |
| **合计** | **~190** | **~248** | ✅ |

---

## 埋点原则

1. **不影响功能**：所有 `se_ci_log` 调用以 `[ "$SE_CI_LOGON" = "1" ] || return 0` 守卫开头（在函数内），非 CI 模式零开销
2. **覆盖关键路径**：每个函数入口、关键决策分支、外部脚本调用点
3. **不覆盖循环内部**：`while true` 主循环内不添加埋点，仅在外层入口添加
4. **格式统一**：`se_ci_log "filename.sh" "function_name: description"`，文件名不含路径前缀

---

## 详细变更（按文件）

### 1. `scripts/monitor.sh` — 调度器埋点

在 `. "$_se_common"` 之后、`case "$1"` 之前，以及各函数入口添加：

| 行/位置 | 日志 |
|---------|------|
| 脚本入口（source 后） | `se_ci_log "monitor.sh" "monitor.sh 启动 | cmd=$1"` |
| `get_level_display_name()` 入口 | `se_ci_log "monitor.sh" "get_level_display_name: entry | level=$1"` |
| `get_level_description()` 入口 | `se_ci_log "monitor.sh" "get_level_description: entry | level=$1"` |
| `compute_overall_level_v2()` 入口 | `se_ci_log "monitor.sh" "compute_overall_level_v2: entry | net=$1 ping=$4 sinr=$5"` |
| `compute_overall_level_v2()` 结果 | `se_ci_log "monitor.sh" "compute_overall_level_v2: result=$base_level"` (在最后 echo 前) |
| `apply_dynamic_params()` 入口 | `se_ci_log "monitor.sh" "apply_dynamic_params: entry | level=$1"` |
| `write_state()` 入口 | `se_ci_log "monitor.sh" "write_state: entry | level=$2"` |
| `send_switch_notification()` 入口 | `se_ci_log "monitor.sh" "send_switch_notification: entry | level=$1"` |
| `handle_fake_5g()` 入口（非 weaknet 跳过时） | `se_ci_log "monitor.sh" "handle_fake_5g: entry | active=$FAKE_5G_ACTIVE"` |
| `handle_fake_5g()` 首次触发降级 | `se_ci_log "monitor.sh" "handle_fake_5g: 触发降级"` |
| `handle_fake_5g()` 恢复 5G | `se_ci_log "monitor.sh" "handle_fake_5g: 触发恢复 | count=$RECOVERY_COUNT"` |
| `handle_no_network_rollback()` 入口 | `se_ci_log "monitor.sh" "handle_no_network_rollback: entry | ping=$1"` |
| `run_monitor_loop()` 入口 | `se_ci_log "monitor.sh" "run_monitor_loop: entry"` |
| `start_monitor()` 入口 | `se_ci_log "monitor.sh" "start_monitor: entry"` |
| `stop_monitor()` 入口 | `se_ci_log "monitor.sh" "stop_monitor: entry"` |
| `show_status()` 入口 | `se_ci_log "monitor.sh" "show_status: entry"` |
| `detect_once()` 入口 | `se_ci_log "monitor.sh" "detect_once: entry"` |
| `case` 分发 | `se_ci_log "monitor.sh" "cmd=$1"` |

### 2. `scripts/carrier.sh` — 运营商优化埋点

| 行/位置 | 日志 |
|---------|------|
| 脚本入口 | `se_ci_log "carrier.sh" "carrier.sh 启动 | cmd=$1"` |
| `se_verify_network_type_changed()` 入口 | `se_ci_log "carrier.sh" "se_verify_network_type_changed: entry | expected=$1"` |
| `lock_lte()` 入口 | `se_ci_log "carrier.sh" "lock_lte: entry"` |
| `lock_lte()` PNM 备份后 | `se_ci_log "carrier.sh" "lock_lte: 备份 PNM=$current_mode"` |
| `unlock_lte()` 入口 | `se_ci_log "carrier.sh" "unlock_lte: entry | backup=$backup_mode"` |
| `degrade_5g_to_4g()` 入口 | `se_ci_log "carrier.sh" "degrade_5g_to_4g: entry"` |
| `apply_carrier_settings()` 入口 | `se_ci_log "carrier.sh" "apply_carrier_settings: entry | carrier=$carrier"` |
| `apply_carrier_settings()` 各运营商分支 | `se_ci_log "carrier.sh" "apply_carrier_settings: carrier=$carrier"` |
| `show_carrier_status()` 入口 | `se_ci_log "carrier.sh" "show_carrier_status: entry"` |
| `reset_carrier()` 入口 | `se_ci_log "carrier.sh" "reset_carrier: entry"` |
| `case` 分发 | `se_ci_log "carrier.sh" "cmd=$1"` |

### 3. `scripts/weaknet.sh` — 弱网自救埋点

| 行/位置 | 日志 |
|---------|------|
| 脚本入口 | `se_ci_log "weaknet.sh" "weaknet.sh 启动 | cmd=$1"` |
| `set_weaknet_active()` 入口 | `se_ci_log "weaknet.sh" "set_weaknet_active: entry | mode=$1"` |
| `clear_weaknet_active()` 入口 | `se_ci_log "weaknet.sh" "clear_weaknet_active: entry"` |
| `notify_lte_only_voice_warning()` 入口 | `se_ci_log "weaknet.sh" "notify_lte_only_voice_warning: entry"` |
| `dns_prefetch()` 入口 | `se_ci_log "weaknet.sh" "dns_prefetch: entry | tag=$1"` |
| `silent_reset()` 入口 | `se_ci_log "weaknet.sh" "silent_reset: entry"` |
| `apply_video_mode()` 入口 | `se_ci_log "weaknet.sh" "apply_video_mode: entry"` |
| `apply_game_mode()` 入口 | `se_ci_log "weaknet.sh" "apply_game_mode: entry"` |
| `apply_game_mode()` lock-lte 调用前 | `se_ci_log "weaknet.sh" "apply_game_mode: 调用 carrier.sh lock-lte"` |
| `apply_game_mode()` Data Saver 后 | `se_ci_log "weaknet.sh" "apply_game_mode: Data Saver 已开启"` |
| `apply_social_mode()` 入口 | `se_ci_log "weaknet.sh" "apply_social_mode: entry"` |
| `apply_download_mode()` 入口 | `se_ci_log "weaknet.sh" "apply_download_mode: entry"` |
| `apply_normal_mode()` 入口 | `se_ci_log "weaknet.sh" "apply_normal_mode: entry"` |
| `apply_normal_mode()` Data Saver 关闭后 | `se_ci_log "weaknet.sh" "apply_normal_mode: Data Saver 已关闭"` |
| `apply_normal_mode()` unlock-lte 调用前 | `se_ci_log "weaknet.sh" "apply_normal_mode: 调用 carrier.sh unlock-lte"` |
| `show_status()` 入口 | `se_ci_log "weaknet.sh" "show_status: entry"` |
| `apply_vpn_mode()` 入口 | `se_ci_log "weaknet.sh" "apply_vpn_mode: entry"` |
| `apply_vpn_mode()` lock-lte 调用前 | `se_ci_log "weaknet.sh" "apply_vpn_mode: 调用 carrier.sh lock-lte"` |
| `validate_package_name()` 入口 | `se_ci_log "weaknet.sh" "validate_package_name: entry | pkg=$1"` |
| `get_uid_by_package()` 入口 | `se_ci_log "weaknet.sh" "get_uid_by_package: entry | pkg=$1"` |
| `add_vpn_whitelist()` 入口 | `se_ci_log "weaknet.sh" "add_vpn_whitelist: entry | pkg=$1"` |
| `remove_vpn_whitelist()` 入口 | `se_ci_log "weaknet.sh" "remove_vpn_whitelist: entry | pkg=$1"` |
| `list_vpn_whitelist()` 入口 | `se_ci_log "weaknet.sh" "list_vpn_whitelist: entry"` |
| `case` 分发 | `se_ci_log "weaknet.sh" "cmd=$1"` |

### 4. `scripts/wifi.sh` — WiFi 优化埋点

| 行/位置 | 日志 |
|---------|------|
| 脚本入口 | `se_ci_log "wifi.sh" "wifi.sh 启动 | cmd=$1"` |
| `apply_wifi()` 入口 | `se_ci_log "wifi.sh" "apply_wifi: entry"` |
| `show_wifi_status()` 入口 | `se_ci_log "wifi.sh" "show_wifi_status: entry"` |
| `reset_wifi()` 入口 | `se_ci_log "wifi.sh" "reset_wifi: entry"` |
| `case` 分发 | `se_ci_log "wifi.sh" "cmd=$1"` |

### 5. `scripts/dns.sh` — DNS 管理埋点

| 行/位置 | 日志 |
|---------|------|
| 脚本入口 | `se_ci_log "dns.sh" "dns.sh 启动 | cmd=$1 $2"` |
| `get_provider_host()` 入口 | `se_ci_log "dns.sh" "get_provider_host: entry | provider=$1"` |
| `select_best_dot()` 入口 | `se_ci_log "dns.sh" "select_best_dot: entry"` |
| `check_dot_reachable()` 入口 | `se_ci_log "dns.sh" "check_dot_reachable: entry | host=$1"` |
| `enable_private_dns()` 入口 | `se_ci_log "dns.sh" "enable_private_dns: entry | provider=$1"` |
| `disable_private_dns()` 入口 | `se_ci_log "dns.sh" "disable_private_dns: entry"` |
| `reset_private_dns()` 入口 | `se_ci_log "dns.sh" "reset_private_dns: entry"` |
| `show_status()` 入口 | `se_ci_log "dns.sh" "show_status: entry"` |
| `list_providers()` 入口 | `se_ci_log "dns.sh" "list_providers: entry"` |
| `case` 分发 | `se_ci_log "dns.sh" "cmd=$1"` |

### 6. `scripts/network_info.sh` — 网络状态采集埋点

| 行/位置 | 日志 |
|---------|------|
| 脚本入口 | `se_ci_log "network_info.sh" "network_info.sh 启动 | cmd=$1"` |
| `get_wifi_ssid()` 入口 | `se_ci_log "network_info.sh" "get_wifi_ssid: entry"` |
| `get_wifi_rssi()` 入口 | `se_ci_log "network_info.sh" "get_wifi_rssi: entry"` |
| `get_wifi_freq()` 入口 | `se_ci_log "network_info.sh" "get_wifi_freq: entry"` |
| `get_carrier_name()` 入口 | `se_ci_log "network_info.sh" "get_carrier_name: entry"` |
| `get_mobile_rat()` 入口 | `se_ci_log "network_info.sh" "get_mobile_rat: entry"` |
| JSON 输出开始 | `se_ci_log "network_info.sh" "JSON 输出开始"` |
| `case` 分发 | `se_ci_log "network_info.sh" "cmd=$1"` |

### 7. `scripts/oem_compat.sh` — OEM 兼容性埋点

| 行/位置 | 日志 |
|---------|------|
| `se_detect_brand()` 入口 | `se_ci_log "oem_compat.sh" "se_detect_brand: entry"` |
| `se_detect_brand()` 结果 | `se_ci_log "oem_compat.sh" "se_detect_brand: result=$brand"` |
| `se_detect_api()` 入口 | `se_ci_log "oem_compat.sh" "se_detect_api: entry"` |
| `se_detect_soc()` 入口 | `se_ci_log "oem_compat.sh" "se_detect_soc: entry"` |
| `se_should_verify_write()` 入口 | `se_ci_log "oem_compat.sh" "se_should_verify_write: entry"` |
| `se_is_brand_supports_pnm()` 入口 | `se_ci_log "oem_compat.sh" "se_is_brand_supports_pnm: entry"` |
| `se_key_supported()` 入口 | `se_ci_log "oem_compat.sh" "se_key_supported: entry | key=$1"` |
| `se_key_replacement()` 入口 | `se_ci_log "oem_compat.sh" "se_key_replacement: entry | key=$1"` |
| `se_put_safe()` 入口 | `se_ci_log "oem_compat.sh" "se_put_safe: entry | $1.$2=$3"` |
| `se_put_safe_verify()` 入口 | `se_ci_log "oem_compat.sh" "se_put_safe_verify: entry | $1.$2=$3"` |
| `se_probe_oem_env()` 入口 | `se_ci_log "oem_compat.sh" "se_probe_oem_env: entry"` |
| `se_show_oem_info()` 入口 | `se_ci_log "oem_compat.sh" "se_show_oem_info: entry"` |

### 8. `scripts/diag_dump.sh` — 诊断抓取埋点

注意：`diag_dump.sh` 不 source `common.sh`（独立运行），需自行实现 CI 检测。但考虑到它可能被 source 调用，需在 `_se_find_common` 后检测。

| 行/位置 | 日志 |
|---------|------|
| 脚本入口（source common 后） | `se_ci_log "diag_dump.sh" "diag_dump.sh 启动"` |
| 各诊断阶段 `log_section` 后 | `se_ci_log "diag_dump.sh" "阶段: $title"` |

### 9. `customize.sh` — 安装脚本埋点

注意：`customize.sh` 不 source `common.sh`（被 `source` 而非 `sh` 执行，且运行在安装器环境），需自行内联 CI 检测逻辑。

| 行/位置 | 日志 |
|---------|------|
| 脚本入口（SKIPUNZIP=0 后） | 自行检测 CI 模式并写入首条日志 |
| OEM 兼容性预检后 | `"customize.sh: OEM 预检 | brand=$_brand_norm"` |
| 运营商预检后 | `"customize.sh: 运营商预检 | mccmnc=$mccmnc"` |
| 权限设置后 | `"customize.sh: 权限设置完成"` |
| 安装完成前 | `"customize.sh: 安装完成"` |

### 10. `config.sh` — 配置中心埋点

| 行/位置 | 日志 |
|---------|------|
| 文件末尾 | `se_ci_log "config.sh" "config.sh 加载 | CARRIER=$CARRIER MONITOR=$ENABLE_MONITOR"` |

### 11. `uninstall.sh` — 卸载清理埋点

| 行/位置 | 日志 |
|---------|------|
| 脚本入口 | `se_ci_log "uninstall.sh" "uninstall.sh 启动"` |
| 停止调度器后 | `se_ci_log "uninstall.sh" "停止调度器"` |
| 关闭 Data Saver 后 | `se_ci_log "uninstall.sh" "关闭 Data Saver"` |
| 恢复网络制式后 | `se_ci_log "uninstall.sh" "恢复网络制式"` |
| 各设置还原后 | `se_ci_log "uninstall.sh" "WiFi/移动网络/Private DNS 还原完成"` |
| 清理运行时文件后 | `se_ci_log "uninstall.sh" "运行时文件清理"` |
| **CI 日志清理** | 在运行时清理循环中添加 `rm -f "/data/local/tmp/Network_Enhance/ci.log"` |

### 12. `webroot/index.html` — WebUI JavaScript 埋点

在 `<script>` 标签内，`MODDIR` 解析后添加 CI 检测基础设施：

```javascript
// CI 调试模式
var SE_CI_LOGON = false;

function ciLog(src, msg) {
  if (!SE_CI_LOGON) return;
  try {
    var ts = new Date().toISOString().replace('T', ' ').substring(0, 19);
    execSync('echo "' + ts + ' [' + src + '] INFO ' + msg.replace(/"/g, '\\"') + '" >> /data/local/tmp/Network_Enhance/ci.log 2>/dev/null');
  } catch(e) {}
}
```

CI 检测（在 `execSync` 可用后）：
```javascript
(function detectCiMode() {
  try {
    var ver = execSync('grep "^version=" ' + MODDIR + '/module.prop 2>/dev/null | cut -d= -f2').trim();
    if (ver.indexOf('ci') === 0) { SE_CI_LOGON = true; ciLog('index.html', 'CI 调试模式已启用 | version=' + ver); }
  } catch(e) {}
})();
```

埋点位置：

| 位置 | 日志 |
|------|------|
| API 就绪后 | `ciLog('index.html', 'API 就绪 | type=' + apiType)` |
| `execSync()` 入口 | `ciLog('index.html', 'execSync: ' + cmd.substring(0, 80))` |
| `runCmd()` 入口 | `ciLog('index.html', 'runCmd: ' + name)` |
| `refreshAll()` 入口 | `ciLog('index.html', 'refreshAll')` |
| `loadNetworkInfo()` 入口 | `ciLog('index.html', 'loadNetworkInfo')` |
| `loadMonitorStatus()` 入口 | `ciLog('index.html', 'loadMonitorStatus')` |
| `loadDnsStatus()` 入口 | `ciLog('index.html', 'loadDnsStatus')` |
| `loadWeaknetStatus()` 入口 | `ciLog('index.html', 'loadWeaknetStatus')` |
| `runDiagnostics()` 入口 | `ciLog('index.html', 'runDiagnostics')` |
| `addVpnWhitelist()` 入口 | `ciLog('index.html', 'addVpnWhitelist')` |
| `removeVpnWhitelist()` 入口 | `ciLog('index.html', 'removeVpnWhitelist')` |
| `confirmReset()` 入口 | `ciLog('index.html', 'confirmReset')` |
| `clearLog()` 入口 | `ciLog('index.html', 'clearLog')` |
| `testExec()` 入口 | `ciLog('index.html', 'testExec')` |

---

## 检查要点（已审查通过 ✅）

1. ✅ 所有 `se_ci_log` 调用以 `[ "$SE_CI_LOGON" = "1" ] || return 0` 守卫，不影响原有逻辑
2. ✅ 日志文件名统一为脚本基名（不含路径前缀），如 `monitor.sh`、`carrier.sh`
3. ✅ 主循环内部（`while true`）无埋点，仅函数入口有日志（每次循环约 6-7 条，720 条/天，可接受）
4. ✅ `uninstall.sh` 包含 `Network_Enhance/ci.log` 清理（第 206 行）
5. ✅ `customize.sh` 内联了 CI 检测（不依赖 common.sh）
6. ✅ `index.html` 的 JS 日志通过 `execSync` 写入，正确转义引号