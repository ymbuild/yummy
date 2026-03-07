# 01 — 配置与 Schema

## 概述

ym 使用 `package.json` 作为项目配置文件，`package-lock.json` 作为依赖锁定文件。设计目标：与 npm/yarn 生态开发者零学习成本，同时满足 Java 构建需求。

## package.json Schema

```jsonc
{
  "name": "com.example:my-app",          // 必填，Maven 坐标格式 groupId:artifactId
  "version": "1.0.0",                    // 语义化版本
  "description": "...",                   // 项目描述
  "target": "21",                        // Java 目标版本（javac --release）
  "private": true,                       // 禁止发布
  "main": "com.example.myapp.Main",      // 主类（全限定名）
  "package": "com.example.myapp",        // 根包名（init/create 使用）
  "author": "Allen",
  "license": "MIT",

  "dependencies": {                       // 运行时依赖
    "groupId:artifactId": "^version"      // 支持 ^/~ 前缀（npm/yarn 语法）
  },
  "devDependencies": {                    // 开发/测试依赖
    "org.junit.jupiter:junit-jupiter": "^5.11.0"
  },
  "workspaceDependencies": [              // 工作空间内模块间依赖
    "core", "utils"
  ],
  "workspaces": [                         // 工作空间模式 glob
    "apps/*", "libs/*"
  ],

  "jvmArgs": ["-Xmx512m"],              // JVM 参数
  "env": {                               // 环境变量（支持 ~/ 展开）
    "ARTIFACT": "my-app",
    "DEV_JAVA_HOME": "~/.ym/jdks/jbr-25"
  },
  "scripts": {                           // 自定义脚本
    "dev": "JAVA_HOME=$DEV_JAVA_HOME ymc dev",
    "build": "ymc build"
  },

  "resolutions": {                       // 依赖版本覆盖（解决冲突）
    "groupId:artifactId": "pinned-version"
  },
  "exclusions": [                        // 传递依赖排除
    "commons-logging:commons-logging"
  ],
  "registries": {                        // 自定义 Maven 仓库
    "private": "https://maven.example.com/releases"
  },

  "sourceDir": "src/main/java",          // 自定义源码目录
  "testDir": "src/test/java",            // 自定义测试目录

  "jvm": {                               // JVM 管理
    "vendor": "temurin",
    "version": "21",
    "autoDownload": true
  },
  "compiler": {                          // 编译器配置
    "engine": "javac",                   // "javac" | "ecj"
    "encoding": "UTF-8",
    "annotationProcessors": ["org.projectlombok:lombok"],
    "lint": ["all", "-serial"],
    "args": ["-parameters"]
  },
  "hotReload": {                         // 热重载配置
    "enabled": true,
    "watchExtensions": [".java", ".xml"]
  }
}
```

## 版本语法

采用 npm/yarn 兼容的版本前缀规则：

| 语法 | 含义 | 示例 |
|------|------|------|
| `^1.2.3` | 兼容版本（允许 minor/patch 升级） | `>=1.2.3 <2.0.0` |
| `~1.2.3` | 近似版本（仅允许 patch 升级） | `>=1.2.3 <1.3.0` |
| `1.2.3` | 精确版本 | 仅 `1.2.3` |

**当前行为：** `^` 和 `~` 前缀被剥离，使用精确版本解析。`ym add` 默认添加 `^` 前缀。`ym upgrade` 时参考前缀规则判断可升级范围。

## 名称与 Maven 坐标

`name` 字段用于标识项目，同时作为发布时的 Maven 坐标来源：

| name 格式 | groupId | artifactId |
|-----------|---------|------------|
| `com.example:my-app` | `com.example` | `my-app` |
| `my-app`（无冒号） | 从 `package` 字段推导，fallback `com.example` | `my-app` |

**推荐格式：** `groupId:artifactId`，与 dependencies 中的坐标格式一致。

## 文件查找规则

1. **find_config()**：从当前目录向上搜索 `package.json`
2. **find_workspace_root()**：向上搜索含 `workspaces` 字段的 `package.json`（最顶层优先）
3. **source_dir()**：优先 `sourceDir` 配置 → `src/main/java` → fallback `src/`
4. **test_dir()**：优先 `testDir` 配置 → `src/test/java` → fallback `test/`

## 目录结构

```
project/
  package.json
  package-lock.json
  .ym/
    cache/maven/          # 依赖 JAR 缓存
    pom-cache/            # POM 解析结果缓存
    fingerprints/         # 增量编译指纹
    graph.json            # 工作空间图缓存
    credentials.json      # Maven 仓库凭证
    tools/                # 工具 JAR（JaCoCo 等）
  src/main/java/          # 源码
  src/main/resources/     # 资源文件
  src/test/java/          # 测试源码（单元测试 + 集成测试）
  src/test/resources/     # 测试资源
  out/
    classes/              # 编译输出
    test-classes/         # 测试编译输出
```

## 已知限制

- [ ] `package.json` 与 Node.js 项目冲突检测（同一目录下是否有 `node_modules/`）
- [ ] Schema 验证增强：类型检查、未知字段警告
- [ ] 支持 `package.jsonc`（带注释的 JSON）
- [ ] `version` 字段自动同步到编译产物 MANIFEST
