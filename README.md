# Multi-Container App on EC2 — Flask + MySQL with Docker Compose

## Overview

This lab solves a classic production problem: **how do you run an application and its database as isolated, reproducible services that start and stop together, with zero manual wiring?**

A single EC2 instance running a bare app process is fragile — the database URL is hardcoded, the process dies on reboot, and there is no clear boundary between app and data. Docker Compose addresses this by declaring both the Flask API and the MySQL database as first-class services inside a shared internal network. The app never sees the host; it reaches the database by service name. Credentials are injected at runtime from a `.env` file that is never committed.

The result is a two-tier architecture that starts with one command, verifies itself through health checks, and is torn down completely — including all data — with one cleanup command.

---

## Objectives

- Provision an EC2 instance (Amazon Linux 2, t2.micro) and install Docker + Docker Compose v2
- Build a Flask API that reads from and writes to a MySQL database
- Declare both services in a single `docker-compose.yml` with environment variable injection, named networks, and volume mounts
- Gate the web service startup on a MySQL health check so the app never races the database
- Run the full lifecycle: `up --build` → verify with `curl` → `down --volumes`
- Keep credentials out of version control with `.env` + `.gitignore`

---

## Tools & Versions

| Tool             | Version       |
|------------------|---------------|
| Docker           | v27.x         |
| Docker Compose   | v2.x (plugin) |
| Python           | 3.11-slim     |
| Flask            | 3.0.3         |
| MySQL            | 8.0           |
| EC2 AMI          | Amazon Linux 2|
| Instance Type    | t2.micro      |
| Region           | eu-north-1    |
| OS (local)       | macOS         |

---

## Problem This Lab Solves

Running an application and a database on the same host without containerization leads to:

- **Environment drift** — works on one machine, breaks on another
- **Tight coupling** — app and DB start/stop manually, in no guaranteed order
- **Secret sprawl** — credentials embedded in source code or shell history
- **Cleanup pain** — leftover data volumes and processes after a lab session

Docker Compose eliminates all four problems. It declares the full topology — services, networks, volumes, env vars, health checks — in a single version-controlled file. A fresh EC2 instance reproduces the exact same running state every time.

---

## Architecture

```
EC2 Instance (Amazon Linux 2)
└── Docker Engine
    └── Compose Project: multi-container-app
        ├── Service: web  (Flask, port 5000 → host)
        │     └── reads DB_HOST / DB_USER / DB_PASSWORD / DB_NAME from .env
        └── Service: db   (MySQL 8.0, internal only)
              ├── healthcheck: mysqladmin ping
              └── init volume: ./db/init.sql → seeds schema + sample data
        [app-net] — internal bridge network; web reaches db by hostname "db"
        [db-data] — named volume; MySQL data persists across restarts
```

The `db` service is **not** published on any host port. Only `web` exposes port 5000. This means the database is unreachable from outside the Docker network — a key security boundary.

---

## Project Structure

```
multi-container-app-on-ec2/
├── docker-compose.yml       # Declares both services, network, volumes
├── .env.example             # Credential template — copy to .env before running
├── .gitignore               # Excludes .env and Python bytecode
├── README.md                # This file
├── web/
│   ├── Dockerfile           # Builds the Flask image (non-root user)
│   ├── app.py               # Flask application with DB-backed endpoints
│   └── requirements.txt     # Flask + mysql-connector-python
└── db/
    └── init.sql             # Creates users table and seeds 3 rows
```

---

## API Endpoints

| Method | Path           | Description                          |
|--------|----------------|--------------------------------------|
| GET    | `/`            | Welcome message + endpoint list      |
| GET    | `/health`      | Liveness + DB connectivity check     |
| GET    | `/users`       | Returns all users from MySQL         |
| GET    | `/users/<id>`  | Returns a single user by primary key |

---

## Security Considerations

- The Flask container runs as a **non-root user** (`app`) — privilege escalation from inside the container is blocked
- The `db` service is **not exposed** on any host port — MySQL is only reachable within the `app-net` bridge network
- All credentials live in `.env`, which is listed in `.gitignore` and never committed
- The `init.sql` volume mount is **read-only** (`:ro`) — the container cannot modify the seed script at runtime
- The MySQL image uses parameterised queries (`%s` placeholders) throughout the Flask app — no SQL injection surface

