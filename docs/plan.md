# Azure SRE Agent Workshop — Implementation Plan

## Problem Statement

Create a half-day (~3-4 hour) hands-on workshop that introduces operations-focused audiences to the Azure SRE Agent. The workshop takes attendees through the full lifecycle: provision infrastructure → deploy an app → onboard SRE Agent → introduce a fault via IaC → watch SRE Agent detect, diagnose, and fix it with a PR.

## Approach

Build a self-contained workshop repo with step-by-step markdown guides and all supporting code (Bicep IaC, a minimal containerized web app, K8s manifests, and GitHub Actions). The fault scenario is realistic and ops-relevant: a Bicep change removes a managed identity role assignment, causing the app to lose access to its CosmosDB backend. The SRE Agent detects the resulting failures, traces to the offending commit, and opens a PR to restore the role assignment.

## Participant Model

Attendees **fork** the workshop repository to their own GitHub account, then configure their own Azure subscription credentials as GitHub Actions secrets. All deployments run in the attendee's fork against their own Azure subscription. The SRE Agent opens PRs against the attendee's fork. The container image is pre-published to GitHub Packages (ghcr.io) by the workshop maintainer, so attendees don't need to build images — they pull the public image directly.

## Cost Estimate

| Resource | Estimated Cost/Hour |
|----------|-------------------|
| AKS (2× Standard_DS2_v2 nodes) | ~$0.25 |
| CosmosDB (serverless, minimal RU) | ~$0.05 |
| Log Analytics + App Insights | ~$0.10 |
| SRE Agent | ~$0.50 |
| **Total** | **~$1.00/hr (~$4 for the full workshop)** |

> Note: Costs vary by region and usage. CosmosDB serverless charges per RU consumed — minimal for a workshop. SRE Agent cost depends on model provider and investigation volume. Budget ~$5-10 to be safe.

## Technical Architecture

### Azure Resources (Bicep)

| Resource | Purpose |
|----------|---------|
| Resource Group | Container for all workshop resources |
| AKS Cluster | Hosts the web app; workload identity + OIDC issuer enabled |
| CosmosDB (NoSQL API) | Simple backend database for the app |
| Log Analytics Workspace | Centralized logging for AKS + app |
| Application Insights | APM for the web app |
| User-Assigned Managed Identity | Workload identity for the app to auth to CosmosDB |
| Federated Identity Credential | Links K8s ServiceAccount → Azure managed identity |
| Role Assignment | CosmosDB data-plane RBAC for the UAMI |

> **No ACR needed.** The container image is pulled from GitHub Packages (ghcr.io), which is public. This simplifies the infrastructure and reduces cost.

### Simple Web App

- **Runtime:** Node.js (Express)
- **Endpoints:**
  - `GET /` — Landing page showing connection status
  - `GET /health` — Health check (used by K8s probes)
  - `GET /items` — Reads items from CosmosDB (uses `DefaultAzureCredential` via workload identity)
- **Auth:** Uses `@azure/identity` `DefaultAzureCredential` (picks up workload identity automatically)
- **Container:** Published to `ghcr.io/{owner}/sre-agent-workshop/app` via GitHub Packages

### Kubernetes Manifests

- `namespace.yaml` — Workshop namespace
- `service-account.yaml` — ServiceAccount annotated for workload identity (`azure.workload.identity/client-id`)
- `deployment.yaml` — App deployment referencing the SA, with health/readiness probes, image from ghcr.io
- `service.yaml` — LoadBalancer service exposing the app

### GitHub Actions

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `publish-image.yml` | Push to `src/**` on main (maintainer only) | Builds container image and publishes to GitHub Packages (ghcr.io) |
| `deploy-infra.yml` | `workflow_dispatch` / push to `infra/**` | Deploys Bicep to Azure (AKS, CosmosDB, monitoring, identity, role assignments) |
| `deploy-app.yml` | `workflow_dispatch` / push to `k8s/**` | Deploys K8s manifests to AKS (image pulled from ghcr.io) |

### Fault Injection Mechanism

