# Infrastructure Repo Setup

Repo: `scenario-lab-infra`. Holds Terraform (provisioning) and Ansible (configuration).

## Repo Structure

```
scenario-lab-infra/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── providers.tf
├── ansible/
│   ├── playbook.yml
│   ├── inventory/
│   │   └── hosts.ini
│   └── roles/
│       ├── docker/
│       │   └── tasks/main.yml
│       └── nginx/
│           ├── tasks/main.yml
│           └── templates/
│               └── nginx.conf.j2
└── .github/
    └── workflows/
        └── deploy.yml
```

## Terraform

Provisions a single EC2 instance with security group, elastic IP, and DNS.

```hcl
# terraform/main.tf
provider "aws" {
  region = var.aws_region
}

resource "aws_instance" "app" {
  ami           = var.ami_id
  instance_type = "t3.small"
  key_name      = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.app.id]
  tags = { Name = "scenario-lab" }
}

resource "aws_security_group" "app" {
  name = "scenario-lab-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eip" "app" {
  instance = aws_instance.app.id
}
```

State backend → S3 bucket + DynamoDB lock table (create once manually).

## Ansible

### Docker Role — `roles/docker/tasks/main.yml`

```yaml
- name: Install Docker
  apt:
    name: [docker.io, docker-compose-plugin]
    state: present
    update_cache: true

- name: Log into GHCR
  community.docker.docker_login:
    registry: ghcr.io
    username: "{{ ghcr_user }}"
    password: "{{ ghcr_token }}"

- name: Run backend container
  community.docker.docker_container:
    name: scenario-lab-api
    image: "ghcr.io/<org>/scenario-lab-api:{{ image_tag | default('latest') }}"
    pull: true
    restart_policy: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"
```

### Nginx Role — `roles/nginx/tasks/main.yml`

```yaml
- name: Install Nginx and Certbot
  apt:
    name: [nginx, certbot, python3-certbot-nginx]
    state: present

- name: Deploy Nginx config
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/sites-available/scenario-lab
  notify: Reload Nginx

- name: Enable site
  file:
    src: /etc/nginx/sites-available/scenario-lab
    dest: /etc/nginx/sites-enabled/scenario-lab
    state: link
  notify: Reload Nginx

- name: Obtain TLS certificate
  command: >
    certbot --nginx -d {{ domain }}
    --non-interactive --agree-tos -m {{ admin_email }}
  args:
    creates: /etc/letsencrypt/live/{{ domain }}
```

### Nginx Config — `roles/nginx/templates/nginx.conf.j2`

```nginx
server {
    listen 80;
    server_name {{ domain }};

    location /api/ {
        proxy_pass http://127.0.0.1:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        root /var/www/scenario-lab;
        try_files $uri $uri/ /index.html;
    }
}
```

### Playbook — `ansible/playbook.yml`

```yaml
- hosts: app
  become: true
  roles:
    - docker
    - nginx
```

## Deploy Workflow — `.github/workflows/deploy.yml`

Triggered by `repository_dispatch` from the app repos.

```yaml
name: Deploy

on:
  repository_dispatch:
    types: [deploy-backend, deploy-frontend]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan ${{ secrets.SERVER_IP }} >> ~/.ssh/known_hosts

      - name: Install Ansible
        run: pip install ansible

      - name: Deploy backend
        if: github.event.action == 'deploy-backend'
        run: |
          cd ansible
          ansible-playbook playbook.yml \
            -i "${{ secrets.SERVER_IP }}," \
            -u ubuntu \
            --extra-vars "image_tag=${{ github.event.client_payload.image_tag }}"

      - name: Deploy frontend
        if: github.event.action == 'deploy-frontend'
        run: |
          cd ansible
          ansible-playbook playbook.yml \
            -i "${{ secrets.SERVER_IP }}," \
            -u ubuntu \
            --tags nginx
```

## Notes

- Nginx config is infra concern → lives here, not in app repos.
- TLS via Let's Encrypt + Certbot — free, auto-renewing.
- Frontend static files get rsync'd to `/var/www/scenario-lab` during frontend deploy.
