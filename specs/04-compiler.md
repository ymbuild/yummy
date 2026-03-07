# 04 — 编译管线

## 概述

ym 的编译管线支持 javac 和 ECJ 两种引擎，核心特性是增量编译（基于源码哈希 + ABI 哈希）和工作空间拓扑并行编译。

## 编译引擎

### javac（默认）

调用系统 `javac` 命令行。

**编译参数构建：**
```
javac -d {output_dir}
      --release {target}
      -encoding {encoding|UTF-8}
      -cp {classpath}
      -Xlint:{lint_options}
      -processorpath {annotation_processor_jars}
      {extra_args}
      {source_files | @argfile}
```

- 超过 50 个文件时使用 `@argfile`（避免命令行长度限制）
- argfile 路径：`.ym-sources.txt`，RAII 守卫自动清理

### ECJ（Eclipse Compiler for Java）

长期运行 JVM 进程，通过 TCP JSON-RPC 通信。

**优势：** 更详细的错误信息、增量编译友好
**当前状态：** 代码存在但标记 `#[allow(dead_code)]`，未完全集成

## 增量编译

### 策略

```
文件改变 → 计算 sourceHash
  → sourceHash 未变 → 跳过（mtime 快速路径）
  → sourceHash 改变 → 编译 → 计算 abiHash
    → abiHash 未变 → 仅更新 .class，不传播重编译
    → abiHash 改变 → 递归重编译所有依赖该文件的类
```

### ABI 哈希提取

解析 Java `.class` 文件的二进制格式（ClassFile structure），提取 ABI 相关字节：

**包含在 ABI 中的：**
- Magic number + 版本号
- 完整常量池（类名、方法签名、字段类型）
- access_flags、this_class、super_class
- 接口列表
- 非 private 的字段及其属性
- 非 private 的方法（排除 Code 属性）
- 类级属性（SourceFile、InnerClasses 等）

**排除在 ABI 外的：**
- Code 属性（方法体字节码）
- private 字段和方法

**效果：** 方法体内部修改不会触发依赖模块的级联重编译。

### 指纹存储

```
.ym/fingerprints/{output_dir_hash}/fingerprints.json
```

每个文件记录：
- `source_hash`: 源码内容 SHA-256
- `abi_hash`: 编译后 ABI 的哈希
- `mtime`: 文件修改时间（快速路径）

### 变更检测流程

1. walkdir 扫描所有 `.java` 文件
2. 对比 mtime → 相同则跳过内容哈希
3. mtime 不同 → 计算 source_hash → 对比指纹
4. 返回 (changed_files, all_files) 元组
5. 如果 output_dir 为空 → 强制全量编译

### 编译后更新

编译成功后：
1. 更新每个编译文件的 source_hash 和 mtime
2. 查找对应 `.class` 文件，计算 ABI hash 并存储
3. 清理已删除文件的指纹条目

## 注解处理器自动发现

扫描 classpath 中所有 JAR 文件，查找 `META-INF/services/javax.annotation.processing.Processor`：

1. 优先使用 `compiler.annotationProcessors` 中显式配置的坐标
2. 若未配置，自动扫描 classpath JAR（排除 JDK/JUnit/常见框架 JAR）
3. 发现的处理器 JAR 自动添加到 `-processorpath`

## 构建命令 (`ymc build`)

### 单项目模式

```bash
ymc build                               # 增量编译
ymc build --release                      # 编译 + 打包 fat JAR
ymc build --clean                        # 清理后全量编译
ymc build --watch                        # 监听模式
ymc build --profile                      # 显示各阶段计时
ymc build -j 4                           # 指定并行线程数
ymc build -v                             # 显示编译器完整输出
```

**流程：**
1. 加载配置
2. 确保 JDK 可用
3. 解析依赖（快速路径优先）
4. 增量编译源码
5. 复制资源文件（`src/main/resources/` → `out/classes/`）
6. （--release）打包 JAR

### 工作空间模式

```bash
ymc build <module>                       # 编译指定模块及其依赖
ymc build                                # 编译所有模块
```

**拓扑并行编译：**
1. 构建工作空间 DAG（petgraph）
2. 合并解析所有模块的 Maven 依赖（`resolve_workspace_deps`，一次性解析）
3. 计算拓扑层级：无依赖关系的包归为同一层
4. 按层顺序处理：
   - 单包层 → 直接编译
   - 多包层 → rayon par_iter 并行编译
5. 每层完成后，将输出目录加入后续层的 classpath

### 资源文件复制

支持的扩展名：
```
.properties .xml .yml .yaml .json .txt .csv .sql .fxml
.css .html .conf .cfg .ini .toml .graphql .graphqls
.proto .ftl .mustache
```

源：`src/main/resources/` → 目标：`out/classes/`
增量复制：仅当 src mtime > dest mtime 时复制。

### Release JAR 打包

```
out/{name}.jar
  META-INF/MANIFEST.MF    → Main-Class: {main}
  *.class                  → 编译输出
  **/*.jar (依赖)          → 解压合并（fat jar）
```

## 错误输出美化

- `: error:` 行 → 红色加粗
- `: warning:` 行 → 黄色
- `^` 指示符 → 绿色加粗
- `symbol:` / `location:` → 灰色

## 已知限制

| 问题 | 影响 | 严重性 |
|------|------|--------|
| ECJ 集成未完成 | 无法使用 ECJ 引擎 | 中 |
| fat JAR 依赖冲突 | 多个 JAR 有同名类时覆盖不可控 | 中 |
| 不支持 multi-release JAR | JDK 9+ 特性 | 低 |

## 优化路线图

### P0 — ECJ 完整集成

启用 ECJ 长驻进程模式，利用其内存缓存加速增量编译。

### P1 — 编译缓存共享

支持团队/CI 间共享编译缓存（类似 Gradle Build Cache），基于输入哈希匹配。

### P2 — fat JAR 冲突处理

检测 JAR 中的类名冲突，支持 shade/relocate 规则（类似 Maven Shade Plugin）。
