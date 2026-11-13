# AWS Emulator Infrastructure & Cloud-Native Reference Lab

A production-grade Platform Engineering and Site Reliability Engineering (SRE) reference implementation demonstrating local AWS cloud emulation using the official **AWS Emulator**, **Terraform**, **Kubernetes (`kind`)**, **FastAPI**, **Amazon Bedrock (`Converse` API)**, and **GitHub Actions**.

This repository validates full-lifecycle infrastructure provisioning, least-privilege IAM modeling, containerized microservices, and automated static security auditing without requiring active cloud credentials or internet access.

---

## Architecture Overview

- **Local AWS Control & Data Plane (`aws-emulator`):** Runs natively on Linux (`x86_64`), exposing an HTTPS endpoint (`https://127.0.0.1:9297`) with dynamic SigV4 credentials and an ephemeral TLS Certificate Authority (`ca.pem`).
- **Infrastructure as Code (`terraform/`):** Modular Terraform architecture (`network`, `data`, `iam`, `eks`) featuring a multi-AZ VPC (`10.0.0.0/16`), public/private subnets, NAT Gateway, S3 bucket with versioning and SSE-S3, DynamoDB table with a Global Secondary Index (`CustomerOrdersIndex`) and PITR, SQS main queue with Dead-Letter Queue (`redrive_policy`), Secrets Manager configuration, least-privilege IAM policies, and a hardened EKS control plane.
- **Backend Microservice (`app/`):** Lightweight Python FastAPI service using `boto3` to persist order receipts in S3, store metadata in DynamoDB, publish events to SQS, and retrieve runtime secrets from Secrets Manager.
- **Local Kubernetes Runtime (`k8s/`):** `kind` cluster configuration supporting rootless Podman/Docker. Pods inject the host emulator's `ca.pem` and `emulator_credentials` via Kubernetes Secrets and route traffic through a lightweight `socat` sidecar to preserve `https://localhost:9297` TLS Subject Alternative Name (SAN) validation.
- **Hybrid AI Code Reviewer (`scripts/bedrock_reviewer.py`):** Evaluates Terraform and code diffs using `bedrock-runtime` (`Converse` API). Operates in contract-verification mode against the local emulator and seamlessly switches to live LLM inference when pointed to an AWS regional endpoint.
- **CI/CD & Static Security Gate (`.github/workflows/ci.yml`):** Automated pipeline that provisions `aws-emulator`, applies Terraform modules, runs `pytest` integration tests, validates the Bedrock SDK contract, and enforces security compliance via **Checkov**.

---

## Repository Structure

- `.github/workflows/ci.yml` — CI pipeline: Emulator setup, Terraform, pytest, Bedrock & Checkov
- `app/Dockerfile` — Non-root Python 3.12 container image
- `app/main.py` — FastAPI REST service (S3, DynamoDB, SQS, Secrets Manager)
- `app/requirements.txt` — Python runtime dependencies
- `k8s/deployment.yaml` — ServiceAccount, Deployment (API + socat sidecar), NodePort Service
- `k8s/kind-config.yaml` — kind cluster definition mapping host port 8000 to NodePort 30080
- `scripts/bedrock_reviewer.py` — Hybrid Amazon Bedrock Converse API code/IaC reviewer
- `scripts/deploy-kind.sh` — Builds image, configures kind cluster, syncs TLS certs & deploys app
- `scripts/env-emulator.sh` — Exports dynamic SigV4 credentials, CA bundle & SDK compatibility flags
- `scripts/start-emulator.sh` — Lifecycle manager & HTTPS health-check for aws-emulator
- `terraform/modules/data/` — S3, DynamoDB + GSI, SQS + DLQ, Secrets Manager
- `terraform/modules/eks/` — EKS control plane with full audit logging
- `terraform/modules/iam/` — Least-privilege workload & cluster IAM roles/policies
- `terraform/modules/network/` — VPC, Subnets, IGW, NAT Gateway, Route Tables & Default SG
- `tests/test_integration.py` — End-to-end boto3 integration test suite

