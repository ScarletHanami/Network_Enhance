# AGENTS.md — 项目上下文指南

## 项目概况

**Network_Enhance (AxManager 网络增强模块)**

中国大陆网络优化模块，基于 AxManager 免 Root ADB 权限运行。专为 Android 14+ 国产手机设计，提供 5G 假满格降级、游戏模式 LTE 锁定、代理稳定模式、智能 DNS、WiFi 优化等能力。

- **运行环境**: AxManager (ADB shell, `#!/system/bin/sh`)
- **最低 Android**: 14 (API 34)
- **当前版本**: 见 `module.prop` 中的 `version` 和 `versionCode` 字段
- **支持的品牌**: 小米/HyperOS, OPPO/ColorOS, vivo/OriginOS, 华为/HarmonyOS, 荣耀/MagicOS, 三星/OneUI
- **技术约束**: 无 Root 权限，所有操作基于 `settings put/get`、`cmd wifi/netpolicy`、`getprop/setprop`、`dumpsys`

---

## 目录结构

```
Network_Enhance/          # 项目根目录（即模块发布根目录）
├── scripts/                      # 功能脚本（9 个）
│   ├── common.sh                 # 核心函数库（1360+ 行）
│   ├── oem_compat.sh             # OEM 兼容性矩阵
│   ├── monitor.sh                # 动态调度器
│   ├── carrier.sh                # 运营商优化 + 制式管理
│   ├── network_info.sh           # 网络状态采集（JSON 输出）
│   ├── weaknet.sh                # 弱网自救 + 代理稳定模式
│   ├── wifi.sh                   # WiFi 专用优化
│   ├── dns.sh                    # Private DNS 管理
│   └── diag_dump.sh              # 诊断数据抓取（开发调试用）
├── webroot/index.html            # WebUI 控制面板
├── action.sh                     # 用户菜单入口（35 项）
├── config.sh                     # 用户配置中心
├── customize.sh                  # 安装脚本
├── post-fs-data.sh               # BOOT_COMPLETED first sync
├── service.sh                    # BOOT_COMPLETED late_start
├── uninstall.sh                  # 卸载清理
├── module.prop                   # AxManager 模块清单
├── banner.png                    # 模块横幅图
├── CHANGELOG.md                  # 版本变更日志
├── LICENSE                       # MIT 许可证
├── README.md                     # 模块项目主页 README
├── AGENTS.md                     # 本文件
└── .gitignore                    # Git 忽略规则
```

---

## 代码约定

### Shell 脚本规范

| 规约 | 要求 |
|------|------|
| **Shebang** | `#!/system/bin/sh`（Android 环境） |
| **双引号引用** | 所有 shell 变量引用必须用双引号包裹（`"$var"`），防止词分割 |
| **默认值保护** | `"${var:-default}"` 模式为所有变量提供默认值 |
| **函数风格** | `func_name() { ... }`（小写+下划线） |
| **本地变量** | 函数内部 `local var` 声明，避免全局污染 |
| **错误处理** | `|| return $?` 传播关键错误，不静默吞掉 |
| **日志** | 用 `log_msg()` 函数统一输出，标签为 `[core]`/`[boot]`/`[warn]`/`[oem]` 等 |

### 注释规范

- **函数文档**: 只写 WHY，不写 HOW（代码本身说明实现）
- **无追踪标记**: 禁止 `⚠️ 修改点 N:`、`来源: Sx` 等开发过程标记
- **有价值的注释**:
  - 非显而易见的决策理由（如"此处不关闭 enable_nr_dc 是为了快速恢复 5G"）
  - AOSP 源码参考（如"RILConstants.java 数值表"）
  - OEM 特殊行为说明（如"vivo 上 nr_sa_mode 写入会崩溃"）
  - 跨文件协作关系（如"与 lock_lte 共用 $SE_5G_BACKUP_FILE"）
- **内联注释**: 仅当代码意图不直观时使用，自明代码不加注释

### WebUI (index.html) 规范

- 单 `index.html` 文件，内嵌 CSS + JavaScript
- 通过 `window.networkBridge` 与 AxManager 通信
- 所有 API 调用经 `networkBridge.call()` 封装
- 状态轮询用 `setInterval` + `fetchStatus()`

---

## 关键架构决策

### 1. 免 Root 能力边界

| 无法实现 | 替代方案 |
|----------|----------|
| 完全禁用 4G+ CA | 锁 LTE Only + 关 ENDC 间接降低概率 |
| `setprop persist.*` | 已移除 system.prop，改用 `settings put global` |
| `service call phone` | 通过 `settings put global preferred_network_mode` 间接切换 |
| 各品牌私有 cmd 子命令 | 无可用公开命令 |

### 2. 调度器架构

```
monitor.sh（主循环，120s 周期）
├── 5G 假满格检测 → handle_fake_5g() → degrade_5g_to_4g()
├── 网络等级判定 → compute_overall_level_v2()
├── 动态参数计算 → se_compute_dynamic_params()
├── 无网络回退 → handle_no_network_rollback()
└── 弱网隔离 → weaknet 激活时跳过整轮
```

