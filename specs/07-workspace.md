# 07 — 工作空间

## 概述

ym 的工作空间支持在一个仓库中管理多个 Java 模块，通过 petgraph DAG 实现拓扑排序和并行构建。

## 配置

根 `package.json`：

```json
{
  "name": "my-monorepo",
  "workspaces": ["apps/*", "libs/*"]
}
```

子模块 `apps/web/package.json`：

```json
{
  "name": "web",
  "main": "com.example.web.Main",
  "workspaceDependencies": ["core", "utils"],
  "dependencies": {
    "org.springframework.boot:spring-boot-starter-web": "3.4.0"
  }
}
```

## 目录结构

```
monorepo/
  package.json              ← workspaces: ["apps/*", "libs/*"]
  package-lock.json
  .ym/
    cache/maven/            ← 共享依赖缓存
    pom-cache/              ← POM 解析结果缓存
    graph.json              ← 工作空间图缓存
  apps/
    web/
      package.json
      src/main/java/...
    api/
      package.json
      src/main/java/...
  libs/
    core/
      package.json
      src/main/java/...
    utils/
      package.json
      src/main/java/...
```

## 工作空间图（DAG）

### 构建流程

1. 尝试加载 `GraphCache`（`.ym/graph.json`）
2. 缓存有效 → 从缓存恢复图
3. 缓存无效 → 全新构建：
   a. 从根 `package.json` 读取 `workspaces` glob 模式
   b. 扫描匹配目录中的 `package.json` 文件
   c. 构建 petgraph::DiGraph（节点 = 模块，边 = workspaceDependencies）
   d. 验证无环（DAG）
   e. 保存缓存

### 缓存（GraphCache）

`.ym/graph.json` 缓存图结构：

```json
{
  "created_at": 1709856000,
  "config_mtimes": {
    "/path/to/apps/web/package.json": 1709855000,
    "/path/to/libs/core/package.json": 1709854000
  },
  "packages": [
    { "name": "web", "path": "/path/to/apps/web", "workspace_dependencies": ["core"] }
  ],
  "workspace_patterns": ["apps/*", "libs/*"],
  "workspace_root": "/path/to/monorepo"
}
```

**缓存失效条件：**
- 任何已缓存的 `package.json` 的 mtime 发生变化
- workspace glob 模式匹配到的文件数与缓存中的包数不同（新包出现或包被删除）

### 核心操作

| 操作 | 说明 |
|------|------|
| `transitive_closure(target)` | 计算目标模块的所有依赖（Kahn 拓扑排序） |
| `topological_levels()` | 按拓扑层级分组（同层可并行） |
| `get_package(name)` | 获取模块信息 |

## 工作空间级 Maven 依赖解析

**不再逐模块解析。** 构建时：

1. 收集所有模块的 `dependencies` + `devDependencies` → 合并去重
2. 调用 `resolve_workspace_deps()` 一次性解析完整传递依赖图
3. 遍历 lock file 依赖图，为每个模块筛选其直接依赖的传递闭包
4. 返回 `HashMap<String, Vec<PathBuf>>`（模块名 → JAR 列表）

## 工作空间命令

### `ym workspace list`

列出所有模块。

### `ym workspace graph`

显示模块依赖关系图。

### `ym workspace build [target]`

编译指定模块（含依赖）或所有模块。

- 拓扑分层 → 同层 rayon 并行编译
- 每层完成后 classpath 累加

### `ym workspace run <target>`

编译并运行指定模块。

### `ym workspace test <target>`

编译并测试指定模块。

### `ym workspace clean`

清理所有模块的 `out/` 目录。

### `ym workspace foreach <command>`

在每个模块中执行命令。

```bash
ym workspace foreach -- echo "hello"
ym workspace foreach --parallel -- ymc build
```

### `ym workspace changed`

列出自上次 Git commit 以来有变更的模块。

### `ym workspace impact <target>`

显示修改指定模块后受影响的下游模块。

### `ym workspace info`

显示工作空间概要信息。

### `ym workspace focus <target>`

显示指定模块的完整依赖详情。

## `ymc create` — 创建子模块

```bash
ymc create my-service                    # 创建 app 模块 → apps/my-service/
ymc create my-lib -t lib                 # 创建 lib 模块 → libs/my-lib/
ymc create my-service --deps             # 附带模板依赖
```

- 自动生成 `package.json`，含 `package` 和全限定 `main`
- 创建 `src/main/java/{pkg}/`、`src/main/resources/`、`src/test/java/`
- app 模板生成 `Main.java`，lib 模板生成 `{ClassName}.java` + 测试

## 已知限制

| 问题 | 影响 | 严重性 |
|------|------|--------|
| foreach 无拓扑顺序保证 | 构建命令可能失序 | 中 |
| 无模块版本管理 | workspace 内模块无独立发布版本 | 低 |
| changed 仅基于 Git status | 不考虑传递影响 | 低 |

## 优化路线图

### P0 — foreach 拓扑排序

`--parallel` 模式下按拓扑层级执行，保证依赖先于消费者。

### P1 — 受影响模块检测

`changed` 命令结合 `impact` 分析，输出真正需要重编译/重测的模块集。

### P2 — 模块版本管理

支持 workspace 内模块独立版本号，`publish` 时发布指定模块。
