# Project Overview: Cloud-Native Microservices Demo (Online Boutique)

## 1. Executive Summary

**Online Boutique** is a cloud-native, polyglot microservices demonstration application originally created by Google Cloud to showcase modern software architecture, containerization, service mesh, and distributed systems design. The application simulates an end-to-end e-commerce platform where users can browse products, view details, select currencies, manage items in a shopping cart, and place orders.

This project is being adapted as a real-world **AWS Cloud & DevOps Portfolio Project**, migrating away from Google Cloud-specific tooling toward an industry-standard open-source and AWS-native DevOps toolchain:
* **Infrastructure as Code (IaC)**: Terraform
* **Container Registry**: Amazon Elastic Container Registry (ECR)
* **Container Orchestration**: Amazon Elastic Kubernetes Service (EKS)
* **Continuous Integration (CI)**: Jenkins / GitHub Actions
* **Continuous Delivery (CD)**: Argo CD (GitOps)
* **Observability & Monitoring**: Prometheus, Grafana, and OpenTelemetry

---

## 2. Current Repository Structure

Following a cleanup of legacy Google Cloud-specific configuration files (such as GKE manifests, DeployStack, and Skaffold), the repository maintains a clean, decoupled state:

```
microservices-demo/
├── protos/                      # Protocol Buffer definitions (gRPC contracts)
│   ├── demo.proto               # Primary schema for all 11 core microservices
│   └── grpc/health/v1/          # Canonical gRPC health check proto
│       └── health.proto
│
├── src/                         # Complete microservices source code
│   ├── adservice/               # Java / gRPC contextual advertising service
│   ├── cartservice/             # C# (.NET) / gRPC cart persistence service
│   ├── checkoutservice/         # Go / gRPC checkout orchestrator
│   ├── currencyservice/         # Node.js / gRPC foreign exchange conversion
│   ├── emailservice/            # Python / gRPC order confirmation service
│   ├── frontend/                # Go / HTTP web server & UI proxy
│   ├── loadgenerator/           # Python / Locust synthetic traffic generator
│   ├── paymentservice/          # Node.js / gRPC credit card authorization
│   ├── productcatalogservice/   # Go / gRPC product listing and search
│   ├── recommendationservice/   # Python / gRPC recommendation engine
│   ├── shippingservice/         # Go / gRPC shipping quote & tracking
│   └── shoppingassistantservice/# Python (Flask) / HTTP Gemini AI assistant
│
├── docs/                        # Architecture and DevOps documentation
│   └── architecture/
│       ├── PROJECT_OVERVIEW.md
│       ├── MICROSERVICES_ANALYSIS.md
│       ├── APPLICATION_ARCHITECTURE.md
│       ├── SERVICE_COMMUNICATION.md
│       ├── DOCKER_IMPLEMENTATION_PLAN.md
│       └── AWS_DEPLOYMENT_PLAN.md
│
├── .gitignore                   # Standard Git hygiene exclusions
├── LICENSE                      # Apache 2.0 Open Source License
└── README.md                    # Project landing documentation
```

### Purpose of Core Directories and Files

1. **`src/` Directory**: Contains 12 discrete subdirectories. Each subdirectory represents an independent microservice or support utility with its own package configuration (`go.mod`, `package.json`, `requirements.txt`, `build.gradle`, or `.csproj`) and a standalone multi-stage `Dockerfile`.
2. **`protos/` Directory**: Serves as the single source of truth for inter-service communication. All data payloads, service RPC definitions, and message schemas are declared here in Protocol Buffer v3 format. Code generation scripts (`genproto.sh`) in the service directories consume these files.
3. **`docs/architecture/` Directory**: Architectural documentation, service catalogs, dependency maps, and deployment plans for the AWS cloud implementation.

---

## 3. High-Level Architecture & Component Summary

The application comprises 11 core microservices, 1 load generator, and 1 AI assistant:

| Component | Directory | Runtime Language | Primary Protocol & Port | Responsibility |
| :--- | :--- | :--- | :--- | :--- |
| **`frontend`** | `src/frontend` | Go | HTTP `:8080` | Serves web UI templates, tracks user sessions via cookies, aggregates backend gRPC calls. |
| **`cartservice`** | `src/cartservice` | C# (.NET) | gRPC `:7070` | Manages shopping cart items per user; persists data to Redis or in-memory fallback. |
| **`productcatalogservice`** | `src/productcatalogservice` | Go | gRPC `:3550` | Provides product listing, search, and individual item lookups from `products.json`. |
| **`currencyservice`** | `src/currencyservice` | Node.js | gRPC `:7000` | Calculates currency conversion rates based on ECB exchange data (highest QPS service). |
| **`paymentservice`** | `src/paymentservice` | Node.js | gRPC `:50051` | Validates credit card formats and generates mock transaction authorization IDs. |
| **`shippingservice`** | `src/shippingservice` | Go | gRPC `:50051` | Computes shipping fees based on item counts and generates package tracking IDs. |
| **`emailservice`** | `src/emailservice` | Python | gRPC `:8080` | Formats and sends mock order confirmation emails via Jinja2 templates. |
| **`checkoutservice`** | `src/checkoutservice` | Go | gRPC `:5050` | Core orchestrator: validates cart, calculates totals, charges payment, and ships order. |
| **`recommendationservice`** | `src/recommendationservice` | Python | gRPC `:8080` | Generates 5 recommended items for a user based on current cart contents. |
| **`adservice`** | `src/adservice` | Java | gRPC `:9555` | Generates contextual advertising banners based on product category context words. |
| **`loadgenerator`** | `src/loadgenerator` | Python (Locust) | *Client Only* | Continuously simulates synthetic browser traffic against the frontend. |
| **`shoppingassistantservice`** | `src/shoppingassistantservice` | Python (Flask) | HTTP `:8080` | Generative AI assistant using Google Gemini and AlloyDB vector search (optional). |

---

## 4. Architectural Principles

1. **Polyglot Microservices**: Implements five distinct languages (Go, C#, Node.js, Python, Java) running simultaneously to demonstrate polyglot compatibility in a Kubernetes cluster.
2. **gRPC Internal Mesh**: All east-west (service-to-service) traffic utilizes gRPC over HTTP/2 with binary protobuf serialization. Only north-south client ingress to `frontend` uses HTTP/1.1 or HTTP/2 REST.
3. **Stateless Services & Externalized State**: All services (including `frontend`) are strictly stateless, enabling horizontal pod autoscaling. State (user carts) is centralized in a Redis data store.
4. **Resilience & Graceful Degradation**: Non-critical services (such as `adservice` and `recommendationservice`) degrade gracefully—if either service is down or times out, the `frontend` continues serving the home, product, and checkout pages without crashing.
5. **Observability Instrumentation**: All services include hooks for OpenTelemetry distributed tracing, emitting W3C TraceContext headers across gRPC metadata.
