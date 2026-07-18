# AGENTS.md — 项目上下文指南

## 项目概况

**Network_Enhance (AxManager 网络增强模块)**

中国大陆网络优化模块，基于 AxManager 免 Root ADB 权限运行。专为 Android 14+ 国产手机设计，提供 5G 假满格降级、游戏模式 LTE 锁定、智能 DNS、WiFi 优化等能力。

- **运行环境**: AxManager (ADB shell, `#!/system/bin/sh`)
- **最低 Android**: 14
- **支持的品牌**: 小米/HyperOS, OPPO/ColorOS, vivo/OriginOS, 华为/HarmonyOS, 荣耀/MagicOS, 三星/OneUI
- **技术约束**: 无 Root 权限，所有操作基于 `settings put/get`、`cmd wifi/netpolicy`、`getprop/setprop`、`dumpsys`

---

## 目录结构

```
e:\code\Network_Enhance/
├── work/Network_Enhance/         # 模块源码（发布工件）
│   ├── scripts/                  # 功能脚本
│   │   ├── common.sh             # 核心函数库（1400+ 行）
│   │   ├── oem_compat.sh         # OEM 兼容性矩阵
│   │   ├── monitor.sh            # 动态调度器
│   │   ├── carrier.sh            # 运营商优化
│   │   ├── network_info.sh       # 网络状态采集
│   │   ├── weaknet.sh            # 弱网自救场景
│   │   ├── wifi.sh               # WiFi 专用优化
│   │   ├── dns.sh                # Private DNS 管理
│   │   └── diag_dump.sh          # 诊断日志
│   ├── webroot/index.html        # WebUI 控制面板
│   ├── action.sh                 # 用户菜单入口（32 项）
│   ├── config.sh                 # 用户配置中心
│   ├── customize.sh              # 安装脚本
│   ├── post-fs-data.sh           # BOOT_COMPLETED first sync
│   ├── service.sh                # BOOT_COMPLETED late_start
│   ├── uninstall.sh              # 卸载清理
│   └── module.prop               # AxManager 模块清单
├── download/                     # 发布包存档
├── upload/                       # 用户上传包
├── work/extract/                 # 旧版 v6.3.x 提取参考（不修改）
├── work/search/                  # 研究阶段技术证据（不修改）
├── .github/workflows/build.yml   # CI 构建（打包 + artifact）
├── AGENTS.md                     # 本文件
└── README.md                     # 模块项目主页 README
```

---

## 代码约定

### Shell 脚本规范

| 规约 | 要求 |
|------|------|
| **Shebang** | `#!/system/bin/sh`（Android 环境） |
| **单引号原则** | 所有 shell 变量引用必须用双引号包裹（`"$var"`），防止词分割 |
| **默认值保护** | `"${var:-default}"` 模式为所有变量提供默认值 |
| **函数风格** | `func_name() { ... }`（小写+下划线） |
| **本地变量** | 函数内部 `local var` 声明，避免全局污染 |
| **错误处理** | `|| return $?` 传播关键错误，不静默吞掉 |
| **日志** | 用 `log_d/log_i/log_w/log_e` 函数统一输出 |

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
├── 5G 假满格检测 → degrade_5g_to_4g()
├── 网络等级判定 → se_overall_level()
├── 动态参数计算 → se_compute_dynamic_params()
└── 无网络回退 → handle_no_network_rollback()
```

- 与 `weaknet.sh` 严格隔离：weaknet 激活时监控器不做任何 PNM 操作
- 防振荡冷却：降级后 30 分钟冷却期，结束后连续 3 次正常才恢复

### 3. OEM 兼容策略

采用 4 级方案：
1. **品牌黑名单**: 跳过已知崩溃的键（如 vivo 的 `nr_sa_mode`）
2. **键名替换**: （如小米的 `nr_sa_mode → nr_mode`）
3. **写入验证**: 华为/荣耀/三星启用 3 次循环验证 + 功能性验证
4. **PNM 受限标记**: 验证失败后标记避免反复尝试

### 4. 运营商默认值修正

| 运营商 | 旧值 | 新值 | 原因 |
|--------|------|------|------|
| 电信 | 26 | 27 | 原 26 不含 CDMA 失语音 |
| 移动 | 23 | 32 | 原 23 NR only 丢失 4G 回退 |
| 广电 | 26 | 33 | 补全 TD-SCDMA/CDMA/EvDo |

---

## 构建与部署

```
发布流程：
1. 更新 versionCode 在 customize.sh / module.prop
2. 更新 CHANGELOG.md
3. 在根目录执行: cd work/Network_Enhance && zip -r ../../download/Network_Enhance_vX.X.X.zip ./* && cd ../.. && zip download/Network_Enhance_vX.X.X.zip README.md
4. 上传至 AxManager
```

CI 自动构建（`.github/workflows/build.yml`）：
- 每次 push 触发
- 将 `work/Network_Enhance/` 内容 + 根目录 `README.md` 打包为 `Network_Enhance_ci_{时间戳}.zip`

---

## 测试指南

### 模拟测试（PC 端）

```bash
# 导出关键函数后测试
source work/Network_Enhance/scripts/common.sh
source work/Network_Enhance/scripts/oem_compat.sh
# 调用目标函数验证逻辑
```

### 真机验证

1. 部署到 AxManager
2. 执行菜单 26（模块自检）
3. 执行菜单 30（5G 假满格自检）
4. 检查 `/data/local/tmp/network_enhance.log`

### 验证要点

- `se_detect_carrier()` 在各运营商 SIM 卡下的识别准确性
- `se_should_verify_write()` 的品牌过滤逻辑
- `lock_lte` / `unlock_lte` 的 PNM 写入验证流程
- `degrade_5g_to_4g()` 的假满格触发条件
- WebUI 的 `fetchStatus()` 状态更新

---

## 可维护性指南

### 添加新品牌支持

1. 在 `oem_compat.sh` 的 `get_brand()` 中添加识别
2. 在 `se_key_supported()` 中添加键名过滤/替换
3. 在 `se_should_verify_write()` 中添加品牌到验证名单
4. 更新 README.md 的品牌兼容表

### 添加新场景模式

1. 在 `weaknet.sh` 中添加模式函数
2. 在 `action.sh` 的菜单 switch 中添加选项
3. 在 `config.sh` 中添加配置开关
4. 在 `monitor.sh` 的 `is_weaknet_active()` 中添加隔离逻辑

### 调试技巧

- 查看运行时日志: `tail -f /data/local/tmp/network_enhance.log`
- 查看 settings 写入: `dumpsys services | grep -i "network\|preferred\|endc"`
- 查看当前 PNM: `settings get global preferred_network_mode`
