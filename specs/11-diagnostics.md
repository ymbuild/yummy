# 11 — 诊断与工具

## 概述

ym 提供一系列诊断和辅助命令，用于调试环境问题、分析依赖关系和项目健康度。

## 命令清单

### `ym doctor`

诊断环境问题。

```bash
ym doctor                                # 检查所有
ym doctor --fix                          # 自动修复
```

检查项及 `--fix` 行为：

| 检查项 | `--fix` 动作 |
|--------|-------------|
| package.toml 存在且可解析 | 无法自动修复，报错提示 |
| package.toml schema 校验（字段类型、坐标格式、版本格式、workspaceDependencies 引用完整性） | 无法自动修复，报告具体问题 |
| JDK 可用且版本匹配 `target` | 自动下载匹配的 JDK |
| 依赖缓存完整性（JAR 文件存在 + SHA-256 校验） | 重新下载缺失或哈希不一致的 JAR |
| `.ym/` 目录权限 | 修正为 755（目录）/ 644（文件） |
| `~/.ym/credentials.json` 权限 | 修正为 600 |

### `ym info`

显示项目与环境信息。

```bash
ym info                                  # 显示项目与环境概要
ym info --json                           # JSON 输出
```

输出：项目名称、版本、target、依赖数量（按 scope 分类）、工作空间模块数、主类、ym 版本、Java 版本、JAVA_HOME、OS。

### `ym tree`

显示依赖树。

```bash
ym tree                                  # 树形显示
ym tree --flat                           # 扁平列表
ym tree --depth 2                        # 限制深度
ym tree --json                           # JSON 输出
ym tree --dot                            # DOT 格式（可用 Graphviz 可视化）
ym tree --reverse jackson-core           # 反向依赖：谁依赖了 jackson-core
```

### `ymc clean`

清理构建输出。

```bash
ymc clean                                # 清理 out/
ymc clean --all                          # 清理 out/ + .ym/cache/（确认后执行）
ymc clean --all -y                       # 跳过确认（CI 用）
```

`ymc clean` 清理编译输出，无需确认。`ymc clean --all` 额外清理依赖缓存，需确认。

**工作空间行为：** 在工作空间根执行时清理所有模块的 `out/` 目录。在子模块目录执行时仅清理当前模块。

**注意：** `ymc rebuild` 已移除，使用 `ymc build --clean` 代替。`ymc watch` 已移除，监听编译使用 `ymc dev`，监听测试使用 `ymc test --watch`，通用文件监听使用外部工具（如 `watchexec`）。
