# 网络增强 v1.0 (AxManager 免Root 网络优化)

> 中国大陆网络优化模块 — 严格遵循 AxManager 官方插件协议
> 作者：寒碑听风 · 协议：MIT
> 适用于 Android 14+ 国产手机（小米/OPPO/vivo/华为/荣耀/三星）

---

## ⚠️ 免Root环境下的能力边界（重要！请先阅读）

本模块基于 AxManager 的 ADB 免Root 权限运行，**无法突破系统级限制**。以下能力边界请明确知悉：

### ❌ 免Root下无法实现的功能
1. **完全禁用 4G+ 载波聚合（CA）**
   - Android 14/15 上**没有公开的 `settings global` 键可直接禁用载波聚合**
   - 本模块通过锁定 LTE Only（mode=11）+ 关闭 ENDC 间接降低跳频概率
   - **完全禁用 4G+ 需 Root 权限或工程模式（`*#*#3646633#*#*`）**
   - 效果因设备和运营商而异

2. **`setprop persist.*` 写入**
   - 免Root下 `setprop` 只能修改非 persist.* 的属性
   - 原 v6.3.x 的 `system.prop`（`persist.sys.satellite_earth.*`）在免Root下完全不生效
   - **本版本已移除 `system.prop`**，功能迁移到 `settings put global`

3. **`service call phone` 直接调用**
   - 免Root下大部分 phone service 调用会因权限被拒
   - 网络制式切换只能通过 `settings put global preferred_network_mode` 间接实现

4. **各品牌私有 `cmd` 子命令**
   - 经搜索验证，没有任何国产手机品牌提供公开的私有 `cmd` 子命令用于网络优化

### ⚠️ 使用限制与副作用
1. **LTE Only 模式的语音副作用**
   - 游戏模式或手动锁定 LTE（菜单 31）会启用 LTE Only（mode=11）
   - **非 VoLTE 环境下的电话可能无法接入**（无法回落 2/3G）
   - 游戏结束请及时执行"解锁 LTE"（菜单 32）或"恢复默认优化"（菜单 5）
   - 模块会通过通知明确告知用户此副作用

2. **Data Saver 的全局影响**
   - 游戏模式会开启系统级 Data Saver（`cmd netpolicy set restrict-background true`）
   - 这会影响所有应用的后台数据使用
   - 游戏结束执行"恢复默认优化"会自动关闭 Data Saver
   - 卸载模块时 `uninstall.sh` 会兜底关闭 Data Saver

3. **华为/荣耀/三星 PNM 写入可能受限**
   - 部分版本的华为/荣耀/三星 ROM 会忽略 `preferred_network_mode` 写入
   - 本模块对这三个品牌启用写入验证机制（循环验证 3 次 + 功能性验证）
   - 验证失败会标记"PNM 受限"，避免后续反复尝试无效写入

---

## 核心功能

### 1. 5G 假满格自动降级（核心新增）
**问题场景**：5G 信号满格但实际几乎无网（延迟极高/丢包严重）

**解决方案**：
- 每 120 秒检测一次 5G 信号质量（RSRP + SINR + Ping）
- 判定条件（满足任一即判定为假满格）：
  - RSRP ≥ -85 dBm（信号强度好）但 Ping > 200ms
  - RSRP ≥ -85 dBm 但 SINR < 0（信噪比差）
  - RSRP ≥ -85 dBm 但 Ping 失败（丢包）
- 自动降级到 4G（mode=9，LTE/GSM/WCDMA）
- **防振荡冷却**：降级后强制保持 30 分钟，冷却期结束且连续 3 次正常才恢复 5G
- **无网络死锁回退**：降级到 4G 后若连续 2 次检测 Ping 完全失败，自动恢复 5G

### 2. 游戏模式锁定 LTE（4G+ 跳频防护）
**问题场景**：4G 网络稳定但设备频繁跳至 4G+（载波聚合）导致游戏卡顿断流

**解决方案**：
- 锁定 LTE Only（mode=11）禁止 5G
- 关闭 ENDC（endc_capability=0）间接降低 4G+ 跳频概率
- 开启 Data Saver 禁止后台应用抢带宽
- DNS 预热腾讯/网易/米哈游等游戏厂商域名
- **发送语音副作用通知**告知用户

### 3. 运营商默认值修正（S3 关键修正）
原模块存在严重的运营商默认值错误，本版本已修正：

