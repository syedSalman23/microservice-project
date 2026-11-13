# Microservices Analysis

This document provides a verified, code-level analysis of all 12 components in the repository. Every attribute has been verified directly against the service source files, build descriptors, and Dockerfiles.

---

## 1. `frontend`

* **Directory**: [`src/frontend`](../../src/frontend)
* **Language & Version**: Go (Module declares `go 1.25.0`, `toolchain go1.27.1`; Dockerfile builds with `golang:1.27.0-alpine`)
* **Entry Point**: `main.go`
* **Build Command**: `go build -ldflags="-s -w" -o /go/bin/frontend .`
* **Startup Command**: `/src/server` (inside container) or `go run .`
* **Listening Port**: `8080` (configurable via `PORT`, binds to `LISTEN_ADDR` or `0.0.0.0`)
* **Communication Protocol**:
  * Inbound: HTTP/1.1 & HTTP/2 (Web browser traffic)
  * Outbound: gRPC (calls backend microservices) and HTTP (optional call to shopping assistant)
* **Environment Variables**:
  * `PORT` *(Optional, default: `"8080"`)*: Web server port.
  * `LISTEN_ADDR` *(Optional, default: `""`)*: IP address to bind.
  * `BASE_URL` *(Optional, default: `""`)*: URL prefix path.
  * `PRODUCT_CATALOG_SERVICE_ADDR` *(Mandatory)*: e.g., `productcatalogservice:3550`
  * `CURRENCY_SERVICE_ADDR` *(Mandatory)*: e.g., `currencyservice:7000`
  * `CART_SERVICE_ADDR` *(Mandatory)*: e.g., `cartservice:7070`
  * `RECOMMENDATION_SERVICE_ADDR` *(Mandatory)*: e.g., `recommendationservice:8080`
  * `CHECKOUT_SERVICE_ADDR` *(Mandatory)*: e.g., `checkoutservice:5050`
  * `SHIPPING_SERVICE_ADDR` *(Mandatory)*: e.g., `shippingservice:50051`
  * `AD_SERVICE_ADDR` *(Mandatory)*: e.g., `adservice:9555`
  * `SHOPPING_ASSISTANT_SERVICE_ADDR` *(Mandatory - application panics at startup if missing)*: e.g., `shoppingassistantservice:8080`
  * `ENABLE_TRACING` *(Optional, `"1"` to enable)*: Initializes OpenTelemetry OTLP gRPC exporter.
  * `COLLECTOR_SERVICE_ADDR` *(Mandatory if `ENABLE_TRACING="1"`)*: e.g., `otel-collector:4317`
  * `ENABLE_PROFILER` *(Optional, `"1"` to enable)*: Google Cloud Profiler agent.
  * `ENV_PLATFORM` *(Optional, values: `local`, `gcp`, `aws`, `azure`, `alibaba`)*: Displays platform badge in UI footer.
  * `CYMBAL_BRANDING` *(Optional, `"true"`)*: Changes theme to Cymbal Shops.
  * `BANNER_COLOR` *(Optional)*: Injects CSS color banner for testing canary deployments.
* **Dependencies**:
  * Go modules: `github.com/gorilla/mux`, `github.com/sirupsen/logrus`, `go.opentelemetry.io/otel`, `google.golang.org/grpc`, `cloud.google.com/go/profiler`.
  * Static files: `./templates/*.html` and `./static/*` (CSS, images, icons).
* **API Endpoints**:
  * `GET /`: Home page (lists products, banner, recommendations, cart count).
  * `GET /product/{id}`: Product detail page.
  * `GET /cart`: View cart contents.
  * `POST /cart`: Add item to cart (`product_id`, `quantity`).
  * `POST /cart/empty`: Empty user's cart.
  * `POST /setCurrency`: Update preferred display currency.
  * `POST /cart/checkout`: Submit order with shipping and credit card info.
  * `GET /logout`: Clear user session cookie.
  * `GET /_healthz`: Liveness and readiness probe (returns `"ok"` with status 200).
  * `GET /assistant`: AI assistant interface page.
  * `POST /bot`: Proxies prompt and image URL to shopping assistant HTTP service.
