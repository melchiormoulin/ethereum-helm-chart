#!/bin/bash
# Vault setup script for Ethereum JWT token
# Prerequisites: vault CLI configured and authenticated

set -e

NAMESPACE="${NAMESPACE:-ethereum}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-default}"
ROLE_NAME="${ROLE_NAME:-ethereum-node}"
POLICY_NAME="${POLICY_NAME:-ethereum-jwt}"
SECRET_PATH="${SECRET_PATH:-secret/ethereum/jwt}"

echo "==> Creating Vault policy: ${POLICY_NAME}"
vault policy write ${POLICY_NAME} ethereum-jwt-policy.hcl

echo "==> Generating and storing JWT token at: ${SECRET_PATH}"
vault kv put ${SECRET_PATH} jwt=$(openssl rand -hex 32)

echo "==> Creating Kubernetes auth role: ${ROLE_NAME}"
vault write auth/kubernetes/role/${ROLE_NAME} \
    bound_service_account_names=${SERVICE_ACCOUNT} \
    bound_service_account_namespaces=${NAMESPACE} \
    policies=${POLICY_NAME} \
    ttl=1h

echo "==> Vault setup complete!"
echo ""
echo "Verify with:"
echo "  vault kv get ${SECRET_PATH}"
echo "  vault read auth/kubernetes/role/${ROLE_NAME}"
