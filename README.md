Setup ethereum validator node

## JWT Token Setup

### Option 1: Using HashiCorp Vault Injector (Default)

The charts are configured to use Vault injector by default.

Prerequisites:
- HashiCorp Vault installed and configured
- Vault Agent Injector deployed in your cluster
- Kubernetes auth method configured in Vault

Run the setup script to configure Vault:
```bash
cd vault/
./setup.sh
```

Or manually:
```bash
# 1. Create policy
vault policy write ethereum-jwt vault/ethereum-jwt-policy.hcl

# 2. Store JWT token
vault kv put secret/ethereum/jwt jwt=$(openssl rand -hex 32)

# 3. Create Kubernetes auth role
vault write auth/kubernetes/role/ethereum-node \
    bound_service_account_names=default \
    bound_service_account_namespaces=ethereum \
    policies=ethereum-jwt \
    ttl=1h
```

The Vault injector will automatically inject the JWT token into the pods at `/vault/secrets/jwt`.

### Option 2: Using Kubernetes Secret

To use native Kubernetes secrets instead of Vault, disable Vault in your values:

```yaml
jwt:
  enabled: true
  existingSecret: "jwt-token"
  vault:
    enabled: false
```

Then create the JWT token as a Kubernetes secret:
```bash
kubectl create secret generic jwt-token --dry-run=client --from-literal=jwt=$(openssl rand -hex 32) -o yaml > jwt-secret.yaml
kubectl apply -f jwt-secret.yaml
```

2. create or update smartnode config

Rocket Pool Smartnode settings are stored as generated, release-specific YAML files and mounted as-is by Helm. The chart selects `charts/rocketpool-smartnode/config/<profile>/user-settings.yml` using `rocketpool-smartnode.config.profile` from `values.yaml`.

When upgrading Rocket Pool, regenerate the profile config with the target Smartnode image, review the diff, and commit the generated file together with the image tag change.

If the execution layer or consensus layer service URLs change, update them manually in each generated `charts/rocketpool-smartnode/config/<profile>/user-settings.yml` file. These URLs are not Helm values.

```
docker run --rm -it --entrypoint=rocketpool-cli -v ./charts/rocketpool-smartnode/config/testnet:/root/.rocketpool/ rocketpool/smartnode:v1.20.2 --allow-root service config
```

For the testnet profile, configure external execution at `http://el-geth-rpc:8545` and `ws://el-geth-rpc:8546`, and external Lighthouse at `http://cl-lighthouse-api:5052`.