* **Health Check**: Native HTTP endpoint `/_healthz`.
* **Docker Requirements**: Multi-stage build (`golang:1.27.0-alpine` -> `gcr.io/distroless/static`). Requires copying `./templates` and `./static`.

---

## 2. `cartservice`

* **Directory**: [`src/cartservice/src`](../../src/cartservice/src)
* **Language & Version**: C# / .NET 10.0 (Project file specifies `<TargetFramework>net10.0</TargetFramework>`)
* **Entry Point**: `Program.cs` / `Startup.cs`
* **Build Command**: `dotnet publish cartservice.csproj -p:PublishSingleFile=true --self-contained true -p:PublishTrimmed=true -c release -o /cartservice`
* **Startup Command**: `/app/cartservice`
* **Listening Port**: `7070` (set via `ASPNETCORE_HTTP_PORTS=7070` or `PORT`)
* **Communication Protocol**: gRPC over HTTP/2
* **Environment Variables**:
  * `ASPNETCORE_HTTP_PORTS` *(Default: `7070`)*: Port to bind.
  * `REDIS_ADDR` *(Optional but recommended for production)*: Host and port of Redis (e.g., `redis-cart:6379` or AWS ElastiCache primary endpoint). If omitted, falls back to in-memory distributed cache (`AddDistributedMemoryCache`).
  * `SPANNER_PROJECT` / `SPANNER_CONNECTION_STRING` *(Optional)*: Google Cloud Spanner connection parameters.
  * `ALLOYDB_PRIMARY_IP` *(Optional)*: PostgreSQL / AlloyDB connection IP.
  * `DOTNET_EnableDiagnostics` *(Default: `"0"`)*: Disables .NET diagnostic debugging.
* **Dependencies**:
  * NuGet packages: `Grpc.AspNetCore` (2.83.0), `Grpc.HealthCheck` (2.83.0), `Microsoft.Extensions.Caching.StackExchangeRedis` (10.0.11), `Npgsql` (10.0.3), `Google.Cloud.Spanner.Data` (5.12.0).
  * External store: Redis server or cluster.
* **gRPC Service & Methods**:
  * `hipstershop.CartService`:
    * `rpc AddItem(AddItemRequest) returns (Empty)`
    * `rpc GetCart(GetCartRequest) returns (Cart)`
    * `rpc EmptyCart(EmptyCartRequest) returns (Empty)`
* **Health Check**: Implements standard `grpc.health.v1.Health` service via `cartservice.services.HealthCheckService`.
* **Docker Requirements**: Multi-stage build (`mcr.microsoft.com/dotnet/sdk:10.0.100-noble` -> `mcr.microsoft.com/dotnet/runtime-deps:10.0.0-noble-chiseled`). Runs as non-root user `USER 1000`.

---

## 3. `productcatalogservice`

* **Directory**: [`src/productcatalogservice`](../../src/productcatalogservice)
* **Language & Version**: Go (Module declares `go 1.25.8`, `toolchain go1.27.1`; Dockerfile uses `golang:1.27.0-alpine`)
* **Entry Point**: `server.go`
* **Build Command**: `go build -ldflags="-s -w" -o /productcatalogservice .`
* **Startup Command**: `/src/server`
* **Listening Port**: `3550` (configurable via `PORT`)
* **Communication Protocol**: gRPC over HTTP/2
* **Environment Variables**:
  * `PORT` *(Optional, default: `"3550"`)*: Listening port.
  * `EXTRA_LATENCY` *(Optional, e.g., `"50ms"`)*: Injects artificial delay for latency testing.
  * `ALLOYDB_CLUSTER_NAME` *(Optional)*: If set, attempts to load catalog from AlloyDB; otherwise loads from local file.
  * `ENABLE_TRACING` *(Optional, `"1"`)*: OpenTelemetry tracing.
  * `COLLECTOR_SERVICE_ADDR` *(Optional)*: OpenTelemetry collector endpoint.
  * `DISABLE_PROFILER` *(Optional)*: Disables Google Cloud Profiler if non-empty.
* **Dependencies**:
  * Go modules: `google.golang.org/grpc`, `github.com/sirupsen/logrus`, `go.opentelemetry.io/otel`.
  * Data file: [`products.json`](../../src/productcatalogservice/products.json) bundled inside the container.
