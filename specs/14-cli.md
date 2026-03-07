# 14 — CLI 架构

## 概述

ym 采用双二进制架构：`ym`（包管理器）和 `ymc`（编译器/运行时），由同一 Rust 二进制根据执行文件名分发。

## 二进制分发

```
ym    → 包管理命令（install, uninstall, upgrade, ...）
ymc   → 编译/运行命令（build, run, dev, test, ...）
```

**实现：** `main.rs` 中读取 `argv[0]` 的文件名，`"ymc"` 走 `ymc_main()`，否则走 `ym_main()`。

安装时复制同一二进制为两个文件名：
```bash
cp ym ymc    # Unix
cp ym.exe ymc.exe  # Windows
```

## ym 命令（包管理器）

```
ym init [name] [-t template] [-y]        # 初始化项目
ym install [dep] [--scope S] [-W]         # 安装依赖（无参数：安装全部；有参数：添加依赖）
ym uninstall <dep> [-W]                  # 移除依赖
ym upgrade [-i] [-y] [--json]            # 升级依赖
ym info [--json]                         # 项目与环境信息
ym tree [--depth N] [--json] [--flat] [--dot] [--reverse <dep>]  # 依赖树
ym doctor [--fix]                        # 诊断
ym convert                               # Maven/Gradle 迁移
ym publish [--registry R] [--dry-run]     # 发布
ym login [--list] [--remove <url>]        # 仓库登录
ym workspace {list|foreach [--parallel] [-j N] [--keep-going]}  # 工作空间
ym completions <shell>                   # Shell 补全
```

## ymc 命令（编译器/运行时）

```
ymc build [target] [--release] [-j N] [--profile] [-v] [--clean] [-o dir] [--keep-going] [--strict]
ymc dev [target] [--no-reload] [--debug] [--debug-port P] [--suspend] [-- args...]
ymc run [target] [--class C] [--debug] [--debug-port P] [--suspend] [-- args...]
ymc test [target] [--watch] [--filter F] [--integration] [--all] [--tag T] [--exclude-tag T] [-v]
         [--fail-fast] [--timeout N] [--coverage] [--list] [--keep-going]
ymc clean [--all]
ymc idea [target] [--sources]
```

## 脚本执行

`ym <name>` 当 `name` 不匹配内置命令时，自动在 `[scripts]` 中查找同名脚本执行：
1. 加载 package.toml
2. 在 `scripts` 中查找匹配名称
3. 找到 → 执行脚本（`ym dev` 等于执行 `scripts.dev`）
4. 未找到 → 报错并建议类似命令

## Shell 补全

```bash
# Bash
eval "$(ym completions bash)"

# Zsh
ym completions zsh > ~/.zsh/completions/_ym

# Fish
ym completions fish | source

# PowerShell
ym completions powershell | Out-String | Invoke-Expression
```

## 错误处理

所有命令使用 `anyhow::Result` 进行错误传播。错误输出格式：

```
✗ Error: dependency 'com.example:nonexistent' not found in Maven Central
```

- 致命错误 → 红色 `✗` 前缀，非零退出码
- 警告 → 黄色 `!` 前缀，继续执行
- 成功 → 绿色 `✓` 前缀

