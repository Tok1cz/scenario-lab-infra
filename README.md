# scenario-lab-infra

Infrastructure-as-code for Scenario Lab. Provisions an AWS EC2 instance with Terraform and configures it with Ansible (Docker, Nginx, TLS).

## Architecture

```
Client ──▶ Nginx (:80/:443)
              ├── /api/*  → Docker container (scenario-lab-api :8080)
              └── /*      → /var/www/scenario-lab (static SPA)
```

## Tech Stack

- **Terraform** ≥ 1.5 · AWS provider ~5.0
- **Ansible** · playbook with `docker` and `nginx` roles
- **GitHub Actions** · deploy workflow triggered via `repository_dispatch`

## Terraform

Provisions a `t3.micro` EC2 instance, security group (SSH + HTTP/S), and an Elastic IP.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in values
terraform init
terraform plan
terraform apply
```

### Variables

| Variable       | Description                             |
| -------------- | --------------------------------------- |
| `aws_region`   | AWS region to deploy into               |
| `ami_id`       | Ubuntu AMI for the region               |
| `ssh_key_name` | Name of the AWS key pair for SSH        |
| `admin_ip`     | Your IP in CIDR notation for SSH access |

### Outputs

| Output        | Description                |
| ------------- | -------------------------- |
| `server_ip`   | Elastic IP of the instance |
| `instance_id` | EC2 instance ID            |

## Ansible

Configures the server: installs Docker, pulls the API container from GHCR, sets up Nginx as reverse proxy, and provisions a TLS certificate via Certbot.

```bash
cd ansible
ansible-playbook playbook.yml -i "<SERVER_IP>," -u ubuntu
```

### Roles

| Role     | What it does                                                         |
| -------- | -------------------------------------------------------------------- |
| `docker` | Installs Docker, logs into GHCR, pulls & runs the API image          |
| `nginx`  | Installs Nginx + Certbot, deploys SPA, configures proxy, obtains TLS |

### Extra Vars (passed at deploy time)

| Variable           | Description                                    |
| ------------------ | ---------------------------------------------- |
| `image_tag`        | Docker image tag to deploy (default: `latest`) |
| `ghcr_user`        | GHCR username for `docker login`               |
| `ghcr_token`       | GHCR token for `docker login`                  |
| `frontend_tarball` | Local path to the frontend `dist` tarball      |

### Config Files

| File                         | Purpose                   |
| ---------------------------- | ------------------------- |
| `ansible/group_vars/all.yml` | Domain & admin email      |
| `terraform/terraform.tfvars` | Region, AMI, key pair, IP |

## CI/CD (GitHub Actions)

The [deploy workflow](.github/workflows/deploy.yml) is triggered via `repository_dispatch` from the API and demo repos — it does **not** run on push.

| Event Type        | Trigger Source      | Action                                        |
| ----------------- | ------------------- | --------------------------------------------- |
| `deploy-backend`  | `scenario-lab-api`  | SSH into server, pull & restart API container |
| `deploy-frontend` | `scenario-lab-demo` | Download release artifact, deploy to Nginx    |

### Required Secrets

| Secret             | Purpose                                                                      |
| ------------------ | ---------------------------------------------------------------------------- |
| `SSH_PRIVATE_KEY`  | SSH private key (`.pem`) to connect to the EC2 instance                      |
| `SERVER_IP`        | Public IP of the target server (Terraform output `server_ip`)                |
| `GHCR_TOKEN`       | PAT with `read:packages` scope to pull images from GHCR                      |
| `GH_RELEASE_TOKEN` | PAT with `repo` scope to download release artifacts from `scenario-lab-demo` |
