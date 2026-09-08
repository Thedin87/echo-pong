## Kubernetes Deployment

The manifests in `k8s/` deploy the service to Docker Desktop Kubernetes with an NGINX Ingress.
The container image is the multi-architecture GHCR image `ghcr.io/thedin87/echo-pong`.
The Deployment prefers ARM64 nodes when available and falls back to AMD64 nodes, so it also
works on Docker Desktop's usual AMD64 Kubernetes node.

### Prerequisites

- Docker Desktop with Kubernetes enabled
- `kubectl` configured for the Docker Desktop context
- An NGINX Ingress controller installed in the cluster
- A published GHCR image tagged with the version configured in `k8s/kustomization.yaml`

### Go version

Go 1.25 is used instead of Go 1.24 because Trivy found 19 high-severity Go standard-library
vulnerabilities in Go 1.24.13. The reported fixes are available in patched Go 1.25.x releases;
there were no critical findings. The Go builder image and `go.mod` are therefore pinned to Go
1.25 to reduce the vulnerability exposure.

The Ingress uses class `nginx` and host `ping-pong.local`. If an NGINX controller is not
already installed, install one using the controller's official instructions before applying
these manifests.

### Configure the image

The default image tag is `v1.0.0`. Set it to a published release before deployment:

```bash
cd echo-pong
sed -i.bak 's/newTag: v1.0.0/newTag: v1.2.3/' k8s/kustomization.yaml
rm -f k8s/kustomization.yaml.bak
```

On Windows, edit `newTag` in `k8s/kustomization.yaml` directly.

If the GHCR package is private, create an image-pull Secret and add `imagePullSecrets` to
the Deployment. Do not commit a GitHub token to this repository.

### Create the application Secret

The token is deliberately not stored in Git. Create the Secret in the `ping-pong` namespace:

```bash
kubectl create namespace ping-pong --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ping-pong create secret generic ping-pong-secret \
	--from-literal=ping-pong-token="$(openssl rand -hex 32)" \
	--dry-run=client -o yaml | kubectl apply -f -
```

The Deployment mounts the Secret read-only at `/run/secrets/ping-pong-token`, which is the
path expected by the container. Rotate it by recreating the Secret and restarting the
Deployment:

```bash
kubectl -n ping-pong delete secret ping-pong-secret
kubectl -n ping-pong create secret generic ping-pong-secret \
	--from-literal=ping-pong-token="$(openssl rand -hex 32)"
kubectl -n ping-pong rollout restart deployment/ping-pong
```

For production, use a managed secret solution such as External Secrets or a cloud secret
manager rather than generating the token in a shell command.

### Deploy

Apply all resources with Kustomize:

```bash
kubectl apply -k k8s/
kubectl -n ping-pong rollout status deployment/ping-pong
kubectl -n ping-pong get pods,service,ingress
```

The Deployment has two replicas and a rolling update policy with `maxUnavailable: 0`.
The startup probe allows for the application's documented 10-second startup delay before
readiness and liveness checks control traffic and restarts.

### Configure local Ingress access

Add the Ingress hostname to the local hosts file:

```bash
echo '127.0.0.1 ping-pong.local' | sudo tee -a /etc/hosts
```

If Docker Desktop exposes the Ingress controller through another address, use that address
instead of `127.0.0.1`.

Verify the public health endpoint:

```bash
curl http://ping-pong.local/health
```

Read the token from the local shell only when testing. The Secret value is base64 encoded in
Kubernetes:

```bash
TOKEN=$(kubectl -n ping-pong get secret ping-pong-secret \
	-o jsonpath='{.data.ping-pong-token}' | base64 --decode)
curl -H "Authorization: Bearer $TOKEN" http://ping-pong.local/ping
curl -H "Authorization: Bearer $TOKEN" http://ping-pong.local/pong
```

### Inspect and remove the deployment

```bash
kubectl -n ping-pong describe deployment/ping-pong
kubectl -n ping-pong describe ingress/ping-pong
kubectl -n ping-pong logs deployment/ping-pong
kubectl delete -k k8s/
```
