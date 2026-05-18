# Ethereum Helm Charts - Project Guide

## Overview

This repository contains Helm charts for deploying an Ethereum validator node stack on Kubernetes.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────┐                                       │
│  │  Geth            │  Execution Layer Client               │
│  │  (StatefulSet)   │  - Engine API (8551) - JWT protected  │
│  │                  │  - HTTP RPC (8545)                    │
│  │                  │  - WebSocket (8546)                   │
│  │                  │  - P2P (30303)                        │
│  │                  │  - Metrics (6060)                     │
│  └────────┬─────────┘                                       │
│           │ Engine API (JWT authenticated)                  │
│           ▼                                                 │
│  ┌──────────────────┐                                       │
│  │  Lighthouse      │  Consensus Layer Client               │
│  │  (StatefulSet)   │  - HTTP API (5052)                    │
│  │                  │  - P2P TCP/UDP (30304)                │
│  │                  │  - QUIC (30305)                       │
│  │                  │  - Metrics (5054)                     │
│  └────────┬─────────┘                                       │
│           │                                                 │
│           ▼                                                 │
│  ┌──────────────────┐                                       │
│  │  Rocket Pool     │  Saturn Node Infrastructure            │
│  │  Smartnode       │  - Daemon API (8080)                  │
│  │  (Deployment)    │  - Metrics (9102)                     │
│  └────────┬─────────┘                                       │
│           │ shared data PVC                                  │
│           ▼                                                 │
│  ┌──────────────────┐                                       │
│  │  Rocket Pool VC  │  Lighthouse Validator Client           │
│  │  (Deployment)    │  - HTTP API (5062)                    │
│  │                  │  - Metrics (5064)                     │
│  └──────────────────┘                                       │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## Charts

### 1. Geth (`charts/geth/`)

Ethereum execution layer client.

**Key files:**
- `values.yaml` - Configuration defaults
- `templates/statefulset.yaml` - Pod definition
- `templates/services.yaml` - Kubernetes Services
- `templates/servicemonitor.yaml` - Prometheus monitoring

**Important values:**
- `network`: Ethereum network (mainnet, sepolia, holesky)
- `syncMode`: Sync mode (snap, full, light)
- `jwt.vault.enabled`: Use Vault for JWT (default: true)
- `persistence.size`: Storage size (default: 200Gi)

### 2. Lighthouse (`charts/lighthouse/`)

Ethereum consensus layer client (beacon node).

**Key files:**
- `values.yaml` - Configuration defaults
- `templates/statefulset.yaml` - Pod definition
- `templates/services.yaml` - Kubernetes Services
- `templates/servicemonitor.yaml` - Prometheus monitoring

**Important values:**
- `network`: Ethereum network (mainnet, sepolia, holesky)
- `execution.endpoint`: Geth Engine API endpoint
- `jwt.vault.enabled`: Use Vault for JWT (default: true)
- `persistence.size`: Storage size (default: 100Gi)
- `checkpointSyncUrl`: Optional checkpoint sync URL for fast sync

### 3. Rocketpool Smartnode (`charts/rocketpool-smartnode/`)

Rocket Pool Saturn smartnode daemon.

**Key files:**
- `values.yaml` - Configuration defaults
- `templates/deployment.yaml` - Pod definition
- `templates/configmap.yaml` - Configuration
- `config/<profile>/user-settings.yml` - Generated Rocket Pool settings mounted as-is

**Configuration workflow:**
- Helm does not template Rocket Pool application settings.
- `values.yaml` selects the generated settings profile via `config.profile` (default: `testnet`).
- Regenerate `user-settings.yml` with the target `rocketpool/smartnode` image when upgrading Smartnode versions, review the diff, and commit it with the image tag change.
- If execution layer or consensus layer service URLs change, update them manually in each generated `config/<profile>/user-settings.yml` file. These URLs are not Helm values.
- Keep Rocket Pool app settings in the generated profile file; keep Helm values focused on Kubernetes concerns such as image, resources, persistence, services, labels, and secrets.

**Current deployed behavior:**
- Image/tag default: `rocketpool/smartnode:v1.20.2`
- Entrypoint: `/go/bin/rocketpool --settings=/data/.rocketpool/user-settings.yml node`
- Daemon API service port: `8080`
- Metrics service port: `9102`

**Operator commands:**
```bash
POD=$(kubectl -n ethereum get pod -l app.kubernetes.io/name=rocketpool-smartnode -o jsonpath='{.items[0].metadata.name}')

# Recover wallet without recovering validator keys
kubectl -n ethereum exec -it "$POD" -- rocketpool-cli -c /.rocketpool/ wallet recover --skip-validator-key-recovery

# Register node
kubectl -n ethereum exec -it "$POD" -- rocketpool-cli -c /.rocketpool/ node register

# Create rewards tree directory so Smartnode can download reward trees
kubectl -n ethereum exec "$POD" -- mkdir -p /.rocketpool/data/rewards-trees
kubectl -n ethereum rollout restart deployment/rocketpool-smartnode

# Wallet status
kubectl -n ethereum exec -it "$POD" -- rocketpool-cli -c /.rocketpool/ wallet status

# Node status
kubectl -n ethereum exec -it "$POD" -- rocketpool-cli -c /.rocketpool/ node status

# Service status
kubectl -n ethereum exec -it "$POD" -- rocketpool-cli -c /.rocketpool/ service status
```

