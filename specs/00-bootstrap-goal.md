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

## 阻塞分析

按"不修复则完全无法工作"排序：

### 🔴 Blocker — 不修复则 Spring Boot 4 项目无法编译

| # | 问题 | 当前代码 | 影响 |
|---|------|---------|------|
| B1 | **BOM import 不支持** | `resolver.rs:426-429` 跳过 `dependencyManagement` | Spring Boot 核心依赖管理全靠 BOM，无版本号的依赖全部解析失败 |
| B2 | **父 POM 深度限制 3 级** | `resolver.rs:343` `depth > 3` | spring-boot-starter-parent → spring-boot-dependencies → spring-framework-bom 已 3 级，再多则丢失 |
| B3 | **每模块独立解析依赖** | `build.rs:272-282` 每包调 `resolve_deps` | 1000 模块 × 数百依赖 = 数十万次重复 POM 解析，不可接受 |
| B4 | **多模块 Gradle 迁移不支持** | `migrate.rs` 仅单项目 | 无法从 Gradle 迁移 1000 模块工程 |

### 🟡 Critical — 不修复则严重影响可用性

| # | 问题 | 当前代码 | 影响 |
|---|------|---------|------|
| C1 | **注解处理器不自动发现** | 需手动配 `compiler.annotationProcessors` | Lombok/MapStruct 等不生效，大量代码编译失败 |
| C2 | **不支持 `<scope>import</scope>`** | `resolver.rs:453-457` 仅检查 test/provided/system | BOM 通过 import scope 引入，不处理则版本丢失 |
| C3 | **版本冲突策略缺失** | 先到先得（BFS 顺序） | 无 Maven nearest-wins 或 Gradle highest-wins 策略 |
| C4 | **属性插值不完整** | `resolver.rs:469` 跳过含 `${` 的版本 | 部分间接属性引用被丢弃 |
| C5 | **IDE 路径 WSL 不兼容** | `idea.rs` 绝对路径 | Windows 开发者无法使用 |

### 🟢 Important — 影响性能但不阻塞功能

| # | 问题 | 当前代码 | 影响 |
|---|------|---------|------|
| I1 | POM 解析串行 BFS | `resolver.rs:150-182` | 首次解析慢 |
| I2 | 工作空间图全量失效 | `cache.rs:34-39` | 每次操作多余扫描 |
| I3 | dev 模式全量重编译 | `dev.rs:247` | 大项目热更新慢 |
| I4 | ABI 哈希未真正实现 | `incremental.rs` | 级联重编译范围过大 |

## 实施阶段

### Phase 1 — 依赖解析可用（B1 + B2 + C1 + C2 + C3 + C4）

**目标：** `ym install` 能正确解析 Spring Boot 4 项目的全部依赖。

#### 1.1 BOM import 支持 (B1 + C2)

**文件：** `src/workspace/resolver.rs`

当前 `parse_pom_dependencies_with_props()` 收集 `<dependencyManagement>` 中的版本做 managed versions，但跳过了 `<scope>import</scope><type>pom</type>` 的 BOM 导入。

**改动：**

在 `collect_managed_versions()` 中，当遇到 `scope=import` + `type=pom` 时：
1. 下载该 BOM POM 文件
2. 递归解析其 `<dependencyManagement>`
3. 合并 managed versions（外层优先，内层不覆盖）

```rust
// 伪代码
fn collect_managed_versions(doc, properties, client, cache_dir, repos, depth) -> HashMap {
    let mut managed = HashMap::new();
    for dep in dependencyManagement.dependencies {
        if dep.scope == "import" && dep.type == "pom" {
            // 下载 BOM POM
            let bom_pom = download_pom(dep.coord);
            let bom_doc = parse(bom_pom);
            // 递归收集（depth 限制防循环）
            let bom_managed = collect_managed_versions(bom_doc, ..., depth + 1);
            // 合并：当前层不覆盖
            for (k, v) in bom_managed {
                managed.entry(k).or_insert(v);
            }
        } else {
            managed.insert(format!("{}:{}", g, a), version);
        }
    }
    managed
}
```

**需要传递 `client`/`cache_dir`/`repos` 到 `collect_managed_versions`**（当前是纯解析函数，需改签名）。

#### 1.2 移除父 POM 深度限制 (B2)

**文件：** `src/workspace/resolver.rs:343`

```rust
// 当前
if depth > 3 { return Ok(()); }

// 改为：循环检测 + 合理上限
if depth > 20 { return Ok(()); }  // 安全上限
// + visited set 防循环
```

#### 1.3 版本冲突解决策略 (C3)

**文件：** `src/workspace/resolver.rs`

当前 BFS 先到先得。改为 **nearest-wins**（Maven 策略）：
- 记录每个 artifact 的解析深度
- 同一 `groupId:artifactId` 出现多个版本时，取深度最浅的
- `resolutions` 中的固定版本始终优先

#### 1.4 属性插值增强 (C4)