* **gRPC Service & Methods**:
  * `hipstershop.ProductCatalogService`:
    * `rpc ListProducts(Empty) returns (ListProductsResponse)`
    * `rpc GetProduct(GetProductRequest) returns (Product)`
    * `rpc SearchProducts(SearchProductsRequest) returns (SearchProductsResponse)`
* **Health Check**: Implements `grpc_health_v1.RegisterHealthServer` (serving status `SERVING`).
* **Docker Requirements**: Multi-stage build (`golang:1.27.0-alpine` -> `gcr.io/distroless/static`). Must copy `products.json` alongside the binary.

---

## 4. `currencyservice`

* **Directory**: [`src/currencyservice`](../../src/currencyservice)
* **Language & Version**: Node.js (Dockerfile builder uses `node:24.20.0-alpine`, runtime uses `alpine:3.24.1` with `nodejs`)
* **Entry Point**: `server.js`
* **Build Command**: `npm install --only=production`
* **Startup Command**: `node server.js`
* **Listening Port**: `7000` (configurable via `PORT`)
* **Communication Protocol**: gRPC over HTTP/2
* **Environment Variables**:
  * `PORT` *(Optional, default: `"7000"`)*: Listening port.
  * `DISABLE_PROFILER` *(Optional)*: Set to `"1"` to disable Google Cloud Profiler.
  * `ENABLE_TRACING` *(Optional, `"1"`)*: Initializes OpenTelemetry OTLP gRPC trace exporter.
  * `COLLECTOR_SERVICE_ADDR` *(Optional, default: `"localhost:4317"`)*: OTLP endpoint.
* **Dependencies**:
  * npm packages: `@grpc/grpc-js` (1.14.4), `@grpc/proto-loader` (0.8.1), `pino` (10.3.1), `@opentelemetry/api`, `@opentelemetry/sdk-node`.
  * Data: Reads currency exchange rates from European Central Bank XML/JSON data in `data/currency_conversion.json`.
* **gRPC Service & Methods**:
  * `hipstershop.CurrencyService`:
    * `rpc GetSupportedCurrencies(Empty) returns (GetSupportedCurrenciesResponse)`
    * `rpc Convert(CurrencyConversionRequest) returns (Money)`
* **Health Check**: Implements `healthProto.Health` check returning `{ status: 'SERVING' }`.
* **Docker Requirements**: Multi-stage build (`node:24.20.0-alpine` -> `alpine:3.24.1`). Requires copying `node_modules`, `data/`, and `proto/`.

---

## 5. `paymentservice`

* **Directory**: [`src/paymentservice`](../../src/paymentservice)
* **Language & Version**: Node.js (Dockerfile builder uses `node:24.20.0-alpine`, runtime uses `alpine:3.24.1`)
* **Entry Point**: `index.js`
* **Build Command**: `npm install --only=production`
* **Startup Command**: `node index.js`
* **Listening Port**: `50051` (configurable via `PORT`)
* **Communication Protocol**: gRPC over HTTP/2
* **Environment Variables**:
  * `PORT` *(Optional, default: `"50051"`)*: Listening port.
  * `DISABLE_PROFILER` *(Optional)*: Disables profiler if set.
  * `ENABLE_TRACING` *(Optional, `"1"`)*: Enables OpenTelemetry tracing.
  * `COLLECTOR_SERVICE_ADDR` *(Optional, default: `"localhost:4317"`)*: OTLP collector.
* **Dependencies**:
  * npm packages: `@grpc/grpc-js` (1.14.4), `simple-card-validator` (^1.1.0), `uuid` (^14.0.0), `pino` (10.3.1).
* **gRPC Service & Methods**:
  * `hipstershop.PaymentService`:
    * `rpc Charge(ChargeRequest) returns (ChargeResponse)`: Validates credit card number and expiration date, then generates a random UUID transaction ID.
* **Health Check**: Implements `healthProto.Health` check returning `{ status: 'SERVING' }`.
* **Docker Requirements**: Multi-stage build (`node:24.20.0-alpine` -> `alpine:3.24.1`).

---

## 6. `shippingservice`

