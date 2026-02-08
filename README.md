# scenario-lab-infra

Infrastructure for Scenario Lab. Terraform provisions the server, Ansible configures it.

## Structure

- **terraform/** — EC2 instance, security group, elastic IP (state stored locally)
- **ansible/** — Docker + Nginx roles, TLS via Certbot
- **ansible/group_vars/all.yml** — non-secret config (domain, email, etc.)
- **.github/workflows/** — deploy workflow triggered by app repos

## Config & Secrets

| What | Where | Committed? |
|------|-------|------------|
| Domain, admin email | `ansible/group_vars/all.yml` | ✅ yes |
| GHCR token, SSH key, server IP | GitHub repo secrets | ❌ no |
| Terraform vars (region, AMI, etc.) | `terraform/terraform.tfvars` | ❌ no (gitignored) |

See `terraform/terraform.tfvars.example` and `.env.example` for templates.

## Usage

### Provision

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars  # fill in your values
terraform init && terraform apply
```

### Configure server manually

```bash
cd ansible
ansible-playbook playbook.yml -i "SERVER_IP," -u ubuntu \
  --extra-vars "ghcr_user=YOUR_GH_USER ghcr_token=YOUR_TOKEN"
```

### Automated deploys

App repos trigger deploys via `repository_dispatch`. See the deploy workflow for details.