### 4. Base Node (`charts/base/`)

Base mainnet node (OP Stack L2).

**Key files:**
- `values.yaml` - Configuration defaults
- `templates/statefulset-op-geth.yaml` - op-geth execution layer Pod definition
- `templates/statefulset-op-node.yaml` - op-node rollup node Pod definition
- `templates/services.yaml` - Kubernetes Services for both components
- `templates/servicemonitor.yaml` - Prometheus monitoring for both components

**Important values:**
- `network`: Network preset (`mainnet`) — passed as `--network=base-<network>` to both components
- `opGeth.image.tag`: op-geth version (default: `v1.101411.4`)
- `opNode.image.tag`: op-node version (default: `v1.13.1`)
- `opNode.l1.rpc`: **Required** — L1 Ethereum RPC endpoint (e.g. `http://el-geth-rpc:8545`)
- `opNode.l1.rpckind`: L1 RPC provider kind (default: `basic`)
- `opNode.l2.engineRpc`: op-geth Engine API URL (auto-resolved from release name when empty)
- `opGeth.jwt.vault.enabled` / `opNode.jwt.vault.enabled`: Use Vault for JWT (default: true)
- `opGeth.persistence.size`: op-geth storage size (default: 500Gi)
- `opNode.persistence.size`: op-node storage size (default: 50Gi)

**Current deployed behavior:**
- op-geth: archive mode (`--gcmode=archive`), tx-pool gossip disabled (`--rollup.disabletxpoolgossip=true`)
- op-node: execution-layer sync mode, connects to op-geth Engine API at `<release>-op-geth-engine:8551`

### 5. Rocketpool Validator (`charts/rocketpool-validator/`)

Separate Lighthouse validator client for Rocket Pool Saturn.

**Key files:**
- `values.yaml` - Configuration defaults
- `templates/deployment.yaml` - Pod definition
- `templates/service.yaml` - Kubernetes Service
- `templates/pvc.yaml` - PVC template (skipped when `existingClaim` is set)

**Current deployed behavior:**
- Image/tag default: `sigp/lighthouse:v8.0.0`
- Runs `lighthouse vc` in Hoodi mode
- Connects to beacon node at `cl-lighthouse-api:5052`
- Validator API port: `5062`, metrics port: `5064`
- Supports sharing the smartnode PVC via `persistence.existingClaim`
- Supports `suggestedFeeRecipient` for the Lighthouse `--suggested-fee-recipient` flag; set it to the Rocket Pool fee distributor address from `rocketpool-cli -c /.rocketpool/ node status`

**Operator commands:**
Use this only when Lighthouse fails with `UnregisteredValidator(...)` and the validator has never signed duties elsewhere, or after carefully accepting the slashing-protection reset risk.

If Lighthouse fails with `Validator is missing fee recipient`, initialize the Rocket Pool fee distributor and set `rocketpool-validator.suggestedFeeRecipient` to the fee distributor address before redeploying the validator.

```bash
POD=$(kubectl -n ethereum get pod -l app.kubernetes.io/name=rocketpool-smartnode -o jsonpath='{.items[0].metadata.name}')
kubectl -n ethereum exec -it "$POD" -- rocketpool-cli -c /.rocketpool/ node initialize-fee-distributor
kubectl -n ethereum exec -it "$POD" -- rocketpool-cli -c /.rocketpool/ node status

helm upgrade --install rocketpool-validator charts/rocketpool-validator -n ethereum \
  --set persistence.existingClaim=<smartnode-pvc> \
  --set suggestedFeeRecipient=<fee-distributor-address>
```

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

## JWT Authentication

Both Geth and Lighthouse use JWT tokens for Engine API authentication. By default, the charts use HashiCorp Vault injector to mount the JWT token.

**Default Vault configuration:**
- Secret path: `secret/data/ethereum/jwt`
- Secret key: `jwt`
- Vault role: `ethereum-node`
- Mount path: `/vault/secrets/jwt`

**To use Kubernetes secrets instead:**
```yaml
jwt:
  vault:
    enabled: false
  existingSecret: "jwt-token"
```

## Service Names

When deployed with default names:
- Geth RPC: `el-geth-rpc:8545`
- Geth WebSocket: `el-geth-rpc:8546`
- Geth Engine API: `el-geth-engine:8551`
- Lighthouse API: `cl-lighthouse-api:5052`
- Rocket Pool daemon API: `rocketpool-smartnode:8080`
- Rocket Pool validator API: `rocketpool-validator:5062`
- Base op-geth RPC: `<release>-base-op-geth-rpc:8545`
- Base op-geth Engine API: `<release>-base-op-geth-engine:8551`
- Base op-node API: `<release>-base-op-node-api:9545`

## Monitoring

All charts support Prometheus ServiceMonitor for metrics collection:
- Geth metrics: port 6060, path `/debug/metrics/prometheus`
- Lighthouse metrics: port 5054, path `/metrics`
- Rocketpool metrics: port 9102, path `/metrics`
- Base op-geth metrics: port 6060, path `/metrics`
- Base op-node metrics: port 7300, path `/metrics`
