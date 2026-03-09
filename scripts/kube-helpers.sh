#!/bin/bash
# kube-helpers.sh — useful kubectl shortcuts
# Place in /data/scripts/ on the PVC to persist across pod restarts

# Switch namespace
kns() {
  kubectl config set-context --current --namespace="$1"
  echo "Switched to namespace: $1"
}

# Switch context
kctx() {
  kubectl config use-context "$1"
}

# Tail logs for a deployment
klogs() {
  local deploy=${1:?Usage: klogs <deployment> [namespace]}
  local ns=${2:-$(kubectl config view --minify -o jsonpath='{..namespace}')}
  kubectl logs -f "deployment/${deploy}" -n "${ns}"
}

# Quick pod exec
kexec() {
  local pod=${1:?Usage: kexec <pod> [namespace] [command]}
  local ns=${2:-$(kubectl config view --minify -o jsonpath='{..namespace}')}
  local cmd=${3:-bash}
  kubectl exec -it "${pod}" -n "${ns}" -- "${cmd}"
}

# Show all resources in a namespace
kall() {
  local ns=${1:-$(kubectl config view --minify -o jsonpath='{..namespace}')}
  kubectl get all -n "${ns}"
}

# Test TCP connectivity from pod
tcptest() {
  local host=${1:?Usage: tcptest <host> <port>}
  local port=${2:?Usage: tcptest <host> <port>}
  echo "Testing TCP ${host}:${port}..."
  nc -zv -w5 "${host}" "${port}" && echo "✓ OPEN" || echo "✗ CLOSED/FILTERED"
}

# Test DNS resolution
dnstest() {
  local host=${1:?Usage: dnstest <hostname>}
  echo "Resolving ${host}..."
  dig +short "${host}" || nslookup "${host}"
}

# MySQL quick connect (reads from /data/config/mysql.env if exists)
myconnect() {
  if [ -f /data/config/mysql.env ]; then
    # shellcheck disable=SC1091
    source /data/config/mysql.env
  fi
  mysql -h "${MYSQL_HOST:-localhost}" \
        -P "${MYSQL_PORT:-3306}" \
        -u "${MYSQL_USER:-root}" \
        -p"${MYSQL_PASSWORD:-}" \
        "${MYSQL_DB:-}" "$@"
}

# PostgreSQL quick connect
pgconnect() {
  if [ -f /data/config/pg.env ]; then
    # shellcheck disable=SC1091
    source /data/config/pg.env
  fi
  PGPASSWORD="${PGPASSWORD:-}" psql \
    -h "${PGHOST:-localhost}" \
    -p "${PGPORT:-5432}" \
    -U "${PGUSER:-postgres}" \
    -d "${PGDATABASE:-postgres}" "$@"
}

# MSSQL quick connect via sqlcmd
mssqlconnect() {
  if [ -f /data/config/mssql.env ]; then
    # shellcheck disable=SC1091
    source /data/config/mssql.env
  fi
  sqlcmd \
    -S "${MSSQL_HOST:-localhost},${MSSQL_PORT:-1433}" \
    -U "${MSSQL_USER:-sa}" \
    -P "${MSSQL_PASSWORD:-}" \
    -d "${MSSQL_DB:-master}" "$@"
}

echo "kube-helpers loaded: kns kctx klogs kexec kall tcptest dnstest myconnect pgconnect mssqlconnect"
