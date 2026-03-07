# 13 — 脚本与生命周期

## 概述

ym 支持 npm 风格的自定义脚本和生命周期钩子。

## 自定义脚本

```json
{
  "scripts": {
    "dev": "JAVA_HOME=$DEV_JAVA_HOME ymc dev",
    "build": "JAVA_HOME=$PROD_JAVA_HOME ymc build",
    "test": "ymc test",
    "start": "ymc run",
    "docker:build": "docker build -t $ARTIFACT .",
    "native": "ymc build --release && $GRAALVM_HOME/bin/native-image -jar out/$ARTIFACT.jar"
  }
}
```

### 运行方式

```bash
ym run dev                               # 显式运行
ym dev                                   # 快捷方式（外部子命令匹配）
```

当 `ym <name>` 不匹配内置命令时，自动在 `scripts` 中查找同名脚本执行。

### 执行机制

- **Shell 选择：** Windows 使用 `cmd /C`，Unix 使用 `sh -c`
- **工作目录：** 项目根目录（package.json 所在目录）
- **环境变量注入：**
  - `env` 字段中的变量自动注入到脚本环境
  - `~/` 前缀自动展开为 `$HOME` 路径
  - 脚本内部可通过 shell 语法引用 `$VAR`（由 shell 自身处理）

## 生命周期钩子

| 钩子 | 触发时机 | 实现状态 |
|------|---------|---------|
| `prebuild` | `ymc build` 之前 | ✅ |
| `postbuild` | `ymc build` 之后 | ✅ |
| `predev` | `ymc dev` 之前 | ✅ |
| `postdev` | `ymc dev` 之后（Ctrl+C 退出时） | ✅ |
| `pretest` | `ymc test` 之前 | ✅ |
| `posttest` | `ymc test` 之后 | ✅ |
| `prepublish` | `ym publish` 之前 | 🔲 |
| `postpublish` | `ym publish` 之后 | 🔲 |
| `preinit` | `ym init` 之前 | ✅ |
| `postinit` | `ym init` 之后 | ✅ |

钩子定义在 `scripts` 中，命名即触发。钩子执行失败时阻止主命令执行（pre 钩子）或仅打印警告（post 钩子）。

## 已知限制

- [ ] 无超时控制
- [ ] 无并行脚本执行
- [ ] 环境变量展开仅支持 `~/` 前缀，ym 不做 `$VAR` 交叉引用（由 shell 处理）
- [ ] 脚本参数传递需要 `--` 分隔符

## 优化路线图

### P0 — 脚本参数传递

```bash
ym run build -- --release                # 将 --release 追加到脚本命令后
```

### P1 — 脚本超时

```json
{
  "scripts": {
    "test": { "command": "ymc test", "timeout": "5m" }
  }
}
```

### P2 — 并行脚本

```bash
ym run --parallel lint test build        # 并行执行多个脚本
```
