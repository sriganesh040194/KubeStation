# ═══════════════════════════════════════════════════════════════════════════════
# KubeStation — generic CLI tools pod
# Base: mcr.microsoft.com/mirror/docker/library/debian:stable-slim
#       (Microsoft's public mirror — no Docker Hub auth required)
# Includes: kubectl, kubelogin, helm, k9s, oc-cli, network tools,
#           SSH/SFTP, MySQL, PostgreSQL, MSSQL (sqlcmd/bcp), Redis, SQLite
# ═══════════════════════════════════════════════════════════════════════════════

# ── Stage 1: Download binary tools ────────────────────────────────────────────
FROM mcr.microsoft.com/mirror/docker/library/debian:stable-slim AS downloader

ARG HELM_VERSION=3.17.1
ARG K9S_VERSION=v0.32.7
ARG OC_VERSION=4.17.0
ARG KUBELOGIN_VERSION=v0.2.15

RUN apt-get update -qq && \
    apt-get upgrade -y -qq && \
    apt-get install -y -qq --no-install-recommends \
      curl \
      ca-certificates \
      unzip \
      tar \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /downloads

# kubectl — from official Kubernetes CDN
RUN KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt) && \
    curl -fsSL -o /downloads/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    chmod +x /downloads/kubectl

# kubelogin — from GitHub releases
RUN curl -fsSL -o /tmp/kubelogin.zip \
      "https://github.com/Azure/kubelogin/releases/download/${KUBELOGIN_VERSION}/kubelogin-linux-amd64.zip" && \
    unzip -q /tmp/kubelogin.zip -d /tmp/kubelogin-extracted && \
    find /tmp/kubelogin-extracted -name 'kubelogin' -type f \
      -exec cp {} /downloads/kubelogin \; && \
    chmod +x /downloads/kubelogin

# helm — from get.helm.sh
RUN curl -fsSL -o /tmp/helm.tar.gz \
      "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" && \
    tar -xzf /tmp/helm.tar.gz -C /tmp --strip-components=1 && \
    cp /tmp/helm /downloads/helm && \
    chmod +x /downloads/helm

# k9s — from GitHub releases (may be blocked in prod; build offline if needed)
RUN curl -fsSL -o /tmp/k9s.tar.gz \
      "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" && \
    tar -xzf /tmp/k9s.tar.gz -C /tmp k9s && \
    cp /tmp/k9s /downloads/k9s && \
    chmod +x /downloads/k9s

# OpenShift CLI (oc) — from Red Hat mirror
RUN curl -fsSL -o /tmp/oc.tar.gz \
      "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OC_VERSION}/openshift-client-linux.tar.gz" && \
    tar -xzf /tmp/oc.tar.gz -C /tmp oc && \
    cp /tmp/oc /downloads/oc && \
    chmod +x /downloads/oc


# ── Stage 2: Final image ───────────────────────────────────────────────────────
FROM mcr.microsoft.com/mirror/docker/library/debian:stable-slim AS final

LABEL maintainer="kubestation"
LABEL description="KubeStation — generic CLI tools pod for AKS: kubectl, kubelogin, helm, oc, network, db"
LABEL org.opencontainers.image.source="https://github.com/sriganesh040194/KubeStation"

ARG DEBIAN_FRONTEND=noninteractive
ARG ACCEPT_EULA=Y