---

## Prerequisites

1. An AWS account with access to EC2 (Free Tier eligible)
2. A key pair to SSH into the instance
3. Security group with inbound rules:
   - Port 22 (SSH) from your IP
   - Port 5000 (Flask) from your IP (or 0.0.0.0/0 for lab purposes)

---

## Usage

### 1 — Provision EC2 and Install Docker

Launch a **t2.micro Amazon Linux 2** instance, SSH in, then run:

```bash
sudo yum update -y

# Install Docker
sudo amazon-linux-extras install docker -y
sudo service docker start
sudo usermod -aG docker ec2-user

# Install Docker Compose v2 plugin
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

# Re-login so group membership takes effect
exit
```

SSH back in, then verify:

```bash
docker --version
docker compose version
```

---

### 2 — Clone the Repository

```bash
git clone <your-repo-url>
cd multi-container-app-on-ec2
```

---

### 3 — Configure Credentials

```bash
cp .env.example .env
nano .env   # replace all change_me_* values with real passwords
```

The `.env` file is listed in `.gitignore` — it is never committed.

---

### 4 — Build and Start

```bash
docker compose up --build -d
```

Docker Compose will:
1. Build the `web` image from `./web/Dockerfile`
2. Pull `mysql:8.0`
3. Start `db`, wait for the MySQL health check to pass
4. Start `web` only after `db` is healthy

Watch startup logs:

```bash
docker compose logs -f
```

---

### 5 — Verify

```bash
# Welcome message
curl http://localhost:5000

# DB connectivity
curl http://localhost:5000/health

# All users (seeded by init.sql)
curl http://localhost:5000/users

# Single user
curl http://localhost:5000/users/1
```

From outside EC2 (replace with your instance's public IP):

```bash
curl http://<EC2-PUBLIC-IP>:5000/users
```

---

### 6 — Teardown

```bash
docker compose down --volumes
```

This stops and removes both containers, the `app-net` network, and the `db-data` volume — the EC2 host is left clean.

---

## Evidence

### Docker and Docker Compose Installed

![Docker and Compose versions](screenshoots/01-docker-compose-version.png)

### Compose Up — Services Starting

![docker compose up output](screenshoots/02-compose-up.png)

### Services Running

![docker compose ps](screenshoots/03-compose-ps.png)

### Health Check Passing

![curl /health](screenshoots/04-curl-health.png)

### Root Endpoint

![curl /](screenshoots/05-curl-root.png)

### Users Endpoint — Data from MySQL

![curl /users](screenshoots/06-curl-users.png)

### Single User Endpoint

![curl /users/1](screenshoots/07-curl-users-id.png)

### Compose Logs

![docker compose logs](screenshoots/08-compose-logs.png)

### Teardown — Down with Volumes

![docker compose down --volumes](screenshoots/09-compose-down-volumes.png)

---

## Key Design Decisions

**Health check gates startup** — `depends_on: condition: service_healthy` ensures the Flask container never attempts a DB connection before MySQL has finished initializing. Without this, the app crashes on first start and requires a manual restart.

**Named internal network** — Both services share `app-net`, a dedicated bridge network. The `db` service is not published on the host, so MySQL is only reachable by name (`db`) from within the network — not from the internet or even other Docker projects on the same host.

**Non-root container user** — The Flask image creates a system user `app` and drops to it before the process starts. If the container is ever compromised, the attacker has no root access to the host filesystem.

**Volume for init SQL** — Mounting `init.sql` into `/docker-entrypoint-initdb.d/` is the official MySQL image convention for seeding. It runs exactly once — when the data directory is empty — and is ignored on subsequent starts, so restart-safe.

**`.env` for secrets** — No credentials appear in `docker-compose.yml` or any committed file. The compose file uses `${VAR}` substitution, and Docker Compose automatically reads `.env` from the project root. `.env.example` serves as a self-documenting template.
