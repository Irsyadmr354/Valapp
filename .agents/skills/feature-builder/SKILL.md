---
name: feature-builder
description: Macro-orchestrator workflow for end-to-end feature creation using CodeGraph. Activate when building new features, full modules, or screens from scratch that require data models, state management, and UI.
---

# Feature Builder (Macro-Orchestrator & Self-Healing)

**Role**: End-to-End Feature Architect (Building New Features from Scratch).

This skill guides the agent to plan, scaffold, and implement complete, production-ready features from end to end with strict architecture boundaries.

---

## Strict Quality Gates

1. **Gate 1 (Architecture Discovery)**: Must inspect existing patterns, DI setup, and state management conventions via CodeGraph prior to scaffolding.
2. **Gate 2 (Global Rules Sync)**: Ikuti Global Rules untuk YAGNI, immutability, layer separation, resource disposal, dan self-healing loop.
3. **Gate 3 (Completeness)**: Must implement all states (loading, success, empty, error) gracefully.

---

## Activation Triggers

- **WHEN**: Building new features, full modules, or screens from scratch that require data models + state management + UI.
- **WHEN NOT**: Fixing bugs in existing features (use autonomous-debugger), pure UI refinement (use ui-polisher), pure API integration without UI (use api-integrator).
- **COMPOSABILITY**: Orchestrates api-integrator (for data layer) and ui-polisher (for presentation refinement). Feature-builder is the lead.

---

## Workflow Phases

### Phase 1: Architecture & Graph Discovery
1. **Map Existing Architecture**: Run `codegraph_explore` on existing features to mirror conventions, DI injection, and state patterns.
2. **Identify Integration Touchpoints**: Locate routers, navigation tables, API clients, and repositories.

### Phase 2: Contracts & Core Implementation
1. **Define Strict Data Contracts**: Create models with full null-safety.
2. **Testing Rule**: New features with business logic MUST include basic unit tests for the domain/logic layer.
3. **Performance Rule**: Lists MUST use lazy builders (ListView.builder). All states (loading, success, empty, error) MUST be implemented.

### Phase 3: Integration & Self-Healing
1. Register routes, wire dependency injections, and link UI navigation.
2. Lakukan self-healing dan formatting sesuai aturan global jika terdapat error saat verifikasi.

### Phase 4: Tech-Stack Architecture & Folder Structure
- **Flutter**: `lib/features/<name>/data|domain|presentation/`
- **React / Next.js**: `src/features/<name>/components|hooks|services/`
- **Python**: `app/<name>/models|services|routers/`
- **Go**: `internal/<name>/handler|service|repository/`
- **Rust**: `src/<name>/mod.rs` (submodules: `models`, `handlers`, `services`)
- **Java / Kotlin**: `src/main/kotlin/com/app/<feature>/controller|service|repository/`
- **C# / .NET**: `Features/<Name>/Commands|Queries|Controllers/` (Vertical Slice) atau `Controllers/`, `Services/`
