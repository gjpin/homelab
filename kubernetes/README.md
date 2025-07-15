# Variables
```bash
# argocd, traefik
export BASE_DOMAIN=domain.com

# external-dns, cert-manager
export CLOUDFLARE_API_TOKEN=

# cert-manager
export ACME_EMAIL=
```

# Helm repos
```bash
# argo
helm repo add argo https://argoproj.github.io/argo-helm

# cert-manager
helm repo add cert-manager https://charts.jetstack.io

# external-dns
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/

# metrics-server
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/

# longhorn
helm repo add longhorn https://charts.longhorn.io
```

# 
Why cert-manager if Traefik handles certificates generation?
- Traefik certificates are not shared across multiple nodes by default
  - Resolved by using shared volumes
- With shared volumes approach, multiple Traefik instances can try to renew the certs at the same time (race condition)
  - Resolved by having a single node renewing the certs