# ── Apply base image security patches ─────────────────────────────────────────
RUN apt-get update -qq && apt-get upgrade -y -qq && rm -rf /var/lib/apt/lists/*

# ── System packages ────────────────────────────────────────────────────────────
RUN apt-get update -qq && \
    # Network tools
    apt-get install -y -qq --no-install-recommends \
      curl \
      wget \
      dnsutils \
      bind9-dnsutils \
      iputils-ping \
      iputils-tracepath \
      traceroute \
      nmap \
      netcat-openbsd \
      net-tools \
      iproute2 \
      tcpdump \
      socat \
      openssl \
      ca-certificates \
      telnet \
      mtr \
      iperf3 \
    && \
    # SSH / SFTP
    apt-get install -y -qq --no-install-recommends \
      openssh-client \
      sshpass \
      lftp \
    && \
    # Database clients (Debian 12 package names)
    apt-get install -y -qq --no-install-recommends \
      default-mysql-client \
      mariadb-client \
      postgresql-client \
      sqlite3 \
      redis-tools \
    && \
    # General utilities
    apt-get install -y -qq --no-install-recommends \
      jq \
      yq \
      vim \
      nano \
      less \
      git \
      unzip \
      zip \
      tar \
      gzip \
      python3 \
      python3-pip \
      procps \
      lsof \
      strace \
      htop \
      tree \
      watch \
      bash-completion \
      gnupg \
      apt-transport-https \
      sudo \
    && \
    rm -rf /var/lib/apt/lists/*

# ── mssql-tools (sqlcmd / bcp) from Microsoft APT repo ────────────────────────
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg && \
    curl -fsSL \
      "https://packages.microsoft.com/config/debian/12/prod.list" \
      -o /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update -qq && \
    ACCEPT_EULA=Y apt-get install -y -qq mssql-tools18 unixodbc-dev 2>/dev/null || \
    ACCEPT_EULA=Y apt-get install -y -qq mssql-tools   unixodbc-dev 2>/dev/null || \
    echo "WARN: mssql-tools unavailable — skipping" && \
    rm -rf /var/lib/apt/lists/*

# ── Copy binary tools from downloader stage ────────────────────────────────────
COPY --from=downloader /downloads/kubectl    /usr/local/bin/kubectl
COPY --from=downloader /downloads/kubelogin  /usr/local/bin/kubelogin
COPY --from=downloader /downloads/helm       /usr/local/bin/helm
COPY --from=downloader /downloads/k9s        /usr/local/bin/k9s
COPY --from=downloader /downloads/oc         /usr/local/bin/oc

# ── Add mssql-tools to PATH ────────────────────────────────────────────────────
RUN echo 'export PATH="$PATH:/opt/mssql-tools18/bin:/opt/mssql-tools/bin"' \
      >> /etc/bash.bashrc

# ── Copy entrypoint and helper scripts ────────────────────────────────────────
COPY scripts/          /usr/local/share/cli-tools/scripts/
COPY entrypoint/       /usr/local/share/cli-tools/entrypoint/
RUN chmod +x /usr/local/share/cli-tools/entrypoint/*.sh \
             /usr/local/share/cli-tools/scripts/*.sh 2>/dev/null || true

# ── Persistent data directories ────────────────────────────────────────────────
# These are the mount points for PVC volumes in the StatefulSet.
# Data written here survives pod restarts.
RUN mkdir -p \
      /data/kube \
      /data/scripts \
      /data/config \
      /data/workspace \
      /root/.kube \
      /root/.ssh

# ── Environment ────────────────────────────────────────────────────────────────
ENV KUBECONFIG=/data/kube/config \
    HOME=/root \
    ACCEPT_EULA=Y \
    PATH="/opt/mssql-tools18/bin:/opt/mssql-tools/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"

# ── Bash config ────────────────────────────────────────────────────────────────
RUN cat >> /root/.bashrc <<'EOF'

# ── cli-tools pod config ─────────────────────────────────────────────────────
export KUBECONFIG=/data/kube/config
export PATH="/opt/mssql-tools18/bin:/opt/mssql-tools/bin:$PATH"

# kubectl aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgn='kubectl get nodes'
alias kns='kubectl config set-context --current --namespace'
alias kctx='kubectl config use-context'

# Source bash completion
source /usr/share/bash-completion/bash_completion 2>/dev/null || true
source <(kubectl completion bash) 2>/dev/null || true
source <(helm completion bash) 2>/dev/null || true

EOF

ENTRYPOINT ["/usr/local/share/cli-tools/entrypoint/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]
