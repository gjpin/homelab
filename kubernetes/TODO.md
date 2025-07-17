- automated upgrades (https://docs.k3s.io/upgrades/automated)
- check if created ingresses match the ones created manually
- order of installataion (dependency between apps)
- confirm if traefik service/ingress should be in kube-system
- confirm if dns records created by external-dns have expected IP


# check if created ingresses match the ones created manually
## ArgoCD
```yaml
# https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/#option-2-ssl-termination-at-ingress-controller
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-http-ingress
  namespace: argocd
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/service.serversscheme: "http"
    cert-manager.io/cluster-issuer: letsencrypt-prod
    external-dns.alpha.kubernetes.io/hostname: argocd.${BASE_DOMAIN}
spec:
  ingressClassName: traefik
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: http
    host: argocd.${BASE_DOMAIN}
  tls:
  - hosts:
    - argocd.${BASE_DOMAIN}
    secretName: argocd-ingress-http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-grpc-ingress
  namespace: argocd
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/service.serversscheme: "h2c"
    cert-manager.io/cluster-issuer: letsencrypt-prod
    external-dns.alpha.kubernetes.io/hostname: grpc.argocd.${BASE_DOMAIN}
spec:
  ingressClassName: traefik
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: https
    host: grpc.argocd.${BASE_DOMAIN}
  tls:
  - hosts:
    - grpc.argocd.${BASE_DOMAIN}
    secretName: argocd-ingress-grpc
---
```

## hyperdx
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hyperdx-app-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$1
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  rules:
    - host: hyperdx.${BASE_DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <service-name>
                port:
                  number: 3000
  tls:
    - hosts:
        - hyperdx.${BASE_DOMAIN}
      secretName: hyperdx-tls
```

## longhorn
```yaml
# https://longhorn.io/kb/troubleshooting-traefik-2.x-as-ingress-controller/
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: svc-longhorn-headers
  namespace: longhorn-system
spec:
  headers:
    customRequestHeaders:
      X-Forwarded-Proto: "https"
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: longhorn-ingress
  namespace: longhorn-system
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/router.middlewares: longhorn-system-svc-longhorn-headers@kubernetescrd
    cert-manager.io/cluster-issuer: letsencrypt-prod
    external-dns.alpha.kubernetes.io/hostname: longhorn.${BASE_DOMAIN}
spec:
  ingressClassName: traefik
  rules:
  - host: longhorn.${BASE_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: longhorn-frontend
            port:
              number: 80
  tls:
  - hosts:
    - longhorn.${BASE_DOMAIN}
    secretName: longhorn-ingress-http
---
```