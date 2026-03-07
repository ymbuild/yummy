# 05 — 运行与开发模式

## 概述

ym 提供两种运行模式：`ymc run`（一次性运行）和 `ymc dev`（开发模式：编译+运行+监听+热重载），两者均支持 JDWP 远程调试。

## `ymc run` — 编译并运行

```bash
ymc run                                  # 运行默认主类
ymc run --class com.example.App          # 指定主类
ymc run --debug                          # 启用 JDWP 调试（端口 5005）
ymc run --debug --suspend                # 启动后挂起等待调试器
ymc run --debug-port 8000                # 自定义调试端口
ymc run -- arg1 arg2                     # 传递程序参数（main 方法的 args）
```

**Classpath scope 规则：**
- 编译阶段：`compile` + `provided`（排除 `runtime` 和 `test`）
- 运行阶段：`compile` + `runtime`（排除 `provided` 和 `test`）

`ymc dev` 同理。

### `--` 参数语义

`ymc run` 和 `ymc dev` 中 `--` 后的参数含义不同：

| 命令 | `--` 后传递 | 原因 |
|------|-----------|------|
| `ymc run -- arg1` | 程序参数（`main(String[] args)`） | 一次性执行，用户需要传参给程序 |
| `ymc dev -- -Dfoo` | JVM 参数 | 常驻进程，用户需要调整 JVM 配置（如 Spring profiles） |

`ymc run` 的 JVM 参数通过 `package.toml` 的 `jvmArgs` 字段或 `--debug` 等专用标志配置。

### 主类解析优先级

1. `--class` 命令行参数
2. `package.toml` 的 `main` 字段
3. 扫描源码中的 `public static void main` 方法
   - 0 个 → 报错
   - 1 个 → 自动选中
   - 多个 → 交互式选择（dialoguer::Select）
   - 非交互模式（CI/无 TTY）→ 多个主类时报错退出，要求使用 `--class` 指定

### JDWP 调试

```
-agentlib:jdwp=transport=dt_socket,server=y,suspend={y|n},address=*:{port}
```

默认端口：5005。`--suspend` 时 JVM 启动后暂停，等待调试器连接。

## `ymc dev` — 开发模式

```bash
ymc dev                                  # 默认模式
ymc dev --no-reload                      # 禁用热重载，变更时重启
ymc dev --debug                          # 启用 JDWP 调试（端口 5005）
ymc dev --debug --suspend                # 启动后挂起等待调试器
ymc dev --debug-port 8000                # 自定义调试端口
ymc dev -- -Dspring.profiles.active=dev  # 传递 JVM 参数（非程序参数）
```

### 完整生命周期

```
1. 执行 predev 脚本
2. 解析依赖
3. 首次编译
4. 查找主类
5. 构建 classpath
6. 配置 JVM 参数（jvmArgs + DCEVM + agent）
7. 启动 Java 进程
8. 进入监听循环：
   a. 等待文件变化（100ms 防抖）
   b. 增量编译变更文件
   c. 尝试 DCEVM HotSwap
   d. HotSwap 失败 → 重启进程
9. Ctrl+C →
   a. 终止 Java 子进程（Unix: SIGTERM → 5s 超时后 SIGKILL；Windows: `taskkill` 终止进程树）
   b. 等待进程退出
   c. 执行 postdev 脚本
```

### 热重载策略（DCEVM 双级）

| 级别 | 策略 | 条件 | 速度 |
|------|------|------|------|
| L1 | DCEVM HotSwap | 方法体、新增/删除方法和字段、接口变更 | ~50-200ms |
| L2 | 进程重启 | 修改类继承层次、enum 常量等极端变更 | ~2-5s |

`ym init` 默认引导选择 JetBrains Runtime (JBR) 作为开发 JDK，内置 DCEVM 支持。DCEVM 下 95%+ 的日常代码变更可通过 L1 HotSwap 完成，无需重启、不丢失状态。

**等级判定流程：**
1. ym 将变更的 `.class` 文件发送给 agent
2. Agent 通过 DCEVM 增强 HotSwap（`Instrumentation.redefineClasses()`）推送变更
3. HotSwap 成功 → 完成（L1，不丢失状态）
4. HotSwap 失败（极端结构变更） → 通知 ym 进行进程重启（L2）

**ym-agent 通信协议：**
- 传输：TCP，127.0.0.1:{port}
- 端口选择：启动时随机选取可用端口，通过 JVM 系统属性 `-Dym.agent.port={port}` 传递给 agent
- 格式：JSON
- 请求：`{"method":"reload","params":{"classDir":"...","classes":["com.example.Main"]}}`
- 响应：`{"success":true,"strategy":"HotSwap","timeMs":45}`

**DCEVM 检测：** 如果 JAVA_HOME 路径包含 `jbr` 或 `jetbrains`，自动添加 `-XX:+AllowEnhancedClassRedefinition`。

### 文件监听

- 引擎：`notify` crate，`RecursiveMode::Recursive`
- 监听目录：源码目录 + 资源目录
- 默认扩展名：`.java`（可通过 `hotReload.watchExtensions` 配置）
- 防抖：首个事件后等待 deadline，收集批量变更，去重

### ym-agent.jar

- 通过 Rust `include_bytes!` 宏嵌入在 ym 二进制中（~7KB）
- 查找顺序：可执行文件目录 → `.ym/` → `~/.ym/`
- 首次使用自动提取到 `~/.ym/ym-agent.jar`

## 工作空间模式

```bash
ymc dev <module>                         # 开发指定模块
```

### 细粒度增量重编译

1. 构建 `src_to_module` 映射（源码目录 → 模块名称）
2. 文件变化时，`identify_changed_modules()` 将变更文件映射到所属模块
3. `recompile_affected_modules()` 按拓扑序传播：
   - 直接变更的模块加入 affected 集合
   - 遍历所有模块（拓扑序），如果依赖了 affected 中的模块则加入
   - 仅按拓扑序重编译 affected 集合中的模块

**示例：** 修改 `libs/core/src/Main.java` → 仅重编译 `core` 和依赖 `core` 的模块，跳过无关模块。

## 已知限制

| 问题 | 影响 | 严重性 |
|------|------|--------|
| DCEVM 检测基于路径字符串 | 可能误检/漏检 | 低 |
| 热重载失败自动回退无配置 | 用户无法控制行为 | 低 |
| JDWP 地址 `*` 绑定所有接口 | 安全风险 | 中 |
| 多主类检测在 CI 中失败 | 非交互模式无法选择 | 中 |
| agent 仅支持 IPv4 本地 | 远程开发不可用 | 低 |
| postdev 在进程崩溃时可能不执行 | 非 graceful shutdown 场景 | 低 |

## 优化路线图

### P0 — DCEVM 检测改进

通过 `java -version` 输出检测 DCEVM/JBR，而非路径字符串。

### P1 — Spring Boot DevTools 集成

检测 `spring-boot-devtools` 依赖，自动配置 livereload 端口和 restart classloader。

### P2 — 端口冲突检测

启动前检查 JDWP 端口和 agent 端口是否被占用。
