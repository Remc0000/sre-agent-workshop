# Operational Guidelines

## Infrastructure as Code — No Direct Changes

All infrastructure changes MUST go through code. Never modify Azure resources directly via CLI, portal, or API during incident remediation.

**When you identify a fix:**

1. **Create a branch** on the connected GitHub repository
2. **Edit the Bicep template** (in `infra/bicep/`) to restore or fix the resource
3. **Open a Pull Request** against `main` with a clear description of the root cause and fix
4. The CI/CD pipeline (`deploy-infra.yml`) will deploy the change automatically after merge

**Do NOT:**
- Run `az` CLI commands to directly create, modify, or delete Azure resources
- Use the Azure portal to make manual changes
- Apply temporary fixes outside of version control

**Why:** This team follows GitOps principles. All infrastructure state is defined in Bicep templates under `infra/bicep/`. Direct changes create drift between code and reality, making future incidents harder to diagnose.

## Architecture Overview

- **AKS cluster** (`srelab-aks`): Hosts the web app in the `workshop` namespace
- **CosmosDB** (`srelab-cosmos`): NoSQL database, accessed via workload identity (no connection strings)
- **Managed Identity** (`srelab-id`): UAMI with federated credential linked to K8s ServiceAccount `workshop-app`
- **Authentication chain**: Pod → K8s OIDC → Federated Credential → UAMI → CosmosDB RBAC role assignment

## Common Failure: CosmosDB RBAC

If the app returns HTTP 500 with "RBAC permissions" errors on `/items`:
- **Root cause**: The CosmosDB SQL role assignment for the UAMI is missing
- **Where to fix**: `infra/bicep/modules/identity.bicep` — the `cosmosRoleAssignment` resource block
- **How to fix**: Restore the role assignment resource in Bicep and open a PR
- **Do NOT** run `az cosmosdb sql role assignment create` directly
