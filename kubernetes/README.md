# Variables
```bash
# argocd
export ARGOCD_BASE_DOMAIN=domain.com

# external-dns
export EXTERNAL_DNS_CLOUDFLARE_API_TOKEN=
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
```