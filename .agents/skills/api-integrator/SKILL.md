---
name: api-integrator
description: Specialized network integration workflow using CodeGraph. Activate when connecting backend endpoints, managing authentication headers/tokens, writing type-safe serialization models, implementing pagination, or adding error retry interceptors.
---

# API Integrator (Specialized Network & Self-Healing Specialist)

**Role**: Deep Backend & Network Plumbing Specialist.

This skill guides the agent to integrate, configure, and consume backend APIs with enterprise-grade error resilience, auth security, lifecycle management, and type safety.

---

## Strict Quality Gates

1. **Gate 1 (Client Consistency)**: Must inspect existing network client and interceptors via CodeGraph.
2. **Gate 2 (Global Rules Sync)**: Ikuti Global Rules untuk pragmatisme (KISS/YAGNI) dan siklus perbaikan otomatis (self-healing loop 3-loop).
3. **Gate 3 (Security)**: Never log raw tokens or credentials; ensure thread-safe token refresh handling.

---

## Activation Triggers

- **WHEN**: Connecting backend endpoints, managing auth tokens, writing serialization models, implementing pagination, adding retry interceptors.
- **WHEN NOT**: Pure UI changes (use ui-polisher), refactoring existing API code without adding new endpoints (use smart-refactor).
- **COMPOSABILITY**: Can be used alongside feature-builder (api-integrator handles data layer, feature-builder orchestrates).

---

## Workflow Phases

### Phase 1: Client & Architecture Discovery
1. **Inspect Network Stack**:
   - Use `codegraph_explore` to inspect existing HTTP clients (Dio/Axios/Http), base URLs, headers, and interceptor chains.
2. **Trace Auth Token Lifecycle**:
   - Identify where access/refresh tokens are stored securely and how headers are injected.

### Phase 2: Type-Safe Data Models & DTOs
1. **Generate Null-Safe & Immutable Models**:
   - Create clean, direct DTOs with defensive deserializers (`fromJson`) that handle missing/null keys without throwing runtime type errors.
2. **Anti-Patterns to Avoid**:
   - **NO Token Race Conditions**: Token refresh must be mutex-locked to prevent duplicate concurrent refresh calls.

### Phase 3: Service Layer & Interceptors
1. **Implement Clean Service Methods**: Strongly-typed request payloads and return types.
2. **Performance Rule**: API responses MUST implement pagination for list endpoints. Enforce connection/send/receive timeout configs.
3. **Network Resilience**: 401 Unauthorized token refresh interceptor, CancelTokens, and human-readable error mapping.

### Phase 4: Integration Branching (Tech-Stack Specific)
- **Flutter/Dart**: Dio interceptors, `cookie_jar`, CancelToken.
- **Node.js/TypeScript**: Axios interceptors, fetch API, AbortController.
- **Python**: `httpx` / `requests` with HTTPAdapter retry and async clients.
- **Go**: `net/http` client with `context.Context` timeout, Resty, middleware roundtrippers.
- **Rust**: `reqwest` async client with timeout, retry middleware, serde JSON deserialization.
- **Java/Kotlin**: Retrofit / OkHttp interceptors / Spring WebClient.
- **C#/.NET**: `HttpClientFactory` singleton, Polly retry policy, Refit.