* **Directory**: [`src/shippingservice`](../../src/shippingservice)
* **Language & Version**: Go (Module declares `go 1.26.0`, `toolchain go1.27.1`; Dockerfile uses `golang:1.27.0-alpine`)
* **Entry Point**: `main.go`
* **Build Command**: `go build -ldflags="-s -w" -o /go/bin/shippingservice .`
* **Startup Command**: `/src/shippingservice`
* **Listening Port**: `50051` (configurable via `PORT`)
* **Communication Protocol**: gRPC over HTTP/2
* **Environment Variables**:
  * `PORT` *(Optional, default: `"50051"`)*: Listening port.
  * `DISABLE_STATS` *(Optional)*: Disables statistics if non-empty.
  * `DISABLE_TRACING` *(Optional)*: Disables tracing if non-empty.
  * `DISABLE_PROFILER` *(Optional)*: Disables profiler if non-empty.
* **Dependencies**:
  * Go modules: `google.golang.org/grpc`, `github.com/sirupsen/logrus`.
* **gRPC Service & Methods**:
  * `hipstershop.ShippingService`:
    * `rpc GetQuote(GetQuoteRequest) returns (GetQuoteResponse)`: Calculates shipping cost based on item count.
    * `rpc ShipOrder(ShipOrderRequest) returns (ShipOrderResponse)`: Generates tracking ID (formatted as 2 random uppercase letters followed by digits).
* **Health Check**: Implements `grpc_health_v1.RegisterHealthServer` returning `SERVING`.
* **Docker Requirements**: Multi-stage build (`golang:1.27.0-alpine` -> `gcr.io/distroless/static`).

---

## 7. `emailservice`

* **Directory**: [`src/emailservice`](../../src/emailservice)
* **Language & Version**: Python 3.14 (Dockerfile uses `python:3.14.7-alpine`)
* **Entry Point**: `email_server.py`
* **Build Command**: `pip install -r requirements.txt`
* **Startup Command**: `python email_server.py`
* **Listening Port**: `8080` (configurable via `PORT`)
* **Communication Protocol**: gRPC over HTTP/2
* **Environment Variables**:
  * `PORT` *(Optional, default: `"8080"`)*: Listening port.
  * `ENABLE_TRACING` *(Optional, `"1"`)*: Enables OpenTelemetry OTLP tracing.
  * `COLLECTOR_SERVICE_ADDR` *(Optional, default: `"localhost:4317"`)*: OTLP endpoint.
  * `DISABLE_PROFILER` *(Optional)*: Disables profiler if set.
* **Dependencies**:
  * Python packages: `grpcio` (1.76.0), `grpcio-health-checking` (1.76.0), `jinja2` (3.1.6), `opentelemetry-api`.
  * Templates: [`templates/confirmation.html`](../../src/emailservice/templates/confirmation.html).
* **gRPC Service & Methods**:
  * `hipstershop.EmailService`:
    * `rpc SendOrderConfirmation(SendOrderConfirmationRequest) returns (Empty)`: Renders HTML email template and logs confirmation message (mock delivery).
* **Health Check**: Uses `grpcio-health-checking` (`health_pb2_grpc.add_HealthServicer_to_server`).
* **Docker Requirements**: Multi-stage build (`python:3.14.7-alpine` builder with `g++` and `linux-headers` -> clean `python:3.14.7-alpine` runtime).

---

## 8. `checkoutservice`

* **Directory**: [`src/checkoutservice`](../../src/checkoutservice)
* **Language & Version**: Go (Module declares `go 1.25.0`, `toolchain go1.27.1`; Dockerfile uses `golang:1.27.0-alpine`)
* **Entry Point**: `main.go`
* **Build Command**: `go build -ldflags="-s -w" -o /checkoutservice .`
* **Startup Command**: `/src/checkoutservice`
* **Listening Port**: `5050` (configurable via `PORT`)
* **Communication Protocol**:
  * Inbound: gRPC over HTTP/2 (from `frontend`)
  * Outbound: gRPC over HTTP/2 (to 6 downstream services)
