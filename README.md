# Multi-Container App on EC2 — Flask + MySQL with Docker Compose, Terraform & Ansible

## Overview

This lab solves a production problem: **how do you run an application and its database as isolated, reproducible services that start and stop together, with zero manual wiring?**

A single EC2 instance running a bare app process is fragile — the database URL is hardcoded, the process dies on reboot, and there is no clear boundary between app and data. This project addresses that by combining three tools:

- **Terraform** provisions the EC2 infrastructure (VPC, subnet, security group, key pair) with a remote backend for state management
- **Ansible** configures the instance over SSH — installs Docker, Docker Compose, and Git automatically
- **Docker Compose** declares the Flask API and MySQL database as first-class services in a shared internal network, started with one command

The result is a fully automated two-tier architecture: infrastructure as code, configuration as code, and application deployment as code.

---

## Objectives

- Provision EC2 (Amazon Linux 2, t3.micro) with Terraform using a remote S3 backend + DynamoDB state lock
- Auto-generate `inventory.ini` from Terraform output — no manual IP hardcoding
- Configure Docker + Docker Compose on the instance via Ansible over SSH
- Deploy a Flask API backed by MySQL using Docker Compose
- Gate web service startup on a MySQL health check — no startup race condition
- Keep all credentials in `.env`, gitignored and never committed
- Run the full lifecycle: `up --build` → verify with `curl` → `down --volumes` → `terraform destroy`

---

## Tools & Versions

| Tool             | Version        |
|------------------|----------------|
| Terraform        | >= 1.5.0       |
| AWS Provider     | ~> 5.0         |
| Ansible          | 2.x            |
| Docker           | 25.0.14        |
| Docker Compose   | v2.29.1        |
| Python           | 3.11-slim      |
| Flask            | 3.0.3          |
| MySQL            | 8.0            |
| EC2 AMI          | Amazon Linux 2 |
| Instance Type    | t3.micro       |
| Region           | eu-west-1      |
| OS (local)       | macOS          |

---

## Problem This Lab Solves

Running an application and a database on the same host without containerization leads to:

- **Environment drift** — works on one machine, breaks on another
- **Tight coupling** — app and DB start/stop manually, in no guaranteed order
- **Secret sprawl** — credentials embedded in source code or shell history
- **Manual provisioning** — every new server requires manual SSH steps to install dependencies

Terraform + Ansible + Docker Compose eliminates all four. The full topology — infrastructure, server configuration, services, networks, volumes, env vars, health checks — is declared in version-controlled files. A fresh EC2 instance reproduces the exact same running state every time.

---

## Architecture

```
YOUR MACHINE
│
├── Terraform → provisions EC2 + networking on AWS
│               writes inventory.ini with real EC2 IP
│
└── Ansible   → SSHes into EC2, installs Docker + Compose + Git
                  ↓
              EC2 Instance (Amazon Linux 2, t3.micro)
              └── Docker Engine
                  └── Compose Project: multi-container-app
                      ├── Service: web  (Flask, port 5000 → host)
                      │     └── reads DB credentials from .env
                      └── Service: db   (MySQL 8.0, internal only)
                            ├── healthcheck: mysqladmin ping
                            └── init volume: db/init.sql → seeds schema
                      [app-net] — internal bridge network
                      [db-data] — named volume, persists MySQL data
```

The `db` service is **not** published on any host port — MySQL is unreachable from outside the Docker network.

---

## Project Structure