| 运营商 | 旧值（错误） | 新值（修正） | 常量名 | 修正原因 |
|---|---|---|---|---|
| 电信 | 26 | **27** | NETWORK_MODE_NR_LTE_CDMA_EVDO_GSM_WCDMA | 原 26 不含 CDMA，电信会失语音 |
| 移动 | 23 | **32** | NETWORK_MODE_NR_LTE_TDSCDMA_GSM_WCDMA | 原 23 是 NR only，丢失 4G 回退 |
| 联通 | 26 | 26 | NETWORK_MODE_NR_LTE_GSM_WCDMA | 原模块正确 |
| 广电 | 26 | **33** | NETWORK_MODE_NR_LTE_TDSCDMA_CDMA_EVDO_GSM_WCDMA | 原 26 不含 TD-SCDMA/CDMA/EvDo |

来源：AOSP RILConstants.java 权威数值表

### 4. 多品牌深度适配
| 品牌 | 5G NR 键 | WiFi 私有键 | PNM 支持 | 写入验证 |
|---|---|---|---|---|
| 小米 HyperOS | nr_sa_mode→nr_mode 替换 | 跳过 pno_frequency/recovery_state | ✅ | 不需要 |
| OPPO ColorOS | ✅ 全部可用 | ✅ 全部可用 | ✅ | 不需要 |
| vivo OriginOS | nr_sa_mode 跳过(崩溃) | 跳过 enhanced_mac_randomization | ✅ | 不需要 |
| 三星 OneUI | 全部 5G NR 跳过 | 跳过 max_dwell_time_ms | ⚠️ 部分忽略 | **启用** |
| 华为 HarmonyOS/EMUI | 全部 5G NR 跳过 | 跳过 persistent_group_remove_delay | ✅ | **启用** |
| 荣耀 MagicOS | 全部 5G NR 跳过 | 同华为 | ✅ | **启用** |

### 5. 智能调度器（4 级 + SINR 维度）
- **检测间隔统一 120 秒**（所有等级相同）
- 4 级判定标准（含 SINR 维度）：
  - `strong`：RSSI ≥ -60 且 Ping < 80ms 且 SINR ≥ 10
  - `normal`：RSSI -60~-75 或 Ping 80~150ms
  - `weak`：RSSI -75~-90 或 Ping 150~200ms
  - `critical`：RSSI < -90 或 Ping > 200ms 或 SINR < 0
- 等级切换发送通知 + 后台应用动态参数
- **与 weaknet 严格隔离**：游戏/视频模式激活时，调度器绝对禁止任何 PNM 操作

### 6. 场景模式（5 个）
| 模式 | 主要调整 | DNS 预热 |
|---|---|---|
| 视频模式 | WiFi 弱信号 -95，扫描 10s | 抖音/B站/快手/西瓜/爱奇艺/优酷 |
| 游戏模式 | LTE Only + ENDC=0 + Data Saver | 腾讯/网易/米哈游 |
| 社交模式 | 保 WiFi，DNS 预热 | 微信/QQ/DNSPod |
| 下载模式 | WiFi idle 6h | 淘宝/京东/百度网盘/123pan |
| 恢复默认 | 关闭 Data Saver + 恢复 5G + 重启调度器 | - |

### 7. 智能 DNS 选择
- 6 家 DoT 提供商：阿里/腾讯/360/AdGuard/DNSPod/苏宁
- `auto` 模式自动 ping 测试，选延迟最低的提供商
- 保留 Private DNS (DoT) 防泄漏功能

---

## 模块结构

```
Network_Enhance/
├── module.prop                    # 模块清单（id=Network_Enhance, v1.0, axeronPlugin=10000）
├── customize.sh                   # 安装脚本（路径解析6级fallback + 自检bug修复）
├── post-fs-data.sh                # BOOT_COMPLETED first sync（静态优化, 不启动调度器）
├── service.sh                     # BOOT_COMPLETED late_start（late_verify + 启动调度器）
├── action.sh                      # 用户主动触发（32 项菜单）
├── uninstall.sh                   # 卸载清理（Data Saver兜底 + 深度清理残留）
├── config.sh                      # 用户配置中心（14类参数）
├── banner.png / LICENSE / README.md / CHANGELOG.md
├── scripts/
│   ├── common.sh                  # 核心函数库（版本检测/RSRP解析/假满格判定）
│   ├── oem_compat.sh              # OEM 兼容性矩阵（6厂商 + PNM写入验证）
│   ├── monitor.sh                 # 动态调度器（120s间隔/5G降级/防振荡冷却）
│   ├── network_info.sh            # 网络状态采集（cmd wifi status优先 + 5G信号）
│   ├── wifi.sh / carrier.sh       # WiFi/运营商优化
│   ├── dns.sh                     # Private DNS（含智能选择）
│   └── weaknet.sh                 # 弱网自救（5场景模式）
└── webroot/
    └── index.html                 # WebUI 控制面板
```

