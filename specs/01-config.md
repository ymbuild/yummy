# 01 — 配置与 Schema

## 概述

ym 使用 `package.toml` 作为项目配置文件。无锁文件 — 依赖解析缓存为内部实现（`.ym/resolved.json`），用户不需要直接操作。

## package.toml Schema

```toml
name = "com.example:my-app"
version = "1.0.0"
description = "..."
target = "21"                              # 字符串或整数均可（target = 21 也合法）
private = true
main = "com.example.myapp.Main"
package = "com.example.myapp"
author = "Allen"
license = "MIT"

workspaceDependencies = ["core", "utils"]
workspaces = ["apps/*", "libs/*"]
jvmArgs = ["-Xmx512m"]
sourceDir = "src/main/java"
testDir = "src/test/java"
exclusions = ["commons-logging:commons-logging"]

[dependencies]
"com.google.guava:guava" = "33.4.0"                    # 简写：精确版本字符串
"com.fasterxml.jackson.core:jackson-databind" = { version = "2.19.0", exclude = ["com.fasterxml.jackson.core:jackson-annotations"] }
"javax.servlet:javax.servlet-api" = { version = "4.0.1", scope = "provided" }
"mysql:mysql-connector-java" = { version = "8.0.33", scope = "runtime" }
"org.junit.jupiter:junit-jupiter" = { version = "5.11.0", scope = "test" }
"org.junit.platform:junit-platform-console-standalone" = { version = "1.11.0", scope = "test" }

[env]
ARTIFACT = "my-app"
DEV_JAVA_HOME = "~/.ym/jdks/jbr-25"

[scripts]
dev = "JAVA_HOME=$DEV_JAVA_HOME ymc dev"
build = "ymc build"

[resolutions]
"com.google.guava:guava" = "33.4.0"

[registries]
central = "https://repo1.maven.org/maven2"
[registries.internal]
url = "https://maven.internal.com/releases"
scope = "com.mycompany.*"

[jvm]
autoDownload = true

[compiler]
encoding = "UTF-8"
annotationProcessors = ["org.projectlombok:lombok"]
lint = ["all", "-serial"]
args = ["-parameters"]
resourceExtensions = [".properties", ".xml"]  # 替换默认列表（默认含 20 种常见扩展名，见 04-compiler.md）
jacocoVersion = "0.8.12"

[hotReload]
enabled = true
watchExtensions = [".java", ".xml"]
```

**TOML 结构说明：** 根级字段（`name`、`workspaces`、`exclusions` 等）必须在第一个 `[section]` 之前。`[dependencies]`、`[env]`、`[scripts]` 等是独立的 TOML 表。

## 依赖 Scope

所有依赖统一在 `[dependencies]` 中管理，通过 `scope` 字段控制可见性：

| scope | 编译 classpath | 运行 classpath | fat JAR 打包 | 典型用途 |
|-------|:---:|:---:|:---:|------|
| `compile`（默认） | ✓ | ✓ | ✓ | 大部分依赖 |
| `runtime` | ✗ | ✓ | ✓ | JDBC 驱动、SLF4J 实现 |
| `provided` | ✓ | ✗ | ✗ | Servlet API、Lombok（注：测试运行时仍在 classpath 上，与 Maven 行为一致） |
| `test` | ✓（仅测试） | ✓（仅测试） | ✗ | JUnit、Mockito |

- 简写字符串格式的 scope 固定为 `compile`
- 对象格式中 `scope` 缺省时也为 `compile`
- `test` scope 的依赖仅在测试编译和测试运行时可见，不影响主源码编译
- **传递依赖 scope 传播：** 传递依赖继承引入它的直接依赖的 scope。例如 `mysql-connector`（runtime）依赖 `protobuf` → protobuf 也是 runtime scope，不进入编译 classpath。如果同一 JAR 被多条路径以不同 scope 引入，取最强 scope（compile > provided > runtime > test）

