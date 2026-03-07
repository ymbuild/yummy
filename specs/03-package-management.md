# 03 — 包管理命令

## 概述

ym 提供一组包管理命令，用于依赖的安装、添加、删除、升级、搜索和版本管理。版本语法兼容 npm/yarn（`^`/`~` 前缀）。

## 命令

### `ym install`

安装 `package.json` 中声明的所有依赖。

```bash
ym install                               # 安装所有依赖
```

**流程：**
1. 读取 `package.json` 的 `dependencies` + `devDependencies`
2. 检查 `package-lock.json` 是否存在且匹配
3. 快速路径：锁文件命中 + 缓存 JAR 存在 → 零网络请求
4. 慢速路径：解析传递依赖 → 下载 → 校验 → 更新锁文件

### `ym add`

添加新依赖。

```bash
ym add com.google.guava:guava            # 添加依赖（自动获取最新版本，^前缀）
ym add com.google.guava:guava@33.0.0     # 指定版本
ym add jackson-databind                  # 模糊搜索：按 artifactId 搜索 Maven Central
ym add guava -D                          # 添加到 devDependencies
ym add core -W                           # 添加到 workspaceDependencies
```

**版本行为：**
- 自动获取版本时，添加 `^` 前缀（如 `"^33.0.0"`），表示允许兼容升级
- 显式指定版本时，使用原始值
- 下载失败时显示警告但仍写入 package.json（下次 build 时解析）

**模糊搜索：**
- 当输入不含 `:` 时，按 artifactId 搜索 Maven Central
- 显示候选列表，交互式选择

### `ym remove`

移除依赖。

```bash
ym remove com.google.guava:guava         # 精确匹配
ym remove guava                          # 模糊匹配：按 artifactId 后缀查找
ym remove guava -D                       # 从 devDependencies 移除
```

**模糊匹配：** 当输入不含 `:` 时，搜索所有依赖的 artifactId 部分。

### `ym upgrade`

升级依赖到最新版本。

```bash
ym upgrade                               # 升级所有依赖
ym upgrade -i                            # 交互式选择要升级的依赖
```

**升级规则：**
- 遵守版本前缀：`^1.2.3` 允许升级到 `<2.0.0`，`~1.2.3` 允许升级到 `<1.3.0`
- 无前缀的精确版本不自动升级（除非 `-i` 交互确认）
- 升级后更新 package.json 和 package-lock.json

### `ym outdated`

检查哪些依赖有新版本（不修改，仅报告）。

```bash
ym outdated                              # 列出过时依赖
ym outdated --json                       # JSON 输出（CI 集成）
```

输出：
```
Package                                    Current   Latest
com.fasterxml.jackson.core:jackson-databind  2.17.0    2.19.0
com.google.guava:guava                       32.1.3    33.0.0
```

### `ym search`

搜索 Maven Central 仓库（类似 `apt search`）。

```bash
ym search jackson                        # 按关键词搜索
ym search jackson --limit 20             # 限制结果数（默认 10）
```

**搜索方式：** 查询 Maven Central Search API（`search.maven.org`）。按 artifactId 和 groupId 匹配。

**输出格式：**
```
com.fasterxml.jackson.core:jackson-databind    2.19.0
com.fasterxml.jackson.core:jackson-core        2.19.0
com.fasterxml.jackson.core:jackson-annotations 2.19.0
com.fasterxml.jackson.dataformat:jackson-dataformat-yaml 2.19.0
```

**与 `ym add` 的区别：**
- `ym search` 只搜索展示，不修改 package.json
- `ym add jackson-databind` 搜索并直接添加选中的依赖

### `ym lock`

重建锁文件。

```bash
ym lock                                  # 重新解析并生成锁文件
ym lock --check                          # 仅检查锁文件是否最新（CI 模式，不修改）
```

`--check` 模式：如果锁文件与 package.json 不同步，返回非零退出码。适用于 CI 防止未提交的依赖变更。

### `ym dedupe`

去重传递依赖。

```bash
ym dedupe                                # 执行去重
ym dedupe --dry-run                      # 仅显示可去重项
```

### `ym pin`

固定依赖版本（移除 `^`/`~` 前缀）。

```bash
ym pin com.google.guava:guava            # 固定版本：^33.0.0 → 33.0.0
ym pin --unpin com.google.guava:guava    # 恢复前缀：33.0.0 → ^33.0.0
```

### `ym sources`

下载所有依赖的 `-sources.jar`（用于 IDE 调试跳转）。

```bash
ym sources                               # 下载所有源码 JAR
```

## 已知限制

- [ ] 不支持 URL 依赖（`https://...`）
- [ ] 不支持 Git 依赖（`git+https://...`）
- [ ] `^`/`~` 前缀当前被剥离后精确匹配，未做真正的范围解析
- [ ] 无 `--frozen` 锁文件模式（CI 中禁止任何锁文件修改）
- [ ] 无离线模式（`--offline`）

## 优化路线图

### P0 — `--frozen` 模式

```bash
ym install --frozen                      # 严格按锁文件安装，任何不匹配则报错
```

适用于 CI 环境，防止意外的依赖变更。

### P1 — Version Range 真正解析

实际解析 `^`/`~` 前缀含义，查询 Maven Central 候选版本，选择最高匹配：

| 前缀 | 当前值 | 候选版本 | 选择结果 |
|------|--------|---------|---------|
| `^1.2.3` | — | 1.2.3, 1.2.5, 1.3.0, 2.0.0 | 1.3.0 |
| `~1.2.3` | — | 1.2.3, 1.2.5, 1.3.0 | 1.2.5 |

### P2 — 离线模式

```bash
ym install --offline                     # 仅使用本地缓存，不发网络请求
```