```
multi-container-app-on-ec2/
├── docker-compose.yml           # Declares both services, network, volumes
├── .env.example                 # Credential template — copy to .env before running
├── .gitignore                   # Excludes .env, keys/, Terraform state, Python bytecode
├── README.md                    # This file
├── web/
│   ├── Dockerfile               # Builds the Flask image (non-root user)
│   ├── app.py                   # Flask application with DB-backed endpoints
│   └── requirements.txt         # Flask + mysql-connector-python
├── db/
│   └── init.sql                 # Creates users table and seeds 3 rows
├── infra/
│   ├── backend/                 # Stage 1 — bootstraps S3 + DynamoDB (local state)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── terra-modules/           # Stage 2 — modular EC2 infrastructure
│   │   ├── main.tf              # Root module — calls vpc, security-group, ec2 modules
│   │   ├── variables.tf         # Input variables for the root module
│   │   ├── outputs.tf           # Outputs — EC2 IP, SSH command, Ansible command
│   │   └── modules/
│   │       ├── vpc/             # VPC, subnet, IGW, route table
│   │       │   ├── main.tf
│   │       │   ├── variables.tf
│   │       │   └── outputs.tf
│   │       ├── security-group/  # Security group + ingress/egress rules
│   │       │   ├── main.tf
│   │       │   ├── variables.tf
│   │       │   └── outputs.tf
│   │       └── ec2/             # Key pair + EC2 instance
│   │           ├── main.tf
│   │           ├── variables.tf
│   │           └── outputs.tf
│   └── ansible/                 # Ansible playbook + auto-generated inventory
│       ├── site.yml             # Installs Docker, Compose v2.29.1, Git
│       └── inventory.ini        # Auto-generated by Terraform after apply (gitignored)
├── keys/                        # SSH key pair — gitignored, never committed
└── screenshoots/                # Evidence screenshots
```

---

## API Endpoints

| Method | Path          | Description                          |
|--------|---------------|--------------------------------------|
| GET    | `/`           | Welcome message + endpoint list      |
| GET    | `/health`     | Liveness + DB connectivity check     |
| GET    | `/users`      | Returns all users from MySQL         |
| GET    | `/users/<id>` | Returns a single user by primary key |

---

## Security Considerations

- Flask container runs as a **non-root user** (`app`) — no privilege escalation from inside the container
- `db` service is **not exposed** on any host port — MySQL only reachable within `app-net`
- All credentials live in `.env`, listed in `.gitignore`, never committed
- `init.sql` volume mount is **read-only** (`:ro`)
- Parameterised queries (`%s` placeholders) throughout — no SQL injection surface
- SSH access restricted to a single IP (`/32`) via the security group
- S3 state bucket has versioning enabled, public access blocked, encryption at rest

---

## Prerequisites

1. Terraform >= 1.5.0
2. Ansible installed locally
3. AWS CLI configured (`aws configure`)
4. An AWS account (Free Tier eligible)

---

## Usage

### Step 0 — Generate Your SSH Key

```bash
cd multi-container-app-on-ec2
ssh-keygen -t ed25519 -f keys/app -N ""
```

Creates two files:

- `keys/app` — private key, stays on your machine forever, never committed
- `keys/app.pub` — public key, Terraform uploads this to AWS

EC2 instances don't have passwords. AWS uses key pairs — you prove identity by holding the private key. Ansible also uses this key to SSH in and configure the server.

---

### Stage 1 — Bootstrap the Remote Backend

```bash
cd infra/backend
terraform init
```

Downloads the AWS provider locally. State is stored locally in `.terraform/` at this stage — intentionally, because the S3 bucket doesn't exist yet.

```bash
terraform apply
```

Type `yes`. Creates two AWS resources in eu-west-1:

| Resource | Purpose |
|----------|---------|
| S3 bucket `cedrick-multi-container-state-2026` | Stores `terraform.tfstate` remotely |
| DynamoDB table `multi-container-lock` | Locks state during apply — prevents corruption |

![Backend Terraform Apply](screenshoots/01-backend-terraform-apply.png)

---

### Stage 2 — Deploy EC2 Infrastructure

```bash
cd ../terra-modules
terraform init
```

Downloads the AWS + local providers and connects to the S3 backend you just created. You'll see:

```
Successfully configured the backend "s3"!
```

![Terraform Init](screenshoots/02-terraform-init.png)

```bash
terraform fmt
terraform validate
```

`fmt` enforces consistent style across all `.tf` files. `validate` checks syntax and references without calling AWS — should return `Success! The configuration is valid.`

![Terraform Validate](screenshoots/03-terraform-validate.png)

```bash
terraform plan -var="my_ip=$(curl -s https://checkip.amazonaws.com)/32"
```

Dry run — shows every resource the three modules (`vpc`, `security-group`, `ec2`) will create. Nothing changes yet.

```bash
terraform apply -var="my_ip=$(curl -s https://checkip.amazonaws.com)/32"
```

Type `yes`. Creates:

| Resource | Purpose |
|----------|---------|
| VPC | Private network in eu-west-1 |
| Subnet | eu-west-1a — where EC2 lives |
| Internet Gateway | Door between VPC and the internet |
| Route Table | Sends internet traffic through the IGW |
| Security Group | SSH (22) from your IP only, Flask (5000) from anywhere |
| Key Pair | Uploads `keys/app.pub` to AWS |
| EC2 Instance | Amazon Linux 2, t3.micro |
| `infra/ansible/inventory.ini` | Written automatically with the real EC2 IP |

At the end you'll see:

```
ansible_command = "cd ../ansible && ansible-playbook -i inventory.ini site.yml"
ec2_public_ip   = "x.x.x.x"
ssh_command     = "ssh -i ../../keys/app ec2-user@x.x.x.x"
app_url         = "http://x.x.x.x:5000"
```

![Terraform Apply Complete](screenshoots/04-terraform-apply-complete.png)

---

### Stage 3 — Configure EC2 with Ansible

Wait ~30 seconds for EC2 to finish booting, then:

```bash
cd ../ansible
ansible-playbook -i inventory.ini site.yml
```

`-i inventory.ini` — Ansible reads the EC2 IP Terraform just wrote into that file.
`site.yml` — runs these tasks in order over SSH:

| Task | What happens |
|------|-------------|
| Update all packages | `yum update -y` — patches the OS |
| Install Docker and Git | `yum install -y docker git` — skipped if already installed |
| Start and enable Docker | Starts now + auto-starts on reboot |
| Add ec2-user to docker group | No `sudo` needed for docker commands |
| Create CLI plugins directory | Where Compose binary will live |
| Download Docker Compose v2.29.1 | Pinned — v5+ requires buildx which AL2 doesn't have |
| Symlink docker-compose | Makes both `docker compose` and `docker-compose` work |
| Verify Docker version | Smoke test — prints version |
| Verify Compose version | Smoke test — prints version |

Final line should be:

```
PLAY RECAP
x.x.x.x : ok=11   changed=7    unreachable=0    failed=0
```

`failed=0` is what matters.

![Ansible Playbook Complete](screenshoots/12-ansible-playbook-complete.png)

---

### Stage 4 — Test Locally First

Before touching EC2, verify the app works on your machine:

```bash
cd ../..    # back to project root
cp .env.example .env
nano .env
```

Fill in real values:

```
DB_NAME=appdb
DB_USER=appuser
DB_PASSWORD=yourpassword
MYSQL_ROOT_PASSWORD=yourrootpassword
```

`Ctrl+O` to save, `Ctrl+X` to exit.

```bash
docker compose up --build -d
```

What happens:

1. Docker builds the Flask image from `web/Dockerfile`
2. Pulls `mysql:8.0` from Docker Hub
3. Starts `db` — MySQL creates `appdb`, runs `init.sql` (creates `users` table, seeds Alice/Bob/Carol)
4. Health check runs every 10 seconds — waits for MySQL to be ready
5. Only after `db` is healthy, starts `web` — Flask connects to MySQL

```bash
docker compose ps
```

Both services should show `Up (healthy)`.

![Local Compose Up and PS](screenshoots/06-local-compose-up-ps.png)

```bash
curl http://localhost:5000
curl http://localhost:5000/health
curl http://localhost:5000/users
curl http://localhost:5000/users/1
```

Expected:

```json
{ "status": "ok", "message": "Multi-container Flask + MySQL app..." }
{ "status": "healthy", "database": "connected" }
{ "count": 3, "users": [{ "id": 1, "name": "Alice Martin", ... }] }
{ "id": 1, "name": "Alice Martin", "email": "alice@example.com" }
```

![Local Curl Responses](screenshoots/07-local-curl-responses.png)

```bash
docker compose logs
```

Shows MySQL startup + Flask request logs with 200 status codes per request.

![Local Compose Logs](screenshoots/08-local-compose-logs.png)

```bash
docker compose down --volumes
```

Stops everything, removes containers, removes the `db-data` volume. Clean slate.

---

### Stage 5 — Deploy on EC2

```bash
cd infra/terra-modules
ssh -i ../../keys/app ec2-user@$(terraform output -raw ec2_public_ip)
```

Inside EC2:

```bash
git clone https://github.com/cedrick13bienvenue/multi-container-app-on-ec2
cd multi-container-app-on-ec2
cp .env.example .env
nano .env    # fill in the same passwords as locally
docker compose up --build -d
```