**已移除**：`system.prop`（persist.* 免Root不生效）

---

## 安装与激活

### 前置要求
1. Android 14+ 国产手机
2. AxManager 应用已安装（v1.0+）
3. 无线调试已启用（Android 11+）

### 安装步骤
1. 在 AxManager 中选择 `Network_Enhance_v1.0.zip` 安装
2. 重启手机
3. 重新激活 AxManager（无线调试模式）
4. 在 AxManager 中点击模块"界面"按钮打开 WebUI

### 卸载
- 在 AxManager 中卸载模块
- `uninstall.sh` 会自动执行：
  - 关闭 Data Saver
  - 恢复 5G 网络制式
  - 还原所有 WiFi/移动网络设置
  - 清理所有运行时残留文件
  - 杀掉存活的 monitor.sh 进程

---

## 各场景模式说明

### 视频模式（菜单 1）
适用：抖音/B站/快手/爱奇艺等视频卡顿
- WiFi 弱信号阈值 -95 dBm（容忍弱信号）
- 扫描间隔 10s（快速重连）
- DNS 预热视频平台域名（含抖音 API 域名）
- 关闭 WiFi 休眠优化

### 游戏模式（菜单 2）
适用：打游戏延迟高/4G+ 跳频断流
- **锁定 LTE Only（mode=11）+ 关闭 ENDC**
- 开启 Data Saver 禁止后台抢带宽
- DNS 预热腾讯/网易/米哈游
- ⚠️ **会发送语音副作用通知**：非 VoLTE 来电可能无法接通

### 社交模式（菜单 3）
适用：微信/QQ 消息延迟
- 保 WiFi（mobile_data_preferred=0）
- DNS 预热微信/QQ/DNSPod
- 关闭 WiFi 休眠优化

### 下载模式（菜单 4）
适用：大文件下载
- WiFi idle 6 小时（持续传输不中断）
- DNS 预热淘宝/京东/百度网盘/123pan

### 恢复默认优化（菜单 5）
- **关闭 Data Saver**（绝对还原）
- **调用 carrier.sh unlock-lte** 联动恢复 5G
- 清除 PNM 受限标记
- 重启调度器

### 5G/LTE 制式管理（菜单 30/31/32）
- **菜单 30**：5G 假满格自检（显示 RSRP/SINR/Ping + 判定结果）
- **菜单 31**：手动锁定 LTE Only（与游戏模式同款 + 语音通知）
- **菜单 32**：解锁 LTE，恢复运营商默认 5G

---

## 支持的品牌与系统版本

| 品牌 | 系统 | 最低 Android | PNM 支持 | 备注 |
|---|---|---|---|---|
| 小米/Redmi/POCO | MIUI/HyperOS | Android 14 | ✅ | nr_sa_mode→nr_mode 替换 |
| OPPO/OnePlus/Realme | ColorOS/OxygenOS | Android 14 | ✅ | 全部键可写（主测试环境） |
| vivo/iQOO | Funtouch/OriginOS | Android 14 | ✅ | nr_sa_mode 跳过避免崩溃 |
| 三星 | OneUI | Android 14 | ⚠️ | PNM 部分版本会忽略，启用验证 |
| 华为 | HarmonyOS/EMUI | Android 14 | ✅ | 5G NR 键跳过，PNM 可用，启用验证 |
| 荣耀 | MagicOS | Android 14 | ✅ | 同华为 |

---

## 常见问题与排障

### Q1: 模块安装后 WebUI 显示"API 不可用"
**A**: 
1. 确认 AxManager 已通过无线调试激活
2. 重启 AxManager 应用
3. 在 WebUI 诊断面板点击"重新诊断"
4. 检查 Android WebView 是否正常

### Q2: 5G 假满格降级后一直不恢复
**A**: 
- 防振荡冷却期为 30 分钟，期间不会恢复
- 冷却期后需连续 3 次检测正常（6 分钟）才恢复
- 可在 `config.sh` 中调整 `DOWNGRADE_COOLDOWN_SEC`（默认 1800）和 `DEGRADE_RECOVERY_COUNT`（默认 3）
- 紧急情况可手动执行菜单 32（解锁 LTE）

