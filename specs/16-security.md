# 16 — 安全

## 概述

ym 作为构建工具，处于 supply chain 的关键位置。本规格定义依赖完整性、凭证安全和审计能力的要求。

## 依赖完整性

### SHA-256 校验

所有下载的 JAR 文件在首次下载时计算 SHA-256 哈希，记录到内部缓存 `.ym/resolved.json`：

```json
{
  "com.fasterxml.jackson.core:jackson-databind:2.19.0": {
    "sha256": "abc123...",
    "dependencies": [...]
  }
}
```

后续安装时校验本地文件哈希与缓存记录一致。

**命令：** `ym doctor` 的依赖缓存完整性检查包含 SHA-256 校验，`--fix` 时自动重新下载不一致的 JAR。

依赖解析结果缓存在 `.ym/resolved.json`（内部文件），SHA-256 校验确保 JAR 完整性。

### 待实现：GPG 签名验证

Maven Central 的 artifact 通常有 `.asc` GPG 签名。ym 应支持：

1. 下载 `.jar.asc` 签名文件
2. 验证签名（可配置 keyserver 或信任指纹）
3. 验证失败时警告或阻止（可配置严格级别）

## 凭证安全

### 凭证存储

`~/.ym/credentials.json`（全局，文件权限 600）：

```json
{
  "https://maven.example.com": {
    "username": "deploy",
    "password": "token_xxx"
  }
}
```

**安全要求：**
- ✅ 文件权限 600（仅所有者可读写）
- ✅ 凭证文件位于用户 home 目录（`~/.ym/credentials.json`），不在项目目录内，无 git 泄露风险
- 🔲 待实现：支持系统 keychain（macOS Keychain / Windows Credential Manager）
- 🔲 待实现：环境变量 fallback（`YM_REGISTRY_USERNAME` / `YM_REGISTRY_PASSWORD`）

### 待实现：令牌认证

支持 Bearer token 认证（GitHub Packages、GitLab 等）：

```json
{
  "https://maven.pkg.github.com": {
    "token": "ghp_xxx"
  }
}
```

## 构建隔离

### 当前保障

- ym 不执行任何从依赖下载的代码（不像 Gradle 会执行 `build.gradle`）
- `package.toml` 是纯 TOML，无图灵完备性
- 脚本仅在显式 `scripts` 配置下执行

### 风险点

| 风险 | 当前状态 | 缓解 |
|------|---------|------|
| 恶意 JAR 替换 | SHA-256 校验 | 加强：GPG 签名验证 |
| 依赖混淆攻击 | scope 路由已部分缓解（见 02-resolver.md） | 加强：默认阻止未配置 scope 的私有 groupId |
| 脚本注入 | shell 执行 `scripts` | 设计如此，用户自行管控 |
| POM 解析漏洞 | roxmltree 解析 | 定期更新依赖 |

## 已知限制

| 问题 | 严重性 |
|------|--------|
| 无 GPG 签名验证 | 中 |
| 凭证明文存储 | 中 |
| 依赖混淆防护仅限显式配置 scope 的仓库 | 低 |
| 无 SBOM 生成 | 低 |

## 优化路线图

### P0 — 环境变量凭证

支持 `YM_REGISTRY_USERNAME` / `YM_REGISTRY_PASSWORD` / `YM_REGISTRY_TOKEN` 环境变量，避免文件明文存储。

### P1 — GPG 签名验证

下载 `.asc` 文件，使用 `gpg --verify` 或内嵌验证逻辑。

### P2 — SBOM 生成

`ym sbom` 命令生成 CycloneDX 或 SPDX 格式的 Software Bill of Materials。

### P3 — 依赖混淆防护

已在 `registries` 配置中支持 `scope` 规则（见 01-config.md），匹配的 groupId 只从指定仓库解析，不 fallback 到 Maven Central。解析策略见 02-resolver.md。