- 与 `weaknet.sh` 严格隔离：weaknet 激活时监控器不做任何 PNM 操作（三重防护：主循环 continue + 函数入口检查 × 2）
- 防振荡冷却：降级后 30 分钟冷却期，结束后连续 3 次正常才恢复
- 无网络死锁回退：降级到 4G 后连续 2 次 Ping 完全失败，自动恢复 5G

### 3. OEM 兼容策略

采用 4 级方案：
1. **品牌黑名单**: 跳过已知崩溃的键（如 vivo 的 `nr_sa_mode`）
2. **键名替换**: 小米专用键名替换（如 `nr_sa_mode → nr_mode`）
3. **写入验证**: 华为/荣耀/三星启用 3 次循环验证 + 功能性验证（dumpsys telephony.registry 检查网络制式实际变化）
4. **PNM 受限标记**: 验证失败后标记避免反复尝试

### 4. 运营商默认值修正

| 运营商 | 旧值 | 新值 | 原因 |
|--------|------|------|------|
| 电信 | 26 | 27 | 原 26 不含 CDMA 失语音 |
| 移动 | 23 | 32 | 原 23 NR only 丢失 4G 回退 |
| 广电 | 26 | 33 | 补全 TD-SCDMA/CDMA/EvDo |

### 5. 场景模式隔离

| 模式 | 入口 | 调度器行为 | PNM 操作 |
|------|------|-----------|---------|
| 游戏模式 | 菜单 2 | 严格让位（跳过整轮） | lock_lte (mode=11) + ENDC=0 |
| 代理稳定模式 | 菜单 33 | 严格让位（跳过整轮） | lock_lte (mode=11) + Data Saver |
| 视频/社交/下载模式 | 菜单 1/3/4 | 严格让位 | 无 PNM 操作 |
| 5G 假满格降级 | 自动触发 | 主动执行 | degrade_5g_to_4g (mode=9) |

---

## 构建与部署

```
发布流程：
1. 更新 versionCode 在 customize.sh（头部注释）和 module.prop
2. 更新 CHANGELOG.md
3. 在项目根目录执行:
   zip -r Network_Enhance_vX.X.X.zip \
     scripts/ webroot/ action.sh config.sh customize.sh \
     post-fs-data.sh service.sh uninstall.sh module.prop \
     banner.png LICENSE README.md CHANGELOG.md
4. 上传至 AxManager
```

注意：CI 构建流水线（`.github/workflows/build.yml`）不在本仓库中，如需配置请参考 AxManager 插件 CI 文档。

---

## 测试指南

### 模拟测试（PC 端）

```bash
# 导出关键函数后测试
source scripts/common.sh
source scripts/oem_compat.sh
# 调用目标函数验证逻辑
```

### 真机验证

1. 部署到 AxManager
2. 执行菜单 26（模块自检）
3. 执行菜单 30（5G 假满格自检）
4. 检查 `/data/local/tmp/network_enhance.log`

### 验证要点

- `se_detect_carrier()` 在各运营商 SIM 卡下的识别准确性（含双卡逗号分隔场景）
- `se_should_verify_write()` 的品牌过滤逻辑
- `lock_lte` / `unlock_lte` 的 PNM 写入验证流程（三层验证）
- `degrade_5g_to_4g()` 的假满格触发条件
- `se_get_wifi_rssi()` 的四阶段 fallback 机制（cmd wifi status → dumpsys wifi → 兜底）
- WebUI 的 `fetchStatus()` 状态更新
- 代理白名单的 `validate_package_name()` / `validate_uid()` 安全校验

---

## 可维护性指南

### 添加新品牌支持

1. 在 `oem_compat.sh` 的 `se_detect_brand()` 中添加识别
2. 在 `se_key_supported()` 中添加键名过滤/替换
3. 在 `se_should_verify_write()` 中添加品牌到验证名单
4. 在 `se_is_brand_supports_pnm()` 中添加品牌支持声明
5. 更新 README.md 的品牌兼容表

### 添加新场景模式

1. 在 `weaknet.sh` 中添加模式函数
2. 在 `action.sh` 的菜单 switch 中添加选项
3. 在 `config.sh` 中添加配置开关
4. 在 `monitor.sh` 的 `is_weaknet_active()` 等效逻辑中添加隔离（检查 `$WEAKNET_ACTIVE_FLAG`）

### 添加新代理白名单管理功能

1. 在 `weaknet.sh` 中添加 `add-wl`/`rm-wl` 命令处理
2. 确保 `validate_package_name()` 和 `validate_uid()` 安全校验
3. 在 `action.sh` 菜单中添加对应入口
4. 在 WebUI 中添加交互卡片

### 调试技巧

- 查看运行时日志: `tail -f /data/local/tmp/network_enhance.log`
- 查看 settings 写入: `settings list global | grep -i "network\|preferred\|endc\|wifi"`
- 查看当前 PNM: `settings get global preferred_network_mode`
- 查看网络制式实际状态: `dumpsys telephony.registry | grep -E 'mServiceState|NR|LTE'`
- 诊断数据抓取: `sh scripts/diag_dump.sh`（输出到 `/data/local/tmp/network_enhance_diag.txt`）
- 查看 PNM 受限标记: `ls /data/local/tmp/network_enhance_pnm_restricted_*`