![EC2 Git Clone and Compose Up](screenshoots/09-ec2-git-clone-compose-up.png)

```bash
docker compose ps
```

Both services should show `Up (healthy)`.

![EC2 Compose PS](screenshoots/10-ec2-compose-ps.png)

```bash
curl http://localhost:5000
curl http://localhost:5000/health
curl http://localhost:5000/users
curl http://localhost:5000/users/1
```

![EC2 Curl Responses and Compose Down](screenshoots/13-ec2-curl-compose-down.png)

```bash
docker compose logs
```

![EC2 Compose Logs](screenshoots/11-ec2-compose-logs.png)

From your local machine, you can also hit the API directly using the EC2 public IP:

```bash
curl http://$(terraform output -raw ec2_public_ip):5000/users
```

Or open it in the browser:

```
http://<ec2_public_ip>:5000/users
```

![EC2 Browser - /users endpoint](screenshoots/15-ec2-browser-users-endpoint.png)

---

### Stage 6 — Teardown (Reverse Order)

```bash
# On EC2
docker compose down --volumes
exit
```

```bash
# Back on local machine — destroy EC2 infrastructure
cd infra/terra-modules
terraform destroy -var="my_ip=$(curl -s https://checkip.amazonaws.com)/32"
```

Type `yes`. Destroys EC2, VPC, subnet, IGW, route table, security group, key pair. AWS billing stops immediately.

```bash
# Destroy the backend last
cd ../backend
terraform destroy
```

![Terraform Destroy Backend](screenshoots/14-terraform-destroy-backend.png)

> **Order matters** — always destroy main infra before the backend. Destroying the backend first removes the state file and Terraform loses track of what to destroy.

---

## Resources Deployed

| Resource         | Name                              | Details                              |
|------------------|-----------------------------------|--------------------------------------|
| VPC              | multi-container-app-vpc           | CIDR: 10.0.0.0/16, DNS hostnames on  |
| Public Subnet    | multi-container-app-public-subnet | CIDR: 10.0.1.0/24, eu-west-1a        |
| Internet Gateway | multi-container-app-igw           | Attached to VPC                      |
| Route Table      | multi-container-app-public-rt     | Route: 0.0.0.0/0 → IGW               |
| Security Group   | multi-container-app-sg            | SSH (22) from my IP, Flask (5000)    |
| Key Pair         | multi-container-app-key           | Ed25519, registered from local key   |
| EC2 Instance     | multi-container-app-ec2           | t3.micro, Amazon Linux 2             |

---

## Remote Backend

| Component      | Name                              | Purpose                            |
|----------------|-----------------------------------|------------------------------------|
| S3 Bucket      | cedrick-multi-container-state-2026 | Stores terraform.tfstate file     |
| DynamoDB Table | multi-container-lock              | State locking (prevents conflicts) |

State file path in S3: `multi-container-app/terraform.tfstate`


---

## Key Design Decisions

**Health check gates startup** — `depends_on: condition: service_healthy` ensures Flask never attempts a DB connection before MySQL has finished initializing. Without this, the app crashes on first start and requires a manual restart.

**Ansible over user_data** — `user_data` runs blind: no live output, can't be re-run, can't tell which step failed. Ansible gives task-by-task output, idempotency, and can be re-run at any time against any instance.

**Inventory auto-generated by Terraform** — the `local_file` resource writes `inventory.ini` with the real EC2 IP after `terraform apply`. No manual copy-pasting of IPs between tools.

**Docker Compose v2.29.1 pinned** — Compose v5+ requires Docker Buildx, which is not bundled with Docker 25 on Amazon Linux 2. v2.29.1 uses the legacy builder with no external dependency.

**Named internal network** — the `db` service is not published on the host. MySQL is only reachable by service name (`db`) from within `app-net` — not from the internet or other Docker projects on the same host.

**Terraform modules** — infrastructure is split into three reusable modules (`vpc`, `security-group`, `ec2`). Each module owns its own resources, variables, and outputs. The root module (`terra-modules/main.tf`) wires them together by passing outputs from one module as inputs to the next — e.g. `module.vpc.subnet_id` feeds directly into `module.ec2.subnet_id`. This makes each component independently testable and reusable across projects.

**Non-root container user** — the Flask image creates a system user `app` and drops to it before the process starts. If the container is compromised, the attacker has no root access to the host filesystem.
