# KubeStation — CLI Tools Pod Image

A generic Docker image for running a rich CLI environment as a Kubernetes StatefulSet.
All tools are baked into the image — no initContainers, no runtime downloads.

## Tools included

| Category     | Tools |
|---|---|
| Kubernetes   | kubectl, kubelogin, helm, k9s, oc (OpenShift CLI) |
| Network      | curl, wget, dig, nslookup, ping, traceroute, nmap, netcat, mtr, iperf3, tcpdump, socat, telnet |
| SSH / SFTP   | ssh, scp, sftp, sshpass, lftp |
| Database     | mysql (MariaDB client), psql (PostgreSQL), sqlcmd + bcp (MSSQL), redis-cli, sqlite3 |
| Utilities    | jq, yq, vim, nano, git, python3, htop, tree, watch, lsof, strace |

## Persistent data layout (`/data` PVC — 5Gi)

```
/data/
  kube/         ← kubeconfig (copied from Secret on startup)
  scripts/      ← your custom .sh scripts (auto-added to PATH)
  config/       ← .bashrc_extra, mysql.env, pg.env, mssql.env etc.
  workspace/    ← scratch space, manifests, notes
```

Anything written under `/data/` survives pod restarts and redeployments.

## Quick start

### 1. Build the image

```bash
export REGISTRY=your-registry.example.com

make build REGISTRY=$REGISTRY
```

### 2. Push to your registry

```bash
make push REGISTRY=$REGISTRY
```

The `login` Makefile target is a no-op by default — authenticate with your registry first:
```bash
# Azure Container Registry
az acr login --name <registry-name>

# GitHub Container Registry
echo $CR_PAT | docker login ghcr.io -u <username> --password-stdin

# Docker Hub
docker login docker.io
```

### 3. Deploy to Kubernetes

Two modes are available:

**Persistent** (default) — `/data` is backed by a PVC. Survives pod restarts. Use this when you want to save kubeconfig, docker/gh logins, or custom scripts across sessions.

```bash
make deploy REGISTRY=$REGISTRY NAMESPACE=<your-namespace>
```

**Ephemeral** — `/data` is an `emptyDir`, lost on restart. Use for one-off debugging or CI runners.

```bash
make deploy REGISTRY=$REGISTRY NAMESPACE=<your-namespace> MANIFEST=deployment.yaml
```

Both commands patch the image reference via `sed` and apply with `kubectl`.

### 4. Exec into the pod

```bash
make exec NAMESPACE=<your-namespace>
```

## AAD Authentication (kubelogin)

Set `AUTH_METHOD` env var in the StatefulSet to control kubelogin mode:

| AUTH_METHOD        | Use case |
|---|---|
| `workloadidentity` | Pod has a federated/managed identity (default) |
| `spn`              | Service Principal — needs AZURE_CLIENT_ID/SECRET/TENANT_ID |
| `msi`              | Managed Service Identity |
| `azurecli`         | Uses `az cli` token (interactive) |
| `devicecode`       | Device code flow (interactive) |

For SPN auth, create a Secret and uncomment the env block in `statefulset.yaml`:
```bash
kubectl create secret generic cli-tools-spn -n <namespace> \
  --from-literal=client-id=<appId> \
  --from-literal=client-secret=<password> \
  --from-literal=tenant-id=<tenantId>
```

## Persisting your own scripts and config

```bash
# Copy a custom script to the PVC
kubectl cp my-script.sh <namespace>/<pod-name>:/data/scripts/my-script.sh

# Add personal aliases
kubectl exec -it <pod-name> -n <namespace> -- bash -c \
  "echo 'alias ll=\"ls -la\"' >> /data/config/.bashrc_extra"

# Store DB connection details (read by kube-helpers.sh)
kubectl exec -it <pod-name> -n <namespace> -- bash -c \
  "cat > /data/config/mysql.env <<'EOF'
MYSQL_HOST=my-db.example.com
MYSQL_USER=dbadmin
MYSQL_PASSWORD=changeme
MYSQL_DB=mydb
EOF"
```

## Updating tool versions

Edit the `ARG` values at the top of `Dockerfile`:
```dockerfile
ARG HELM_VERSION=3.17.1
ARG K9S_VERSION=v0.32.7
ARG OC_VERSION=4.17.0
ARG KUBELOGIN_VERSION=v0.2.15
```
Then rebuild: `make rebuild REGISTRY=$REGISTRY && make push REGISTRY=$REGISTRY && make deploy REGISTRY=$REGISTRY`

## File structure

```
KubeStation/
├── Dockerfile              ← multi-stage build
├── Makefile                ← build/push/deploy helpers
├── statefulset.yaml        ← StatefulSet + headless Service
├── entrypoint/
│   └── entrypoint.sh       ← startup: kubeconfig + kubelogin + inventory
└── scripts/
    └── kube-helpers.sh     ← helper functions (kns, tcptest, myconnect etc.)
```
