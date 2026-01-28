# Claude Code Instructions

## Project Context

This is an Ethereum validator node Helm chart repository containing three charts:
- **geth** - Execution layer client
- **lighthouse** - Consensus layer client (beacon node)
- **rocketpool-smartnode** - Staking infrastructure

## Key Technical Details

### JWT Token Handling

JWT tokens are used for secure communication between Geth (execution) and Lighthouse (consensus) via the Engine API.

**Default: Vault Injector**
- Vault annotations are added to pod metadata when `jwt.vault.enabled: true`
- JWT is injected at `/vault/secrets/jwt`
- Template uses `{{- with secret "path" -}}{{ .Data.data.key }}{{- end -}}`

**Alternative: Kubernetes Secret**
- When `jwt.vault.enabled: false`, uses native K8s secret
- JWT is mounted at `/secrets/jwt`

### Chart Structure

```
charts/
├── geth/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── statefulset.yaml
│       ├── services.yaml
│       └── servicemonitor.yaml
├── lighthouse/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── statefulset.yaml
│       ├── services.yaml
│       └── servicemonitor.yaml
└── rocketpool-smartnode/
    ├── Chart.yaml
    ├── values.yaml
    ├── config/
    │   └── user-settings.yml
    └── templates/
        ├── _helpers.tpl
        ├── deployment.yaml
        ├── configmap.yaml
        ├── pvc.yaml
        ├── service.yaml
        └── servicemonitor.yaml
```

### Important Patterns

1. **Conditional Vault annotations** - Only added when both `jwt.enabled` and `jwt.vault.enabled` are true
2. **Conditional volume mounts** - Native secret volumes only when Vault is disabled
3. **JWT path switching** - `/vault/secrets/jwt` vs `/secrets/jwt` based on Vault config

### Helm Template Conventions

- Use `{{- include "chartname.fullname" . }}` for resource names
- Use `{{- include "chartname.labels" . | nindent N }}` for labels
- StatefulSets for blockchain clients (persistent state)
- Deployment for smartnode (stateless-ish)

## Common Tasks

### Adding a new secret via Vault

1. Add vault config to `values.yaml`:
```yaml
secretName:
  vault:
    enabled: true
    secretPath: "secret/data/path"
    secretKey: "key"
    role: "role-name"
```

2. Add annotations to template metadata:
```yaml
{{- if .Values.secretName.vault.enabled }}
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/agent-inject-secret-name: {{ .Values.secretName.vault.secretPath | quote }}
  # ... other annotations
{{- end }}
```

3. Update volume mounts/args to use `/vault/secrets/name`

### Testing Chart Changes

```bash
# Lint the chart
helm lint charts/geth

# Template with default values
helm template test charts/geth

# Template with Vault disabled
helm template test charts/geth --set jwt.vault.enabled=false
```

## Dependencies

- Kubernetes 1.19+
- Helm 3.x
- HashiCorp Vault with Agent Injector (for default JWT handling)
- Prometheus Operator (for ServiceMonitor resources)
