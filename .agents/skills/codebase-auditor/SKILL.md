---
name: codebase-auditor
description: Autonomous read-only architectural, security, performance, memory leak, and rules compliance audit workflow using CodeGraph. Activate when requested to audit a project, review codebase health, assess technical debt, or verify adherence to Global Rules.
---

# Codebase Auditor (Diagnostic, Security & Architectural Health Specialist)

**Role**: Read-Only Codebase Quality, Security & Architecture Auditor.

This skill guides the agent to systematically analyze, evaluate, and benchmark codebases against architecture boundaries, security best practices, memory lifecycle management, async safety, test coverage, and Global Rules without modifying code.

---

## Strict Quality Gates

1. **Gate 1 (Read-Only Safety)**: STRICTLY FORBIDDEN to modify or delete code during audit phases. Output must be a diagnostic assessment.
2. **Gate 2 (Zero-Hallucination & Verifiable Evidence)**: Every reported violation or finding MUST include exact file path and line number reference (`file:///...#Lxx`) verified via CodeGraph or file inspection.
3. **Gate 3 (Structured Artifact Deliverable)**: Must produce a structured Markdown Artifact containing Executive Health Score, Findings Matrix by Severity (Critical, High, Medium, Low), and an Actionable Remediation Roadmap.

---

## Activation Triggers

- **WHEN**: User requests "audit project", "audit codebase", "review arsitektur", security review, memory leak assessment, technical debt audit, or pre-release verification.
- **WHEN NOT**: Active bug fixing (use `autonomous-debugger`), active refactoring (use `smart-refactor`), building new features (use `feature-builder`).
- **COMPOSABILITY**: Primary diagnostic skill. Feeds actionable findings to `autonomous-debugger` (for critical defects/leaks) or `smart-refactor` (for structural/debt cleanup).

---

## 6 Audit Pillars

1. **Pillar 1 (Architecture & Separation of Concerns)**:
   - UI/Client accessing raw HTTP or database queries directly?
   - Handler/Controller bypassing Service/UseCase layer in Backend services?
   - God classes/widgets exceeding single responsibility? State mutability violations?
2. **Pillar 2 (Security & Secret Leakage)**:
   - Hardcoded API keys, tokens, credentials, or un-gitignored `.env` files?
   - Insecure plaintext storage of authentication tokens in client or logs?
3. **Pillar 3 (Memory Leaks & Lifecycle Disposal)**:
   - Undisposed controllers (`TextEditingController`, `AnimationController`, `ScrollController`)?
   - Uncancelled `StreamSubscription`, abandoned goroutines without context cancellation, or undisposed `IDisposable` / `AutoCloseable`?
   - Unclosed database connections, sockets, or HTTP response bodies?
4. **Pillar 4 (Performance & Async Safety)**:
   - Unawaited side-effectful Futures/Tasks, blocking async event loops, or `.Result` deadlock hazards in C#?
   - N+1 database queries inside loops (missing batching/joins/eager loading)?
   - O(n²) operations in hot paths, non-lazy lists (>20 items), or unpaginated list APIs?
   - Un-debounced search inputs or unthrottled event listeners?
5. **Pillar 5 (Testing & Regression Readiness)**:
   - Complex business logic without unit tests covering happy/error paths?
   - Existing test suite pass status and regression coverage health?
6. **Pillar 6 (Global Rules & Standards Compliance)**:
   - Naming conventions adherence across layers according to tech-stack template?
   - For UI projects: hardcoded user strings (i18n), touch targets <48dp, and missing accessibility semantics?
   - SQL schema modifications lacking versioned migration scripts, or NoSQL schema changes lacking defensive deserialization?

---

## Workflow Phases

### Phase 1: Codebase Mapping & Scale Assessment
1. **Scale Check**:
   - Small repo/module (<30 files): Perform direct single-agent inspection via `codegraph_explore`.
   - Large repo (>50 files): Spawn 2–3 parallel `research` subagents (e.g. Subagent A: Architecture & Leaks, Subagent B: Security & Async, Subagent C: Testing & Standards) using lean prompts.
2. **Explore Call Hierarchy**: Map entry points, dependency injection setup, and global state stores.

### Phase 2: Multi-Pillar Deep Inspection
1. Inspect each of the 6 pillars systematically against Global Rules (§1 to §17).
2. Record evidence for each finding: exact file, line number, violated rule, and impact.

### Phase 3: Risk Scoring & Remediation Planning
1. Categorize findings into Severity Tiers:
   - **Critical**: Security leaks, persistent memory leaks, crash-inducing unhandled async errors.
   - **High**: Architectural boundary breaches, unawaited critical mutations, missing migrations.
   - **Medium**: Performance bottlenecks, non-lazy lists, missing unit tests on core logic.
   - **Low**: Naming inconsistencies, hardcoded strings, missing documentation comments.
2. Separate remediation into **Quick-Wins** (immediate auto-fix) vs **Deep Refactors** (architectural realignment).

### Phase 4: Deliverable Artifact Publication & Next-Step Guidance
1. Create a structured Markdown Artifact (`audit-report.md`) in the brain directory with:
   - Executive Summary & Overall Health Score (e.g. A/B/C/D).
   - Findings Table with direct links.
   - Actionable Remediation Roadmap.
2. Provide a concise chat summary offering next actions (e.g. "Trigger `autonomous-debugger` to fix Critical Leaks").
