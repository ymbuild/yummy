# ym — Modern Java Build Tool

Fast, zero-config Java build tool. Drop-in replacement for Maven/Gradle with npm-style DX.

## Install

**Linux / macOS / Git Bash (Windows):**

```bash
curl -fsSL https://raw.githubusercontent.com/ympkg/yummy/main/install.sh | bash
```

**Windows PowerShell:**

```powershell
irm https://raw.githubusercontent.com/ympkg/yummy/main/install.ps1 | iex
```

Installs `ym` and `ymc` to `~/.ym/bin/`.

## Quick Start

```bash
ym init -y my-app                   # Create project
cd my-app
ym install com.google.guava:guava    # Add dependency
ymc dev                             # Compile + run + hot reload
```

## Why ym?

| | Gradle (2000 modules) | ym (2000 modules) |
|---|---|---|
| Config load | ~20 min (execute 2000 Groovy scripts) | ~2 sec (parse 2000 TOML files) |
| Startup | ~5s (JVM + Daemon) | ~5ms (native binary) |
| Incremental build | ~30s | ~5s |
| Config format | Groovy/Kotlin DSL | Declarative TOML |

## Commands

```bash
# Package manager (ym)
ym install                          # Install all dependencies
ym install <dep>                     # Add dependency
ym uninstall <dep>                   # Remove dependency
ym upgrade                          # Upgrade dependencies
ym tree                             # Show dependency tree

# Compiler & runtime (ymc)
ymc build                           # Compile (incremental)
ymc build --release                 # Build fat JAR
ymc dev                             # Dev mode with hot reload
ymc run                             # Compile and run
ymc test                            # Run tests
ymc idea                            # Generate IntelliJ IDEA project
```

## License

MIT
