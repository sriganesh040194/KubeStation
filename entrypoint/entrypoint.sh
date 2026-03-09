#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# entrypoint.sh — cli-tools pod startup script
# Runs on every pod start. Handles kubeconfig, kubelogin AAD conversion,
# and prints tool inventory before handing off to CMD.
# ═══════════════════════════════════════════════════════════════════════════════
set -e

# ── Colour helpers ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[entrypoint]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }

# ── 1. kubeconfig setup ────────────────────────────────────────────────────────
log "Setting up kubeconfig..."

mkdir -p /data/kube /root/.kube

# Priority: mounted secret > existing PVC config > service account token
if [ -f /etc/kube/config ]; then
    cp /etc/kube/config /data/kube/config
    chmod 600 /data/kube/config
    ok "kubeconfig loaded from secret → /data/kube/config"
elif [ -f /data/kube/config ]; then
    ok "kubeconfig found on PVC → /data/kube/config"
else
    warn "No kubeconfig found — falling back to service account token"
fi

# Symlink so tools that hardcode ~/.kube/config also work
ln -sf /data/kube/config /root/.kube/config 2>/dev/null || true
export KUBECONFIG=/data/kube/config

# ── 2. kubelogin — AAD conversion ─────────────────────────────────────────────
# AUTH_METHOD env var controls the login mode. Set via StatefulSet env or:
#   kubectl set env statefulset/<name> AUTH_METHOD=spn -n <namespace>
# Valid values: workloadidentity | spn | azurecli | msi | devicecode
AUTH_METHOD="${AUTH_METHOD:-workloadidentity}"

if command -v kubelogin &>/dev/null && [ -f /data/kube/config ]; then
    log "Converting kubeconfig for AAD (method: ${AUTH_METHOD})..."

    case "$AUTH_METHOD" in
      spn)
        # Requires: AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID env vars
        kubelogin convert-kubeconfig -l spn \
          --client-id "${AZURE_CLIENT_ID:-}" \
          --client-secret "${AZURE_CLIENT_SECRET:-}" \
          --tenant-id "${AZURE_TENANT_ID:-}" \
          2>/dev/null && ok "kubelogin: SPN conversion done" \
          || warn "kubelogin SPN conversion failed — check AZURE_CLIENT_ID/SECRET/TENANT_ID"
        ;;
      msi)
        kubelogin convert-kubeconfig -l msi \
          2>/dev/null && ok "kubelogin: MSI conversion done" \
          || warn "kubelogin MSI conversion failed"
        ;;
      azurecli)
        kubelogin convert-kubeconfig -l azurecli \
          2>/dev/null && ok "kubelogin: azurecli conversion done" \
          || warn "kubelogin azurecli conversion failed — az cli may not be available"
        ;;
      devicecode)
        kubelogin convert-kubeconfig -l devicecode \
          2>/dev/null && ok "kubelogin: devicecode conversion done" \
          || warn "kubelogin devicecode conversion failed"
        ;;
      workloadidentity|*)
        kubelogin convert-kubeconfig -l workloadidentity \
          2>/dev/null && ok "kubelogin: workloadidentity conversion done" \
          || warn "kubelogin workloadidentity conversion failed"
        ;;
    esac
else
    warn "kubelogin not found or no kubeconfig present — skipping AAD conversion"
fi

