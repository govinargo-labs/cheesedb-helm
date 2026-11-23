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
| NetworkPolicy (off by default) | only chosen pods reach the server; no traffic out |

The pod runs as a non-root user with a read-only root file system, no added capabilities and no Kubernetes API token. The server calls nothing outside: no model, no other service.

## Try it on a laptop (kind)

```sh
# the image, from a checkout of cheesedb
docker build -t cheesedb:dev https://github.com/govinargo-labs/cheesedb.git
kind create cluster --name cheesedb
kind load docker-image cheesedb:dev --name cheesedb

helm install mem ./charts/cheesedb -n cheesedb --create-namespace \
  --set image.repository=cheesedb --set image.tag=dev --set image.pullPolicy=Never
```

The notes printed after install show how to:
- get the certificate to trust;
- read the admin token;
- reach the server with `kubectl port-forward`:

```sh
kubectl get secret -n cheesedb mem-cheesedb-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > cheesedb-ca.crt
ADMIN=$(kubectl get secret -n cheesedb mem-cheesedb-admin -o jsonpath='{.data.admin-token}' | base64 -d)
kubectl port-forward -n cheesedb svc/mem-cheesedb 7700:7700 &

curl --cacert cheesedb-ca.crt https://localhost:7700/v1/health
curl --cacert cheesedb-ca.crt -H "Authorization: Bearer $ADMIN" -d '{"name":"alice"}' https://localhost:7700/v1/admin/agents
```

Inside the cluster, programs call `https://mem-cheesedb.cheesedb.svc:7700` and trust the same `ca.crt`.

## TLS

The server serves TLS only; there is no plain HTTP setting. `tls.mode` picks where the certificate comes from:

| `tls.mode` | Certificate |
|---|---|
| `selfSigned` (default) | The chart makes a small certificate authority and a certificate signed by it, for the service's names, `localhost` and `127.0.0.1`. They are kept in the Secret and reused on upgrades, so clients keep trusting the same `ca.crt`. |
| `certManager` | A cert-manager `Certificate` from `tls.certManager.issuerRef`. |
| `existingSecret` | Your own `kubernetes.io/tls` Secret, named in `tls.existingSecret`. |

Add more names with `tls.extraDnsNames`.

## Admin token

The admin token creates and deletes agents. The server keeps only its SHA-256 (the key hash) and is given only that file.

- **Default:** the chart makes a random token on first install, keeps it and its hash in the Secret `<release>-cheesedb-admin`, and reuses it on upgrades. Anyone who can read that Secret can act as admin.
- **Keep the token out of the cluster:** make it yourself and give only its hash, which is safe to store anywhere:

  ```sh
  TOKEN=$(openssl rand -hex 32)          # keep this one secret
  helm install mem ./charts/cheesedb --set admin.keyHash=$(printf %s "$TOKEN" | shasum -a 256 | cut -d' ' -f1)
  ```

- **Or** name your own Secret holding the hash under the key `admin.key`: `admin.existingSecret`.

Each agent's token is returned once, by the request that creates the agent. The server keeps only its hash.

## Settings

| Value | Default | |
|---|---|---|
| `image.repository`, `image.tag` | `ghcr.io/govinargo-labs/cheesedb`, the chart's appVersion | |
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

## License

Apache-2.0, like cheesedb.
