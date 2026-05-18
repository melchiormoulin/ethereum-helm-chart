Setup ethereum validator node

## JWT Token Setup

Geth and Lighthouse share an Engine API JWT. Provide it via a Kubernetes Secret:

```bash
kubectl create secret generic jwt-token \
  --dry-run=client \
  --from-literal=jwt=$(openssl rand -hex 32) \
  -o yaml > jwt-secret.yaml
kubectl apply -f jwt-secret.yaml
```

Then reference it in each chart's values:

```yaml
jwt:
  enabled: true
  existingSecret: "jwt-token"
  existingSecretKey: jwt
```

> The HashiCorp Vault injector path was removed in commit `2439197`. The
> charts no longer support `jwt.vault.enabled` — use the Kubernetes Secret
> path above. The legacy `vault/` directory at the repo root is retained
> only for operators still bootstrapping Vault for unrelated workloads.

## Rocket Pool architecture & persistent volume layout

The Rocket Pool charts pack the entire Smartnode state into a single PV.
The patterns below are intentional — do not "simplify" them without
understanding the daemon's expectations.

### One PVC, two mount paths

`charts/rocketpool-smartnode/templates/deployment.yaml` mounts the same
PVC at both `/data/.rocketpool` and `/.rocketpool`. Kubernetes allows a
single `persistentVolumeClaim` volume to appear in `volumeMounts` more
than once — this is two views of the same volume, not nested PVs.

The dual mount is required because the Smartnode daemon (running with
`isNative: "false"`) hardcodes the `/.rocketpool/data/...` prefix when
looking up the wallet, password, validator keystores, rewards trees, and
voting records, while our `dataPath` is `/data/.rocketpool/data`. Both
prefixes resolve to the same files on disk. See `shared/services/config/`
in the `rocket-pool/smartnode` repo for the path defaults.

### Wallet password lives in the PV, not in a Secret

