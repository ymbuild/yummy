# 06 — 测试

## 概述

ym 的测试系统支持 JUnit 5（JUnit Platform），提供测试发现、执行、过滤、覆盖率和监听模式。遵循 Java 测试最佳实践，区分单元测试和集成测试。

## 命令

```bash
ymc test                                 # 运行所有单元测试
ymc test --filter "UserServiceTest"      # 按类名过滤
ymc test --integration                   # 运行集成测试（*IT.java）
ymc test --all                           # 运行所有测试（单元 + 集成）
ymc test --verbose                       # 显示详细输出
ymc test --fail-fast                     # 首个失败即停止
ymc test --timeout 30                    # 每个测试超时（秒，JUnit 5 配置）
ymc test --coverage                      # 生成 JaCoCo 覆盖率报告
ymc test --list                          # 仅列出测试类
ymc test --watch                         # 监听模式：文件变化自动重跑
ymc test <module>                        # 工作空间：测试指定模块
```

## 测试分类

遵循 Maven/JUnit 5 最佳实践，按命名约定区分测试类型：

### 单元测试（默认）

- **命名约定：** `*Test.java`、`Test*.java`、`*Tests.java`
- **排除：** `*IT.java`、`*IntegrationTest.java`
- **特点：** 快速、无外部依赖、可并行
- **运行：** `ymc test`

### 集成测试

- **命名约定：** `*IT.java`、`*IntegrationTest.java`
- **特点：** 可能依赖外部服务（DB、HTTP）、较慢、默认顺序执行
- **运行：** `ymc test --integration`

### JUnit 5 Tag 过滤

支持通过 `@Tag` 注解精确控制：

```java
@Tag("slow")
class DatabaseIT { ... }

@Tag("fast")
class UtilsTest { ... }
```

```bash
ymc test --tag fast                      # 仅运行 @Tag("fast")
ymc test --exclude-tag slow              # 排除 @Tag("slow")
```

## 执行流程

### 单项目模式

1. 编译主源码（`src/main/java` → `out/classes`）
2. 编译测试源码（`src/test/java` → `out/classes`，classpath 含主源码 + 所有依赖）
3. 发现测试类（按命名约定扫描 `.java` 文件中的 `@Test` 或 `@org.junit` 注解）
4. 构建测试 classpath：`out/classes` + dependencies + devDependencies
5. 运行 JUnit Platform Console

### 工作空间模式

1. 构建目标模块的传递闭包（所有上游依赖）
2. 编译所有依赖模块
3. 构建组合 classpath：所有依赖模块的 `out/classes/` + Maven JAR
4. 仅编译和运行目标模块的测试

### 测试发现

扫描测试目录中的 `.java` 文件，检查内容包含：
- `@Test`
- `@org.junit`

将文件路径转为类名：`src/test/java/com/example/FooTest.java` → `com.example.FooTest`

### JUnit Platform 执行

**优先方式：** 查找 `junit-platform-console-standalone` JAR（从 devDependencies 解析）：
```
java -jar junit-platform-console-standalone.jar
  --classpath {classpath}
  --scan-classpath
  --details verbose
  --include-classname-pattern ".*Test"
  --exclude-classname-pattern ".*IT"
```

**回退方式：** 直接用 `java -cp` 逐个运行测试类（当 junit-platform-console-standalone 不可用时）。

### 覆盖率（JaCoCo）

启用 `--coverage` 时：

1. 自动下载 JaCoCo agent（v0.8.12）到 `.ym/tools/jacocoagent.jar`
2. 添加 JVM 参数：`-javaagent:jacocoagent.jar=destfile=out/coverage/jacoco.exec`
3. 测试完成后生成 `out/coverage/jacoco.exec`
4. 通过 JaCoCo CLI 生成 HTML 报告到 `out/coverage/html/`

### 监听模式

`--watch` 启用后进入循环：

1. 使用 `FileWatcher`（notify crate）监听源码和测试目录
2. 文件变更 → 100ms 防抖
3. 增量编译变更的源码/测试文件
4. 重新运行受影响的测试

## 测试最佳实践建议

### 项目结构

```
src/
  main/java/
    com/example/
      UserService.java
      OrderService.java
  test/java/
    com/example/
      UserServiceTest.java           # 单元测试
      OrderServiceTest.java          # 单元测试
      UserServiceIT.java             # 集成测试
      TestUtils.java                 # 测试工具类（不会被当作测试运行）
  test/resources/
    application-test.yml             # 测试配置
```

### 依赖配置

```json
{
  "devDependencies": {
    "org.junit.jupiter:junit-jupiter": "^5.11.0",
    "org.junit.platform:junit-platform-console-standalone": "^1.11.0",
    "org.mockito:mockito-core": "^5.14.0",
    "org.assertj:assertj-core": "^3.26.0"
  }
}
```

## 已知限制

- [ ] 不支持 TestNG
- [ ] 测试编译不使用增量编译（每次全量）
- [ ] 无 JUnit XML 报告输出（CI 系统集成）
- [ ] `--filter` 仅按类名过滤，不支持方法级过滤（`TestClass#method`）
- [ ] 并行测试执行需要在 JUnit 配置中手动启用

## 优化路线图

### P0 — 增量测试编译

复用增量编译指纹系统，仅重编译变更的测试文件。

### P1 — JUnit XML 报告

```bash
ymc test --report junit-xml             # 生成 out/test-reports/TEST-*.xml
ymc test --report html                  # 生成 out/test-reports/index.html
```

兼容 CI 系统（Jenkins、GitHub Actions、GitLab CI）的测试报告格式。

### P2 — 受影响测试检测

基于变更的源码文件，分析类依赖关系，仅运行引用了变更类的测试：

```
Main.java 变更 → 查找 import Main 的测试 → 仅运行 MainTest.java
```

### P3 — 并行测试执行

自动配置 JUnit 5 并行执行：

```
junit.jupiter.execution.parallel.enabled=true
junit.jupiter.execution.parallel.mode.default=concurrent
```

单元测试默认并行，集成测试默认顺序。
