# Sorrow Infra Repository Guide

## Overview
This repository manages GCP infrastructure using Terraform.

It follows a **multi-environment layout** where each environment maps to a separate GCP project.

Current environment:
- **bld** → `build-000` (development)

---

## Repository Structure

```
sorrow-infra/
├── docs/              # Documentation (this file lives here)
├── envs/              # Environment-specific config (vars + backend)
│   └── bld/
│       ├── backend.hcl
│       └── terraform.tfvars
├── live/              # Terraform root modules (one per environment)
│   └── bld/
│       ├── main.tf
│       ├── provider.tf
│       ├── variables.tf
│       ├── versions.tf
│       └── outputs.tf
├── modules/           # Reusable Terraform modules (optional, grows over time)
├── exported/          # Temporary GCP export (ignored in git)
└── README.md
```

---

## Key Concepts

### live/
Contains **root Terraform configurations**.

Each folder:
- corresponds to one environment
- has its own Terraform state
- deploys to one GCP project

Example:
```
live/bld → build-000
```

---

### envs/
Contains **environment-specific configuration**.

- `backend.hcl` → where Terraform state is stored
- `terraform.tfvars` → values for variables

---

### modules/
Reusable building blocks.

Use only when:
- logic is repeated
- or complexity grows

Avoid premature abstraction.

---

## How Terraform is Run

Always run Terraform **against a specific environment**.

### From repo root

```bash
terraform -chdir=live/bld init \
  -backend-config=../../envs/bld/backend.hcl

terraform -chdir=live/bld plan \
  -var-file=../../envs/bld/terraform.tfvars

terraform -chdir=live/bld apply \
  -var-file=../../envs/bld/terraform.tfvars
```

---

## State Management

- Remote backend: **GCS bucket**
- Each environment uses a different prefix:
  - `bld`
  - `prod` (future)

Never commit:
```
*.tfstate
```

---

## Git Rules

### Commit:
- `.tf` files
- `.terraform.lock.hcl`
- `terraform.tfvars.example`

### Do NOT commit:
```
.terraform/
*.tfstate
*.tfvars
exported/
```

---

## Workflow

### Adding new infrastructure

1. Write Terraform in `live/bld`
2. Run:
   ```bash
   terraform plan
   ```
3. Apply:
   ```bash
   terraform apply
   ```

---

### Importing existing resources

1. Define resource in `.tf`
2. Add import block
3. Run:
   ```bash
   terraform plan -generate-config-out=generated.tf
   ```
4. Review and apply

---

## Environments Strategy

Each environment = separate GCP project

| Environment | GCP Project |
|------------|------------|
| bld        | build-000  |
| prod       | production-000 (future) |

When adding prod:
- copy `live/bld` → `live/prod`
- copy `envs/bld` → `envs/prod`
- change only `project_id`

---

## Naming Conventions

- environment: `bld`, `prod`
- folders: match environment name
- backend prefix: same as environment

Consistency is critical.

---

## Notes

- `exported/` is temporary — used only for reference
- keep Terraform configs clean and intentional
- refactor aggressively as you learn the infra

---

## Future Improvements

- Introduce modules when patterns repeat
- Add CI/CD (plan/apply pipelines)
- Add `prod` environment
- Introduce shared project if needed

---

## Summary

- `live/` = execution
- `envs/` = configuration
- `modules/` = reuse (optional)
- each env = separate GCP project

Keep it simple, evolve as needed.
