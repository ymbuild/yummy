# 02 — 依赖解析

## 概述

ym 的依赖解析器负责将 `package.toml` 中的 Maven 坐标解析为完整的传递依赖图，下载 JAR 到本地缓存。

## 坐标格式

```
groupId:artifactId  →  "com.fasterxml.jackson.core:jackson-databind": "2.19.0"
```

- 仅支持精确版本号
- 解析缓存记录实际解析版本 + SHA-256

## Scope 与解析的关系

用户在 `package.toml` 中声明的 `scope`（compile/runtime/provided/test）**不影响依赖解析过程**。所有 scope 的依赖都会参与传递依赖解析和 JAR 下载。scope 仅在后续阶段（classpath 构建、fat JAR 打包、POM 生成）生效。

POM 文件中的 `<scope>` 是不同的概念——BFS 遍历时跳过 POM 中 `scope=test/provided/system` 的传递依赖（这是 Maven 标准行为）。

## 解析流程

### 快速路径（缓存命中）

```
package.toml 中所有依赖的 JAR 文件在本地缓存中存在
  && .ym/resolved.json 中的依赖列表与 package.toml 一致
  && SHA-256 校验通过
  → 直接返回 JAR 路径列表，零网络请求
```

### 慢速路径（需要网络）

```
1. 收集 package.toml 中的直接依赖
2. 分层并行 BFS 遍历：
   a. 获取 POM 文件（内存缓存 → 磁盘缓存 → 网络下载）
   b. 解析 <parent>（最多 20 级深度 + visited set 循环检测）
   c. 收集 <properties> 和 <dependencyManagement>
   d. BOM import：<scope>import</scope> + <type>pom</type> 递归解析
   e. 属性插值 ${property.name}（循环替换最多 10 轮，支持嵌套）
   f. 解析 <dependencies>，跳过 scope=test/provided/system 和 optional=true；scope=runtime 的依赖正常包含（参与运行时 classpath）
   g. 版本冲突解决：nearest-wins（Maven 策略，记录解析深度）
      同一深度出现同一 artifact 的不同版本时，以 BFS 遍历中先遇到的为准（与 Maven 行为一致）
   h. 同一深度的 POM 通过 rayon par_iter 并行获取和解析
3. 应用 exclusions 过滤（全局 `exclusions` 数组 + per-dependency `exclude` 字段）
4. 应用 resolutions 版本覆盖（resolutions 永远优先于任何显式版本，包括直接依赖和子模块声明）
5. 并行下载所有 JAR（rayon par_iter）
6. SHA-256 校验
7. 写入 .ym/resolved.json（内部缓存）
```

### BOM Import 解析

当 `<dependencyManagement>` 中的依赖声明 `<scope>import</scope>` + `<type>pom</type>` 时：

1. 下载该 BOM 的 POM 文件
2. 递归解析其 `<dependencyManagement>` 中的 managed versions
3. 合并规则：外层优先，内层不覆盖已有版本
4. 深度限制：最多 10 层 BOM 嵌套

### 版本冲突解决

采用 Maven **nearest-wins** 策略：

- BFS 遍历时记录每个 artifact 的首次出现深度
- 同一 `groupId:artifactId` 出现多个版本时，取深度最浅的
- `resolutions` 中的固定版本始终优先（覆盖 nearest-wins）

### 仓库顺序与 Scope 路由

`registries` 中的仓库 value 支持两种格式：
- **字符串：** 纯 URL，适用于所有依赖
- **对象：** `{url = "...", scope = "com.mycompany.*"}`，仅匹配 `scope` 前缀的 groupId 才查此仓库

**解析策略：**
1. 如果依赖的 groupId 匹配某个仓库的 `scope` → 只从该仓库拉取（不 fallback 到其他仓库）
2. 无 scope 匹配的依赖 → 按配置顺序查无 scope 的仓库，最后查 Maven Central
3. Maven Central（`https://repo1.maven.org/maven2`）始终作为兜底（除非依赖已被 scope 路由）

