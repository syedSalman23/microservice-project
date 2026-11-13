# Application Architecture & Execution Flows

This document details the architectural topology, patterns, and end-to-end execution journeys of the Online Boutique application.

---

## 1. Architectural Topology

```mermaid
flowchart TD
    subgraph Ingress [Client Layer]
        Browser([Web Browser])
        Bot[loadgenerator]
    end

    subgraph Presentation [Web Presentation Layer]
        FE[frontend\nGo :8080]
    end

    subgraph CoreServices [Core gRPC Microservices Mesh]
        AD[adservice\nJava :9555]
        RC[recommendationservice\nPython :8080]
        PC[productcatalogservice\nGo :3550]
        CR[currencyservice\nNode.js :7000]
        CS[cartservice\nC# :7070]
        SH[shippingservice\nGo :50051]
        CK[checkoutservice\nGo :5050]
        PM[paymentservice\nNode.js :50051]
        EM[emailservice\nPython :8080]
    end

    subgraph StateAndAI [Data & External Services]
        RD[(Redis Cart Store\nTCP :6379)]
        SA[shoppingassistantservice\nPython :8080]
        Gemini[[Google Gemini LLM]]
        AlloyDB[(AlloyDB Vector DB)]
    end

    Browser -->|HTTP GET/POST| FE
    Bot -.->|Synthetic HTTP| FE

    FE -->|gRPC GetAds| AD
    FE -->|gRPC ListRecommendations| RC
    FE -->|gRPC ListProducts / GetProduct| PC
    FE -->|gRPC Convert / GetSupportedCurrencies| CR
    FE -->|gRPC GetCart / AddItem / EmptyCart| CS
    FE -->|gRPC GetQuote| SH
    FE -->|gRPC PlaceOrder| CK
    FE -->|HTTP POST /bot| SA

    RC -->|gRPC ListProducts| PC
    CS -->|TCP Store/Retrieve| RD

    CK -->|gRPC GetCart / EmptyCart| CS
    CK -->|gRPC GetProduct| PC
    CK -->|gRPC Convert| CR
    CK -->|gRPC Charge| PM
    CK -->|gRPC GetQuote / ShipOrder| SH
    CK -->|gRPC SendOrderConfirmation| EM

    SA -->|Prompt / Image| Gemini
    SA -->|Vector Similarity| AlloyDB
```

---

## 2. Core Architectural Patterns

1. **Composite UI / Ingress Aggregator Pattern**:
   * The `frontend` acts as an API gateway and UI renderer. It receives browser HTTP requests, invokes multiple backend gRPC microservices concurrently, assembles the responses, and renders HTML server-side.
2. **Saga / Orchestration Pattern (`checkoutservice`)**:
   * Order placement involves multiple distributed participants (Cart, Catalog, Currency, Payment, Shipping, Email). The `checkoutservice` acts as a centralized orchestrator managing the workflow sequentially:
     1. Validate & retrieve cart
     2. Calculate totals and convert currency
     3. Authorize payment
     4. Book shipping label
     5. Clear cart
     6. Dispatch confirmation email
3. **Graceful Fallback & Fault Tolerance**:
   * **Non-critical failures**: If `adservice` or `recommendationservice` fails or times out, the `frontend` catches the gRPC exception, logs a warning, and renders the webpage without ads or recommendations.
   * **Critical failures**: Failures in `cartservice`, `productcatalogservice`, or `paymentservice` during checkout abort the transaction and display a structured error page (`HTTP 500`).
4. **Externalized Polyglot State**:
   * The web and business logic tiers maintain zero in-memory session data. State is externalized to Redis, allowing pods to be destroyed, rescheduled, or scaled without user data loss.

---

## 3. End-to-End User Journeys & Sequence Flows

### Journey A: User Opens the Home Page (`GET /`)

