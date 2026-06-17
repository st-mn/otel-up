# istio-up

```bash
#!/usr/bin/env bash
set -euo pipefail

helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null 2>&1 || true
helm repo add kiali https://kiali.org/helm-charts >/dev/null 2>&1 || true
helm repo update

kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -

# If CRDs already exist from a previous failed install, ensure ownership matches this release.
for crd in \
  authorizationpolicies.security.istio.io \
  destinationrules.networking.istio.io \
  envoyfilters.networking.istio.io \
  gateways.networking.istio.io \
  peerauthentications.security.istio.io \
  proxyconfigs.networking.istio.io \
  requestauthentications.security.istio.io \
  serviceentries.networking.istio.io \
  sidecars.networking.istio.io \
  telemetries.telemetry.istio.io \
  trafficextensions.extensions.istio.io \
  virtualservices.networking.istio.io \
  wasmplugins.extensions.istio.io \
  workloadentries.networking.istio.io \
  workloadgroups.networking.istio.io

do
  kubectl annotate crd "$crd" \
    meta.helm.sh/release-name=istio-base \
    meta.helm.sh/release-namespace=istio-system \
    --overwrite >/dev/null 2>&1 || true
done

helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set operator.replicas=1 \
  --wait --timeout 10m

helm upgrade --install istio-base istio/base \
  --namespace istio-system \
  --wait --timeout 10m

helm upgrade --install istiod istio/istiod \
  --namespace istio-system \
  --wait --timeout 10m

helm upgrade --install istio-ingressgateway istio/gateway \
  --namespace istio-system \
  --wait --timeout 10m

helm upgrade --install kiali kiali/kiali-server \
  --namespace istio-system \
  --wait --timeout 10m

kubectl get pods -n kube-system | grep -E "cilium|hubble" || true
kubectl get pods -n istio-system

echo
echo "Deployment complete."
echo "Starting port-forwards..."
kubectl port-forward -n kube-system svc/hubble-ui 8081:80 >/dev/null 2>&1 &
kubectl port-forward -n istio-system svc/kiali 20001:20001 >/dev/null 2>&1 &
echo "Hubble Dashboard: http://localhost:8081"
echo "Kiali Dashboard:  http://localhost:20001"
```

# istio-down

```bash
#!/usr/bin/env bash
set -euo pipefail

# Stop any local port-forwards started by the up script.
pkill -f "port-forward -n kube-system svc/hubble-ui 8081:80" || true
pkill -f "port-forward -n istio-system svc/kiali 20001:20001" || true

# Uninstall app-level components first.
helm uninstall kiali -n istio-system || true
helm uninstall istio-ingressgateway -n istio-system || true
helm uninstall istiod -n istio-system || true
helm uninstall istio-base -n istio-system || true
helm uninstall cilium -n kube-system || true

# Optional cleanup of Istio CRDs and namespace to get back to a pristine state.
kubectl delete crd \
  authorizationpolicies.security.istio.io \
  destinationrules.networking.istio.io \
  envoyfilters.networking.istio.io \
  gateways.networking.istio.io \
  peerauthentications.security.istio.io \
  proxyconfigs.networking.istio.io \
  requestauthentications.security.istio.io \
  serviceentries.networking.istio.io \
  sidecars.networking.istio.io \
  telemetries.telemetry.istio.io \
  trafficextensions.extensions.istio.io \
  virtualservices.networking.istio.io \
  wasmplugins.extensions.istio.io \
  workloadentries.networking.istio.io \
  workloadgroups.networking.istio.io \
  --ignore-not-found=true || true

kubectl delete namespace istio-system --ignore-not-found=true

echo "Teardown complete."
```