对于每个依赖，按上述规则逐个尝试。第一个仓库返回 404 后尝试下一个，直到找到或全部失败。不做并行查询（避免向所有仓库泄露依赖列表）。

### 凭证认证

私有仓库下载 POM/JAR 时使用 `~/.ym/credentials.json` 中的 Basic Auth 凭证。查找规则与发布时一致（详见 [10-publish.md](10-publish.md)）：

1. 精确匹配 registry URL
2. 忽略尾部斜杠后重试
3. 🔲 待实现：环境变量覆盖（优先）：`YM_REGISTRY_USERNAME` + `YM_REGISTRY_PASSWORD`，或 `YM_REGISTRY_TOKEN`（Bearer）

## POM 缓存

### 双层缓存架构

| 层级 | 存储 | 生命周期 | 用途 |
|------|------|---------|------|
| 内存缓存 | `PomCache`（`Mutex<HashMap>`） | 单次解析过程 | 避免同一 BFS 中重复解析 |
| 磁盘缓存 | `.ym/pom-cache/{group}/{artifact}/{version}.pom` | 跨运行持久化 | 避免重复网络请求 |

### PomCache 接口

```rust
pub struct PomCache {
    cache: Mutex<HashMap<String, Vec<MavenCoord>>>,
}

impl PomCache {
    pub fn get(&self, key: &str) -> Option<Vec<MavenCoord>>;
    pub fn insert(&self, key: String, deps: Vec<MavenCoord>);
}
```

## 工作空间级依赖合并

### 问题

1000 模块 × 数百依赖 = 数十万次重复 POM 解析。

### 解决方案

```rust
pub fn resolve_workspace_deps(
    ws: &WorkspaceGraph,
    cache_dir: &Path,
    resolved: &mut ResolvedCache,
    repos: &[String],
    exclusions: &[String],
) -> Result<HashMap<String, Vec<PathBuf>>>
```

1. 收集所有模块的 `dependencies`（所有 scope）→ 合并去重
2. 一次性解析完整传递依赖图
3. 按模块分发：遍历解析缓存依赖图，为每个模块筛选其直接依赖的传递闭包

## 缓存结构

```
.ym/cache/maven/
  com.fasterxml.jackson.core/
    jackson-databind/
      2.19.0/
        jackson-databind-2.19.0.jar
        jackson-databind-2.19.0.pom

.ym/pom-cache/
  com.fasterxml.jackson.core/
    jackson-databind/
      2.19.0.pom
```

## 内部缓存 (.ym/resolved.json)

解析结果缓存在 `.ym/resolved.json`，用户不需要直接操作此文件：
- 记录完整传递依赖树 + SHA-256
- `ym install`（无参数）时自动判断缓存是否有效
- 缓存失效时自动重新解析

**缓存失效条件（任一变化即失效）：**
- `[dependencies]` 变更（增删改依赖）
- `[resolutions]` 变更（版本覆盖改变）
- `exclusions` 变更（全局排除改变）
- `[registries]` 变更（仓库 URL/顺序/scope 改变）

## 已知限制

| 问题 | 影响 | 严重性 |
|------|------|--------|
| 不支持 classifier | `natives-linux` 等分类器 JAR 无法获取 | 中 |
| 无 SNAPSHOT 支持 | 开发阶段依赖 | 中 |
| 无代理支持 | 企业内网无法使用 | 中 |
| 下载无总超时限制 | 大文件下载可能无限等待 | 低 |

### 下载失败策略

JAR/POM 下载失败时：
1. 重试最多 3 次，指数退避（1s → 2s → 4s）
2. 所有重试失败 → 报错并列出失败的坐标
3. 部分依赖失败不影响已成功下载的依赖（但整体解析标记为失败）

## 优化路线图

### P1 — Classifier 支持

在 `MavenCoord` 中添加 `classifier` 字段，支持 `natives-linux` 等分类器 JAR。

### P2 — SNAPSHOT 支持

支持 `-SNAPSHOT` 版本，定期检查远程更新（`maven-metadata.xml` 的 `lastUpdated`）。

### P3 — HTTP 代理支持

读取 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量，配置 reqwest client。
