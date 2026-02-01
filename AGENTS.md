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
│  │  Rocketpool      │  Staking Infrastructure               │
│  │  Smartnode       │  - HTTP (9101)                        │
│  │  (Deployment)    │  - Metrics (9102)                     │
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
- `jwt.vault.enabled`: Use Vault for JWT (default: false)
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
- `jwt.vault.enabled`: Use Vault for JWT (default: false)
- `persistence.size`: Storage size (default: 100Gi)
- `checkpointSyncUrl`: Optional checkpoint sync URL for fast sync

### 3. Rocketpool Smartnode (`charts/rocketpool-smartnode/`)

Rocketpool staking infrastructure.

**Key files:**
- `values.yaml` - Configuration defaults
- `templates/deployment.yaml` - Pod definition
- `templates/configmap.yaml` - Configuration
- `config/user-settings.yml` - Default settings

## JWT Authentication

Both Geth and Lighthouse use JWT tokens for Engine API authentication. By default, the charts use Kubernetes secrets.

**Default configuration:**
- `jwt.existingSecret`: Name of the Kubernetes secret containing the JWT token
- `jwt.existingSecretKey`: Key within the secret (default: `jwt`)

**To use HashiCorp Vault instead:**
```yaml
jwt:
  vault:
    enabled: true
    secretPath: "secret/data/ethereum/jwt"
    secretKey: "jwt"
    role: "ethereum-node"
```

## Service Names

When deployed with default names:
- Geth RPC: `el-geth-rpc:8545`
- Geth WebSocket: `el-geth-rpc:8546`
- Geth Engine API: `el-geth-engine:8551`
- Lighthouse API: `cl-lighthouse-api:5052`

## Monitoring

All charts support Prometheus ServiceMonitor for metrics collection:
- Geth metrics: port 6060, path `/debug/metrics/prometheus`
- Lighthouse metrics: port 5054, path `/metrics`
- Rocketpool metrics: port 9102, path `/metrics`