**文件：** `src/workspace/resolver.rs`

当前 `resolve_properties()` 单次替换。改为循环替换直到无 `${` 或达到上限：

```rust
fn resolve_properties(value: &str, props: &HashMap) -> String {
    let mut result = value.to_string();
    for _ in 0..10 {  // 最多 10 轮替换
        let prev = result.clone();
        // 替换所有 ${key}
        result = regex_replace(result, props);
        if result == prev { break; }
    }
    result
}
```

支持 `${project.groupId}`、`${project.version}`、`${parent.version}` 等内置属性。

#### 1.5 注解处理器自动发现 (C1)

**文件：** `src/compiler/javac.rs`

扫描 classpath JAR 中的 `META-INF/services/javax.annotation.processing.Processor`：

```rust
fn discover_annotation_processors(classpath: &[PathBuf]) -> Vec<PathBuf> {
    classpath.iter()
        .filter(|jar| {
            // 打开 JAR(zip)，检查是否含 META-INF/services/javax.annotation.processing.Processor
            zip::ZipArchive::new(File::open(jar))
                .map(|z| z.by_name("META-INF/services/javax.annotation.processing.Processor").is_ok())
                .unwrap_or(false)
        })
        .cloned()
        .collect()
}
```

自动添加到 `-processorpath`。

### Phase 2 — 工作空间性能 (B3 + I1 + I2)

**目标：** 1000 模块的 `ymc build` < 5 分钟。

#### 2.1 工作空间级依赖合并 (B3)

**文件：** `src/commands/build.rs`, `src/workspace/resolver.rs`

新增函数：

```rust
/// 一次性解析工作空间所有模块的 Maven 依赖
pub fn resolve_workspace_deps(
    ws: &WorkspaceGraph,
    cache_dir: &Path,
    lock: &mut LockFile,
    repos: &[String],
    exclusions: &[String],
) -> Result<HashMap<String, Vec<PathBuf>>> {
    // 1. 收集所有模块的 dependencies + devDependencies
    let mut all_deps = BTreeMap::new();
    for pkg in ws.all_packages() {
        for (coord, version) in pkg.config.dependencies.iter().flatten() {
            all_deps.entry(coord.clone()).or_insert(version.clone());
        }
    }

    // 2. 一次性解析
    let all_jars = resolve_and_download_full(&all_deps, cache_dir, lock, repos, exclusions)?;

    // 3. 按模块分发：每个模块取其声明的依赖子集 + 传递依赖
    let mut per_module = HashMap::new();
    for pkg in ws.all_packages() {
        let module_jars = filter_jars_for_module(&pkg.config, &all_jars, lock);
        per_module.insert(pkg.name.clone(), module_jars);
    }

    Ok(per_module)
}
```

#### 2.2 POM 解析缓存 + 并行化 (I1)

- POM 解析结果（依赖列表）缓存到 `.ym/pom-cache/`
- BFS 改为分层：同一层级的 POM 并行下载和解析

#### 2.3 增量图更新 (I2)

仅重新加载 mtime 变更的 `package.json` 节点，保持其余不变。

### Phase 3 — 多模块迁移 (B4)

**目标：** `ym convert` 能从 Gradle 多模块项目一键迁移。

#### 3.1 Gradle 多模块迁移

**文件：** `src/commands/migrate.rs`

```
1. 解析 settings.gradle(.kts) 的 include 语句
2. 生成根 package.json 的 workspaces 字段
3. 遍历每个子模块的 build.gradle(.kts)：
   a. 提取 dependencies（implementation, api, testImplementation）
   b. 检测 inter-module 依赖 → workspaceDependencies
   c. 提取 java sourceCompatibility
   d. 生成子模块 package.json
4. 运行 ym install 验证
```

#### 3.2 Maven 多模块迁移

解析根 `pom.xml` 的 `<modules>`，递归生成 workspace 结构。

### Phase 4 — IDE 和开发体验 (C5 + I3)

#### 4.1 IDE 路径自适应 (C5)

检测 WSL 环境（`/mnt/` 前缀），自动转换为 Windows 路径。

#### 4.2 工作空间 dev 细粒度增量 (I3)

根据变更文件的模块归属，仅重编译该模块及下游依赖。

## 里程碑

| 阶段 | 目标 | 预计改动量 |
|------|------|-----------|
| Phase 1 | Spring Boot 依赖解析正确 | resolver.rs ~300 行改动 |
| Phase 2 | 1000 模块性能达标 | resolver.rs + build.rs ~200 行 |
| Phase 3 | Gradle 多模块迁移 | migrate.rs ~400 行新增 |
| Phase 4 | 开发体验完善 | idea.rs + dev.rs ~150 行 |

## 验证项目

建议用以下项目验证：
1. **小型 Spring Boot**：单模块，spring-boot-starter-web，验证 BOM 解析
2. **中型多模块**：~50 模块，验证 workspace 编译
3. **大型工程**：1000+ 模块，验证性能目标
