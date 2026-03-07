# 10 — 发布与分发

## 概述

ym 支持将 Java 库发布到 Maven 仓库（私有仓库、Maven Central、GitHub Packages），以及通过 `link` 命令进行本地跨项目开发。

## `ym publish`

```bash
ym publish                               # 发布到默认仓库
ym publish --registry internal           # 发布到指定仓库（按 [registries] 中的键名）
ym publish --dry-run                     # 模拟发布（不上传）
```

### 发布流程

1. 检查 `private = true` → 拒绝发布
2. 执行 `prepublish` 脚本
3. 编译项目
4. 打包 JAR
5. 生成 POM 文件
6. 上传到 Maven 仓库（JAR + POM）
7. 执行 `postpublish` 脚本

### Maven 坐标提取

从 `package.toml` 的 `name` 字段提取 groupId 和 artifactId：

| name 格式 | groupId | artifactId |
|-----------|---------|------------|
| `com.example:my-lib` | `com.example` | `my-lib` |
| `my-lib`（无冒号） | 从 `package` 字段推导 | `my-lib` |

**推荐：** 始终使用 `groupId:artifactId` 格式的 name，避免 groupId 推导歧义。

### POM 生成

从 `package.toml` 映射：

| package.toml | POM |
|-------------|-----|
| `name`（冒号前） | `<groupId>` |
| `name`（冒号后） | `<artifactId>` |
| `version` | `<version>` |
| `description` | `<description>` |
| `license` | `<license>` |
| `dependencies` | `<dependencies>` |
| `workspaceDependencies` | `<dependencies>`（从目标模块的 `package.toml` 的 `name` 字段提取 Maven 坐标） |

**workspaceDependencies 映射：** 发布时，workspace 依赖通过查找目标模块的 `package.toml` 的 `name` 字段转为 Maven 坐标。例如 `workspaceDependencies = ["core"]` → 查找 core 的 `name = "com.example:core"` → POM 中写入 `<groupId>com.example</groupId><artifactId>core</artifactId><version>{core.version}</version>`。

**Scope 映射：**

| ym scope | POM 处理 |
|----------|---------|
| `compile` | 写入 `<dependencies>`，不写 `<scope>`（Maven 默认） |
| `runtime` | 写入 `<dependencies>`，`<scope>runtime</scope>` |
| `provided` | 写入 `<dependencies>`，`<scope>provided</scope>` |
| `test` | **不写入 POM**（库的测试依赖不应暴露给消费者） |

### 仓库选择

1. `--registry <name>` → 使用 `[registries]` 中对应键名的仓库
2. 无 `--registry` → 查找 `[registries]` 中的 `default` 键
3. 无 `default` 且仅一个仓库 → 使用该仓库
4. 无 `default` 且多个仓库 → 报错，要求使用 `--registry` 指定
5. 无 `[registries]` → 报错，要求在 package.toml 中配置 `[registries]`（不默认推到 Maven Central）

## `ym login`

支持多账户登录状态——同一台机器可以同时保存多个 Maven 仓库的凭证。

```bash
ym login                                 # 交互式输入仓库 URL + 凭证
```

每次执行 `ym login` 会追加/更新指定仓库的凭证，不会覆盖已有的其他仓库凭证。

### 凭证存储格式

凭证存储在 `~/.ym/credentials.json`（文件权限 0o600），以仓库 URL 为键：

```json
{
  "https://maven.example.com": {
    "username": "deploy",
    "password": "token_xxx"
  },
  "https://maven.pkg.github.com/OWNER/REPO": {
    "username": "github-user",
    "password": "ghp_xxx"
  },
  "https://private.nexus.company.com/repository/releases": {
    "username": "ci-bot",
    "password": "secret_token"
  }
}
```

### 凭证查找

`ym publish` 时根据目标 registry URL 查找对应凭证：

1. 精确匹配 registry URL
2. 忽略尾部斜杠后重试匹配
3. 无匹配 → 报错提示 `ym login`
4. 🔲 待实现：环境变量覆盖（优先于文件）：`YM_REGISTRY_USERNAME` + `YM_REGISTRY_PASSWORD`，或 `YM_REGISTRY_TOKEN`（Bearer 模式）

### 安全措施

- 文件权限设置为 600（仅所有者可读写，Unix）
- 凭证文件位于 `~/.ym/credentials.json`（用户 home 目录），不在项目目录内，无 git 泄露风险
- 凭证文件不含明文 registry 默认值，仅存储用户实际登录过的仓库

### 凭证管理命令

```bash
ym login                                 # 添加/更新仓库凭证
ym login --list                          # 列出已登录的仓库（不显示密码）
ym login --remove <registry-url>         # 移除指定仓库的凭证
```

`--list` 输出示例：
```
  ✓ https://maven.example.com (username: deploy)
  ✓ https://maven.pkg.github.com/OWNER/REPO (username: github-user)
```

## 已知限制

| 问题 | 严重性 |
|------|--------|
| 不支持 GPG 签名（Maven Central 要求） | 高 |
| 不支持 Javadoc JAR 上传 | 中 |
| 不支持 Sources JAR 上传 | 中 |
| 不生成 SHA-256 校验文件上传 | 中 |
| POM 不含 parent/dependencyManagement | 低 |

## 优化路线图

### P0 — 发布脚本钩子

在发布流程中正确调用 `prepublish` 和 `postpublish` 脚本。

### P1 — Maven Central 完整发布

支持完整的 Maven Central 发布流程：

1. GPG 签名（`.asc` 文件）
2. Javadoc JAR 生成和上传
3. Sources JAR 生成和上传
4. SHA-256/MD5 校验文件
5. Staging → Release 流程（Sonatype OSSRH）

### P2 — GitHub Packages 集成

自动检测 GitHub Actions 环境，使用 `GITHUB_TOKEN` 发布：

```toml
[registries]
github = "https://maven.pkg.github.com/OWNER/REPO"
```

### P3 — 凭证环境变量

支持环境变量配置凭证（避免文件存储）：

```bash
export YM_REGISTRY_USERNAME=deploy
export YM_REGISTRY_PASSWORD=token_xxx
export YM_REGISTRY_TOKEN=ghp_xxx          # Bearer token 模式
```
