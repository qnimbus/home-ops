# Home Lab

A bare-metal **Talos Linux** Kubernetes cluster managed entirely by **GitOps (FluxCD)**.
Infrastructure-as-Code only: no manual `kubectl apply`, no imperative changes that aren't reflected in
Git. Three control-plane nodes (scheduling enabled, no dedicated workers) run Cilium (kube-proxy
replacement), CoreDNS, cert-manager, External Secrets + 1Password Connect, and an application stack
deployed via Helm + Flux.

- **Provisioning:** `talhelper` renders Talos machine configs from [`talos/talconfig.yaml`](talos/talconfig.yaml); `go-task` drives the workflow (`task` lists all targets).
- **GitOps:** Flux reconciles [`kubernetes/`](kubernetes/) from this repo; bootstrap is via Helmfile.
- **Secrets:** two-tier — SOPS+age for Talos secrets, External Secrets Operator + 1Password for app secrets.

## Documentation

Start at the **[documentation index](docs/README.md)** — it lists every doc by audience (👤 human /
🤖 agent) and status, and includes a source-of-truth map. Quick links:

| Doc | What it covers |
|-----|----------------|
| [docs/CLUSTER.md](docs/CLUSTER.md) | Current-state reference: hardware, networks, components, FluxCD layout, **bootstrap runbook** |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Backlog and in-progress work |
| [docs/HARDWARE-ARCHITECTURE.md](docs/HARDWARE-ARCHITECTURE.md) | Planned 5-node + Rook-Ceph expansion |
| [docs/QA.md](docs/QA.md) · [docs/BOOT-ISSUE-TROUBLESHOOTING.md](docs/BOOT-ISSUE-TROUBLESHOOTING.md) | Operational gotchas and recovery runbooks |
| [CLAUDE.md](CLAUDE.md) | Agent operating rules and repo conventions |

---

## Getting Started

### Option A — Dev Container (recommended)

Requires: VS Code + [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers), Docker Desktop (or equivalent), WSL2.

Before opening the container, export your 1Password service account token in your **WSL2 host shell** (e.g. `~/.bashrc`). If you don't have a service account yet, [create one in 1Password](https://developer.1password.com/docs/service-accounts/get-started/):

```sh
export OP_SERVICE_ACCOUNT_TOKEN="<your-service-account-token>"
```

Docker reads `localEnv` variables at container creation time. If this is unset when the container starts, all `op` CLI calls inside the container will fail with a misleading auth error.

Then open the repo in VS Code and choose **Reopen in Container**. The `postCreateCommand` will:

- Install all tools via `mise` (versions pinned in `.mise.toml`)
- Install the `helm-diff` plugin (required by helmfile)
- Set `SOPS_AGE_KEY_FILE`, `KUBECONFIG`, and `TALOSCONFIG` automatically via `remoteEnv`
- Forward `OP_SERVICE_ACCOUNT_TOKEN` from the WSL2 host into the container

---

### Option B — mise directly (WSL2 / Linux)

Requires: [mise](https://mise.jdx.dev/) installed in your shell.

**1. Install tools**

```sh
mise trust
mise install
```

All tools (kubectl, talosctl, talhelper, sops, age, helmfile, helm, flux, task, gh, op) are pinned in `.mise.toml`.

**2. Install the helm-diff plugin** (required by helmfile; one-time)

```sh
helm plugin install https://github.com/databus23/helm-diff --verify=false
```

**3. Export required environment variables** in your `~/.bashrc` (or `~/.profile`):

```sh
# 1Password service account — used by bootstrap:age-key and bootstrap:flux-github-app tasks
# See: https://developer.1password.com/docs/service-accounts/get-started/
export OP_SERVICE_ACCOUNT_TOKEN="<your-service-account-token>"
```

`SOPS_AGE_KEY_FILE`, `KUBECONFIG`, and `TALOSCONFIG` are set automatically by the root
`Taskfile.yaml` for all `task` invocations. If you invoke `sops`, `kubectl`, or `talosctl`
directly from the shell (outside of `task`), add these too:

```sh
export SOPS_AGE_KEY_FILE="$(pwd)/age.key"
export KUBECONFIG="$(pwd)/kubeconfig"
export TALOSCONFIG="$(pwd)/talos/clusterconfig/talosconfig"
```

**4. Verify**

```sh
task   # lists all available tasks
op whoami
```