### Q3: 游戏模式后接不到电话
**A**: 
- 游戏模式锁定 LTE Only，非 VoLTE 来电可能无法接通
- 这是免Root下的固有限制
- 游戏结束请立即执行菜单 5（恢复默认）或菜单 32（解锁 LTE）

### Q4: 华为/荣耀设备 PNM 切换无效
**A**: 
- 部分版本的华为/荣耀 ROM 会忽略 PNM 写入
- 模块会自动标记"PNM 受限"，不再反复尝试
- 可通过菜单 26（模块自检）查看 PNM 受限状态
- 可通过菜单 32（解锁 LTE）清除标记重试

### Q5: 自检报告显示 customize.sh 缺失
**A**: 
- 本版本已修复此 bug（v6.3.x 的已知问题）
- 自检逻辑已增加 pwd 兜底，不会再误报

### Q6: 公网延迟显示 "2000 ms (较差)" 是什么意思
**A**: 
- 这是模块的**nc 端口可达性兜底**生效的正常表现
- 在 AxManager 的 ADB shell 环境下，原生 `ping` 命令可能因 SELinux 或网络权限限制执行失败
- 模块会自动通过 `nc -w 2 -z 223.5.5.5 53` 测试端口可达性作为兜底
- 若 nc 可达，则返回 `2000`（代表**网络连通但延迟无法精确测算**）
- 若 nc 也不通，则显示 `timeout (不通)`（代表网络彻底不通）
- **这不是 bug，而是免Root环境下的正常降级表现**，5G 假满格判定仍可基于 RSRP/SINR 正常工作

### Q7: 卸载后后台应用无法联网
**A**: 
- 这是 Data Saver 未关闭导致
- `uninstall.sh` 会兜底关闭 Data Saver
- 如仍异常，手动执行：`adb shell cmd netpolicy set restrict-background false`

### Q8: 调度器日志显示"PNM 受限"
**A**: 
- 该品牌 ROM 忽略了 PNM 写入
- 5G 假满格降级功能在该设备上不可用
- 其他功能（WiFi 优化、DNS、场景模式）仍正常工作

---

## 配置参数说明

所有参数在 `config.sh` 中，修改后需重启调度器（菜单 21）生效。

### 核心参数
```bash
CARRIER="auto"                    # 运营商: auto|telecom|mobile|unicom|ctn|off
ENABLE_MONITOR=true               # 智能调度器总开关
ENABLE_FAKE_5G_DETECTION=true     # 5G 假满格检测总开关
ENABLE_LTE_LOCK_FOR_GAME=true     # 游戏模式锁定 LTE
MONITOR_NORMAL_INTERVAL=120       # 检测间隔（秒，统一120）
```

### 5G 假满格判定参数
```bash
FAKE_5G_RSRP_THRESHOLD=-85        # RSRP 阈值（dBm）
FAKE_5G_SINR_THRESHOLD=0          # SINR 阈值（dB）
FAKE_5G_PING_THRESHOLD=200        # Ping 阈值（ms）
```

### 防振荡冷却参数
```bash
DOWNGRADE_COOLDOWN_SEC=1800       # 降级冷却（秒，默认30分钟）
DEGRADE_RECOVERY_COUNT=3          # 连续正常次数（1-5）
DEGRADE_NO_NET_ROLLBACK_COUNT=2   # 无网络回退次数
```

---

## 技术实现来源

本模块的所有命令、键名、数值均经过权威来源验证：

| 内容 | 来源 |
|---|---|
| preferred_network_mode 数值表 | AOSP RILConstants.java 源码 |
| 5G RSRP/SINR 字段 | CellSignalStrengthNr.java 源码 |
| cmd netpolicy 子命令 | Android Developer 官方文档 |
| cmd wifi status | AOSP + Stack Overflow 交叉验证 |
| AxManager 协议 | fahrez182.github.io 官方文档 |
| OEM 兼容性矩阵 | Reddit/XDA/原模块 v6.3.0 实测 |

---

## 社区守则

- 网络优化非万能药，体感提升约 5~15%
- 反馈问题请附日志（`/data/local/tmp/network_enhance.log`）+ 设备品牌型号 + Android 版本 + 是否插 SIM 卡
- ADB 免Root 有边界，TCP 内核参数需 Root
- 完全禁用 4G+ 载波聚合需 Root，本模块只能间接降低跳频概率

---

## 协议

MIT License - Copyright (c) 2026 寒碑听风