The fault is introduced by committing a Bicep change that **removes the CosmosDB role assignment** for the managed identity. When `deploy-infra.yml` runs:
1. AKS and CosmosDB still exist
2. But the app's managed identity no longer has permission to access CosmosDB
3. The app starts returning 500 errors on `/items`
4. Azure Monitor alert fires → SRE Agent responds

## Repository Structure

```
sre-agent-workshop/
├── README.md                           # Workshop overview, quick start
├── docs/
│   ├── 00-prerequisites.md             # Azure sub, tools, fork setup, costs
│   ├── 01-deploy-infrastructure.md     # Module 1: Provision Azure resources
│   ├── 02-deploy-application.md        # Module 2: Deploy the app to AKS
│   ├── 03-onboard-sre-agent.md         # Module 3: Create SRE Agent via portal
│   ├── 04-configure-incident-response.md # Module 4: Azure Monitor + response plan
│   ├── 05-break-it.md                  # Module 5: Introduce the fault
│   ├── 06-watch-sre-agent.md           # Module 6: SRE Agent investigation & PR
│   └── 07-cleanup.md                   # Tear down resources
├── infra/
│   └── bicep/
│       ├── main.bicep                  # Orchestrator template
│       ├── main.bicepparam             # Default parameters
│       └── modules/
│           ├── aks.bicep               # AKS cluster + OIDC + workload identity
│           ├── cosmosdb.bicep          # CosmosDB account + database + RBAC
│           ├── monitoring.bicep        # Log Analytics + App Insights
│           └── identity.bicep          # UAMI + federated cred + role assignments
├── src/
│   └── app/
│       ├── Dockerfile
│       ├── package.json
│       ├── package-lock.json
│       └── server.js                   # Express app with CosmosDB connection
├── k8s/
│   ├── namespace.yaml
│   ├── service-account.yaml
│   ├── deployment.yaml                 # Image from ghcr.io
│   └── service.yaml
├── .github/
│   └── workflows/
│       ├── publish-image.yml           # Build + push to GitHub Packages
│       ├── deploy-infra.yml            # Bicep deployment
│       └── deploy-app.yml             # K8s manifest deployment
└── scripts/
    ├── setup.sh                        # Pre-workshop env validation
    └── cleanup.sh                      # Resource tear-down
```

## Workshop Modules

