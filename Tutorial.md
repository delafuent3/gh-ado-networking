# Azure DevOps + GitHub: Infrastructure Deployment Pipeline

## Overview

This guide covers connecting a public GitHub repository (free plan) to Azure DevOps to deploy infrastructure across three environments:

| Environment | Branch          | Trigger                        |
|-------------|-----------------|--------------------------------|
| **dev**     | `feature/*`     | Push to feature branch         |
| **test**    | `test`          | PR merge into `test`           |
| **prod**    | `main`          | PR merge into `main` + approval|

---

## 1. GitHub Repository Security (Free Plan)

Free plan supports branch protection rules, which are the primary security control.

### 1.1 Branch Protection Rules

Go to **Settings → Branches → Add rule** for each protected branch.

#### `main` (Production)
- [x] Require a pull request before merging
  - Required approvals: **2**
  - Dismiss stale pull request approvals when new commits are pushed
  - Require review from Code Owners
- [x] Require status checks to pass before merging
  - Add your ADO pipeline status check once created
- [x] Require branches to be up to date before merging
- [x] Do not allow bypassing the above settings
- [x] Restrict who can push to matching branches (only CI service account)

#### `test`
- [x] Require a pull request before merging
  - Required approvals: **1**
- [x] Require status checks to pass before merging
- [x] Do not allow force pushes

#### `feature/*`
- No protection needed — developers push freely here

### 1.2 CODEOWNERS File

Create `.github/CODEOWNERS` to auto-assign reviewers:

```
# Global owners — required on every PR
*               @your-team-lead

# Infrastructure files require infra team review
/infra/         @your-infra-team
*.bicep         @your-infra-team
*.tf            @your-infra-team
```

### 1.3 Repository Settings

- **Settings → General → Features**
  - Disable Wiki (reduces attack surface)
  - Disable Projects (if not used)
- **Settings → Actions → General**
  - Set to "Allow all actions and reusable workflows" OR restrict to your org
  - For public repo: set fork pull request workflow to "Require approval for first-time contributors"
- **Settings → Secrets and variables → Actions**
  - Never store secrets here — use Azure DevOps variable groups instead
- **Settings → Security → Secret scanning**
  - Enable secret scanning (free for public repos)
  - Enable push protection

### 1.4 GitHub App vs OAuth for ADO Connection

Use the **Azure Pipelines GitHub App** (recommended over OAuth):
- Fine-grained permissions per repo
- No personal token tied to a user account
- Survives user offboarding

---

## 2. Azure DevOps Setup

### 2.1 Create ADO Project

