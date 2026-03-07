# 10 — 发布与分发

## 概述

ym 支持将 Java 库发布到 Maven 仓库（私有仓库、Maven Central、GitHub Packages），以及通过 `link` 命令进行本地跨项目开发。

## `ym publish`

```bash
ym publish                               # 发布到默认仓库
ym publish --dry-run                     # 模拟发布（不上传）
```

### 发布流程

1. 检查 `"private": true` → 拒绝发布
2. 执行 `prepublish` 脚本
3. 编译项目
4. 打包 JAR
5. 生成 POM 文件
6. 上传到 Maven 仓库（JAR + POM）
7. 执行 `postpublish` 脚本

### Maven 坐标提取

从 `package.json` 的 `name` 字段提取 groupId 和 artifactId：

| name 格式 | groupId | artifactId |
|-----------|---------|------------|
| `com.example:my-lib` | `com.example` | `my-lib` |
| `my-lib`（无冒号） | 从 `package` 字段推导 | `my-lib` |

**推荐：** 始终使用 `groupId:artifactId` 格式的 name，避免 groupId 推导歧义。

### POM 生成

从 `package.json` 映射：

| package.json | POM |
|-------------|-----|
| `name`（冒号前） | `<groupId>` |
| `name`（冒号后） | `<artifactId>` |
| `version` | `<version>` |
| `description` | `<description>` |
| `license` | `<license>` |
| `dependencies` | `<dependencies>` |

### 仓库选择

1. `package.json` 的 `registries` 中查找 `"default"` 键
2. 无 `"default"` → 使用 `registries` 中第一个仓库
3. 无 `registries` → 报错（不默认推到 Maven Central）

## `ym login`

```bash
ym login                                 # 交互式输入仓库 URL + 凭证
```

凭证存储在 `.ym/credentials.json`（文件权限 0o600）：

```json
{
  "https://maven.example.com": {
    "username": "deploy",
    "password": "token_xxx"
  }
}
```

**安全措施：**
- 文件权限设置为 600（仅所有者可读写，Unix）
- `.gitignore` 应包含 `.ym/credentials.json`

## `ym link`

本地跨项目开发（类似 `npm link`）。

```bash
# 在库项目中注册
cd my-lib && ym link

# 在消费项目中引用
cd my-app && ym link my-lib

# 查看已链接
ym link --list

# 解除链接
ym link --unlink my-lib
```

### 链接机制

1. `ym link`（无参数）：在 `~/.ym/links/` 下创建符号链接，指向当前项目的 `out/classes/`
2. `ym link <name>`：在当前项目中，将 `<name>` 的链接目录加入 classpath
3. 平台适配：Unix 使用 `symlink`，Windows 使用 `junction`

## 已知限制

| 问题 | 严重性 |
|------|--------|
| 不支持 GPG 签名（Maven Central 要求） | 高 |
| 不支持 Javadoc JAR 上传 | 中 |
| 不支持 Sources JAR 上传 | 中 |
| 不生成 SHA-256 校验文件上传 | 中 |
| POM 不含 parent/dependencyManagement | 低 |
| link 不支持传递依赖 | 低 |
| prepublish/postpublish 脚本钩子未实现 | 中 |

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

```json
{
  "registries": {
    "github": "https://maven.pkg.github.com/OWNER/REPO"
  }
}
```

### P3 — 凭证环境变量

支持环境变量配置凭证（避免文件存储）：

```bash
export YM_REGISTRY_USERNAME=deploy
export YM_REGISTRY_PASSWORD=token_xxx
export YM_REGISTRY_TOKEN=ghp_xxx          # Bearer token 模式
```
