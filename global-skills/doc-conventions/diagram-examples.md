# Mermaid diagram examples

Canonical shapes for `system_architecture.md`. Regenerate only the diagram the
change affects.

## Request / data flow (flowchart)

```mermaid
flowchart LR
    Client[Browser] -->|HTTPS| API[API service]
    API -->|require_auth| Auth[Firebase Auth]
    API -->|read/write| DB[(Orders DB)]
    API -->|OTLP| Collector[ADOT Collector]
    Collector --> XRay[AWS X-Ray]
```

## Auth handshake (sequenceDiagram)

```mermaid
sequenceDiagram
    participant U as User
    participant FE as Frontend
    participant API as Backend
    participant FB as Firebase
    U->>FE: sign in (OAuth)
    FE->>FB: token exchange
    FB-->>FE: ID token
    FE->>API: request + Bearer token
    API->>API: require_auth -> require_mfa
    API-->>FE: 200 / 401 / 403
```

## Data model (erDiagram)

```mermaid
erDiagram
    USER ||--o{ ORDER : places
    ORDER ||--|{ ORDER_ITEM : contains
    USER {
        string uid
        string email
    }
    ORDER {
        string id
        string uid
        int amount_cents
    }
```
