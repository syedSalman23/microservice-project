# Docker Implementation & Container Readiness Plan

This document audits the existing containerization configuration across all 12 services in [`src/`](../../src) and outlines the container build, tagging, and optimization strategy for AWS ECR and EKS.

---

## 1. Container Readiness Audit

Every microservice in this repository **already contains a production-grade multi-stage `Dockerfile`**. No code modifications are needed to containerize the applications.

| Microservice | Dockerfile Path | Builder Base Image | Final Runtime Base Image | Exposed Port | Non-Root User |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`frontend`** | `src/frontend/Dockerfile` | `golang:1.27.0-alpine` | `gcr.io/distroless/static` | `8080` | `nonroot` (Distroless default) |
| **`cartservice`** | `src/cartservice/src/Dockerfile` | `mcr.microsoft.com/dotnet/sdk:10.0.100-noble` | `mcr.microsoft.com/dotnet/runtime-deps:10.0.0-noble-chiseled` | `7070` | `USER 1000` |
| **`productcatalogservice`** | `src/productcatalogservice/Dockerfile` | `golang:1.27.0-alpine` | `gcr.io/distroless/static` | `3550` | `nonroot` |
| **`currencyservice`** | `src/currencyservice/Dockerfile` | `node:24.20.0-alpine` | `alpine:3.24.1` (with `nodejs`) | `7000` | Alpine default (`node` or `root`) |
| **`paymentservice`** | `src/paymentservice/Dockerfile` | `node:24.20.0-alpine` | `alpine:3.24.1` (with `nodejs`) | `50051` | Alpine default |
| **`shippingservice`** | `src/shippingservice/Dockerfile` | `golang:1.27.0-alpine` | `gcr.io/distroless/static` | `50051` | `nonroot` |
| **`emailservice`** | `src/emailservice/Dockerfile` | `python:3.14.7-alpine` | `python:3.14.7-alpine` | `8080` | Alpine default |
| **`checkoutservice`** | `src/checkoutservice/Dockerfile` | `golang:1.27.0-alpine` | `gcr.io/distroless/static` | `5050` | `nonroot` |
| **`recommendationservice`** | `src/recommendationservice/Dockerfile` | `python:3.14.7-alpine` | `python:3.14.7-alpine` | `8080` | Alpine default |
| **`adservice`** | `src/adservice/Dockerfile` | `eclipse-temurin:25.0.4_7-jdk-noble` | `eclipse-temurin:25.0.4_7-jre-alpine` | `9555` | Alpine default |
| **`loadgenerator`** | `src/loadgenerator/Dockerfile` | `python:3.14.7-alpine` | `python:3.14.7-alpine` | *None* | Alpine default |
| **`shoppingassistantservice`** | `src/shoppingassistantservice/Dockerfile` | `python:3.14.7-slim` | `python:3.14.7-slim` | `8080` | Debian default |

---

## 2. Multi-Stage Build Analysis & Security Assessment

### 1. Minimal Attack Surfaces
* **Go Services (`frontend`, `checkoutservice`, `productcatalogservice`, `shippingservice`)**:
  * Compiled with `CGO_ENABLED=0` and `-ldflags="-s -w"` to produce statically linked binaries.
  * Final runtime uses `gcr.io/distroless/static`, which contains no shell, package manager, or unnecessary OS utilities, virtually eliminating Common Vulnerabilities and Exposures (CVEs).
* **.NET Service (`cartservice`)**:
  * Published with single-file trimming (`-p:PublishSingleFile=true -p:PublishTrimmed=true -p:TrimMode=full --self-contained true`).
  * Final runtime uses `mcr.microsoft.com/dotnet/runtime-deps:10.0.0-noble-chiseled` (an ultra-minimal distroless container for .NET). Runs under dedicated user `USER 1000`.
* **Java Service (`adservice`)**:
  * Gradle build runs inside a JDK container; only the compiled application distribution (`installDist`) is copied to an Alpine JRE image.

### 2. Ephemeral Storage & Statelessness
* None of the 12 microservices require persistent volumes (`PersistentVolumeClaims` or host mounts).
* All container root filesystems can be run in **read-only mode** (`readOnlyRootFilesystem: true` in Kubernetes security contexts) with ephemeral `/tmp` volume mounts where temporary file writes are needed.

---

## 3. Local Docker Build Verification

You can verify container builds locally on your machine with Docker:

```powershell
# 1. frontend
docker build -t onlineboutique/frontend:local ./src/frontend

# 2. cartservice (Note: build context is ./src/cartservice/src)
docker build -t onlineboutique/cartservice:local ./src/cartservice/src

# 3. checkoutservice
docker build -t onlineboutique/checkoutservice:local ./src/checkoutservice

# 4. productcatalogservice
docker build -t onlineboutique/productcatalogservice:local ./src/productcatalogservice

# 5. currencyservice
docker build -t onlineboutique/currencyservice:local ./src/currencyservice

# 6. paymentservice
docker build -t onlineboutique/paymentservice:local ./src/paymentservice

# 7. shippingservice
docker build -t onlineboutique/shippingservice:local ./src/shippingservice

# 8. emailservice
docker build -t onlineboutique/emailservice:local ./src/emailservice

# 9. recommendationservice
docker build -t onlineboutique/recommendationservice:local ./src/recommendationservice

# 10. adservice
docker build -t onlineboutique/adservice:local ./src/adservice

# 11. loadgenerator
docker build -t onlineboutique/loadgenerator:local ./src/loadgenerator
```

---

## 4. Container Tagging & Registry Strategy for AWS ECR

For production deployments to Amazon Elastic Container Registry (ECR):

1. **Repository Naming Convention**:
   * Create 11–12 private ECR repositories under a common namespace:
     * `<aws-account-id>.dkr.ecr.<region>.amazonaws.com/onlineboutique/frontend`
     * `<aws-account-id>.dkr.ecr.<region>.amazonaws.com/onlineboutique/cartservice`
     * `<aws-account-id>.dkr.ecr.<region>.amazonaws.com/onlineboutique/checkoutservice`
     * *(and corresponding repositories for the remaining services)*
2. **Immutable Tagging Scheme**:
   * Never deploy `latest` in production.
   * Use Git commit SHA + build number:
     * `${GIT_COMMIT_SHORT}-${BUILD_NUMBER}` (e.g., `a1b2c3d-42`)
     * Release tag: `v1.0.0`
3. **Build Architecture**:
   * Use Docker Buildx or standard multi-platform flags:
     * `docker build --platform linux/amd64 -t <tag> .`
   * Ensures compatibility with x86_64 EKS worker nodes (e.g., `t3.large`, `m5.large`).
