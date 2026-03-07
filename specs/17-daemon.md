# 17 — Daemon 模式

## 概述

ym 当前采用"无 daemon"设计，依赖原生二进制的快速启动（~5ms）。但在大型工程场景中，JIT 编译结果、依赖图和 POM 缓存的内存加载仍有冷启动开销。本规格定义可选的 daemon 模式。

## 设计原则

1. **Daemon 是可选的**：不影响现有行为，`ym` 默认仍是无 daemon 模式
2. **自动生命周期**：空闲超时自动退出，无需用户手动管理
3. **进程隔离**：daemon 崩溃不影响命令行工具，自动回退到直接执行

## 架构

```
ym build
  ↓
检测 daemon 是否运行（.ym/daemon.sock 或 .ym/daemon.port）
  ├─ daemon 存在 → 发送 RPC 请求 → 返回结果
  └─ daemon 不存在
       ├─ 配置启用 → 启动 daemon → 发送 RPC → 返回
       └─ 配置禁用 → 直接执行（当前行为）
```

### daemon 进程

```
ym-daemon
  ├─ Unix Socket / TCP 监听
  ├─ 内存缓存：
  │   ├─ 工作空间图 (WorkspaceGraph)
  │   ├─ POM 解析缓存 (PomCache)
  │   ├─ 指纹数据库 (Fingerprints)
  │   └─ 依赖图 (LockFile)
  ├─ 文件监听：
  │   └─ package.json 变更 → 自动刷新图
  └─ 空闲计时器：
      └─ 3 小时无请求 → 自动退出
```

### 通信协议

Unix Domain Socket（Linux/macOS）或 Named Pipe（Windows）：

```json
// 请求
{"id": 1, "method": "build", "params": {"target": "web", "release": false}}

// 响应
{"id": 1, "result": {"success": true, "files_compiled": 42, "time_ms": 1200}}

// 通知（daemon → client，实时日志流）
{"method": "log", "params": {"level": "info", "message": "Compiling web..."}}
```

## 命令

```bash
ym daemon start                          # 启动 daemon
ym daemon stop                           # 停止 daemon
ym daemon status                         # 查看状态
ym daemon restart                        # 重启
```

## 配置

```json
{
  "daemon": {
    "enabled": false,
    "idleTimeout": "3h",
    "maxMemory": "512m"
  }
}
```

| 字段 | 默认 | 说明 |
|------|------|------|
| `enabled` | `false` | 是否启用 daemon 模式 |
| `idleTimeout` | `"3h"` | 空闲超时自动退出 |
| `maxMemory` | `"512m"` | daemon 进程最大内存 |

## 缓存加速效果预估

| 操作 | 无 daemon | 有 daemon | 加速 |
|------|-----------|-----------|------|
| 加载工作空间图（1000 模块） | ~200ms（磁盘读取 + 解析） | ~0ms（内存命中） | 200x |
| POM 缓存查询 | ~50ms（磁盘 IO） | ~0ms（内存哈希表） | 50x |
| 指纹加载 | ~100ms（JSON 解析） | ~0ms（内存） | 100x |
| 依赖解析（锁文件命中） | ~300ms | ~50ms | 6x |

## 安全考虑

- Unix Socket 权限 700（仅当前用户可连接）
- daemon 不接受来自不同项目目录的请求（验证 workspace root 匹配）
- daemon PID 文件存放在 `.ym/daemon.pid`
- 多个项目不共享 daemon（每个 workspace root 独立）

## 已知风险

| 风险 | 缓解 |
|------|------|
| daemon 缓存不一致 | 文件监听 + 请求时校验 mtime |
| daemon 内存泄漏 | `maxMemory` 限制 + 定期自检 |
| daemon 崩溃 | 自动回退到直接执行 |
| 端口/socket 冲突 | PID 文件 + 锁检查 |
| daemon 版本不匹配 | 请求时校验版本号，不匹配则重启 |

## 实施阶段

### Phase 1 — 基础设施

1. daemon 进程管理（启动/停止/状态）
2. Unix Socket 通信
3. PID 文件和锁

### Phase 2 — 缓存集成

1. 工作空间图常驻内存
2. POM 缓存常驻内存
3. 指纹数据库常驻内存

### Phase 3 — 文件监听

1. 监听 `package.json` 变更自动刷新
2. 监听源码目录预计算变更文件
3. 主动预热编译（后台预编译变更文件）

## 优先级

daemon 模式是 **Phase 2 Improvement (P2-I2)**，在基本功能验证完成后实施。对小型项目意义不大（原生启动已足够快），但对 1000+ 模块的大型工程可显著改善体验。
