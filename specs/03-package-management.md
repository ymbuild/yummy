# 03 — 包管理命令

## 概述

ym 提供一组包管理命令，用于依赖的安装、删除、升级和搜索。所有版本号均为精确版本，不支持范围语法。

## 命令

### `ym install`

安装依赖。无参数时安装 `package.toml` 中声明的所有依赖；有参数时添加新依赖。

```bash
ym install                               # 安装所有依赖
ym install com.google.guava:guava        # 添加依赖（自动获取最新版本，精确版本号）
ym install com.google.guava:guava@33.4.0 # 指定版本
ym install jackson-databind              # 模糊搜索：按 artifactId 搜索 Maven Central
ym install guava --scope test            # 添加为 test scope
ym install core -W                       # 添加到 workspaceDependencies（验证模块存在）
```

#### 无参数模式

安装 `package.toml` 中声明的所有依赖：

1. 读取 `package.toml` 的 `dependencies`（所有 scope）
2. 检查 `.ym/resolved.json` 缓存是否存在且匹配
3. 快速路径：缓存命中 + JAR 存在 → 零网络请求
4. 慢速路径：解析传递依赖 → 下载 → 校验 → 更新缓存

#### 有参数模式

添加新依赖到 `package.toml` 并安装：

**版本行为：**
- 自动获取最新版本，写入精确版本号（如 `"33.4.0"`）。版本查询遵循 registry scope 路由（见 02-resolver.md）——如果 groupId 匹配某个 scope 仓库，从该仓库查询，否则查询 Maven Central
- 显式指定版本时，使用原始值
- 版本获取成功但 JAR 下载失败时显示警告但仍写入 package.toml（下次 build 时解析）

**scope 行为：**
- 无 `--scope` → 简写格式：`"guava" = "33.4.0"`（compile scope）
- `--scope test` → 对象格式：`"guava" = { version = "33.4.0", scope = "test" }`
- `--scope` 支持 compile/runtime/provided/test

**已存在的依赖：** 如果依赖已在 `[dependencies]` 中，`ym install <dep>` 更新版本号（保留 `scope`、`exclude` 等其他字段）。如果同时指定 `--scope`，scope 也会更新。

**模糊搜索：**
- 当输入不含 `:` 时，按 artifactId 搜索 Maven Central
- 显示候选列表，交互式选择

**非交互模式（CI）：** 当标准输入不是 TTY 时，模糊搜索如果有多个候选则报错退出，要求使用完整 `groupId:artifactId` 格式。

### `ym uninstall`

移除依赖。

```bash
ym uninstall com.google.guava:guava      # 精确匹配
ym uninstall guava                       # 模糊匹配：按 artifactId 精确匹配
ym uninstall core -W                     # 从 workspaceDependencies 移除
```

**模糊匹配：** 当输入不含 `:` 时，搜索所有依赖中 artifactId 完全匹配的条目。不区分 scope。
- 精确匹配 1 个 → 直接删除
- 匹配多个（不同 groupId 有同名 artifactId）→ 交互式选择（非交互模式报错，要求使用完整坐标）
- 无匹配 → 报错

**`-W` 标志：** 从 `workspaceDependencies` 数组中移除指定模块名。

### 工作空间通用行为

`ym install`、`ym uninstall`、`ym upgrade` 在工作空间中的目标 `package.toml` 由 `find_config()` 决定（从当前目录向上搜索最近的 `package.toml`）：
- 在根目录执行 → 操作根 `package.toml`
- 在子模块目录执行 → 操作该子模块的 `package.toml`
- `ym install`（无参数）在根目录时，自动调用 `resolve_workspace_deps()` 一次性解析所有模块依赖

### `ym upgrade`

检查所有依赖是否有新版本，更新 package.toml 中的版本号。

```bash
ym upgrade                               # 显示变更预览，确认后升级
ym upgrade -i                            # 交互式逐个选择要升级的依赖
ym upgrade -y                            # 跳过确认，直接升级所有（CI 用）
ym upgrade --json                        # JSON 输出可升级依赖（不修改，CI 集成）
```

**确认流程：** `ym upgrade`（无 `-i`、无 `-y`）先显示变更预览，然后询问确认：
```
Package                                    Current   Latest
com.fasterxml.jackson.core:jackson-databind  2.17.0  → 2.19.0
com.google.guava:guava                       32.1.3  → 33.0.0

Upgrade 2 dependencies? [y/N]
```

非交互模式（CI/无 TTY）下，无 `-y` 时报错退出，要求显式使用 `-y`。

**`--json` 模式：** 仅输出可升级依赖的 JSON 列表，不修改 package.toml，不询问确认。用于 CI 集成（替代已移除的 `ym outdated --json`）。

**对象格式保留：** 升级时仅更新 `version` 字段，保留 `scope`、`exclude` 等其他字段不变。例如 `{ version = "5.11.0", scope = "test" }` 升级后变为 `{ version = "5.12.0", scope = "test" }`。

**工作空间行为：**
- 在根目录：升级根 `[dependencies]`（版本目录），继承 `""` 的子模块自动受益
- 在子模块目录：升级该模块的显式版本，跳过 `""` 继承版本（这些由根统一管理）
- 不自动遍历所有子模块（如需全部升级，使用 `ym workspace foreach -- ym upgrade`）

## TOML 修改策略

`ym install`、`ym uninstall`、`ym upgrade` 修改 `package.toml` 时：
- **保留注释**：用户添加的行内注释和块注释不丢失
- **保留格式**：不重排已有字段的顺序和缩进
- **最小化变更**：仅修改目标字段，不影响文件其余部分
- 实现：使用 `toml_edit` crate（保留格式的 TOML 解析器），不做序列化 → 反序列化全量重写

## 已知限制

- [ ] 不支持 URL 依赖（`https://...`）
- [ ] 不支持 Git 依赖（`git+https://...`）
- [ ] 无离线模式（`--offline`）

## 优化路线图

### P0 — 离线模式

```bash
ym install --offline                     # 仅使用本地缓存，不发网络请求
```