The daemon writes `password` into the data directory itself when you run
`rocketpool wallet init`. There is no Kubernetes Secret mount for the
wallet password (removed in commit `f298469`) — its lifecycle is bound to
the wallet file, and storing it as a Secret would split that lifecycle
and expose the password through etcd. Treat the PV (and your storage
class's at-rest encryption) as the secret store.

### Rocket Pool CLI commands

Run `rocketpool-cli` inside the smartnode pod and point it at the mounted
Rocket Pool directory with `-c /.rocketpool/`:

```bash
POD=$(kubectl -n ethereum get pod -l app.kubernetes.io/name=rocketpool-smartnode -o jsonpath='{.items[0].metadata.name}')

# Wallet status
kubectl -n ethereum exec -it "$POD" -- rocketpool-cli -c /.rocketpool/ wallet status

# Node status
kubectl -n ethereum exec -it "$POD" -- rocketpool-cli -c /.rocketpool/ node status

# Service status
kubectl -n ethereum exec -it "$POD" -- rocketpool-cli -c /.rocketpool/ service status
```

### user-settings.yml is a ConfigMap subPath mount

`user-settings.yml` is mounted from a ConfigMap as a `subPath` at
`/data/.rocketpool/user-settings.yml`. A directory mount would hide the
rest of the PV. Do not change this to a directory mount.

### Sharing one PV between smartnode and validator

Both `rocketpool-smartnode` and `rocketpool-validator` support
`persistence.existingClaim`. Build the Rocket Pool validator in order:

```bash
# 1. Install the smartnode and create the shared PVC.
helm install rp-smartnode charts/rocketpool-smartnode -n ethereum
# PVC `rp-smartnode-rocketpool-smartnode-data` is created.

# 2. Recover the Rocket Pool wallet without recovering validator keys.
POD=$(kubectl -n ethereum get pod -l app.kubernetes.io/name=rocketpool-smartnode -o jsonpath='{.items[0].metadata.name}')
kubectl -n ethereum exec -it "$POD" -- rocketpool-cli -c /.rocketpool/ wallet recover --skip-validator-key-recovery

# 3. Register the Rocket Pool node.
kubectl -n ethereum exec -it "$POD" -- rocketpool-cli -c /.rocketpool/ node register

# 4. Create the rewards tree directory so Smartnode can download reward trees.
kubectl -n ethereum exec "$POD" -- mkdir -p /.rocketpool/data/rewards-trees
kubectl -n ethereum rollout restart deployment/rocketpool-smartnode

# 5. Install the validator and reuse the smartnode PVC.
helm install rp-validator charts/rocketpool-validator -n ethereum \
  --set persistence.existingClaim=rp-smartnode-rocketpool-smartnode-data
```

`ReadWriteOnce` means both pods must run on the same node. Use matching
`nodeSelector` or pod affinity to keep them scheduled together. This is
the recommended layout — Rocket Pool Saturn is a single-node design.

### Lighthouse slashing-protection recovery

If the validator pod fails with `UnregisteredValidator(...)`, Lighthouse
found a validator keystore that is missing from its slashing protection
database. Only initialize a new slashing protection entry if the validator
has never signed duties elsewhere, or after carefully accepting the
slashing-protection reset risk.

```bash
# Inspect current validator args and pod state
kubectl -n ethereum get deployment rocketpool-validator -o jsonpath='{.spec.template.spec.containers[0].args}'
kubectl -n ethereum get pods -l app.kubernetes.io/name=rocketpool-validator -o wide

# Temporarily initialize Lighthouse slashing protection for discovered keys
kubectl -n ethereum patch deployment rocketpool-validator --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--init-slashing-protection"}]'
kubectl -n ethereum rollout status deployment/rocketpool-validator
kubectl -n ethereum logs -l app.kubernetes.io/name=rocketpool-validator --tail=120

# Remove the temporary flag after the validator starts successfully
kubectl -n ethereum patch deployment rocketpool-validator --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/containers/0/args/12"}]'
kubectl -n ethereum rollout status deployment/rocketpool-validator

# Verify the final pod state, logs, and args
kubectl -n ethereum get pods -l app.kubernetes.io/name=rocketpool-validator -o wide
kubectl -n ethereum logs -l app.kubernetes.io/name=rocketpool-validator --tail=120
kubectl -n ethereum get deployment rocketpool-validator -o jsonpath='{.spec.template.spec.containers[0].args}'
```

## Smartnode config profile (`user-settings.yml`)

The chart selects `charts/rocketpool-smartnode/config/<profile>/user-settings.yml`
via `rocketpool-smartnode.config.profile` (default: `testnet`). The file
is generated by the matching Smartnode release and mounted as-is — Helm
does not template Rocket Pool application settings.

A drift guard in `templates/configmap.yaml` fails Helm install if the
file's `root.version` does not match `image.tag`. Always regenerate the
profile when bumping the image tag.

### Regenerate a profile

```bash
docker run --rm -it --entrypoint=rocketpool-cli \
  -v ./charts/rocketpool-smartnode/config/testnet:/root/.rocketpool/ \
  rocketpool/smartnode:v1.20.2 --allow-root service config
```

Replace `testnet` with `mainnet` for production and the image tag with
the target release. For Hoodi/Saturn, keep the Smartnode profile and
`smartnode.network` as `testnet`; Smartnode `v1.20.2` does not accept
`hoodi` as a network value. After the CLI exits, edit the generated file:

- `externalExecution.httpUrl`: `http://el-geth-rpc:8545`
- `externalExecution.wsUrl`: `ws://el-geth-rpc:8546`
- `externalLighthouse.httpUrl`: `http://cl-lighthouse-api:5052`
- Confirm `smartnode.network` is `testnet` for Hoodi/Saturn or `mainnet` for production
- Confirm `root.version` matches the image tag in `values.yaml`

Then commit the file together with the `image.tag` bump.

### Adding the mainnet profile

The `config/mainnet/` directory ships empty in this repo. Generate the
file with the command above using `mainnet` and commit it before
installing the chart with `--set config.profile=mainnet`.
