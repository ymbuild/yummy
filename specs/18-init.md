# 18 — 项目初始化

## 概述

`ym init` 是用户接触的第一个命令，通过交互式引导创建项目，生成 `package.toml`、目录结构和 JDK 配置。目标是零手动配置即可开始开发。

## 命令

```bash
ym init                                  # 交互式初始化
ym init my-app                           # 指定项目名
ym init -t lib                           # 指定模板
ym init -y                               # 跳过交互，使用默认值
```

## 目录行为

- `ym init`（无名称）→ 在当前目录初始化，使用当前目录名作为默认项目名
- `ym init my-app`（有名称）→ 创建 `my-app/` 子目录并在其中初始化

## 前置检查

- 目标目录已有 `package.toml` → 拒绝覆盖，报错退出（与 `ym convert` 行为一致）

## 交互式流程

```
1. 项目名称？ (默认: 当前目录名)
2. 包名？ (默认: com.example.{name})
3. Java 版本？ (扫描已安装 JDK，默认最新 LTS)
4. 模板？ (app / lib / spring-boot)
5. DEV JDK 选择：
   ├─ 已有 JBR → 自动选中
   ├─ 无 JBR → 推荐下载 JBR（DCEVM 热重载支持）
   └─ 用户可跳过
6. 生成文件
7. 执行 postinit 脚本（如有）
```

### 非交互模式（CI / `-y`）

当标准输入不是 TTY 或使用 `-y` 时：
- 项目名：当前目录名
- 包名：`com.example.{name}`
- Java 版本：检测 JAVA_HOME，未找到则下载 Temurin 最新 LTS
- 模板：app
- 不提示 DEV JDK 选择

## 模板

### app（默认）

```
my-app/
  package.toml
  src/main/java/com/example/myapp/Main.java
  src/main/resources/
  src/test/java/
  .gitignore
```

`Main.java`:
```java
package com.example.myapp;

public class Main {
    public static void main(String[] args) {
        System.out.println("Hello, World!");
    }
}
```

### lib

```
my-lib/
  package.toml
  src/main/java/com/example/mylib/MyLib.java
  src/test/java/com/example/mylib/MyLibTest.java
  .gitignore
```

无 `main` 字段。包含测试文件模板。

### spring-boot

```
my-app/
  package.toml
  src/main/java/com/example/myapp/Application.java
  src/main/resources/application.yml
  src/test/java/
  .gitignore
```

`package.toml` 自动包含 `spring-boot-starter-web` 依赖。

## 生成的 package.toml

```toml
name = "com.example:my-app"
version = "0.1.0"
target = "21"
main = "com.example.myapp.Main"
package = "com.example.myapp"

[dependencies]

[scripts]
dev = "ymc dev"
build = "ymc build"
test = "ymc test"
```

## JDK 引导

`ym init` 在 JDK 选择阶段：

1. 调用 `scan_jdks()` 扫描本机所有 JDK（见 [08-jdk.md](08-jdk.md)）
2. 按 `target` 版本过滤匹配的 JDK
3. 显示可用 JDK 列表（标注供应商、版本、DCEVM 支持）
4. DEV JDK 推荐：优先选择 JBR（内置 DCEVM，支持 L1 HotSwap 热重载）
5. 无可用 JDK → 提供下载选项：
   - Temurin（默认，生产稳定）
   - JBR（开发推荐，DCEVM 支持）
   - GraalVM（可选，native-image）
   - 自定义 URL

下载的 JDK 安装到 `~/.ym/jdks/{name}/`。

## .gitignore 生成

```
out/
.ym/
.ym-sources.txt
*.class
```

## 工作空间初始化

`ym init` 用于创建全新项目或工作空间根。在已有工作空间中添加新模块，手动创建子目录后在其中执行 `ym init`。

## 已知限制

| 问题 | 严重性 |
|------|--------|
| 模板数量有限（app/lib/spring-boot） | 低 |
| 无自定义模板支持 | 低 |
| spring-boot 模板不检测最新 Spring Boot 版本 | 低 |

## 优化路线图

### P0 — 自定义模板

支持从 Git 仓库或本地目录加载模板：

```bash
ym init -t https://github.com/example/ym-template-grpc
ym init -t ./my-templates/microservice
```

### P1 — 依赖交互选择

初始化时可选添加常见依赖（Spring Boot、Jackson、Lombok 等），通过 checkbox 交互选择。