# ── 3. Restore user scripts from PVC ──────────────────────────────────────────
# /data/scripts is a persistent volume — any .sh files placed there
# are sourced into PATH automatically on every startup
if [ -d /data/scripts ] && [ "$(ls -A /data/scripts/*.sh 2>/dev/null)" ]; then
    log "Found user scripts in /data/scripts — adding to PATH"
    export PATH="/data/scripts:$PATH"
    chmod +x /data/scripts/*.sh 2>/dev/null || true
fi

# ── 4. Restore custom bashrc/aliases from PVC ─────────────────────────────────
if [ -f /data/config/.bashrc_extra ]; then
    log "Sourcing /data/config/.bashrc_extra..."
    # shellcheck disable=SC1091
    source /data/config/.bashrc_extra || warn "Failed to source .bashrc_extra"
fi

# ── 5. Print tool inventory ────────────────────────────────────────────────────
v() { $1 "${2:---version}" 2>/dev/null | head -1 | tr -d '\n' || echo "not found"; }

POD_NAMESPACE="${POD_NAMESPACE:-$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null || echo 'unknown')}"
POD_NAME="${POD_NAME:-${HOSTNAME:-unknown}}"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
printf "║  %-54s║\n" "${POD_NAME} — ${POD_NAMESPACE}"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  %-22s %-33s║\n" "KUBERNETES" ""
printf "║  %-22s %-33s║\n" "kubectl:"     "$(kubectl version --client --short 2>/dev/null | tr -d '\n' || echo 'not found')"
printf "║  %-22s %-33s║\n" "kubelogin:"   "$(kubelogin --version 2>/dev/null | tr -d '\n' || echo 'not found')"
printf "║  %-22s %-33s║\n" "helm:"        "$(helm version --short 2>/dev/null | tr -d '\n' || echo 'not found')"
printf "║  %-22s %-33s║\n" "k9s:"         "$(k9s version --short 2>/dev/null | tr -d '\n' || echo 'not found')"
printf "║  %-22s %-33s║\n" "oc:"          "$(oc version --client 2>/dev/null | head -1 | tr -d '\n' || echo 'not found')"
printf "║  %-22s %-33s║\n" "NETWORK" ""
printf "║  %-22s %-33s║\n" "curl:"        "$(curl --version 2>/dev/null | head -1 | awk '{print $1,$2}' || echo 'not found')"
printf "║  %-22s %-33s║\n" "nmap:"        "$(nmap --version 2>/dev/null | head -1 || echo 'not found')"
printf "║  %-22s %-33s║\n" "dig/nslookup:" "$(dig -v 2>&1 | head -1 || echo 'not found')"
printf "║  %-22s %-33s║\n" "az:"          "$(az version --query '\"azure-cli\"' -o tsv 2>/dev/null | tr -d '\n' || echo 'not found')"
printf "║  %-22s %-33s║\n" "SSH/SFTP" ""
printf "║  %-22s %-33s║\n" "ssh:"         "$(ssh -V 2>&1 | tr -d '\n' || echo 'not found')"
printf "║  %-22s %-33s║\n" "lftp:"        "$(lftp --version 2>/dev/null | head -1 || echo 'not found')"
printf "║  %-22s %-33s║\n" "DATABASE" ""
printf "║  %-22s %-33s║\n" "mysql:"       "$(mysql --version 2>/dev/null | tr -d '\n' || echo 'not found')"
printf "║  %-22s %-33s║\n" "psql:"        "$(psql --version 2>/dev/null | tr -d '\n' || echo 'not found')"
printf "║  %-22s %-33s║\n" "sqlcmd:"      "$(sqlcmd -? 2>/dev/null | head -1 | tr -d '\n' || echo 'not found')"
printf "║  %-22s %-33s║\n" "redis-cli:"   "$(redis-cli --version 2>/dev/null | tr -d '\n' || echo 'not found')"
printf "║  %-22s %-33s║\n" "sqlite3:"     "$(sqlite3 --version 2>/dev/null | tr -d '\n' || echo 'not found')"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  %-22s %-33s║\n" "Auth method:" "${AUTH_METHOD}"
printf "║  %-22s %-33s║\n" "KUBECONFIG:"  "${KUBECONFIG}"
printf "║  %-22s %-33s║\n" "Context:"     "$(kubectl config current-context 2>/dev/null | cut -c1-32 || echo 'none')"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── 6. Cluster connectivity check ─────────────────────────────────────────────
log "Testing cluster connectivity..."
kubectl cluster-info 2>/dev/null && ok "Cluster reachable" \
  || warn "Cluster unreachable — check kubelogin auth method (AUTH_METHOD=${AUTH_METHOD})"

echo ""
log "Pod ready. Exec in with: kubectl exec -it ${POD_NAME} -n ${POD_NAMESPACE} -- bash"
echo ""

# ── Hand off to CMD (default: tail -f /dev/null to keep pod alive) ─────────────
exec "$@"