When a user visits the root URL:
1. `frontend` checks for the `shop_session-id` cookie. If not found, it generates a new UUID session token.
2. `frontend` calls `currencyservice.GetSupportedCurrencies()` to populate the currency selector dropdown.
3. `frontend` calls `productcatalogservice.ListProducts()` to retrieve all products.
4. For each product, `frontend` calls `currencyservice.Convert()` to display prices in the selected currency (default: USD).
5. `frontend` calls `cartservice.GetCart(sessionID)` to show current cart item count.
6. `frontend` calls `adservice.GetAds()` passing context keywords to load promotional banners.
7. HTML template `home` is rendered and returned to the browser.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant FE as frontend (Go)
    participant CS as currencyservice (Node.js)
    participant PC as productcatalogservice (Go)
    participant CR as cartservice (C#)
    participant AD as adservice (Java)

    User->>FE: GET / (Browser request)
    FE->>FE: Verify or issue shop_session-id cookie
    par Retrieve initial data
        FE->>CS: GetSupportedCurrencies()
        CS-->>FE: Currency list [USD, EUR, GBP, ...]
        FE->>PC: ListProducts()
        PC-->>FE: Product list
        FE->>CR: GetCart(userId)
        CR-->>FE: Cart items count
        FE->>AD: GetAds(["clothing", "decor"])
        AD-->>FE: Ad banner content
    end
    FE->>CS: Convert(price, targetCurrency)
    CS-->>FE: Localized prices
    FE-->>User: 200 OK (Rendered HTML Home Page)
```

---

### Journey B: User Browses a Product (`GET /product/{id}`)

1. Browser requests a product detail page.
2. `frontend` calls `productcatalogservice.GetProduct(id)`.
3. `frontend` converts product price using `currencyservice.Convert()`.
4. `frontend` calls `recommendationservice.ListRecommendations(userId, [id])`.
   * `recommendationservice` internally calls `productcatalogservice.ListProducts()` to fetch all items, filters out the current product ID, samples up to 5 recommendations, and returns them.
5. `frontend` calls `adservice.GetAds()` using product category context.
6. HTML template `product` is rendered and returned.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant FE as frontend (Go)
    participant PC as productcatalogservice (Go)
    participant RC as recommendationservice (Python)
    participant CS as currencyservice (Node.js)

    User->>FE: GET /product/0PUK6V6EV0
    FE->>PC: GetProduct(id: "0PUK6V6EV0")
    PC-->>FE: Product details (name, price_usd, categories)
    FE->>CS: Convert(price_usd, user_currency)
    CS-->>FE: Localized price
    FE->>RC: ListRecommendations(userId, ["0PUK6V6EV0"])
    RC->>PC: ListProducts()
    PC-->>RC: Full catalog
    RC-->>FE: 5 Recommended Product IDs
    FE-->>User: 200 OK (Product Detail Page)
```

---

### Journey C: User Adds a Product to the Cart (`POST /cart`)

1. User submits product ID and quantity from the product page.
2. `frontend` validates form parameters (`product_id`, `quantity`).
3. `frontend` calls `cartservice.AddItem(userId, CartItem)`.
4. `cartservice` serializes the cart item and executes `HSET` / `SET` against the Redis store.
5. `frontend` redirects browser to `GET /cart`.
6. `frontend` calls `cartservice.GetCart(userId)` to fetch all items, computes line-item prices and totals via `productcatalogservice` and `currencyservice`, and renders the cart page.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant FE as frontend (Go)
    participant CS as cartservice (C#)
    participant RD as Redis Store

    User->>FE: POST /cart {product_id: "OLJCESPC7Z", quantity: 2}
    FE->>CS: AddItem(userId, {productId: "OLJCESPC7Z", quantity: 2})
    CS->>RD: Save/Update cart key: cart:userId
    RD-->>CS: OK
    CS-->>FE: Empty response (Success)
    FE-->>User: 303 See Other (Redirect to /cart)
```

---

### Journey D: User Completes Checkout (`POST /cart/checkout`)

This is the primary distributed transaction in the system:

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant FE as frontend (Go)
    participant CK as checkoutservice (Go)
    participant CS as cartservice (C#)
    participant PC as productcatalogservice (Go)
    participant CR as currencyservice (Node.js)
    participant SH as shippingservice (Go)
    participant PM as paymentservice (Node.js)
    participant EM as emailservice (Python)

    User->>FE: POST /cart/checkout {address, email, cc_info}
    FE->>CK: PlaceOrder(userId, currency, address, email, credit_card)

    rect rgb(240, 248, 255)
    note right of CK: Step 1: Prepare Cart & Prices
    CK->>CS: GetCart(userId)
    CS-->>CK: cartItems [...]
    loop For each cart item
        CK->>PC: GetProduct(item.productId)
        PC-->>CK: Product details & USD price
        CK->>CR: Convert(price_usd, user_currency)
        CR-->>CK: Localized price
    end
    end

    rect rgb(255, 250, 240)
    note right of CK: Step 2: Shipping Quote & Total
    CK->>SH: GetQuote(address, cartItems)
    SH-->>CK: shippingCost (USD)
    CK->>CR: Convert(shippingCost, user_currency)
    CR-->>CK: Localized shipping price
    CK->>CK: Compute Grand Total = Sum(items * qty) + shipping
    end

    rect rgb(240, 255, 240)
    note right of CK: Step 3: Payment Processing
    CK->>PM: Charge(total, credit_card)
    PM-->>CK: transaction_id (UUID)
    end

    rect rgb(255, 240, 245)
    note right of CK: Step 4: Fulfillment & Cleanup
    CK->>SH: ShipOrder(address, cartItems)
    SH-->>CK: tracking_id
    CK->>CS: EmptyCart(userId)
    CS-->>CK: Cart emptied
    CK->>EM: SendOrderConfirmation(email, orderResult)
    EM-->>CK: Email dispatched
    end

    CK-->>FE: PlaceOrderResponse { OrderResult }
    FE-->>User: 200 OK (Order Confirmation Page)
```

---

### Journey E: Shopping Assistant Interaction (`POST /bot`)

1. User opens the Assistant page (`/assistant`), selects or uploads a room image, and enters a prompt.
2. Browser sends `POST /bot` with prompt and image URL.
3. `frontend` forwards the payload via HTTP `POST` to `http://${SHOPPING_ASSISTANT_SERVICE_ADDR}/`.
4. `shoppingassistantservice` performs multimodal RAG:
   * Calls Google Gemini Vision (`gemini-1.5-flash`) to generate a textual description of the room's style.
   * Runs similarity search against the AlloyDB vector database (`AlloyDBVectorStore`) using product embeddings (`models/embedding-001`).
   * Calls Gemini LLM with the retrieved product context and user query.
5. Returns JSON response containing recommendation text and suggested product IDs.
