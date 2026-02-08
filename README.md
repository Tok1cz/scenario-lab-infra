# scenario-lab-infra

Infrastructure for Scenario Lab. Terraform provisions the server, Ansible configures it.

## How it works

Two tools, two stages:

1. **Terraform** — creates AWS resources (EC2 instance, security group, elastic IP). You run this from your laptop. State is stored locally in `terraform.tfstate`.
2. **Ansible** — SSHs into the server and installs Docker, pulls your container from GHCR, sets up Nginx + TLS. Run manually the first time, then automated via GitHub Actions.

## Config & Secrets

| What                                   | Where                        |
| -------------------------------------- | ---------------------------- |
| Domain, admin email                    | `ansible/group_vars/all.yml` |
| Terraform vars (region, AMI, key, IP)  | `terraform/terraform.tfvars` |
| GHCR token, SSH private key, server IP | GitHub repo secrets          |

No `.env` file needed. Terraform reads `terraform.tfvars` automatically. Ansible reads `group_vars/all.yml` automatically and gets secrets via `--extra-vars`.

---

## A) First-time setup

### Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform installed
- Ansible installed (`pip install ansible`)
- An SSH key pair: create one in AWS console (EC2 → Key Pairs) and download the `.pem`
- A GitHub Personal Access Token (classic) with `read:packages` scope for pulling from GHCR

### Step 1: Edit your config

```bash
# Terraform vars — fill in your values
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

```hcl
# terraform/terraform.tfvars
aws_region   = "eu-central-1"            # your preferred region
ami_id       = "ami-0abcdef1234567890"   # Ubuntu 22.04 AMI for that region
ssh_key_name = "my-keypair"              # name of key pair in AWS
admin_ip     = "203.0.113.5/32"          # your IP for SSH access
```

```yaml
domain: yourdomain.com
admin_email: you@example.com
```

### Step 2: Provision the server

```bash
cd terraform
terraform init    # downloads the AWS provider
terraform plan    # preview what will be created
terraform apply   # creates: EC2 instance + security group + elastic IP
```

Terraform prints the elastic IP at the end. **Point your domain's DNS A record to this IP.**

### Step 3: Configure the server

Wait a minute for the EC2 instance to boot, then:

```bash
cd ansible
ansible-playbook playbook.yml \
  -i "ELASTIC_IP," \
  -u ubuntu \
  --private-key ~/.ssh/my-keypair.pem \
  --extra-vars "ghcr_user=YOUR_GITHUB_USERNAME ghcr_token=ghp_xxxxxxxxxxxx"
```

This SSHs into the server and:

- Installs Docker
- Logs into GHCR and pulls your `scenario-lab-api` container
- Installs Nginx, deploys the reverse-proxy config
- Runs Certbot to get a TLS certificate (requires DNS to be pointing at the IP already)

Your app is now live at `https://yourdomain.com`.

---

## B) Changing infrastructure (e.g. instance type)

Edit `terraform/main.tf` (e.g. change `t3.nano` → `t3.small`), then:

```bash
cd terraform
terraform plan    # shows what will change
terraform apply   # applies it
```

⚠️ **Some changes (like instance type) require a stop/start of the EC2 instance.** Terraform handles this automatically — it will stop, resize, and restart. Your elastic IP stays the same, so DNS doesn't break.

If Terraform says it needs to **destroy and recreate** the instance (e.g. changing the AMI), you'll need to re-run Ansible afterward to reconfigure the fresh server.

---

## C) Deploying app updates (automated)

Once GitHub Actions secrets are set up, deploys happen automatically:

### Required GitHub secrets on this repo

| Secret            | Value                                |
| ----------------- | ------------------------------------ |
| `SSH_PRIVATE_KEY` | Contents of your `.pem` file         |
| `SERVER_IP`       | The elastic IP from Terraform output |
| `GHCR_TOKEN`      | GitHub PAT with `read:packages`      |

### How it triggers

Your app repos (e.g. `scenario-lab-api`) send a `repository_dispatch` event at the end of their CI:

```yaml
# In scenario-lab-api's CI workflow, after pushing the Docker image:
- name: Trigger deploy
  uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.INFRA_REPO_PAT }}
    repository: your-org/scenario-lab-infra
    event-type: deploy-backend
    client-payload: '{"image_tag": "${{ github.sha }}", "ghcr_user": "${{ github.actor }}"}'
```

This triggers the deploy workflow here, which runs Ansible to pull and restart the container.

---

## D) Deploying manually

If you need to deploy without CI:

```bash
cd ansible
ansible-playbook playbook.yml \
  -i "ELASTIC_IP," \
  -u ubuntu \
  --private-key ~/.ssh/my-keypair.pem \
  --extra-vars "ghcr_user=YOUR_GH_USER ghcr_token=ghp_xxx image_tag=latest"
```
