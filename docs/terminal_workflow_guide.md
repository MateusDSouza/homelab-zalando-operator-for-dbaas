# Kubernetes Operational: Terminal Workflow Guide

This guide outlines the standard terminal workflow required for interacting with the `zalando-postgres-operator-lab` and the underlying `kind` cluster efficiently. Relying on raw CLI commands is error-prone and slow. While all study notes and runbooks provide explicit, raw commands for clarity, adopting these terminal shortcuts and tools creates a faster, ergonomic workflow for day-to-day exploration and debugging.

---

## Tooling Summary

| Tool | Purpose | Install Command |
| --- | --- | --- |
| **Shell Aliases** | Reduce keystrokes for frequent `kubectl` and `docker` commands | Add to `~/.zshrc` |
| **`kubectx` & `kubens`** | Instant cluster and namespace switching without passing flags | `brew install kubectx` |
| **`k9s`** | Terminal UI dashboard for monitoring, logs, and pod exec | `brew install k9s` |
| **`navi`** | Interactive cheat sheets for complex, multi-variable commands | `brew install navi` |
| **`runme`** | Interactive execution of markdown runbooks directly in VS Code | VS Code Extension |

---

## 1. Foundational Shell Aliases

To reduce friction and typing errors, add the following configuration to your `~/.zshrc` (or `~/.bashrc`):

```bash
# ==========================================
# Kubernetes (kubectl) Aliases
# ==========================================
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias krm='kubectl delete'
alias ka='kubectl apply -f'
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias kex='kubectl exec -it'

# Common "get" shortcuts
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kga='kubectl get all'
alias kgns='kubectl get namespaces'

# Fix for Zsh kubectl auto-completion
compdef __start_kubectl k 2>/dev/null || true

# ==========================================
# Docker Aliases (for kind troubleshooting)
# ==========================================
alias d='docker'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dex='docker exec -it'
```

### Alias Reference

| Alias | Expanded Command | Typical Use Case |
| --- | --- | --- |
| `k` | `kubectl` | Base command entry point |
| `kgp` | `kubectl get pods` | Inspect running pods and readiness |
| `kgs` | `kubectl get svc` | Inspect service endpoints and ports |
| `kgn` | `kubectl get nodes` | Check status of kind cluster nodes |
| `kd` | `kubectl describe` | Deep dive into events and pod failures |
| `klf` | `kubectl logs -f` | Follow live container logs |
| `kex` | `kubectl exec -it` | Open an interactive shell inside a container |
| `dps` | `docker ps` | Verify kind node containers |

### Verification

Reload your shell configuration and verify the alias:

```bash
source ~/.zshrc
k version --client
```

---

## 2. Context & Namespace Management

Explicitly typing `--namespace=<name>` (or `-n <name>`) on every command is an anti-pattern. Use `kubectx` and `kubens` to manage your active context and namespace globally.

### Installation

```bash
brew install kubectx
```

### Usage

- **Switch Kubernetes cluster context:**

```bash
kubectx                  # List available contexts
kubectx kind-pg-lab      # Switch to kind-pg-lab context
kubectx -                # Toggle back to the previous context
```

- **Switch active namespace:**

```bash
kubens                   # List available namespaces
kubens demo              # Lock current shell to 'demo' namespace
kubens default           # Switch back to 'default'
kubens -                 # Toggle back to the previous namespace
```

Once locked into a namespace via `kubens`, standard commands like `kgp` automatically scope to that namespace without additional flags.

---

## 3. Terminal UI (TUI) for Operations: `k9s`

For standard debugging, live log tailing, resource monitoring, and port-forwarding, avoid repetitive CLI invocations in favor of `k9s`.

### Installation

```bash
brew install k9s
```

### Launch & Common Navigation

Start the TUI:

```bash
k9s
```

| Key / Command | Action |
| --- | --- |
| `:pods` | Navigate to Pods view |
| `:svc` | Navigate to Services view |
| `:ns` | Switch namespace view |
| `l` | Tail logs of the selected pod / container |
| `s` | Open an interactive shell inside the selected pod |
| `d` | Describe the selected resource |
| `ctrl + d` | Delete the selected pod |
| `<esc>` | Go back or clear filter |
| `?` | Show all available keyboard shortcuts |

> **Why we use it:** It provides an interactive dashboard to navigate the cluster, view live logs across replicas, and shell into Postgres pods with single keystrokes instead of long, syntax-heavy commands.

---

## 4. Parameterized Command Snippets: `navi`

For complex, multi-variable operations (such as extracting base64-encoded secrets, triggering Patroni switchovers, or pausing worker nodes), this repository includes custom Navi cheat sheets in [`cheats/`](../cheats/). Navi generates interactive, searchable prompts and dynamically fetches cluster variables (like active namespaces, pod names, or secret keys), eliminating manual copy-pasting and syntax errors.

### Installation

```bash
brew install navi
```

### Configuring Navi for this Repository

To make the lab's cheat sheet available in Navi, choose one of the following setup options:

#### Option A: Symlink to Navi's Cheats Directory (Recommended)

From the repository root, symlink the `cheats/` folder directly into Navi's default cheat path:

```bash
mkdir -p "$(navi info cheats-path)"
ln -sfn "$(pwd)/cheats" "$(navi info cheats-path)/zalando-lab"
```

Once linked, running `navi` from anywhere will automatically include all lab snippets.

#### Option B: Configure `NAVI_PATH` in `~/.zshrc`

Add the repository's `cheats/` directory to your `NAVI_PATH` environment variable:

```bash
# Add to ~/.zshrc (replace with your absolute repo path)
export NAVI_PATH="$NAVI_PATH:$HOME/Desktop/zalando-postgres-operator-lab/cheats"
```

Then reload:

```bash
source ~/.zshrc
```

#### Option C: Ad-Hoc Execution

To run Navi pointing directly to the local directory without global configuration:

```bash
navi --path ./cheats
```

### Optional: Shell Widget Keybinding (`Ctrl + G`)

To summon Navi directly from your shell prompt and insert commands inline, append the shell widget to `~/.zshrc`:

```bash
eval "$(navi widget zsh)"
```

### Available Cheat Categories

The [`cheats/zalando-lab.cheat`](../cheats/zalando-lab.cheat) file covers:

- **Credentials & Secrets**: Decode database passwords (`app-owner`, `postgres`) or arbitrary secret keys.
- **Patroni Topology**: Run `patronictl list` / `topology`, inspect leader election ConfigMaps, and watch pod roles.
- **HA & Failover Drills**: Trigger planned switchovers, abruptly kill primary pods, and pause/resume Kind worker nodes.
- **Client Connectivity & Port-Forwarding**: Port-forward Master (`5432`), Replica (`5433`), or PgBouncer pooler (`6432`), and spawn `psql` in `pgclient`.
- **Backups & WAL-G**: List base backups stored in S3/MinIO directly from Spilo containers.
- **Troubleshooting & Logs**: Tail logs for the operator, Spilo instances, and PgBouncer poolers.

---

## 5. Executable Runbooks: `runme`

For sequenced operational tasks (e.g., failover drills, failover probing, and backup drills), this repository provides Runme-compatible Markdown files located in [`lab-run-books/`](../lab-run-books/).

### Recommended Workflow

1. Install the **Runme** extension in VS Code (`stateful.runme`).
2. Open any `.md` file inside [`lab-run-books/`](../lab-run-books/).
3. Execute shell commands safely and in order by clicking the interactive **Run** button directly inside each code block instead of copying and pasting commands into the terminal.
