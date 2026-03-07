# 15 — 性能目标与基准测试

## 概述

ym 的核心差异化在于性能。本规格定义了各场景的量化性能目标、基准测试方法和持续监控策略。

## 性能目标

### 启动开销

| 操作 | 目标 | 对比 Gradle |
|------|------|------------|
| `ym --version` | < 5ms | Gradle 3-5s |
| `ym info`（无项目） | < 10ms | — |
| 加载 `package.toml` | < 1ms | Gradle 配置阶段 20s+ |

### 依赖解析

| 场景 | 目标 | 条件 |
|------|------|------|
| 缓存命中 + 缓存命中 | < 500ms（1000 模块） | 所有 JAR 在本地 |
| 缓存命中 + 缓存未命中 | < 30s | 需要下载 JAR |
| 全新解析（无缓存） | < 60s | 需要下载 POM + JAR |
| 单模块增量（1 个依赖变更） | < 3s | — |

### 编译

| 场景 | 目标 | 条件 |
|------|------|------|
| 全量编译 | < 5min | 1000 模块，~50 万行 Java |
| 增量（1 文件修改，ABI 不变） | < 1s | 仅重编译 1 个文件 |
| 增量（1 文件修改，ABI 变化） | < 3s | 重编译依赖链 |
| 空操作（无变更） | < 500ms | mtime 快速路径 |

### 开发模式

| 场景 | 目标 | 说明 |
|------|------|------|
| 文件变化 → 编译完成 | < 500ms | 单文件修改 |
| 编译 → DCEVM HotSwap | < 200ms | L1（不丢失状态） |
| 编译 → 进程重启 | < 3s | L2（极端结构变更） |

### IDE 生成

| 场景 | 目标 |
|------|------|
| `ymc idea`（100 模块） | < 5s |
| `ymc idea --sources`（100 模块） | < 30s（含下载） |

## 基准测试项目

### small-spring-boot

```
模块数：1
源码行数：~1000
依赖数：~20（通过 spring-boot-starter-web BOM）
验证点：BOM 解析、注解处理器、基本编译
```

### medium-monorepo

```
模块数：50
源码行数：~50,000
依赖数：~200
模块间依赖：~100 条边
验证点：工作空间编译、拓扑并行、dev 模式增量
```

### large-enterprise

```
模块数：1000+
源码行数：~500,000
依赖数：~500
验证点：性能目标达标、内存占用、并行效率
```

## 基准测试方法

### 内置基准命令

```bash
ymc build --profile                      # 各阶段计时
```

输出应包含：
```
 Config load:      2ms
 Dependency resolve: 450ms (cache hit)
 Compilation:
   Level 0 (12 modules): 1.2s
   Level 1 (35 modules): 2.8s
   Level 2 (3 modules):  0.4s
 Resource copy:    120ms
 Total:            4.97s
```

### 外部基准测试

使用 `hyperfine` 进行多轮测试：

```bash
# 冷启动全量编译
hyperfine --warmup 1 --runs 5 'ymc build --clean'

# 增量编译（修改 1 文件）
hyperfine --prepare 'touch src/main/java/com/example/Main.java' 'ymc build'

# 对比 Gradle
hyperfine 'ymc build' 'gradle build'
```

### 内存占用

| 场景 | 目标 |
|------|------|
| ym 进程本身 | < 50MB RSS |
| 1000 模块依赖解析 | < 200MB RSS |
| 1000 模块编译（rayon 线程池） | < 500MB RSS |

## 性能回归检测

### CI 集成

每次 PR 运行性能基准：
1. 在基准项目上运行 `ymc build --profile`
2. 与 main 分支的基线对比
3. 如果关键指标劣化 > 10%，标记 warning
4. 如果关键指标劣化 > 30%，阻止合并

### 关键指标

| 指标 | 采集方式 | 基线阈值 |
|------|---------|---------|
| 冷启动时间 | `--profile` 的 Total | 按项目规模 |
| 增量编译时间 | 修改 1 文件后 build | < 3s |
| 依赖解析时间（缓存命中） | `--profile` 的 Dependency resolve | < 500ms |
| 峰值 RSS | `/proc/self/status` VmRSS | < 500MB |

## 性能优化工具链

| 工具 | 用途 |
|------|------|
| `cargo flamegraph` | CPU 热点分析 |
| `heaptrack` | 内存分配追踪 |
| `strace -c` | 系统调用统计 |
| `perf stat` | 硬件计数器 |

## 已知瓶颈

| 瓶颈 | 当前表现 | 优化方向 |
|------|---------|---------|
| POM 网络下载 | 首次解析慢 | 已实现磁盘缓存 + 并行 BFS |
| 大型 classpath 拼接 | 1000 模块 classpath 很长 | 考虑 @argfile 或 classpath jar |
| Fingerprint JSON 序列化 | 大量文件时 IO 明显 | 考虑二进制格式 |
| 工作空间图构建 | glob 扫描文件系统 | 已实现 GraphCache |

## 优化路线图

### P0 — `--profile` 输出标准化

所有命令支持 `--profile`，统一格式，便于自动化采集。

### P1 — CI 性能基准

在 CI 中建立基准测试流水线，自动检测性能回归。

### P2 — Classpath 优化

1000+ 模块场景下 classpath 字符串可能超过 OS 限制，使用 classpath JAR 或 `@argfile`。
