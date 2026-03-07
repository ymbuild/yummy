# 11 — 诊断与工具

## 概述

ym 提供一系列诊断和辅助命令，用于调试环境问题、分析依赖关系和项目健康度。

## 命令清单

### `ym doctor`

诊断环境问题。

```bash
ym doctor                                # 检查所有
ym doctor --fix                          # 自动修复
```

检查项：
- package.json 存在且可解析
- JDK 可用且版本匹配 `target`
- 依赖缓存完整性（JAR 文件存在）
- 锁文件与 package.json 同步
- `.ym/` 目录权限

### `ym env`

显示环境信息。

```bash
ym env
```

输出：ym 版本、Java 版本、JAVA_HOME、OS、项目信息、依赖数量。

### `ym validate`

校验 package.json 配置。

```bash
ym validate
```

检查：字段类型、依赖坐标格式（`groupId:artifactId`）、版本格式、workspaceDependencies 引用完整性。

### `ym verify`

校验缓存的依赖 JAR 完整性。

```bash
ym verify
```

逐个对比 JAR 的 SHA-256 与锁文件记录。发现不一致时报告并可选重新下载。

### `ym audit`

检查依赖的已知漏洞（使用 OSV.dev API）。

```bash
ym audit                                 # 检查并报告
ym audit --json                          # JSON 输出（CI 集成）
```

输出包含：CVE 编号、严重级别、受影响版本、修复版本建议。

### `ym why <dep>`

解释为什么某个依赖被引入。

```bash
ym why jackson-core
```

显示依赖链：`package.json → jackson-databind → jackson-core`
支持模糊匹配 artifactId。

### `ym tree`

显示依赖树。

```bash
ym tree                                  # 树形显示
ym tree --flat                           # 扁平列表
ym tree --depth 2                        # 限制深度
ym tree --json                           # JSON 输出
```

### `ym deps`

平坦依赖列表。

```bash
ym deps                                  # 列出所有依赖
ym deps --json                           # JSON 输出
ym deps --outdated                       # 仅显示过时的
```

### `ym license`

检查所有依赖的许可证。

```bash
ym license                               # 列出许可证
ym license --json                        # JSON 输出
```

从 POM 文件中提取 `<license>` 信息。

### `ymc graph`

依赖关系图（文本或 Graphviz DOT）。

```bash
ymc graph                                # 文本输出
ymc graph --dot                          # DOT 格式（可用 Graphviz 可视化）
ymc graph --reverse                      # 反向依赖（谁依赖了我）
ymc graph --depth 2                      # 限制深度
```

### `ymc size`

项目大小分析。

```bash
ymc size
```

显示：源码文件数/大小、编译输出大小、依赖 JAR 总大小。

### `ymc hash`

项目内容哈希（用于 CI 缓存键）。

```bash
ymc hash
```

基于 package.json + 源码内容计算确定性哈希。可用于 CI 缓存的 cache key。

### `ymc diff`

自上次构建以来的变更文件。

```bash
ymc diff
```

基于指纹系统（Fingerprints），比较当前源码与上次编译时的 source_hash。

### `ymc classpath`

输出项目 classpath。

```bash
ymc classpath                            # 输出完整 classpath 字符串
ymc classpath <module>                   # 工作空间模式
```

可用于集成外部工具：`java -cp $(ymc classpath) com.example.Tool`

### `ymc exec`

在项目 classpath 下执行命令。

```bash
ymc exec -- java -cp {classpath} com.example.Tool
```

### `ym config`

读写 package.json 配置。

```bash
ym config target                         # 读取
ym config target 21                      # 设置
```

### `ym cache`

管理依赖缓存。

```bash
ym cache list                            # 显示缓存大小（Maven + POM + 指纹）
ym cache clean                           # 清理全部
ym cache clean --maven-only              # 仅清理 Maven 缓存
```

### `ymc clean`

清理构建输出。

```bash
ymc clean                                # 清理 out/
ymc clean --all                          # 清理 out/ + .ym/cache/
```

### `ymc fmt`

格式化 Java 源码（使用 google-java-format）。

```bash
ymc fmt                                  # 格式化
ymc fmt --check                          # 仅检查（CI 模式）
ymc fmt --diff                           # 显示差异
```

### `ymc doc`

生成 Javadoc。

```bash
ymc doc                                  # 生成文档到 out/docs/
ymc doc --open                           # 生成并打开浏览器
```

### `ymc bench`

JMH 基准测试。

```bash
ymc bench                                # 运行所有基准
ymc bench --filter "BenchmarkName"       # 过滤
```

自动将 JMH 注解处理器加入 classpath。

### `ymc watch`

通用文件监听。

```bash
ymc watch -- ymc build                   # 文件变化时重建
ymc watch --ext ".java,.xml" -- ymc test # 自定义扩展名
```

### `ymc rebuild`

清理后全量重建。

```bash
ymc rebuild                              # clean + build
ymc rebuild --release                    # clean + build --release
```

等价于 `ymc clean && ymc build [--release]`。
