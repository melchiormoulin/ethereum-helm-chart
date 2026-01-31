# Vault policy for Ethereum JWT token access
# This policy grants read-only access to the JWT secret used for
# Geth <-> Lighthouse Engine API authentication

path "secret/data/ethereum/jwt" {
  capabilities = ["read"]
}