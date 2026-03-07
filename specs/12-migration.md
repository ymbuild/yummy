# 12 — 迁移

## 概述

`ym convert` 自动将 Maven 或 Gradle 项目转为 ym 格式，生成 `package.toml` 文件（TOML 格式）。支持单项目和多模块项目。

## 命令

```bash
ym convert                               # 自动检测 pom.xml 或 build.gradle
```

## 检测逻辑

1. 当前目录有 `settings.gradle` 或 `settings.gradle.kts` → Gradle 多模块迁移
2. 当前目录有 `pom.xml` 且含 `<modules>` → Maven 多模块迁移
3. 当前目录有 `pom.xml` → Maven 单项目迁移
4. 当前目录有 `build.gradle` 或 `build.gradle.kts` → Gradle 单项目迁移
5. 都没有 → 报错
6. 已有 `package.toml` → 拒绝覆盖
7. 迁移完成后保留原始构建文件（`pom.xml`、`build.gradle` 等），不删除不修改

## Maven 迁移

### 单项目

解析 `pom.xml`：

| Maven 字段 | package.toml 字段 |
|------------|-------------------|
| `<groupId>` + `<artifactId>` | `name` |
| `<version>` | `version` |
| `<description>` | `description` |
| `<properties><maven.compiler.source>` | `target` |
| `<dependencies>` (无 scope 或 compile) | `dependencies` |
| `<dependencies>` (scope=test) | `dependencies`（`scope = "test"`） |
| `<dependencies>` (scope=provided) | `dependencies`（`scope = "provided"`） |
| `<dependencies>` (scope=runtime) | `dependencies`（`scope = "runtime"`） |
| `<dependencies>` (scope=system) | **跳过并警告**（system scope 依赖本地路径 JAR，需手动处理） |
| `<dependencies>` (optional=true) | **跳过并提示**（可选依赖由消费者按需手动添加） |

### 多模块

1. 解析根 `pom.xml` 的 `<modules>`
2. 生成根 `package.toml`（`private = true`，`workspaces = ["module-a/*", "module-b/*"]`）
3. 为每个子模块生成 `package.toml`：
   - 检测模块间依赖：子模块的 `<dependency>` 如果 `artifactId` 匹配另一个子模块名 → 加入 `workspaceDependencies`
   - 其余依赖正常映射

## Gradle 迁移

### 单项目

解析 `build.gradle` / `build.gradle.kts`：

| Gradle 配置 | package.toml 字段 |
|-------------|-------------------|
| `group` + `archivesBaseName` | `name` |
| `version` | `version` |
| `sourceCompatibility` | `target` |
| `implementation`, `api` | `dependencies` |
| `testImplementation` | `dependencies`（`scope = "test"`） |

**支持的依赖格式：**
- Groovy: `implementation 'group:artifact:version'`
- Kotlin DSL: `implementation("group:artifact:version")`
- 带前导空格的声明自动 trim

**Scope 映射：**

| Gradle 配置 | ym scope |
|-------------|---------|
| `implementation`, `api` | `compile`（默认） |
| `testImplementation` | `test` |
| `compileOnly` | `provided` |
| `runtimeOnly` | `runtime` |

**注意：** Gradle `api` 和 `implementation` 都映射到 `compile` scope。ym 不区分传递边界（所有 `compile` 依赖对消费者可见），这与 Gradle `implementation` 的隔离语义不同。

**解析方式：** 正则表达式（非 AST），支持常见格式但不保证 100% 覆盖。

### 多模块

1. 解析 `settings.gradle(.kts)` 中的 `include` 语句：
   - Groovy: `include ':module-a', ':module-b'`
   - Kotlin DSL: `include(":module-a", ":module-b")`
   - 嵌套模块 `:parent:child` → `parent/child` 路径
2. 生成根 `package.toml`（`workspaces` 列出所有模块）
3. 为每个子模块解析 `build.gradle(.kts)`：
   - 检测 `project(':module-name')` 依赖 → `workspaceDependencies`
   - 支持 Groovy 和 Kotlin DSL 的 project 依赖语法
   - `project()` 依赖不计入 Maven `dependencies`

## 已知限制

- [ ] Gradle 解析基于正则，复杂脚本可能遗漏
- [ ] 不支持 Gradle Version Catalog (`libs.versions.toml`)
- [ ] 不迁移插件配置（shade/spring-boot/annotation-processing）
- [ ] 不迁移 Maven profiles
- [ ] 不迁移 Gradle buildSrc / convention plugins

## 优化路线图

### P0 — Gradle Version Catalog

解析 `gradle/libs.versions.toml` 提取依赖声明和版本定义。

### P1 — 插件配置迁移

检测常见 Gradle/Maven 插件（spring-boot, shade, annotation-processing），映射到 ym 配置。

### P2 — 迁移后验证

`ym convert` 完成后自动运行 `ym install` + `ymc build`，验证迁移结果。