## Resolutions（版本强制覆盖）

`[resolutions]` 用于强制指定传递依赖的版本，解决版本冲突或安全修复：

```toml
[resolutions]
"com.google.guava:guava" = "33.4.0"
"log4j:log4j" = "2.17.1"
```

**优先级：resolutions 永远赢。** 无论是直接依赖、传递依赖还是子模块显式声明的版本，`[resolutions]` 中的版本始终覆盖。这是全局版本治理的最终手段。

## Exclusions（全局排除）

`exclusions` 数组用于从整个依赖树中排除特定依赖（根级字段）：

```toml
exclusions = ["commons-logging:commons-logging", "log4j:log4j"]
```

被排除的依赖无论出现在依赖树的哪个位置都不会被下载或加入 classpath。常见场景：排除旧日志框架以统一使用 SLF4J。

也可在单个依赖上使用 `exclude` 字段做局部排除（见 schema 示例）。

## 版本继承（工作空间）

工作空间中，根 `package.toml` 的 `[dependencies]` 兼作版本目录。子模块可通过空字符串 `""` 继承根的版本：

```toml
# 根 package.toml
[dependencies]
"org.springframework.boot:spring-boot-starter-web" = "3.4.0"
"com.google.guava:guava" = "33.4.0"
```

```toml
# apps/web/package.toml
[dependencies]
"org.springframework.boot:spring-boot-starter-web" = ""    # 继承根版本 3.4.0
"com.google.guava:guava" = "32.0"                          # 显式覆盖版本
"javax.servlet:javax.servlet-api" = { version = "", scope = "provided" }  # 继承版本，覆盖 scope
```

规则：
- 版本为空字符串 `""` → 从根 `[dependencies]` 继承版本
- 版本非空 → 使用自己的版本
- 对象格式中 `version = ""` 也触发继承，其他字段（`scope`、`exclude`）使用子模块自己的值
- 根的依赖不会自动添加到子模块，子模块必须显式声明坐标
- 子模块使用 `""` 但根中无对应坐标 → 报错
- 详见 [07-workspace.md](07-workspace.md)

## 名称与 Maven 坐标

`name` 字段用于标识项目，同时作为发布时的 Maven 坐标来源：

| name 格式 | groupId | artifactId |
|-----------|---------|------------|
| `com.example:my-app` | `com.example` | `my-app` |
| `my-app`（无冒号） | 从 `package` 字段推导，fallback `com.example` | `my-app` |

**推荐格式：** `groupId:artifactId`，与 dependencies 中的坐标格式一致。

## 文件查找规则

1. **find_config()**：从当前目录向上搜索 `package.toml`
2. **find_workspace_root()**：向上搜索含 `workspaces` 字段的 `package.toml`（最顶层优先）
3. **source_dir()**：优先 `sourceDir` 配置 → `src/main/java` → fallback `src/`
4. **test_dir()**：优先 `testDir` 配置 → `src/test/java` → fallback `test/`

## 目录结构

```
project/
  package.toml
  .ym/
    cache/maven/          # 依赖 JAR 缓存
    pom-cache/            # POM 解析结果缓存
    resolved.json         # 传递依赖解析缓存（内部）
    fingerprints/         # 增量编译指纹
    graph.json            # 工作空间图缓存
    tools/                # 工具 JAR（JaCoCo 等）
  src/main/java/          # 源码
  src/main/resources/     # 资源文件
  src/test/java/          # 测试源码（单元测试 + 集成测试）
  src/test/resources/     # 测试资源
  out/
    classes/              # 编译输出
    test-classes/         # 测试编译输出（独立于 classes/）
```

## 已知限制

- [ ] Schema 验证增强：类型检查、未知字段警告
- [ ] 项目配置验证（如 name 格式、target 值合法性检查）
- [ ] `version` 字段自动同步到编译产物 MANIFEST
