#!/system/bin/sh
# config.sh — 网络增强 用户配置中心
#
# 所有用户可调参数集中在此文件
# 修改后重启模块或重新安装生效

# ===============================
# 1. 运营商
# ===============================
# auto = 自动识别 | telecom = 电信 | mobile = 移动 | unicom = 联通 | ctn = 广电 | off = 禁用
CARRIER="auto"

# ===============================
# 2. WiFi 优化
# ===============================
ENABLE_WIFI_OPTIMIZE=true
# WiFi 弱信号阈值（绝对值, 越大越容忍弱信号, 默认 88 = -88dBm）
WIFI_BAD_RSSI=88
# WiFi 空闲超时（毫秒, 默认 2 小时）
WIFI_IDLE_MS=7200000

# ===============================
# 3. 移动网络优化
# ===============================
ENABLE_MOBILE_OPTIMIZE=true
# 5G SA 独立组网开关（部分 OEM 不支持, oem_compat.sh 会自动跳过）
ENABLE_5G_SA=true

# ===============================
# 4. DNS 预热
# ===============================
# 启动时 ping 常用域名, 触发 DNS 解析缓存加速
ENABLE_DNS_PREFETCH=true

# ===============================
# 5. Private DNS (DoT)
# ===============================
# DoT 加密 DNS 防泄漏
ENABLE_PRIVATE_DNS=false
PRIVATE_DNS_HOST="dns.alidns.com"

# ===============================
# 6. late_start 阶段验证
# ===============================
# service.sh 中重新应用 settings, 防止系统重置
ENABLE_LATE_VERIFY=true

# ===============================
# 7. 智能调度器
# ===============================
ENABLE_MONITOR=true
# 等级切换通知
ENABLE_SWITCH_NOTIFY=true
# 动态参数插值（RSSI 连续插值）
ENABLE_DYNAMIC_PARAMS=true
# Ping 反馈调节
ENABLE_PING_FEEDBACK=true

# OEM 兼容性总开关
ENABLE_OEM_COMPAT=true

# ===============================
# 8. 信号阈值
# ===============================
# WiFi RSSI 等级阈值（绝对值）
WIFI_STRONG_RSSI=60      # RSSI ≥ -60 = strong
WIFI_WEAK_RSSI=75        # RSSI -60~-75 = normal, < -75 = weak
# 移动 dBm 等级阈值（绝对值）
MOBILE_STRONG_DBM=85     # dBm ≥ -85 = strong
MOBILE_WEAK_DBM=105      # dBm -85~-105 = normal, < -105 = weak
# Ping 延迟阈值（毫秒）
PING_GOOD_MS=80          # Ping < 80ms = good
PING_BAD_MS=200          # Ping > 200ms = bad

# ===============================
# 9. 检测间隔（统一 120 秒）
# ===============================
# 所有等级 (strong/normal/weak/critical) 均使用相同间隔
# 不再按等级区分（原 strong=900s/normal=600s/weak=300s/critical=300s 已废弃）
MONITOR_MIN_INTERVAL=120
MONITOR_NORMAL_INTERVAL=120
MONITOR_MAX_INTERVAL=120
# 网络就绪等待超时（秒）
NETWORK_READY_TIMEOUT=10

# ===============================
# 10. 5G 假满格判定参数
# ===============================
# 判定条件（满足任一即判定为假满格）:
#   1. RSRP ≥ FAKE_5G_RSRP_THRESHOLD 但 Ping > FAKE_5G_PING_THRESHOLD
#   2. RSRP ≥ FAKE_5G_RSRP_THRESHOLD 但 SINR < FAKE_5G_SINR_THRESHOLD
#   3. RSRP ≥ FAKE_5G_RSRP_THRESHOLD 但 Ping 失败（丢包）
ENABLE_FAKE_5G_DETECTION=true
# RSRP 阈值（dBm, 负值, 默认 -85 = 信号强度好）
FAKE_5G_RSRP_THRESHOLD=-85
# SINR 阈值（dB, 默认 0, 低于此值视为干扰严重）
FAKE_5G_SINR_THRESHOLD=0
# Ping 阈值（毫秒, 默认 200, 高于此值视为延迟过高）
FAKE_5G_PING_THRESHOLD=200

# ===============================
# 11. 防振荡冷却参数
# ===============================
# 5G 假满格降级到 4G 后, 强制保持冷却时间, 防止网络制式频繁振荡
# 冷却期结束且信号确实稳定优秀才允许恢复 5G
# 默认 1800 秒（30 分钟）, 可调范围 900-3600
DOWNGRADE_COOLDOWN_SEC=1800
# 冷却期结束后, 连续 N 次检测正常才恢复 5G（默认 3 次 = 6 分钟）
# 范围 1-5, 用户可根据网络稳定性自行调整
DEGRADE_RECOVERY_COUNT=3

# ===============================
# 12. 无网络死锁回退参数
# ===============================
# 降级到 4G 后, 如果连续 N 次检测 Ping 完全失败（不是延迟高, 是彻底不通）,
# 则自动恢复 5G, 避免 4G 也无网时死锁
# 默认 2 次（4 分钟）
DEGRADE_NO_NET_ROLLBACK_COUNT=2

# ===============================
# 13. 4G+ 跳频防护参数
# ===============================
# 游戏模式启用时, 锁定 LTE only (mode=11) + 关闭 ENDC, 减少载波聚合跳频
ENABLE_LTE_LOCK_FOR_GAME=true

# ===============================
# 14. Android 版本要求
# ===============================
# 最低 Android API 级别（34 = Android 14）
# 低于此版本的部分功能可能受限, 但不阻止运行
MIN_API_LEVEL=34
