---
number: "0007"
title: Docker Compose for orchestration, not Kubernetes
status: accepted
date: 2026-04-12
---

## Context
Need container orchestration for local dev and production. Solo developer on self-hosted VPSes.

## Decision
Docker Compose for both local and production environments.

## Alternatives considered
- **Kubernetes**: rejected — massive ops overhead for a solo developer with no scaling needs.
- **Bare metal**: rejected — containers provide reproducibility.

## Consequences
- Simple, well-understood tooling.
- Limited to vertical scaling per VPS.
- If horizontal scaling is ever needed, can migrate to K8s or managed containers.
