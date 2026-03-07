# 08 — JDK 管理

## 概述

ym 内置 JDK 扫描、自动下载和版本管理能力，目标是零配置开箱即用——项目声明 `target: "21"` 即可，ym 自动找到或下载对应 JDK。

整个工作空间使用统一的 JDK 版本，不支持模块级别的 JDK 版本差异。

## JDK 扫描

`scan_jdks()` 按优先级扫描：

| 顺序 | 来源 | 路径 |
|------|------|------|
| 1 | ym 管理 | `~/.ym/jdks/` |
| 2 | JAVA_HOME | 环境变量 |
| 3 | IntelliJ/JBR | JetBrains Toolbox + 独立安装 |
| 4 | SDKMAN | `~/.sdkman/candidates/java/` |
| 5 | Jabba | `~/.jabba/jdk/` |
| 6 | 系统 | `/usr/lib/jvm`, `/usr/java`, `/Library/Java/JavaVirtualMachines` |

macOS 额外检查 `/Contents/Home/bin/java` 路径。

每个 JDK 记录：
- vendor（自动检测 10+ 供应商）
- version（主版本号提取）
- path
- source（来源类型）
- has_dcevm（是否支持增强热重载）

### 供应商检测

通过解析 JDK 路径和 `release` 文件自动识别：

| 供应商 | 检测特征 |
|--------|---------|
| JetBrains (JBR) | 路径含 `jbr`/`jetbrains` |
| GraalVM | 路径含 `graalvm` |
| Corretto | 路径含 `corretto` |
| Temurin | 路径含 `temurin`/`adoptium` |
| Zulu | 路径含 `zulu` |
| Semeru | 路径含 `semeru` |
| SapMachine | 路径含 `sapmachine` |
| Liberica | 路径含 `liberica` |
| Microsoft | 路径含 `microsoft` |
| Dragonwell | 路径含 `dragonwell` |
| Oracle | 路径含 `oracle` |
| OpenJDK | 默认 |

### 版本解析

从 `java -version` 或路径解析版本号：
- Java 8: `1.8.0_xxx` → 主版本 `8`
- Java 9+: `21.0.1` → 主版本 `21`

## JDK 自动下载

### 触发条件

`ensure_jdk()` 在以下情况自动下载：
1. JAVA_HOME 未设置
2. PATH 中无 javac
3. 缓存中无匹配版本
4. `jvm.autoDownload` 为 true（默认）

**非交互模式（CI/无 TTY）：** 静默下载默认供应商（Temurin）的对应版本，不弹出交互选择。

### 下载源

| 供应商 | API | 说明 |
|--------|-----|------|
| Adoptium (Temurin) | `https://api.adoptium.net/v3` | 默认，最稳定 |
| JetBrains (JBR) | GitHub Releases API | 支持 DCEVM，适合开发 |
| GraalVM | 交互式选择 | native-image |
| 自定义 URL | 用户输入 | 任意 tar.gz/zip |

### 下载流程

1. 检测 OS（linux/mac/windows）和架构（x64/aarch64）
2. 构建 API URL（Adoptium: `api.adoptium.net/v3/binary/latest/{version}/ga/{os}/{arch}/jdk/hotspot/normal/eclipse`）
3. 下载 tar.gz/zip（带 indicatif 进度条）
4. 解压到 `~/.ym/jdks/{name}/`
5. 清理归档文件

### 交互式选择

`ym init` 交互模式提供：
- DEV JDK 选择（优先 JBR/DCEVM，支持增强热重载）
- PROD JDK 选择（优先 Temurin/Corretto，生产稳定）
- GraalVM 选择（可选，用于 native-image）

## JVM 参数管理

```toml
jvmArgs = ["-Xmx512m", "-XX:+UseG1GC"]

[env]
DEV_JAVA_HOME = "~/.ym/jdks/jbr-25"
PROD_JAVA_HOME = "/usr/lib/jdk/graalvm-jdk-25"

[scripts]
dev = "JAVA_HOME=$DEV_JAVA_HOME ymc dev"
build = "JAVA_HOME=$PROD_JAVA_HOME ymc build"
```

通过 `env` + `scripts` 实现 DEV/PROD JDK 分离。供应商配置不在 `[jvm]` 中，仅通过环境变量和路径控制。

## 供应商选择

`jvm.vendor` 不作为运行时配置。供应商选择仅在以下场景生效：

- `ym init` 交互式引导时，选择下载哪个供应商的 JDK
- `ensure_jdk()` 自动下载时，默认选择 Temurin（CI/非交互）或 JBR（开发）

构建时只校验 JDK 版本与 `target` 匹配，不校验供应商。扫描到的任意 JDK 只要版本满足即可使用。

## 已知限制

| 问题 | 严重性 |
|------|--------|
| 版本匹配基于子字符串包含（可能误匹配） | 低 |
| JBR 外的供应商仅支持 Adoptium API 自动下载 | 中 |
| User-Agent 不统一（`ym-build` vs `ym/0.1.0`） | 低 |
| 下载超时 30s connect / 无总超时限制 | 低 |
| 不支持 HTTP 代理 | 中 |
| 不支持 `.java-version` 文件 | 低 |

## 优化路线图

### P0 — 支持 `.java-version` 文件

读取项目根目录的 `.java-version` 文件自动选择 JDK：

```
# .java-version
21
```

与 SDKMAN、jEnv 等工具兼容。

### P1 — HTTP 代理支持

读取 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量，配置 reqwest client。企业内网环境必需。

### P2 — User-Agent 统一

所有 HTTP 请求统一使用 `ym/{version}` 格式的 User-Agent。

### P3 — 多供应商 API 下载

支持直接从 Corretto / Zulu / Liberica API 自动下载，无需交互选择。
