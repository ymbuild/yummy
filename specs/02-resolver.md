# 02 — 依赖解析

## 概述

ym 的依赖解析器负责将 `package.json` 中的 Maven 坐标解析为完整的传递依赖图，下载 JAR 到本地缓存，并通过锁文件保证可复现构建。

## 坐标格式

```
groupId:artifactId  →  "com.fasterxml.jackson.core:jackson-databind": "2.19.0"
```

- 版本前缀 `^` 和 `~` 会被自动剥离（当前不做语义化范围解析，直接使用精确版本）
- 锁文件记录实际解析版本 + SHA-256

## 解析流程

### 快速路径（锁文件命中）

```
package.json 中所有依赖都在 package-lock.json 中
  && 所有 JAR 文件在本地缓存中存在
  && SHA-256 校验通过
  → 直接返回 JAR 路径列表，零网络请求
```

### 慢速路径（需要网络）

```
1. 收集 package.json 中的直接依赖
2. 分层并行 BFS 遍历：
   a. 获取 POM 文件（内存缓存 → 磁盘缓存 → 网络下载）
   b. 解析 <parent>（最多 20 级深度 + visited set 循环检测）
   c. 收集 <properties> 和 <dependencyManagement>
   d. BOM import：<scope>import</scope> + <type>pom</type> 递归解析
   e. 属性插值 ${property.name}（循环替换最多 10 轮，支持嵌套）
   f. 解析 <dependencies>，跳过 scope=test/provided/system 和 optional
   g. 版本冲突解决：nearest-wins（Maven 策略，记录解析深度）
   h. 同一深度的 POM 通过 rayon par_iter 并行获取和解析
3. 应用 exclusions 过滤
4. 应用 resolutions 版本覆盖
5. 并行下载所有 JAR（rayon par_iter）
6. SHA-256 校验
7. 写入 package-lock.json
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

### 仓库顺序

1. `registries` 中配置的自定义仓库（按配置顺序）
2. Maven Central: `https://repo1.maven.org/maven2`

支持 `.ym/credentials.json` 中的 Basic Auth 凭证。

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
    lock: &mut LockFile,
    repos: &[String],
    exclusions: &[String],
) -> Result<HashMap<String, Vec<PathBuf>>>
```

1. 收集所有模块的 `dependencies` + `devDependencies` → 合并去重
2. 一次性解析完整传递依赖图
3. 按模块分发：遍历 lock file 依赖图，为每个模块筛选其直接依赖的传递闭包

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

## 锁文件格式 (package-lock.json)

```json
{
  "version": 1,
  "dependencies": {
    "com.fasterxml.jackson.core:jackson-databind:2.19.0": {
      "sha256": "abc123...",
      "dependencies": [
        "com.fasterxml.jackson.core:jackson-core:2.19.0",
        "com.fasterxml.jackson.core:jackson-annotations:2.19.0"
      ]
    }
  }
}
```

## 已知限制

| 问题 | 影响 | 严重性 |
|------|------|--------|
| 不支持 version range | `[1.0,2.0)` 等 Maven 范围不生效 | 中 |
| 不支持 classifier | `natives-linux` 等分类器 JAR 无法获取 | 中 |
| 无 SNAPSHOT 支持 | 开发阶段依赖 | 中 |
| 无代理支持 | 企业内网无法使用 | 中 |

## 优化路线图

### P0 — Version Range 支持

解析 Maven 版本范围语法 `[1.0,2.0)`，在候选版本中选择最高匹配。

### P1 — Classifier 支持

在 `MavenCoord` 中添加 `classifier` 字段，支持 `natives-linux` 等分类器 JAR。

### P2 — SNAPSHOT 支持

支持 `-SNAPSHOT` 版本，定期检查远程更新（`maven-metadata.xml` 的 `lastUpdated`）。

### P3 — HTTP 代理支持

读取 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量，配置 reqwest client。
