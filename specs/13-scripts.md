# 13 — 脚本与生命周期

## 概述

ym 支持 npm 风格的自定义脚本和生命周期钩子。

## 自定义脚本

```toml
[scripts]
dev = "JAVA_HOME=$DEV_JAVA_HOME ymc dev"
build = "JAVA_HOME=$PROD_JAVA_HOME ymc build"
test = "ymc test"
start = "ymc run"
"docker:build" = "docker build -t $ARTIFACT ."
native = "ymc build --release && $GRAALVM_HOME/bin/native-image -jar out/$ARTIFACT.jar"
```

### 运行方式

```bash
ym dev                                   # ym <name> 自动查找 scripts 中同名脚本执行
ym build -- --release                    # -- 后的参数追加到脚本命令
```

当 `ym <name>` 不匹配内置命令时，自动在 `scripts` 中查找同名脚本执行。

### 执行机制

- **Shell 选择：** Windows 使用 `cmd /C`，Unix 使用 `sh -c`
- **工作目录：** 项目根目录（package.toml 所在目录）
- **环境变量注入：**
  - `env` 字段中的变量自动注入到脚本环境
  - `~/` 前缀自动展开为 `$HOME` 路径
  - 脚本内部可通过 shell 语法引用 `$VAR`（由 shell 自身处理）
- **优先级：** `env` 字段中定义的变量覆盖同名系统环境变量（与 Docker ENV 行为一致）

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
| `postinit` | `ym init` 之后 | ✅ |

钩子定义在 `scripts` 中，命名即触发。钩子执行失败时阻止主命令执行（pre 钩子）或仅打印警告（post 钩子）。

**防止重复触发：** 钩子仅在 ym/ymc 直接调用命令时触发。如果脚本内容本身调用了 `ymc dev`，不会再次触发 `predev`/`postdev`（通过环境变量 `YM_LIFECYCLE=1` 标记已在钩子链中）。

## 已知限制

- [ ] 无超时控制
- [ ] 无并行脚本执行
- [ ] 环境变量展开仅支持 `~/` 前缀，ym 不做 `$VAR` 交叉引用（由 shell 处理）
- [ ] 脚本参数传递需要 `--` 分隔符

## 优化路线图

### P0 — 脚本超时

```toml
[scripts]
test = { command = "ymc test", timeout = "5m" }
```

### P1 — 并行脚本

支持并行执行多个脚本（待设计命令语法）。
