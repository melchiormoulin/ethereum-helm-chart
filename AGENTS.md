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
- `config/user-settings.yml` - Default settings

**Current deployed behavior:**
- Image/tag default: `rocketpool/smartnode:v1.19.0`
- Entrypoint: `/go/bin/rocketpool --settings=/root/.rocketpool/user-settings.yml node`
- Daemon API service port: `8080`
- Metrics service port: `9102`
- Vault-injected wallet password: `secret/data/ethereum/rocketpool` (`password` key)

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

## JWT Authentication

Both Geth and Lighthouse use JWT tokens for Engine API authentication. By default, the charts use HashiCorp Vault injector to mount the JWT token.

**Default Vault configuration:**
- Secret path: `secret/data/ethereum/jwt`
- Secret key: `jwt`
- Vault role: `ethereum-node`
- Mount path: `/vault/secrets/jwt`

Rocket Pool smartnode additionally uses Vault Agent for wallet password material:
- Secret path: `secret/data/ethereum/rocketpool`
- Secret key: `password`
- Injected file path: `/root/.rocketpool/data/password`

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
