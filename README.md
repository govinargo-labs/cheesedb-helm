# cheesedb Helm chart

Installs the [cheesedb](https://github.com/govinargo-labs/cheesedb) memory server on Kubernetes: one server, one volume, TLS always.

> **Preview.** The server is not released yet, and neither is its image. Sessions approved by a person are still to come, so keep the server inside a cluster you trust.

## What it installs

| Object | What for |
|---|---|
| StatefulSet, 1 pod | `cheesedb serve`. Always one pod: a store has one writer, and its lock file refuses a second server. An update stops the old pod before starting the new one. |
| PersistentVolumeClaim | the store (`/data`), 10 Gi by default |
| Service `<release>-cheesedb`, port 7700 | HTTPS for programs in the cluster |
| Secret `<release>-cheesedb-tls` | the server's certificate (see TLS below) |
| Secret `<release>-cheesedb-admin` | the admin key (see Admin token below) |
| NetworkPolicy (off by default, recommended) | only the pods listed in `networkPolicy.from` reach the server (at least one is required); no traffic out |

The pod runs as a non-root user with a read-only root file system, no added capabilities and no Kubernetes API token, and meets the Kubernetes "restricted" Pod Security Standard. The server calls nothing outside: no model, no other service.

**Turn on the NetworkPolicy.** While it is off, every pod in the cluster can reach the server; a token is still needed, but nothing limits who may try. It is off by default only because it must name your agents' pods, which the chart cannot guess:

```sh
--set networkPolicy.enabled=true --set networkPolicy.from[0].podSelector.matchLabels.app=my-agent
```

Keep `service.type` at `ClusterIP`. `LoadBalancer` or `NodePort` puts the server outside the cluster, often on the internet.

## Install

The chart is published to GitHub's container registry. Needs Helm 3.8 or newer.

```sh
helm install mem oci://ghcr.io/govinargo-labs/charts/cheesedb --version 0.2.0 \
  -n cheesedb --create-namespace
```

It runs the image `ghcr.io/govinargo-labs/cheesedb`, tagged with the chart's `appVersion`.

### Check the signatures

From cheesedb 0.4.1 on, each image is scanned for known vulnerabilities before it is published and signed with [cosign](https://docs.sigstore.dev/) by the workflow that built it. Each new version of this chart is signed the same way. Check them before you install:

```sh
# the image
cosign verify ghcr.io/govinargo-labs/cheesedb:0.4.1 \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github\.com/govinargo-labs/cheesedb/\.github/workflows/image\.yml@refs/'

# the chart
cosign verify ghcr.io/govinargo-labs/charts/cheesedb:<chart version> \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity https://github.com/govinargo-labs/cheesedb-helm/.github/workflows/publish.yaml@refs/heads/main
```

To run exactly the image you checked, even if someone moves its tag, pin its digest (cosign prints it): `--set image.digest=sha256:...`.

| Chart version | Installs cheesedb |
|---|---|
| 0.2.x | 0.4.1 (Go 1.26.11, scanned and signed image) |
| 0.1.x | 0.4.0 |

The chart has its own version: a chart-only fix bumps the patch number (0.1.0 to 0.1.1) and keeps the same cheesedb; a new cheesedb release bumps the minor number (0.2.0). The notes printed after install show how to:
- get the certificate to trust;
- read the admin token;
- reach the server with `kubectl port-forward`:

```sh
kubectl get secret -n cheesedb mem-cheesedb-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > cheesedb-ca.crt
ADMIN=$(kubectl get secret -n cheesedb mem-cheesedb-admin -o jsonpath='{.data.admin-token}' | base64 -d)
kubectl port-forward -n cheesedb svc/mem-cheesedb 7700:7700 &

curl --cacert cheesedb-ca.crt https://localhost:7700/v1/health
# the header comes from stdin, so the token never shows in `ps`
printf 'Authorization: Bearer %s\n' "$ADMIN" |
  curl --cacert cheesedb-ca.crt -H @- -d '{"name":"alice"}' https://localhost:7700/v1/admin/agents
```

Inside the cluster, programs call `https://mem-cheesedb.cheesedb.svc:7700` and trust the same `ca.crt`.

## Try your own build on a laptop (kind)

```sh
docker build -t cheesedb:dev https://github.com/govinargo-labs/cheesedb.git
kind create cluster --name cheesedb
kind load docker-image cheesedb:dev --name cheesedb

git clone https://github.com/govinargo-labs/cheesedb-helm.git && cd cheesedb-helm
helm install mem ./charts/cheesedb -n cheesedb --create-namespace \
  --set image.repository=cheesedb --set image.tag=dev --set image.pullPolicy=Never
```

## TLS

The server serves TLS only; there is no plain HTTP setting. `tls.mode` picks where the certificate comes from:

| `tls.mode` | Certificate |
|---|---|
| `selfSigned` (default) | The chart makes a small certificate authority and a certificate signed by it, for the service's names, `localhost` and `127.0.0.1`. They are kept in the Secret and reused on upgrades, so clients keep trusting the same `ca.crt`. |
| `certManager` | A cert-manager `Certificate` from `tls.certManager.issuerRef`. |
| `existingSecret` | Your own `kubernetes.io/tls` Secret, named in `tls.existingSecret`. |

Add more names with `tls.extraDnsNames`. The self-signed certificate is made once and reused: changing `tls.extraDnsNames` or `validDays` later has no effect until you delete the Secret `<release>-cheesedb-tls` and upgrade (that also makes a new `ca.crt`, which clients must trust again). In `certManager` and `existingSecret` modes the server reads the certificate at start: restart the pod after the certificate is renewed.

## Admin token

The admin token creates and deletes agents. The server keeps only its SHA-256 (the key hash) and is given only that file.

- **Default:** the chart makes a random token on first install, keeps it and its hash in the Secret `<release>-cheesedb-admin`, and reuses it on upgrades. Anyone who can read that Secret can act as admin.
- **Keep the token out of the cluster:** make it yourself and give only its hash, which is safe to store anywhere:

  ```sh
  TOKEN=$(openssl rand -hex 32)          # keep this one secret: save it in your password manager now
  helm install mem oci://ghcr.io/govinargo-labs/charts/cheesedb --version 0.2.0 --set admin.keyHash=$(printf %s "$TOKEN" | shasum -a 256 | cut -d' ' -f1)
  ```

- **Or** name your own Secret holding the hash under the key `admin.key`: `admin.existingSecret`.

- **Argo CD, Flux or other GitOps tools:** they render the chart without reading the cluster, so the chart cannot see the token and certificate it made before. Every sync would make a new admin token and certificate authority (locking out the admin and breaking clients that trust the old `ca.crt`), and committing rendered output would put the token and the TLS key in git. With GitOps, use `admin.keyHash` or `admin.existingSecret`, and `tls.mode` `certManager` or `existingSecret`. Never commit `helm template` output made with the default values.

Each agent's token is returned once, by the request that creates the agent. The server keeps only its hash.

## Settings

| Value | Default | |
|---|---|---|
| `image.repository`, `image.tag` | `ghcr.io/govinargo-labs/cheesedb`, the chart's appVersion | |
| `image.digest` | empty | `sha256:...`: run exactly this image, whatever its tag points to (see Check the signatures) |
| `persistence.size`, `persistence.storageClass` | `10Gi`, the cluster default | |
| `resources` | requests 100m / 256Mi, limit 2Gi | An open agent keeps its graph in memory, and each loaded vector index about one byte per value per vector (1M memories x 768 values: about 1.1 GB). |
| `service.type`, `service.port` | `ClusterIP`, `7700` | |
| `server.extraArgs` | `[]` | more `cheesedb serve` flags, e.g. `["--quiet"]` |
| `networkPolicy.enabled`, `networkPolicy.from` | `false`, `[]` | |
| `nodeSelector`, `tolerations`, `affinity`, `podAnnotations` | empty | |

## Uninstall

```sh
helm uninstall mem -n cheesedb
kubectl delete pvc -n cheesedb data-mem-cheesedb-0   # the store; it is kept unless you delete it
```

## Publishing (maintainers)

A push to `main` that changes the chart publishes the `version` in `charts/cheesedb/Chart.yaml` to `oci://ghcr.io/govinargo-labs/charts/cheesedb` (`.github/workflows/publish.yaml`). A version already published is never overwritten: bump `version` to publish a new one. The chart package must be public on ghcr.io for others to install it.

## License

Apache-2.0, like cheesedb.