---

## Prerequisites (Fedora Linux `x86_64`)

1. **System Packages & AWS CLI:**

    sudo dnf install -y curl jq awscli2 kind kubernetes-client podman

2. **Official AWS Emulator RPM:**

    sudo dnf install -y https://downloads.aws.com/aws-emulator/packages/aws-emulator/LTS/latest/aws-emulator-x86_64.rpm

3. **Rootless Container Cgroup Delegation (Required for `kind` on Rootless Podman):**

    sudo mkdir -p /etc/systemd/system/user@.service.d
    printf "[Service]\nDelegate=yes\n" | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
    sudo systemctl daemon-reload

---

## Quickstart Guide

### 1. Start the AWS Emulator Daemon

Launch the emulator bound to `0.0.0.0:9297` and load its ephemeral credentials and CA bundle into your shell session:

    ./scripts/start-emulator.sh
    source scripts/env-emulator.sh
    aws sts get-caller-identity

### 2. Provision Infrastructure with Terraform

Initialize and apply the VPC, data layer, IAM policies, and EKS control plane against the local emulator:

    cd terraform
    terraform init
    terraform apply -auto-approve
    cd ..

### 3. Deploy the Backend API to Kubernetes (`kind`)

Build the container image, spin up the local `kind` cluster, sync the emulator's TLS CA and credentials into a Kubernetes `Secret`, and deploy the FastAPI service:

    ./scripts/deploy-kind.sh

Verify the end-to-end order pipeline from the host:

    curl -s http://127.0.0.1:8000/health | jq .

    ORDER_ID=$(curl -s -X POST http://127.0.0.1:8000/orders \
      -H "Content-Type: application/json" \
      -d '{"customer_id": "cust-701", "item_sku": "HUSQ-EXHAUST", "amount": 850.50, "notes": "Express shipping"}' \
      | jq -r '.order_id')

    curl -s "http://127.0.0.1:8000/orders/${ORDER_ID}" | jq .

### 4. Run Integration Tests & Hybrid Bedrock Code Reviewer

    python3 -m venv .venv
    source .venv/bin/activate
    PYO3_USE_ABI3_FORWARD_COMPATIBILITY=1 pip install -r app/requirements.txt pytest

    pytest tests/test_integration.py -v
    ./scripts/bedrock_reviewer.py

---

## Key Technical Implementation Notes

- **Terraform AWS Provider (`~> 5.100.0`):** Pinned below `6.23.0` with `s3_use_path_style = true` and `AWS_DISABLE_HOST_PREFIX_INJECTION=true` to prevent SDK host-prefix rewriting (`account-id.127.0.0.1`) that breaks local DNS resolution and TLS SAN verification.
- **Security Group Adoption (`aws_default_security_group`):** `aws-emulator` initializes newly created Security Groups with empty egress rules, causing `aws_security_group` creation to fail when Terraform attempts an unconditional `RevokeSecurityGroupEgress`. Adopting `aws_default_security_group` bypasses that call while enforcing least-privilege ingress/egress rules.
- **Pod-to-Host TLS Tunneling (`socat`):** Because `aws-emulator` signs its self-signed certificate for `localhost` and `127.0.0.1`, pods in `kind` route traffic through a local `alpine/socat` sidecar (`127.0.0.1:9297` -> host gateway `:9297`), allowing strict TLS certificate verification without disabling SSL checks.
- **Compensating Controls for IAM:** Since `aws-emulator` validates IAM API contracts without enforcing runtime policy denials, **Checkov** runs as a blocking CI stage to audit least-privilege IAM statements, encryption at rest, and control-plane logging.

---

## Cleanup

    kind delete cluster --name aws-emulator-lab
    pkill -f "aws-emulator" || true