**颜色控制：**
- 输出到非 TTY（管道/重定向）时自动禁用 ANSI 颜色
- 设置 `NO_COLOR` 环境变量时强制禁用颜色（遵循 [no-color.org](https://no-color.org/) 标准）
- `--color {auto|always|never}` 显式控制（优先级高于环境变量）

### 退出码

| 退出码 | 含义 |
|--------|------|
| 0 | 成功 |
| 1 | 一般错误（编译失败、依赖解析失败等） |
| 2 | 用法错误（无效参数、未知命令） |

## HTTP 客户端约定

所有 HTTP 请求使用 reqwest，统一配置：

| 配置 | 值 | 说明 |
|------|-----|------|
| User-Agent | `ym/{version}` | 标识构建工具 |
| Connect Timeout | 30s | 建立连接超时 |
| 代理 | 🔲 待实现 | `HTTP_PROXY` / `HTTPS_PROXY` |

**注意：** 当前代码中 User-Agent 不统一（`ym/0.1.0` 和 `ym-build` 混用），需要统一为动态版本号。

## 设计决策

| 决策 | 原因 |
|------|------|
| 双二进制分离 | 职责清晰：ym 管依赖（如 yarn），ymc 管编译运行（如 vite） |
| 脚本即命令 | `ym dev` 自动查找 `scripts.dev` 执行，无需 `ym run` 前缀 |
| clap derive | 类型安全的参数解析，自动 --help |
| 无 daemon | 简化架构，原生二进制启动足够快 |
| package.toml 格式 | TOML 支持注释，结构清晰，现代构建工具趋势 |
| 精确版本 | 无版本范围语法，无锁文件，Go 风格简洁 |
| 统一依赖 scope | 无 devDependencies，所有依赖在 `[dependencies]` 中通过 scope 区分 |
| 仅支持 Java | 专注做好一件事，不分散精力到 Kotlin/Scala |
| 消除冗余命令 | 功能已被现有 flag 覆盖的命令不应独立存在 |

## 已移除的命令

以下命令因功能冗余已被移除：

| 移除 | 替代方案 | 理由 |
|------|----------|------|
| `ymc rebuild` | `ymc build --clean` | rebuild 仅做 clean + build，`--clean` flag 已覆盖 |
| `ym deps --outdated` | `ym upgrade`（预览模式） | upgrade 无 `-y` 时已显示版本预览 |
| `ym lock` | 无锁文件 | 依赖解析缓存为内部实现 |
| `ym dedupe` | nearest-wins 已保证单版本 | 无实际场景 |
| `ym pin` | 无版本范围前缀 | 概念不再存在 |
| `ym workspace build/test/run` | `ymc build/test/dev <module>` | 编译运行职责归 ymc，workspace 只管元数据 |
| `ym add` | `ym install <dep>` | install 有参/无参统一，减少命令数 |
| `ym remove` | `ym uninstall` | 与 install 对称 |
| `ymc watch` | `ymc dev` / `ymc test --watch` | 通用文件监听由外部工具（watchexec 等）处理 |
| `ymc build --watch` | `ymc dev` / 外部工具 | dev 模式已覆盖监听编译场景 |
| `ymc graph` | `ym tree --dot` / `ym tree --reverse` | 功能合并到 `ym tree`，统一依赖可视化入口 |
| `ymc check` | `ymc build --strict` | Java 无 check vs build 编译速度差异，`--strict` 覆盖 `-Werror` 需求 |
| `ym deps` | `ym tree --flat` | 功能完全重复 |
| `ym verify` | `ym doctor` | SHA-256 校验合并到 doctor 的缓存完整性检查 |
| `ym outdated` | `ym upgrade` | upgrade 无 `-y` 时就是 outdated（显示预览不执行） |
| `ym why` | `ym tree --reverse` | 功能完全重复 |
| `ym env` | `ym info` | 环境信息合并到 info |
| `ym validate` | `ym doctor` | schema 校验合并到 doctor 检查项 |
| `ym config` | 直接编辑 package.toml | TOML 可读性高，config 命令使用率极低 |
| `ymc exec` | — | 语法糖，价值不大 |
| `ymc diff` | `git diff` / `git status` | 基于指纹的变更检测用户场景极少 |
| `ymc size` | `du -sh` / `wc -l` | shell 命令替代 |
| `ym sources` | `ymc idea --sources` | IDE 集成已覆盖源码下载 |
| `ym license` | 外部合规工具 | 低频需求，企业有专门工具 |
| `ym link` | workspace / monorepo | 工作空间已覆盖多模块开发 |
| `ym cache` | `ymc clean --all` | 缓存清理已被 clean --all 覆盖 |
| `ym search` | `ym install <keyword>` | install 模糊搜索已覆盖 |
| `ym audit` | Dependabot / Snyk | 外部安全工具更专业 |
| `ym run` | `ym <script-name>` | 脚本即命令，无需 run 前缀 |
| `ym daemon` | — | 原生二进制启动足够快，暂不需要 |
| `ymc doc` | `javadoc` / IDE | 直接调用 javadoc 或 IDE 生成 |
| `ymc bench` | 脚本 / JMH CLI | JMH 太小众 |
| `ymc hash` | `sha256sum` / `git rev-parse` | shell 命令替代 |
| `ymc jar` | `ym publish` 内部步骤 | 独立命令价值不大 |
| `ymc classpath` | — | 用户场景极少 |
| `ymc create` | `ym init` + 手动创建目录 | init 已覆盖 |
| `ymc fmt` | IDE / 外部格式化工具 | 硬绑 google-java-format 不够灵活 |
| `ym workspace graph` | — | 模块关系从 package.toml 可读 |
| `ym workspace changed` | `git diff` | 仅基于 git status，价值有限 |
| `ym workspace impact` | — | 依赖 changed，已删 |
| `ym workspace info` | `ym info` | 信息已合并到 info |
| `ym workspace focus` | `ym tree`（在模块目录执行） | 功能重复 |
