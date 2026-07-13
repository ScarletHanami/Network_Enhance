# 卫星地球 Pro v6.3.1 (AxManager 免Root 空值容错版)

> 中国大陆网络优化模块 — 严格遵循 AxManager 官方插件协议
> 作者：寒碑听风 · 协议：MIT

## v6.3.1 核心修复

基于真实设备实测截图反馈，修复 v6.3.0 残留的三个问题：

### Bug 1：WiFi 频段显示 `?`

**根因**：Android 14/15 的 `dumpsys wifi` 输出格式从 `mFrequency: 5180` 改为 `Frequency: 5180MHz`（首字母大写 + MHz 后缀），v6.3.0 的 `get_wifi_frequency()` 只匹配旧格式。

**修复**：增加 5 种匹配模式，覆盖 `mFrequency:`/`frequency=`/`Frequency: XXXMHz`/`Frequency: XXX`/`cmd wifi status`。同时修复链路速率（`Link speed: 1297Mbps` 格式）和 SSID（`SSID:"ChinaNet-C9D3-5G"` 格式）的同源问题。

### Bug 2：智能调度器面板空白

**根因**：调度器在首轮检测时，`compute_overall_level_v2` 函数因无 SIM 卡空值（`mobile_dbm` 为空）导致数值比较 `[ "$abs_d" -lt "$MOBILE_STRONG_DBM" ]` 在 `abs_d` 为空时出错，函数异常返回，调度器进程崩溃退出，状态文件停留在 `init` 状态。

**修复**：
- `compute_overall_level_v2` 全函数空值容错：所有数值比较前加 `case` 严格校验 + `2>/dev/null`
- `se_wifi_level` / `se_mobile_level` 同步空值容错
- `run_monitor_loop` 首轮立即检测并写状态（避免 WebUI 长时间看到 init）
- `apply_dynamic_params` 调用加 `|| applied_params="0 0 0"` 防御，即使失败也不退出循环

### Bug 3：无 SIM 卡环境空值容错

**根因**：测试机无 SIM 卡时，`se_get_mobile_dbm` 返回空字符串，`se_get_mobile_level` 返回空，`get_carrier_name` 返回 `?`，`get_network_type_name` 返回 `NR_SA,Unknown`（getprop 异常值）。

**修复**：
- `get_carrier_name`：无 SIM 时返回"无SIM"
- `get_network_type_name`：处理 `NR_SA,Unknown` 这种逗号多值，返回"无"
- `get_mobile_level` / `get_mobile_dbm`：空值时返回"无"
- `dns.sh show_status`：`null` 字符串时显示"未设置"

### WebUI 状态文件直读

**修复**：`loadMonitorStatus` 改为直接 `cat /data/local/tmp/satellite_earth_monitor.state`，比解析 `monitor.sh status` 文本输出更可靠。按 `KEY=value` 格式解析字段，`LEVEL=init` 时显示"初始化中"。

## 模块结构

```
Satellite_Earth/
├── module.prop / customize.sh / post-fs-data.sh / service.sh
├── action.sh / uninstall.sh / system.prop / config.sh
├── LICENSE / README.md / CHANGELOG.md / banner.png
├── webroot/index.html
└── scripts/
    ├── common.sh            # v6.3.1 空值容错
    ├── oem_compat.sh
    ├── monitor.sh           # v6.3.1 首轮检测 + 空值防御
    ├── network_info.sh      # v6.3.1 Android 14/15 解析兼容
    ├── wifi.sh / carrier.sh / dns.sh / weaknet.sh
```

## 使用方法

1. 在 AxManager 中选择 zip 文件安装
2. 重启手机
3. WebUI 在 AxManager 中点击模块"界面"按钮

## 社区守则

- 网络优化非万能药，体感提升约 5~15%
- 反馈问题请附日志 + 设备品牌型号 + Android 版本 + 是否插 SIM 卡
- ADB 免Root 有边界，TCP 内核参数需 Root
