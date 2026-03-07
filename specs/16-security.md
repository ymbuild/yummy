# 16 — 安全

## 概述

ym 作为构建工具，处于 supply chain 的关键位置。本规格定义依赖完整性、凭证安全和审计能力的要求。

## 依赖完整性

### SHA-256 校验

所有下载的 JAR 文件在首次下载时计算 SHA-256 哈希，记录到 `package-lock.json`：

```json
{
  "com.fasterxml.jackson.core:jackson-databind:2.19.0": {
    "sha256": "abc123...",
    "dependencies": [...]
  }
}
```

后续安装时校验本地文件哈希与锁文件一致。

**命令：**
```bash
ym verify                                # 校验所有缓存 JAR 的 SHA-256
```

### 锁文件保护

- `ym install` 不自动修改锁文件（除非依赖列表变更）
- `ym lock --check` 仅检查锁文件是否最新，不修改（适合 CI）
- 锁文件应提交到版本控制

### 待实现：GPG 签名验证

Maven Central 的 artifact 通常有 `.asc` GPG 签名。ym 应支持：

1. 下载 `.jar.asc` 签名文件
2. 验证签名（可配置 keyserver 或信任指纹）
3. 验证失败时警告或阻止（可配置严格级别）

## 漏洞审计

### `ym audit`

使用 OSV.dev API 检查依赖的已知漏洞：

```bash
ym audit                                 # 检查所有依赖
ym audit --json                          # JSON 输出（CI 集成）
```

**流程：**
1. 收集所有 Maven 坐标（来自锁文件）
2. 构建 OSV API 请求（`pkg:maven/groupId/artifactId@version`）
3. 返回已知 CVE 列表
4. 按严重性分类输出

### 审计策略

| 严重性 | 行为 |
|--------|------|
| CRITICAL / HIGH | 报告并返回非零退出码 |
| MEDIUM | 报告，不影响退出码 |
| LOW | 仅 `--verbose` 时报告 |

### 待实现：CI 自动审计

```json
{
  "scripts": {
    "preinstall": "ym audit --fail-on high"
  }
}
```

## 凭证安全

### 凭证存储

`.ym/credentials.json`：

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
- ✅ 不应提交到版本控制（`.gitignore` 包含 `.ym/credentials.json`）
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
- `package.json` 是纯 JSON，无图灵完备性
- 脚本仅在显式 `scripts` 配置下执行

### 风险点

| 风险 | 当前状态 | 缓解 |
|------|---------|------|
| 恶意 JAR 替换 | SHA-256 校验 | 加强：GPG 签名验证 |
| 依赖混淆攻击 | 无命名空间保护 | 加强：配置私有仓库优先级 |
| 脚本注入 | shell 执行 `scripts` | 设计如此，用户自行管控 |
| POM 解析漏洞 | roxmltree 解析 | 定期更新依赖 |

## 已知限制

| 问题 | 严重性 |
|------|--------|
| 无 GPG 签名验证 | 中 |
| 凭证明文存储 | 中 |
| 无依赖混淆防护 | 中 |
| 审计仅基于 OSV.dev | 低 |
| 无 SBOM 生成 | 低 |

## 优化路线图

### P0 — 环境变量凭证

支持 `YM_REGISTRY_USERNAME` / `YM_REGISTRY_PASSWORD` / `YM_REGISTRY_TOKEN` 环境变量，避免文件明文存储。

### P1 — GPG 签名验证

下载 `.asc` 文件，使用 `gpg --verify` 或内嵌验证逻辑。

### P2 — SBOM 生成

`ym sbom` 命令生成 CycloneDX 或 SPDX 格式的 Software Bill of Materials。

### P3 — 依赖混淆防护

配置 `registries` 时支持 scope 规则：指定 groupId 前缀只从特定仓库解析。
```json
{
  "registries": {
    "internal": {
      "url": "https://maven.internal.com",
      "scope": "com.mycompany.*"
    }
  }
}
```
