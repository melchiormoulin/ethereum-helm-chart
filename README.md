Setup ethereum validator node

1. create jwt token 
```
kubectl create secret generic jwt-token  --dry-run=client --from-literal=jwt=$(openssl rand -hex 32) -o yaml > jwt-secret.yaml
```

2. create smartnode config
```
docker run --rm -it --entrypoint=rocketpool-cli -v ./:/root/.rocketpool/ rocketpool/smartnode:v1.17.3 --allow-root service config     --smartnode-network testnet \
    --executionClientMode external \
    --externalExecution-httpUrl http://el-geth-rpc:8545 \
    --externalExecution-wsUrl  ws://el-geth-rpc:8546 \
    --consensusClientMode external \
    --externalConsensusClient lighthouse \
    --externalLighthouse-httpUrl http://cl-lighthouse-api:5052
```