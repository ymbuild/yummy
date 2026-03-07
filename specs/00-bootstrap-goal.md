# 00 — 自举目标：编译 Spring Boot 4 大型工程 (1000+ 模块)

## 目标

ym 能完整编译一个 1000+ 模块的 Spring Boot 4 项目，速度明显优于 Gradle，且开发者无需学习新配置语法。

## 验收标准

```
1. ym convert                            # 从 Gradle 多模块项目迁移
2. ym install                            # 解析全部依赖 < 30 秒（锁文件命中 < 3 秒）
3. ymc build                             # 全量编译 1000 模块 < 5 分钟
4. ymc build（增量，改 1 文件）           # < 3 秒
5. ymc test <module>                     # 编译+测试单模块 < 10 秒
6. ymc dev <module>                      # 热重载开发 < 200ms 响应
7. ymc idea                              # IDEA 正确识别所有模块和依赖
```

对比 Gradle：配置加载 20+ 分钟，全量编译 15+ 分钟。

## Phase 1 已完成项

> 以下 Blockers 和 Criticals 已在 2026-03 实现并通过 73 个单元测试验证。

### ✅ Blockers（已修复）

| # | 问题 | 修复内容 | 代码位置 |
|---|------|---------|---------|
| B1 | BOM import 不支持 | `collect_managed_versions()` 递归解析 `scope=import` + `type=pom` 的 BOM | `resolver.rs` |
| B2 | 父 POM 深度限制 3 级 | 改为 20 级上限 + visited set 循环检测 | `resolver.rs` |
| B3 | 每模块独立解析依赖 | 新增 `resolve_workspace_deps()` 一次性合并解析，按模块分发 JAR | `resolver.rs` + `build.rs` |
| B4 | 多模块 Gradle 迁移不支持 | 解析 `settings.gradle(.kts)`，检测 `project()` 依赖 → `workspaceDependencies` | `migrate.rs` |

### ✅ Criticals（已修复）

| # | 问题 | 修复内容 | 代码位置 |
|---|------|---------|---------|
| C1 | 注解处理器不自动发现 | 扫描 classpath JAR 的 `META-INF/services/javax.annotation.processing.Processor` | `build.rs` |
| C2 | 不支持 `<scope>import</scope>` | 在 `collect_managed_versions()` 中处理 import scope BOM | `resolver.rs` |
| C3 | 版本冲突策略缺失 | 实现 nearest-wins（Maven 策略），记录解析深度 | `resolver.rs` |
| C4 | 属性插值不完整 | 循环替换（最多 10 轮），支持嵌套属性引用 | `resolver.rs` |
| C5 | IDE 路径 WSL 不兼容 | 检测 WSL 环境，`/mnt/c/...` → `C:/...` 自动转换 | `idea.rs` |

### ✅ Improvements（已修复）

| # | 问题 | 修复内容 | 代码位置 |
|---|------|---------|---------|
| I1 | POM 解析串行 BFS | 分层并行：同一深度的 POM 用 `rayon par_iter` 并行解析 | `resolver.rs` |
| I2 | 工作空间图全量失效 | `GraphCache` 追踪 workspace glob 模式，按需重新加载 | `cache.rs` + `graph.rs` |
| I3 | dev 模式全量重编译 | 按文件归属识别变更模块，拓扑序传播重编译 | `dev.rs` |
| I4 | ABI 哈希未真正实现 | 解析 `.class` 文件格式，排除 Code 属性和 private 成员 | `incremental.rs` |

### 新增基础设施

| 功能 | 说明 | 代码位置 |
|------|------|---------|
| POM 缓存 | 双层缓存：内存 `PomCache`（`Mutex<HashMap>`）+ 磁盘 `.ym/pom-cache/` | `resolver.rs` |
| Maven 多模块迁移 | 解析根 `pom.xml` 的 `<modules>`，检测模块间依赖 | `migrate.rs` |
| Kotlin DSL 支持 | 迁移时支持 `build.gradle.kts` 和 `settings.gradle.kts` 语法 | `migrate.rs` |

---

## Phase 2 — 真实项目验证与生产就绪

> Phase 1 解决了代码层面的功能缺失。Phase 2 目标：用真实 Spring Boot 项目端到端验证，修复实战中暴露的问题。

### 🔴 Blocker — 实战验证

| # | 问题 | 当前状态 | 目标 |
|---|------|---------|------|
| P2-B1 | **无端到端测试** | 只有单元测试，未在真实项目上跑过 | 建立 3 个基准项目（小/中/大），CI 自动验证 |
| P2-B2 | **Version Range 不支持** | `[1.0,2.0)` 等 Maven 范围语法被忽略 | 解析 Maven 版本范围，选择最高匹配版本 |
| P2-B3 | **SNAPSHOT 不支持** | 开发依赖无法使用 | 支持 `-SNAPSHOT` 版本，检查远程更新策略 |
| P2-B4 | **Classifier 不支持** | `natives-linux` 等分类器 JAR 无法获取 | 在 `MavenCoord` 中支持 classifier 字段 |

### 🟡 Critical — 生产可用性

| # | 问题 | 说明 |
|---|------|------|
| P2-C1 | **ECJ 集成** | 完成 ECJ 长驻 JVM 模式，利用内存缓存加速增量编译 |
| P2-C2 | **测试报告** | 生成 JUnit XML 报告（CI 集成），可选 HTML |
| P2-C3 | **并行测试执行** | 利用 JUnit 5 parallel execution 配置 |
| P2-C4 | **Gradle Version Catalog** | 解析 `gradle/libs.versions.toml` 提取依赖声明 |
| P2-C5 | **Maven Central 发布** | GPG 签名 + Javadoc JAR + Sources JAR + Staging |
| P2-C6 | **IDEA 注解处理器配置** | 生成 `.idea/compiler.xml` 的 annotationProcessing 节点 |

### 🟢 Improvement — 性能与体验

| # | 问题 | 说明 |
|---|------|------|
| P2-I1 | **编译缓存共享** | 团队/CI 间共享编译缓存（基于输入哈希匹配，类似 Gradle Build Cache） |
| P2-I2 | **Daemon 模式** | 长驻后台进程缓存 JIT 编译结果和依赖图，减少冷启动 |
| P2-I3 | **受影响测试检测** | 基于变更源码文件反向查找依赖测试，仅运行受影响测试 |
| P2-I4 | **代理支持** | HTTP_PROXY / HTTPS_PROXY 环境变量 |
| P2-I5 | **`.java-version` 文件** | 项目级 JDK 版本声明，类似 `.nvmrc` |

## 基准项目

| 规模 | 模块数 | 依赖数 | 验证重点 |
|------|--------|--------|---------|
| 小型 | 1 | ~20 | BOM 解析、注解处理器、基本编译 |
| 中型 | ~50 | ~200 | 工作空间编译、模块间依赖、dev 模式 |
| 大型 | 1000+ | ~500 | 性能目标、并行编译、增量重编译范围 |

## 里程碑

| 阶段 | 目标 | 状态 |
|------|------|------|
| Phase 1 | Spring Boot 依赖解析正确 + 性能优化 | ✅ 完成 |
| Phase 2 | 真实项目端到端验证 + 生产就绪 | 🔲 进行中 |
| Phase 3 | 生态工具完善（IDEA 插件、CI 集成） | 🔲 待开始 |
