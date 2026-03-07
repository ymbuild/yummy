# 07 — 工作空间

## 概述

ym 的工作空间支持在一个仓库中管理多个 Java 模块，通过 petgraph DAG 实现拓扑排序和并行构建。

## 配置

根 `package.toml`：

```toml
name = "my-monorepo"
workspaces = ["apps/*", "libs/*"]

[dependencies]
"org.springframework.boot:spring-boot-starter-web" = "3.4.0"
"com.google.guava:guava" = "33.4.0"
```

子模块 `apps/web/package.toml`：

```toml
name = "web"
main = "com.example.web.Main"
workspaceDependencies = ["core", "utils"]

[dependencies]
"org.springframework.boot:spring-boot-starter-web" = ""    # 从根继承版本
"com.google.guava:guava" = "32.0"                          # 显式覆盖版本
"javax.servlet:javax.servlet-api" = { version = "", scope = "provided" }  # 继承版本，覆盖 scope
```

### 版本继承

工作空间中，根 `package.toml` 的 `[dependencies]` 作为版本目录：
- 子模块依赖版本为空字符串 `""` → 从根继承版本
- 子模块有显式版本 → 使用自己的版本
- 对象格式中 `version = ""` 也触发继承，其他字段（`scope`、`exclude`）使用子模块自己的值
- 继承仅取版本字符串：根 `{ version = "1.0", scope = "provided" }` → 子模块继承 `"1.0"`，不继承 scope
- 根的依赖不会自动添加到子模块，子模块必须显式声明坐标
- 子模块使用 `""` 但根中无对应坐标 → 报错（`dependency 'x:y' not found in workspace root`）
- `exclusions` 和 `[resolutions]` 仅在根 `package.toml` 生效——工作空间依赖解析是全局的（`resolve_workspace_deps`），子模块不应定义自己的 exclusions/resolutions

## 目录结构

```
monorepo/
  package.toml              ← workspaces: ["apps/*", "libs/*"]
  .ym/
    cache/maven/            ← 共享依赖缓存
    pom-cache/              ← POM 解析结果缓存
    graph.json              ← 工作空间图缓存
  apps/
    web/
      package.toml
      src/main/java/...
    api/
      package.toml
      src/main/java/...
  libs/
    core/
      package.toml
      src/main/java/...
    utils/
      package.toml
      src/main/java/...
```

## 工作空间图（DAG）

### 构建流程

1. 尝试加载 `GraphCache`（`.ym/graph.json`）
2. 缓存有效 → 从缓存恢复图
3. 缓存无效 → 全新构建：
   a. 从根 `package.toml` 读取 `workspaces` glob 模式
   b. 扫描匹配目录中的 `package.toml` 文件
   c. 验证模块 `name` 唯一性（重复时报错并列出冲突模块路径）
   d. 构建 petgraph::DiGraph（节点 = 模块，边 = workspaceDependencies）
   e. 验证无环（DAG）
   发现环时报错并输出完整环路径，例如：`Cycle detected: A → B → C → A`
   f. 保存缓存

### 缓存（GraphCache）

`.ym/graph.json` 缓存图结构：

```json
{
  "created_at": 1709856000,
  "config_mtimes": {
    "/path/to/apps/web/package.toml": 1709855000,
    "/path/to/libs/core/package.toml": 1709854000
  },
  "packages": [
    { "name": "web", "path": "/path/to/apps/web", "workspace_dependencies": ["core"] }
  ],
  "workspace_patterns": ["apps/*", "libs/*"],
  "workspace_root": "/path/to/monorepo"
}
```

**缓存失效条件：**
- 任何已缓存的 `package.toml` 的 mtime 发生变化
- workspace glob 模式匹配到的文件数与缓存中的包数不同（新包出现或包被删除）

### 核心操作

| 操作 | 说明 |
|------|------|
| `transitive_closure(target)` | 计算目标模块的所有依赖（Kahn 拓扑排序） |
| `topological_levels()` | 按拓扑层级分组（同层可并行） |
| `get_package(name)` | 获取模块信息 |

## 工作空间级 Maven 依赖解析

**不再逐模块解析。** 构建时：

1. 收集所有模块的 `dependencies`（所有 scope）→ 合并去重
2. 调用 `resolve_workspace_deps()` 一次性解析完整传递依赖图
3. 遍历内部缓存依赖图，为每个模块筛选其直接依赖的传递闭包
4. 返回 `HashMap<String, Vec<PathBuf>>`（模块名 → JAR 列表）

## 工作空间命令

### `ym workspace list`

列出所有模块。

### `ym workspace foreach <command>`

在每个模块目录下执行命令（自动 `cd` 到模块路径）。

```bash
ym workspace foreach -- echo "hello"
ym workspace foreach --parallel -- ymc build
ym workspace foreach --parallel -j 4 -- ymc build   # 限制并发数
```

`--parallel` 默认并发数为 CPU 核数。`-j N` 可限制最大并发数，避免资源耗尽。非 `--parallel` 模式按拓扑排序顺序执行。

**错误处理：** 默认 fail-fast——命令在某个模块失败时立即停止，返回非零退出码。`--keep-going` 时继续执行剩余模块，最终汇总报告所有失败的模块并返回非零退出码。

## 已知限制

| 问题 | 影响 | 严重性 |
|------|------|--------|
| foreach 非并行模式已按拓扑排序，并行模式按拓扑层级 | 构建命令可能失序 | 中 |
| 无模块版本管理 | workspace 内模块无独立发布版本 | 低 |

## 优化路线图

### P0 — foreach 拓扑排序

`--parallel` 模式下按拓扑层级执行，保证依赖先于消费者。

### P1 — 模块版本管理

支持 workspace 内模块独立版本号，`publish` 时发布指定模块。