* **Environment Variables**:
  * `PORT` *(Optional, default: `"5050"`)*: Listening port.
  * `PRODUCT_CATALOG_SERVICE_ADDR` *(Mandatory)*: e.g., `productcatalogservice:3550`
  * `CURRENCY_SERVICE_ADDR` *(Mandatory)*: e.g., `currencyservice:7000`
  * `CART_SERVICE_ADDR` *(Mandatory)*: e.g., `cartservice:7070`
  * `SHIPPING_SERVICE_ADDR` *(Mandatory)*: e.g., `shippingservice:50051`
  * `PAYMENT_SERVICE_ADDR` *(Mandatory)*: e.g., `paymentservice:50051`
  * `EMAIL_SERVICE_ADDR` *(Mandatory)*: e.g., `emailservice:8080`
  * `ENABLE_TRACING` *(Optional, `"1"`)*: OpenTelemetry tracing.
  * `COLLECTOR_SERVICE_ADDR` *(Mandatory if `ENABLE_TRACING="1"`)*: e.g., `otel-collector:4317`
* **Dependencies**:
  * Go modules: `github.com/google/uuid`, `github.com/sirupsen/logrus`, `google.golang.org/grpc`, `go.opentelemetry.io/otel`.
* **gRPC Service & Methods**:
  * `hipstershop.CheckoutService`:
    * `rpc PlaceOrder(PlaceOrderRequest) returns (PlaceOrderResponse)`
* **Health Check**: Implements `healthpb.RegisterHealthServer` returning `SERVING`.
* **Docker Requirements**: Multi-stage build (`golang:1.27.0-alpine` -> `gcr.io/distroless/static`).

---

## 9. `recommendationservice`

* **Directory**: [`src/recommendationservice`](../../src/recommendationservice)
* **Language & Version**: Python 3.14 (Dockerfile uses `python:3.14.7-alpine`)
* **Entry Point**: `recommendation_server.py`
* **Build Command**: `pip install -r requirements.txt`
* **Startup Command**: `python recommendation_server.py`
* **Listening Port**: `8080` (configurable via `PORT`)
* **Communication Protocol**:
  * Inbound: gRPC over HTTP/2
  * Outbound: gRPC over HTTP/2 (to `productcatalogservice`)
* **Environment Variables**:
  * `PORT` *(Optional, default: `"8080"`)*: Listening port.
  * `PRODUCT_CATALOG_SERVICE_ADDR` *(Mandatory - service throws exception if missing)*: e.g., `productcatalogservice:3550`
  * `ENABLE_TRACING` *(Optional, `"1"`)*: OpenTelemetry tracing.
  * `COLLECTOR_SERVICE_ADDR` *(Optional, default: `"localhost:4317"`)*: OTLP endpoint.
  * `DISABLE_PROFILER` *(Optional)*: Disables profiler if set.
* **Dependencies**:
  * Python packages: `grpcio` (1.76.0), `grpcio-health-checking` (1.76.0), `opentelemetry-api`.
* **gRPC Service & Methods**:
  * `hipstershop.RecommendationService`:
    * `rpc ListRecommendations(ListRecommendationsRequest) returns (ListRecommendationsResponse)`: Calls product catalog, filters out items already viewed/in cart, and returns up to 5 randomized products.
* **Health Check**: Implements `health_pb2_grpc.add_HealthServicer_to_server`.
* **Docker Requirements**: Multi-stage build (`python:3.14.7-alpine` builder -> `python:3.14.7-alpine` runtime).

---

## 10. `adservice`

* **Directory**: [`src/adservice`](../../src/adservice)
* **Language & Version**: Java 21 / 25 (`build.gradle` defines `JavaVersion.VERSION_21`; Dockerfile uses `eclipse-temurin:25.0.4_7-jdk-noble` builder and `eclipse-temurin:25.0.4_7-jre-alpine` runtime)
* **Entry Point**: `hipstershop.AdService` (main class)
* **Build Command**: `./gradlew installDist`
* **Startup Command**: `/app/build/install/hipstershop/bin/AdService`
* **Listening Port**: `9555` (configurable via `PORT`)
* **Communication Protocol**: gRPC over HTTP/2
* **Environment Variables**:
  * `PORT` *(Optional, default: `"9555"`)*: Listening port.
* **Dependencies**:
  * Gradle dependencies: `io.grpc:grpc-netty`, `io.grpc:grpc-protobuf`, `io.grpc:grpc-services`, `org.apache.logging.log4j:log4j-core:2.26.1`.
