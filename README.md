# KubeStation

> A batteries-included CLI toolbox that runs as a pod inside your Kubernetes cluster.

[![Build & Release](https://github.com/sriganesh040194/KubeStation/actions/workflows/release.yml/badge.svg)](https://github.com/sriganesh040194/KubeStation/actions/workflows/release.yml)
[![GitHub Container Registry](https://img.shields.io/badge/ghcr.io-kubestation-blue?logo=github)](https://ghcr.io/sriganesh040194/kubestation)

KubeStation is a Docker image designed to run as a long-lived pod in your AKS cluster. It gives you instant access to Kubernetes management tools, network diagnostics, database clients, and Azure CLI — all pre-installed, pre-configured, and ready to use the moment you `kubectl exec` in.

No initContainers. No runtime downloads. No setup friction.

---

## What's inside

| Category | Tools |
| --- | --- |
| **Kubernetes** | `kubectl`, `kubelogin`, `helm`, `k9s`, `oc` (OpenShift CLI) |
| **Azure** | `az` (Azure CLI) |
| **Network** | `curl`, `wget`, `dig`, `nslookup`, `ping`, `traceroute`, `nmap`, `netcat`, `mtr`, `iperf3`, `tcpdump`, `socat`, `telnet` |
| **SSH / SFTP** | `ssh`, `scp`, `sftp`, `sshpass`, `lftp` |
| **Database** | `mysql` (MariaDB), `psql` (PostgreSQL), `sqlcmd` + `bcp` (MSSQL), `redis-cli`, `sqlite3` |
| **Utilities** | `jq`, `yq`, `vim`, `nano`, `git`, `python3`, `htop`, `tree`, `watch`, `lsof`, `strace` |

---

## Pull the image

```bash
docker pull ghcr.io/sriganesh040194/kubestation:latest
```

The image is published automatically to GitHub Container Registry on every release. See all available tags on the [packages page](https://github.com/sriganesh040194/KubeStation/pkgs/container/kubestation).

---

## Quick start

### 1. Create a kubeconfig Secret

The pod reads your kubeconfig from a Kubernetes Secret at startup:

```bash
kubectl create secret generic kubeconfig \
  --from-file=config=$HOME/.kube/config \
  -n <your-namespace>
```

### 2. Deploy

**Persistent mode** (default) — `/data` is backed by a 5Gi PVC. Kubeconfig, scripts, and config survive pod restarts.

```bash
kubectl apply -f statefulset.yaml -n <your-namespace>
```

**Ephemeral mode** — `/data` is an `emptyDir`, lost on restart. Use for one-off debugging or CI runners.

```bash
kubectl apply -f deployment.yaml -n <your-namespace>
```

### 3. Exec in

```bash
kubectl exec -it kubestation-0 -n <your-namespace> -- bash
```

You'll be greeted with a tool inventory banner and a ready shell.

---

## Persistent storage layout

Everything under `/data` survives pod restarts:

```
/data/
  kube/         ← kubeconfig (copied from Secret on startup)
  scripts/      ← your custom .sh scripts (auto-added to PATH)
  config/       ← .bashrc_extra, mysql.env, pg.env, mssql.env
  workspace/    ← scratch space, manifests, notes
```

Drop files here to persist them across sessions:

```bash
# Copy a script to the PVC
kubectl cp my-script.sh <namespace>/kubestation-0:/data/scripts/

# Add personal aliases (loaded on every startup)
kubectl exec -it kubestation-0 -n <namespace> -- bash -c \
  "echo 'alias ll=\"ls -la\"' >> /data/config/.bashrc_extra"
```

---

## AAD Authentication

Set the `AUTH_METHOD` environment variable to control how `kubelogin` authenticates:

| Value | Description |
| --- | --- |
| `azurecli` | Uses an existing `az login` session **(default)** |
| `workloadidentity` | Federated/managed pod identity — requires `AZURE_CLIENT_ID` |
| `spn` | Service Principal — requires `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` |
| `msi` | Managed Service Identity |
| `devicecode` | Interactive device code flow |

**Using `azurecli` (default):** exec into the pod and run `az login` once. Credentials are cached in `/data` and reused across restarts.

**Using `spn`:** create a Secret and uncomment the env block in `statefulset.yaml`:

```bash
kubectl create secret generic kubestation-spn -n <namespace> \
  --from-literal=client-id=<appId> \
  --from-literal=client-secret=<password> \
  --from-literal=tenant-id=<tenantId>
```

To switch auth method on a running pod without redeploying:

```bash
kubectl set env statefulset/kubestation AUTH_METHOD=devicecode -n <namespace>
```

---

## Helper functions

Source [scripts/kube-helpers.sh](scripts/kube-helpers.sh) for convenience functions:

```bash
source /usr/local/share/cli-tools/scripts/kube-helpers.sh
```

Or copy it to `/data/scripts/` to auto-load on every pod start.

| Function | Usage | Description |
| --- | --- | --- |
| `kns` | `kns my-namespace` | Switch current namespace |
| `kctx` | `kctx my-cluster` | Switch kube context |
| `klogs` | `klogs my-deploy [ns]` | Tail logs for a deployment |
| `kexec` | `kexec my-pod [ns] [cmd]` | Exec into a pod |
| `kall` | `kall [ns]` | `kubectl get all` in a namespace |
| `tcptest` | `tcptest mydb.internal 5432` | Test TCP connectivity |
| `dnstest` | `dnstest mydb.internal` | DNS resolution check |
| `myconnect` | `myconnect` | Quick MySQL connect (reads `/data/config/mysql.env`) |
| `pgconnect` | `pgconnect` | Quick PostgreSQL connect (reads `/data/config/pg.env`) |
| `mssqlconnect` | `mssqlconnect` | Quick MSSQL connect via sqlcmd (reads `/data/config/mssql.env`) |

**DB env file example** (`/data/config/pg.env`):

```bash
PGHOST=mydb.internal
PGPORT=5432
PGUSER=myuser
PGPASSWORD=secret
PGDATABASE=mydb
```

---

## Building locally

```bash
# Build
make build

# Build + push
make release

# Force rebuild without Docker cache
make rebuild
```

Override defaults as needed:

```bash
make release REGISTRY=ghcr.io/sriganesh040194 TAG=v1.2.0
```

---

## Updating tool versions

Edit the `ARG` values at the top of [Dockerfile](Dockerfile):

```dockerfile
ARG HELM_VERSION=3.17.1
ARG K9S_VERSION=v0.32.7
ARG OC_VERSION=4.17.0
ARG KUBELOGIN_VERSION=v0.2.15
```

Then rebuild and push — or just tag a new release to trigger the GitHub Actions workflow.

---

## Releases

Releases are automated via [GitHub Actions](.github/workflows/release.yml). Push a version tag to build, push, and publish a GitHub Release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

This publishes the following image tags:

- `ghcr.io/sriganesh040194/kubestation:1.0.0`
- `ghcr.io/sriganesh040194/kubestation:1.0`
- `ghcr.io/sriganesh040194/kubestation:1`
- `ghcr.io/sriganesh040194/kubestation:latest`

---

## Repository structure

```
KubeStation/
├── Dockerfile                  ← multi-stage build (downloader + final)
├── Makefile                    ← build / push / deploy helpers
├── statefulset.yaml            ← persistent mode (StatefulSet + PVC + Service)
├── deployment.yaml             ← ephemeral mode (Deployment + emptyDir)
├── entrypoint/
│   └── entrypoint.sh           ← startup: kubeconfig setup, kubelogin, tool banner
├── scripts/
│   └── kube-helpers.sh         ← shell helper functions
└── .github/
    └── workflows/
        └── release.yml         ← CI: build, push to GHCR, create release
```