### Module 0: Prerequisites (~15 min reading / pre-work)
- Azure subscription with Contributor+ access
- Azure CLI installed and authenticated
- GitHub account
- `kubectl` installed
- Supported region: East US 2, Sweden Central, or Australia East
- Network: `*.azuresre.ai` accessible
- **Fork the workshop repo** to your own GitHub account
- Configure GitHub Actions secrets on your fork: `AZURE_CREDENTIALS`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RG_NAME`
- **Estimated cost: ~$1/hr (~$4-6 for the full workshop)**; includes AKS, CosmosDB serverless, monitoring, SRE Agent

### Module 1: Deploy Infrastructure (~30 min)
- Run `deploy-infra.yml` workflow from your fork (deploys AKS, CosmosDB, monitoring, identity, role assignments)
- Verify resources in Azure portal
- Get AKS credentials: `az aks get-credentials`

### Module 2: Deploy the Application (~30 min)
- Run `deploy-app.yml` workflow (deploys K8s manifests; image pulled from ghcr.io — pre-published by workshop maintainer)
- Verify pods running: `kubectl get pods -n workshop`
- Test the app: hit the LoadBalancer IP, verify `/health` and `/items` work
- Show the app reading from CosmosDB successfully

### Module 3: Onboard SRE Agent (~30 min)
- Navigate to [sre.azure.com](https://sre.azure.com)
- Create agent via wizard: subscription, resource group, region, model provider
- Connect the GitHub repository (OAuth or PAT)
- Grant Reader access to the workshop resource group
- Team onboarding: tell the agent about the app architecture, the AKS cluster, what services matter
- Let agent explore codebase and build knowledge files

### Module 4: Configure Incident Response (~20 min)
- Connect Azure Monitor as incident platform
- Create an incident response plan:
  - Filter: all severities (workshop environment)
  - Autonomy: Autonomous (so attendees can watch without approving)
- Verify alert rules exist for the AKS cluster (container restart count, pod failure, 5xx errors)
- Optionally configure Azure Monitor alert rules if none exist

### Module 5: Break It (~20 min)
- **The story:** "A well-meaning engineer removes what they think is an unused role assignment..."
- Edit `infra/bicep/modules/identity.bicep` — comment out or remove the CosmosDB role assignment
- Commit and push to a branch, merge to main
- `deploy-infra.yml` triggers automatically
- Bicep deploys without the role assignment
- App starts failing: `DefaultAzureCredential` can no longer auth to CosmosDB → 500 on `/items`
- Azure Monitor detects the spike in errors

### Module 6: Watch SRE Agent Work (~30 min)
- Navigate to SRE Agent portal — observe the incident thread
- Watch the agent:
  1. Acknowledge the alert
  2. Query Azure Monitor for error logs
  3. Check AKS pod logs (auth failures)
  4. Correlate with recent deployments (traces to the commit)
  5. Read the Bicep code to understand the change
  6. Identify root cause: missing role assignment
  7. Propose fix: restore the role assignment in Bicep
  8. Open a PR on GitHub with the fix
- Review the PR together
- Merge the PR → workflow deploys the fix → app recovers
- Discuss what happened, how SRE Agent learned from it

### Module 7: Cleanup (~10 min)
- Run cleanup script or `az group delete`
- Delete SRE Agent resource if desired
- Recap and Q&A

## Key Design Decisions

1. **CosmosDB over simpler storage:** Realistic DB scenario that ops teams encounter. The managed identity → CosmosDB RBAC pattern is common in production.
2. **Workload Identity over pod identity:** Workload identity is the current recommended approach for AKS. More relevant for modern ops teams.
3. **GitHub Actions for all deployments:** Gives the SRE Agent a clear deployment trail to trace. Every change goes through a commit → workflow → deployment chain.
4. **Autonomous run mode for the workshop:** Lets attendees observe the full automated investigation without needing to approve each step. In production, you'd start with Review mode.
5. **Single fault scenario (role assignment removal):** Keeps focus on the end-to-end story rather than breadth of scenarios. Clear, relatable, traceable.
6. **Portal wizard for SRE Agent creation:** Hands-on experience with the real product UI. More engaging than automated provisioning for a workshop.
7. **GitHub Packages (ghcr.io) instead of ACR:** Maintainer publishes the image once; attendees pull from public ghcr.io. Eliminates ACR from Bicep, reduces cost, simplifies the fork workflow — attendees don't need to build images.
8. **Fork-based participant model:** Each attendee forks the repo and configures their own Azure secrets. SRE Agent opens PRs against the attendee's fork. Full isolation between participants.

## Work Items

| ID | Title | Owner | Dependencies |
|----|-------|-------|-------------|
| `bicep-infra` | Create Bicep modules (AKS, CosmosDB, monitoring, identity) | Rusty | — |
| `web-app` | Build the minimal Node.js web app with CosmosDB connection | Linus | — |
| `k8s-manifests` | Create K8s manifests (namespace, SA, deployment, service) — image from ghcr.io | Rusty | `web-app` |
| `gh-actions` | Create GitHub Actions workflows (publish-image, deploy-infra, deploy-app) | Rusty | `bicep-infra`, `web-app` |
| `docs-prereqs` | Write Module 0: Prerequisites (incl. fork instructions, secrets setup, cost estimate) | Basher | — |
| `docs-infra` | Write Module 1: Deploy Infrastructure | Basher | `bicep-infra`, `gh-actions` |
| `docs-app` | Write Module 2: Deploy Application | Basher | `web-app`, `k8s-manifests` |
| `docs-onboard` | Write Module 3: Onboard SRE Agent | Basher | — |
| `docs-incident` | Write Module 4: Configure Incident Response | Basher | — |
| `docs-break` | Write Module 5: Break It | Basher | `bicep-infra` |
| `docs-watch` | Write Module 6: Watch SRE Agent | Basher | — |
| `docs-cleanup` | Write Module 7: Cleanup | Basher | — |
| `readme` | Write main README.md (overview, architecture, cost estimate) | Basher | all docs |
| `scripts` | Create setup/cleanup helper scripts | Rusty | `bicep-infra` |
| `review` | Danny reviews architecture, Bicep, and workshop flow | Danny | all above |