* **gRPC Service & Methods**:
  * `hipstershop.AdService`:
    * `rpc GetAds(AdRequest) returns (AdResponse)`: Matches incoming context keys against hardcoded ads (hair styling, kitchenware, vintage apparel) or returns random ads.
* **Health Check**: Implements `io.grpc.protobuf.services.HealthStatusManager`.
* **Docker Requirements**: Multi-stage build (`eclipse-temurin:25-jdk` -> `eclipse-temurin:25-jre-alpine`).

---

## 11. `loadgenerator`

* **Directory**: [`src/loadgenerator`](../../src/loadgenerator)
* **Language & Version**: Python 3.14 (Dockerfile uses `python:3.14.7-alpine`)
* **Entry Point**: `locustfile.py`
* **Build Command**: `pip install --prefix="/install" -r requirements.txt`
* **Startup Command**: `locust --host="http://${FRONTEND_ADDR}" --headless -u "${USERS:-10}" -r "${RATE:-1}"`
* **Listening Port**: *None* (Outbound HTTP client only)
* **Communication Protocol**: HTTP client (Locust `FastHttpUser`)
* **Environment Variables**:
  * `FRONTEND_ADDR` *(Mandatory)*: URL of frontend (e.g., `frontend:8080`).
  * `USERS` *(Optional, default: `"10"`)*: Concurrent simulated users.
  * `RATE` *(Optional, default: `"1"`)*: Hatch rate (users spawned per second).
* **Dependencies**:
  * Python packages: `locust`, `faker`.
* **API Endpoints**: None (runs as a synthetic load generator).
* **Health Check**: None (batch background client).
* **Docker Requirements**: Multi-stage build (`python:3.14.7-alpine`).

---

## 12. `shoppingassistantservice`

* **Directory**: [`src/shoppingassistantservice`](../../src/shoppingassistantservice)
* **Language & Version**: Python 3.14 (Dockerfile uses `python:3.14.7-slim`)
* **Framework**: **Flask** (`from flask import Flask, request` - note: not FastAPI)
* **Entry Point**: `shoppingassistantservice.py`
* **Build Command**: `pip install -r requirements.txt`
* **Startup Command**: `python shoppingassistantservice.py`
* **Listening Port**: `8080` (HTTP)
* **Communication Protocol**: HTTP REST (`POST /`)
* **Environment Variables**:
  * `PORT` *(Optional, default: `"8080"`)*: Listening port.
  * `PROJECT_ID` *(Mandatory)*: Google Cloud Project ID.
  * `REGION` *(Mandatory)*: Google Cloud Region.
  * `ALLOYDB_DATABASE_NAME` *(Mandatory)*: AlloyDB database name.
  * `ALLOYDB_TABLE_NAME` *(Mandatory)*: AlloyDB table name containing vector embeddings.
  * `ALLOYDB_CLUSTER_NAME` *(Mandatory)*: AlloyDB cluster name.
  * `ALLOYDB_INSTANCE_NAME` *(Mandatory)*: AlloyDB instance name.
  * `ALLOYDB_SECRET_NAME` *(Mandatory)*: Secret Manager secret name holding Postgres password.
* **Dependencies**:
  * Python packages: `flask` (3.1.3), `langchain-google-genai` (4.1.2), `langchain-google-alloydb-pg` (0.13.0), `google-cloud-secret-manager` (2.26.0).
  * Cloud Services: Google Gemini Multimodal API (`gemini-1.5-flash`), Google Generative AI Embeddings (`embedding-001`), Google Secret Manager, Google AlloyDB.
* **API Endpoints**:
  * `POST /`: Accepts `{ "message": "<string>", "image": "<url>" }`, runs multimodal RAG against AlloyDB vector store, and returns Gemini recommendation JSON.
* **Health Check**: Default Flask root handling.
* **Docker Requirements**: Multi-stage build (`python:3.14.7-slim`).
* **DevOps Note for AWS**: This service is tightly coupled to Google Cloud AlloyDB and Secret Manager. For an initial AWS deployment, this service should be kept optional; if enabled in AWS, it can be re-architected to use AWS Bedrock / OpenAI / Gemini API directly and Amazon Aurora PostgreSQL with `pgvector`.
