Setup ethereum validator node

1. create jwt token 
```
kubectl create secret generic jwt-token  --dry-run=client --from-literal=jwt=$(openssl rand -hex 32) -o yaml > jwt-secret.yaml
```

