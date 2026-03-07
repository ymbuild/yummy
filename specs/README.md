# YM 功能规格文档

## 模块总览

| # | 模块 | Spec 文件 | 当前状态 | 核心文件 |
|---|------|----------|---------|---------|
| 0 | [自举目标](00-bootstrap-goal.md) | `00-bootstrap-goal.md` | ⚠️ Phase 1 完成，Phase 2 进行中 | — |
| 1 | [配置与 Schema](01-config.md) | `01-config.md` | ✅ 已实现 | `config/schema.rs`, `config/mod.rs` |
| 2 | [依赖解析](02-resolver.md) | `02-resolver.md` | ✅ 已实现 | `workspace/resolver.rs` |
| 3 | [包管理命令](03-package-management.md) | `03-package-management.md` | ✅ 已实现 | `commands/{install,uninstall,upgrade,...}.rs` |
| 4 | [编译管线](04-compiler.md) | `04-compiler.md` | ✅ 已实现 | `compiler/{mod,incremental,javac}.rs`, `commands/build.rs` |
| 5 | [运行与开发模式](05-runtime.md) | `05-runtime.md` | ✅ 已实现 | `commands/{run,dev}.rs`, `hotreload/`, `watcher/` |
| 6 | [测试](06-testing.md) | `06-testing.md` | ✅ 已实现 | `commands/test_cmd.rs` |
| 7 | [工作空间](07-workspace.md) | `07-workspace.md` | ✅ 已实现 | `workspace/{graph,cache}.rs` |
| 8 | [JDK 管理](08-jdk.md) | `08-jdk.md` | ✅ 已实现 | `jdk_manager.rs`, `jvm.rs` |
| 9 | [IDE 集成](09-ide.md) | `09-ide.md` | ✅ 已实现 | `commands/idea.rs` |
| 10 | [发布与分发](10-publish.md) | `10-publish.md` | ✅ 基本完成 | `commands/{publish,login}.rs` |
| 11 | [诊断与工具](11-diagnostics.md) | `11-diagnostics.md` | ✅ 已实现 | `commands/{doctor,info,tree,clean}.rs` |
| 12 | [迁移](12-migration.md) | `12-migration.md` | ✅ 已实现 | `commands/migrate.rs` |
| 13 | [脚本与生命周期](13-scripts.md) | `13-scripts.md` | ✅ 已实现 | `scripts.rs`, `commands/script.rs` |
| 14 | [CLI 架构](14-cli.md) | `14-cli.md` | ✅ 已实现 | `main.rs` |
| 15 | [性能目标与基准](15-performance.md) | `15-performance.md` | 🔲 待建立基准 | — |
| 16 | [安全](16-security.md) | `16-security.md` | ⚠️ 部分实现 | — |
| 17 | [Daemon 模式](17-daemon.md) | `17-daemon.md` | 🔲 待开发 | — |
| 18 | [项目初始化](18-init.md) | `18-init.md` | ✅ 已实现 | `commands/init.rs`, `jdk_manager.rs` |

## 状态说明

- ✅ **已实现** — 功能完整可用
- ⚠️ **部分实现** — 核心功能可用，有已知限制
- 🔲 **待开发** — 尚未实现

## 实施进度

### Phase 1 — 依赖解析可用 ✅

所有 Blocker (B1-B4) + Critical (C1-C5) + Improvement (I1-I4) 已完成，73 个单元测试通过。

详见 [00-bootstrap-goal.md](00-bootstrap-goal.md)。

### Phase 2 — 真实项目验证 🔲

目标：用真实 Spring Boot 项目端到端验证，修复实战中暴露的问题。

关键任务：
- [ ] 建立基准测试项目（小/中/大）
- [ ] SNAPSHOT / Classifier 支持
- [ ] 测试报告（JUnit XML）
- [ ] Maven Central 完整发布流程

### Phase 3 — 生态工具完善 🔲

- [ ] IDEA 插件
- [ ] Daemon 模式
- [ ] 编译缓存共享
- [ ] SBOM 生成

## 架构原则

1. **双二进制架构**：`ym`（包管理器）+ `ymc`（编译器/运行时），同一二进制按名称分发
2. **声明式配置**：`package.toml`（TOML），支持注释，精确版本，无锁文件，统一 scope 体系（compile/runtime/provided/test）
3. **Maven 生态兼容**：直接使用 Maven Central，复用 `.jar`/`.pom` 格式
4. **渐进式采用**：支持从 Maven/Gradle 迁移，`source_dir()` 自动检测目录结构
5. **原生性能**：Rust 编写，~5ms 启动，rayon 并行编译/下载
6. **安全优先**：SHA-256 校验、漏洞审计、凭证隔离、无隐式代码执行
