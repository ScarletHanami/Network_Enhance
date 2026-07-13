# 卫星地球 Pro 版本日志

## v6.3.3 (2026-06-25) — 数据传递修复版

### 核心修复（基于真实设备实测截图反馈）

#### Bug 1：通知延迟显示 `?`

**根因**：调度器后台 nohup 子进程下 `ping` 命令在 `>/dev/null 2>&1 &` 重定向环境中，ICMP 管道可能超时或权限受限，`se_get_ping_ms` 只尝试 2 个 DNS（223.5.5.5/119.29.29.29），全部失败后返回 `?`，被传入通知文本。

**修复**：
- `se_get_ping_ms` 增加 4 级 fallback：阿里 DNS → 腾讯 DNS → 114 DNS → 本地网关（`ip route` 获取）
- 超时从 1s 提升到 2s，适配后台进程的调度延迟
- `send_switch_notification` 在 ping_ms 为空/`?` 时重新实时获取一次

#### Bug 2：动态参数为空 + 状态文件停留在 init

**根因**：v6.3.2 首轮检测用 `{ ... } 2>/dev/null` 子 shell 组，内部对 `current_level` 的赋值无法传递到父 shell 的 `while` 循环；而且 `apply_dynamic_params` 同步调用会 fork 大量 `settings put` 子进程，在后台 nohup 环境下可能超时返回空字符串，导致 `applied_params` 为空，状态文件 `PARAMS=` 字段空白。

**修复**：
- 首轮检测改为直接在主 shell 执行（去掉子 shell 组），`current_level` 正确传递
- 用 `se_compute_dynamic_params`（纯计算无副作用）替代 `apply_dynamic_params` 的返回值来获取参数
- `settings` 写入放后台 `&` 执行，不阻塞主循环
- `se_compute_dynamic_params` 全函数变量非空兜底，确保 5 字段输出完整

---

## v6.3.2 (2026-06-25) — 前端状态修复版

修复调度器运行中但 WebUI 显示"未运行"（改用 PID + kill -0 验证）。

---

## v6.3.1 (2026-06-25) — 空值容错版

修复无 SIM 卡空值导致调度器崩溃 + WiFi 频段 Android 14/15 解析兼容。

---

## v6.3.0 (2026-06-25) — 路径修复版

基于官方源码确认 action.sh 调用方式，用 pwd 替代 ${0%/*}。

---

## v6.2.0 (2026-06-25) — 多品牌兼容重构版

新增 OEM 兼容性数据库。

---

## v6.1.0 (2026-06-19) — 动态自适应重构版

RSSI 连续插值 + ping 反馈 + critical 极限自救。

---

## v6.0.0 (2026-06-19) — 深度重构版

按 AxManager 官方插件协议深度重构。
