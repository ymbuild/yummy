# 09 — IDE 集成

## 概述

ym 通过 `ymc idea` 命令生成 IntelliJ IDEA 项目文件，使 IDEA 能正确识别源码目录、依赖 JAR 和模块结构，无需 Gradle/Maven 插件。

## 命令

```bash
ymc idea                                 # 生成 IDEA 项目文件
ymc idea --sources                       # 同时下载 -sources.jar
ymc idea <module>                        # 工作空间：生成指定模块
```

## 生成的文件

### 单项目模式

```
project/
  .idea/
    misc.xml                             ← JDK 版本、输出目录
    modules.xml                          ← 模块列表
    libraries/
      jackson-databind-2.19.0.xml        ← 每个 JAR 一个 library
      jackson-core-2.19.0.xml
  {name}.iml                             ← 模块定义（源码目录、依赖引用）
```

### 工作空间模式

```
root/
  .idea/
    misc.xml
    modules.xml                          ← 包含所有子模块
    libraries/
      *.xml                              ← 所有模块的 JAR 去重合并
  apps/web/web.iml
  apps/api/api.iml
  libs/core/core.iml
```

**模块间依赖：** `workspaceDependencies` 在 .iml 中生成为 IDEA module dependency（而非 JAR library 引用）：

```xml
<orderEntry type="module" module-name="core" scope="COMPILE" />
```

这样 IDEA 能正确识别模块间跳转和重构，无需将 workspace 模块的 `out/classes/` 作为 JAR 引用。

## 生成内容详情

### misc.xml

```xml
<project version="4">
  <component name="ProjectRootManager" version="2"
    languageLevel="JDK_{target}" project-jdk-name="{target}" project-jdk-type="JavaSDK">
    <output url="file://$PROJECT_DIR$/out" />
  </component>
</project>
```

### .iml 文件

自动检测源码目录结构：

| 目录 | 类型 | 条件 |
|------|------|------|
| `src/main/java` | sourceFolder | 存在时 |
| `src` | sourceFolder (fallback) | `src/main/java` 不存在时 |
| `src/main/resources` | java-resource | 存在时 |
| `src/test/java` | testSourceFolder | 存在时 |
| `test` | testSourceFolder (fallback) | `src/test/java` 不存在时 |
| `src/test/resources` | java-test-resource | 存在时 |
| `out` | excludeFolder | 始终 |

### library XML

```xml
<component name="libraryTable">
  <library name="jackson-databind-2.19.0">
    <CLASSES>
      <root url="jar://{path}!/" />
    </CLASSES>
    <SOURCES>
      <root url="jar://{sources_jar_path}!/" />
    </SOURCES>
  </library>
</component>
```

### Scope 映射

.iml 中引用 library 时根据 ym scope 设置 IDEA scope：

| ym scope | IDEA scope | 说明 |
|----------|-----------|------|
| `compile` | COMPILE | 默认，编译和运行时可见 |
| `runtime` | RUNTIME | 仅运行时可见 |
| `provided` | PROVIDED | 编译可见，不打包 |
| `test` | TEST | 仅测试编译和运行可见 |

### WSL 路径自适应

在 WSL 环境中（通过 `/proc/version` 检测 "microsoft" 或 "wsl"），JAR 路径自动转换：

| WSL 路径 | Windows 路径 |
|----------|-------------|
| `/mnt/c/Users/...` | `C:/Users/...` |
| `/mnt/d/repos/...` | `D:/repos/...` |

使用 `to_idea_path()` 函数处理，支持 `wslpath -w` 回退。

### Sources JAR 下载

`--sources` 时尝试从 Maven Central 下载 `-sources.jar`：
- 从 JAR 缓存路径反推 Maven 坐标
- 构建 sources JAR URL
- 下载到 JAR 同级目录

## 已知限制

| 问题 | 影响 | 严重性 |
|------|------|--------|
| JAR 路径为绝对路径 | 不可跨机器共享 .idea/ | 中 |
| 不支持注解处理器配置生成 | Lombok 等在 IDEA 中不生效 | 高 |
| 无 IDEA 插件 | 每次依赖变更需手动重跑 | 高 |
| User-Agent 硬编码 `ym/0.1.0` | sources 下载标识过时 | 低 |

## 优化路线图

### P0 — 注解处理器支持

生成 IDEA 的注解处理器配置（`.idea/compiler.xml`）：
```xml
<annotationProcessing>
  <profile name="Default" enabled="true">
    <processorPath useClasspath="false">
      <entry name="{lombok.jar}" />
    </processorPath>
  </profile>
</annotationProcessing>
```

### P1 — IDEA 插件

开发 IntelliJ 插件：
- 读取 `package.toml` 自动配置项目
- 依赖变更时自动刷新（FileWatcher 监听 `package.toml`）
- 在 IDEA 内运行 `ym install` / `ymc build`（`ym install` 无参数安装所有依赖）
- 与 IDEA 的 Run Configuration 集成

### P2 — VSCode 支持

生成 `.vscode/settings.json`，配置 Java Language Server 的 classpath。