1. Go to [dev.azure.com](https://dev.azure.com) → New Project
2. Name: `gh-ado-networking`
3. Visibility: **Private** (your ADO org can be private even if GitHub is public)

### 2.2 Install Azure Pipelines GitHub App

1. In GitHub: go to [github.com/marketplace/azure-pipelines](https://github.com/marketplace/azure-pipelines)
2. Install → **Free plan** → Select your account
3. Choose **Only select repositories** → select `gh-ado-networking`
4. This creates a secure connection without using personal tokens

### 2.3 Create Service Connections

You need one service connection per environment to deploy to Azure.

In ADO: **Project Settings → Service connections → New service connection → Azure Resource Manager**

| Connection Name   | Scope              | Environment |
|-------------------|--------------------|-------------|
| `sc-azure-dev`    | `rg-networking-dev`  | dev         |
| `sc-azure-test`   | `rg-networking-test` | test        |
| `sc-azure-prod`   | `rg-networking-prod` | prod        |

**Recommended:** Use separate subscriptions for prod. Use resource group scope (not subscription scope) to limit blast radius.

For the service principal:
- Use **Workload Identity Federation (OIDC)** — no secrets to rotate
- In ADO: select "Workload Identity federation (automatic)" during setup

### 2.4 Create ADO Environments

In ADO: **Pipelines → Environments → New environment**

Create three environments: `dev`, `test`, `prod`

#### Configure Approvals (for test and prod)

> **Single-user note:** GitHub does not allow you to approve your own PRs, so branch protection approval requirements will block you. For a single-user POC, skip GitHub PR approval requirements and rely on the ADO environment approval gates instead — you *can* approve your own deployments in ADO.

- Click environment → **Approvals and checks → Approvals**
- `test`: Add yourself as approver (1 required)
- `prod`: Add yourself as approver + set a timeout (e.g., 1h) to force a deliberate review pause

Also add a **Branch control** check per environment:
- `dev` environment: allowed branches = `refs/heads/feature/*`
- `test` environment: allowed branches = `refs/heads/test`
- `prod` environment: allowed branches = `refs/heads/main`

This prevents deploying a feature branch directly to prod even if someone bypasses the pipeline trigger.

### 2.5 Create Variable Groups

In ADO: **Pipelines → Library → Variable group**

**`vg-networking-dev`**
```
tf_resource_group    = rg-terraform-state
tf_storage_account   = <your-state-storage-account>
tf_container         = dev
```

**`vg-networking-test`**
```
tf_resource_group    = rg-terraform-state
tf_storage_account   = <your-state-storage-account>
tf_container         = test
```

**`vg-networking-prod`**
```
tf_resource_group    = rg-terraform-state
tf_storage_account   = <your-state-storage-account>
tf_container         = prod
```

> The Terraform state storage account must exist before running any pipeline. Create it once:
> ```bash
> az group create -n rg-terraform-state -l australiaeast
> az storage account create -n <your-state-storage-account> -g rg-terraform-state --sku Standard_LRS
> az storage container create -n dev --account-name <your-state-storage-account>
> az storage container create -n test --account-name <your-state-storage-account>
> az storage container create -n prod --account-name <your-state-storage-account>
> ```

For secrets (connection strings, keys): use **Azure Key Vault linked variable groups** instead of storing secrets in ADO directly.

---

## 3. Pipeline Structure

### 3.1 Recommended File Layout

```
gh-ado-networking/
├── .azure/
│   ├── pipelines/
│   │   ├── ci.yml              # Validate/lint on every PR
│   │   ├── deploy-dev.yml      # Deploy to dev on feature push
│   │   ├── deploy-test.yml     # Deploy to test on merge to test
│   │   └── deploy-prod.yml     # Deploy to prod on merge to main
│   └── templates/
│       ├── steps-validate.yml  # Reusable: lint + what-if
│       └── steps-deploy.yml    # Reusable: actual deployment
├── infra/
│   ├── modules/
│   └── main.bicep              # (or main.tf for Terraform)
├── .github/
│   └── CODEOWNERS
└── README.md
```

### 3.2 CI Pipeline — Validate on Every PR

**`.azure/pipelines/ci.yml`**

```yaml
trigger: none  # Only runs via PR trigger below

pr:
  branches:
    include:
      - main
      - test
      - feature/*
  paths:
    include:
      - infra/**
      - .azure/**

pool:
  vmImage: ubuntu-latest

variables:
  - group: vg-networking-dev  # Use dev for PR validation

stages:
  - stage: Validate
    displayName: Validate Infrastructure
    jobs:
      - job: Lint
        steps:
          - template: ../templates/steps-validate.yml
            parameters:
              serviceConnection: sc-azure-dev
              resourceGroup: $(resource_group)
              location: $(location)
```

### 3.3 Deploy Dev — Feature Branch Push

**`.azure/pipelines/deploy-dev.yml`**

```yaml
trigger:
  branches:
    include:
      - feature/*
  paths:
    include:
      - infra/**

pr: none

pool:
  vmImage: ubuntu-latest

variables:
  - group: vg-networking-dev

stages:
  - stage: Deploy_Dev
    displayName: Deploy to Dev
    jobs:
      - deployment: DeployNetworking
        displayName: Deploy Networking
        environment: dev              # Maps to ADO environment "dev"
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                - template: ../templates/steps-deploy.yml
                  parameters:
                    serviceConnection: sc-azure-dev
                    resourceGroup: $(resource_group)
                    location: $(location)
                    environment: $(environment_tag)
```

### 3.4 Deploy Test — Merge to test branch

**`.azure/pipelines/deploy-test.yml`**

```yaml
trigger:
  branches:
    include:
      - test
  paths:
    include:
      - infra/**

pr: none

pool:
  vmImage: ubuntu-latest

variables:
  - group: vg-networking-test

stages:
  - stage: Validate
    displayName: Validate (What-If)
    jobs:
      - job: WhatIf
        steps:
          - template: ../templates/steps-validate.yml
            parameters:
              serviceConnection: sc-azure-test
              resourceGroup: $(resource_group)
              location: $(location)

  - stage: Deploy_Test
    displayName: Deploy to Test
    dependsOn: Validate
    condition: succeeded()
    jobs:
      - deployment: DeployNetworking
        environment: test             # Requires approval configured in ADO
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                - template: ../templates/steps-deploy.yml
                  parameters:
                    serviceConnection: sc-azure-test
                    resourceGroup: $(resource_group)
                    location: $(location)
                    environment: $(environment_tag)
```

### 3.5 Deploy Prod — Merge to main

**`.azure/pipelines/deploy-prod.yml`**

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - infra/**

pr: none

pool:
  vmImage: ubuntu-latest

variables:
  - group: vg-networking-prod

stages:
  - stage: Validate
    displayName: Validate (What-If)
    jobs:
      - job: WhatIf
        steps:
          - template: ../templates/steps-validate.yml
            parameters:
              serviceConnection: sc-azure-prod
              resourceGroup: $(resource_group)
              location: $(location)

  - stage: Deploy_Prod
    displayName: Deploy to Production
    dependsOn: Validate
    condition: succeeded()
    jobs:
      - deployment: DeployNetworking
        environment: prod             # Requires 2 approvals in ADO
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                - template: ../templates/steps-deploy.yml
                  parameters:
                    serviceConnection: sc-azure-prod
                    resourceGroup: $(resource_group)
                    location: $(location)
                    environment: $(environment_tag)
```

### 3.6 Reusable Templates

**`.azure/templates/steps-validate.yml`**

```yaml
parameters:
  - name: serviceConnection
    type: string
  - name: resourceGroup
    type: string
  - name: location
    type: string

steps:
  - task: AzureCLI@2
    displayName: Lint Bicep / Validate ARM
    inputs:
      azureSubscription: ${{ parameters.serviceConnection }}
      scriptType: bash
      scriptLocation: inlineScript
      inlineScript: |
        az bicep build --file infra/main.bicep
        az deployment group validate \
          --resource-group ${{ parameters.resourceGroup }} \
          --template-file infra/main.bicep \
          --parameters location=${{ parameters.location }}

  - task: AzureCLI@2
    displayName: What-If (Preview Changes)
    inputs:
      azureSubscription: ${{ parameters.serviceConnection }}
      scriptType: bash
      scriptLocation: inlineScript
      inlineScript: |
        az deployment group what-if \
          --resource-group ${{ parameters.resourceGroup }} \
          --template-file infra/main.bicep \
          --result-format FullResourcePayloads
```

**`.azure/templates/steps-deploy.yml`**

```yaml
parameters:
  - name: serviceConnection
    type: string
  - name: resourceGroup
    type: string
  - name: location
    type: string
  - name: environment
    type: string

steps:
  - task: AzureCLI@2
    displayName: Deploy Infrastructure
    inputs:
      azureSubscription: ${{ parameters.serviceConnection }}
      scriptType: bash
      scriptLocation: inlineScript
      inlineScript: |
        az deployment group create \
          --resource-group ${{ parameters.resourceGroup }} \
          --template-file infra/main.bicep \
          --parameters location=${{ parameters.location }} environment=${{ parameters.environment }} \
          --name "deploy-$(Build.BuildId)" \
          --mode Incremental
```

---

## 4. Registering Pipelines in ADO

After pushing the YAML files to GitHub:

1. **ADO → Pipelines → New Pipeline**
2. **Where is your code?** → GitHub
3. Select your repository → Authorize with the Azure Pipelines app
4. **Configure your pipeline** → Existing Azure Pipelines YAML file
5. Branch: `main`, Path: `.azure/pipelines/ci.yml`
6. Save (don't run yet)

Repeat for each pipeline file. Name them clearly:
- `CI - Validate`
- `CD - Deploy Dev`
- `CD - Deploy Test`
- `CD - Deploy Prod`

### Connect CI as a Required GitHub Status Check

After creating the CI pipeline:
1. In GitHub: go to branch protection for `main` and `test`
2. Under **Require status checks** → search for your ADO pipeline name
3. The pipeline only appears after it has run at least once — create a draft PR to trigger it

---

## 5. Developer Workflow

```
main ──────────────────────────────────────── (protected, prod)
  └── test ──────────────────────────────────  (protected, test env)
        └── feature/my-feature ────────────── (developer works here)
```

```bash
# Start new work
git checkout test
git pull
git checkout -b feature/add-vnet-peering

# Work, commit, push — auto-deploys to dev
git push origin feature/add-vnet-peering

# Ready for test — open PR: feature/* → test
# 1 approval required + CI must pass → merge triggers deploy-test.yml

# Ready for prod — open PR: test → main
# 2 approvals required + CI must pass + ADO approval gate
# Merge → triggers deploy-prod.yml
```

---

## 6. Best Practices

### Security
- **Use Workload Identity (OIDC)** for service connections — no client secrets to rotate or leak
- **Scope service principals to resource groups**, not entire subscriptions, to limit blast radius
- **Enable Defender for DevOps** in Azure (free tier) — scans IaC templates for misconfigurations
- **Never put credentials in YAML** — use variable groups or Key Vault linked groups
- **Add Branch control checks** on ADO environments to prevent pipeline bypass attacks

### Pipeline Design
- **Always run What-If before deploy** — makes the change impact visible in the run log
- **Use `--mode Incremental`** not Complete — Complete mode deletes any resource not in the template
- **Tag deployments** with `Build.BuildId` so you can correlate Azure activity logs to pipeline runs
- **Use deployment jobs** (not regular jobs) for environments — gives rollback history and approval gates in ADO

### Branch Strategy
- **Never push directly to `main` or `test`** — enforce via branch protection, no exceptions
- **Keep feature branches short-lived** — long-lived branches accumulate drift and cause painful merges
- **Use semantic PR titles** (`feat:`, `fix:`, `infra:`) for clean automated changelogs
- **Delete feature branches after merge** — keeps the repo clean, reduces confusion

### Infrastructure as Code
- **Run `what-if` in CI and post output as PR comment** — reviewers see exactly what will change in Azure
- **Store Terraform state remotely** in Azure Storage with versioning + soft delete enabled
- **Apply resource locks** on the state storage account to prevent accidental deletion
- **One resource group per environment** — clean isolation, easier cost tracking and access control

### Cost & Governance
- **Tag every deployment**: `environment`, `managed-by: azure-devops`, `repo: gh-ado-networking`
- **Use Azure Policy** to enforce mandatory tagging at the subscription level
- **Set budget alerts** on each resource group or subscription

---

## 7. Quick-Start Checklist

### GitHub
- [ ] Create `main` and `test` branches
- [ ] Add branch protection for `main` (2 approvals, status checks, no bypass)
- [ ] Add branch protection for `test` (1 approval, status checks)
- [ ] Create `.github/CODEOWNERS`
- [ ] Enable secret scanning + push protection in repository settings

### Azure
- [ ] Create 3 resource groups: `rg-networking-dev`, `rg-networking-test`, `rg-networking-prod`
- [ ] Create service principals with Workload Identity Federation (one per environment)
- [ ] Grant `Contributor` on the respective resource group only

### Azure DevOps
- [ ] Create ADO project
- [ ] Install Azure Pipelines GitHub App on the repository
- [ ] Create 3 service connections using OIDC
- [ ] Create 3 environments (`dev`, `test`, `prod`) with approval gates
- [ ] Add Branch control checks to each environment
- [ ] Create 3 variable groups
- [ ] Push pipeline YAML files to repo and register them in ADO
- [ ] Link the CI pipeline as a required status check in GitHub branch protection

### Validate the Flow
- [ ] Push to `feature/test-pipeline` → verify dev deploy triggers automatically
- [ ] Open PR to `test` → verify CI runs and is required before merge
- [ ] Merge to `test` → verify ADO approval gate + test deploy succeeds
- [ ] Open PR to `main` → verify CI + 2 approvals enforced
- [ ] Merge to `main` → verify prod approval gate + prod deploy succeeds




Delete Infra

what are the steps when I want to delete all the infra? this is just learning

● Since it's Terraform, you use terraform destroy. Two ways to do it:
                                                                                                                                                                                                                                   
---                                                                                                                                                                                                                              
Option A — Manual (simplest for a POC/learning)

Run locally from the infra/ folder:

# Authenticate first
az login                                                                                                                                                                                                                         
az account set --subscription <your-subscription-id>

# Init with the backend for the env you want to destroy
terraform init \
-backend-config="resource_group_name=rg-terraform-state" \
-backend-config="storage_account_name=<your-state-storage-account>" \
-backend-config="container_name=dev" \
-backend-config="key=networking.tfstate"

# Preview what will be destroyed
terraform plan -destroy -var-file="environments/dev.tfvars"

# Destroy
terraform destroy -var-file="environments/dev.tfvars"

Repeat for test and prod (change container and tfvars).

  ---
Option B — Add a destroy pipeline (useful to avoid needing local az/terraform setup)

Add .azure/pipelines/destroy.yml with a manual trigger only (trigger: none, pr: none) and a runtime parameter to pick the environment. I can create that file if you want.

  ---
For learning, Option A is fine — faster and more transparent. Option B is worth adding once you're past the POC stage so you don't need local tooling.
