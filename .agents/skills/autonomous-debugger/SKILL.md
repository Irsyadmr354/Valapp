---
name: autonomous-debugger
description: Autonomous bug and error resolution workflow using CodeGraph. Activate when fixing runtime errors, exceptions, stack traces, compiler/linter warnings, or broken functional behavior.
---

# Autonomous Debugger (CodeGraph-Powered & Hardened)

**Role**: Incident & Defect Resolution Specialist (Fixing Broken Code).

This skill guides the agent to systematically diagnose, trace, and resolve bugs, runtime crashes, and memory leaks autonomously with production-ready fixes, zero regressions, and autonomous self-healing.

---

## Strict Quality Gates

1. **Gate 1 (Trace)**: Must identify failing symbols and trace call hierarchy via CodeGraph before touching any file. (Ikuti Global Rules CodeGraph-First).
2. **Gate 2 (Diagnosis & Simplicity)**: Must prove the root cause mechanism and apply the simplest direct fix. Dilarang over-engineering saat memperbaiki bug lokal.
3. **Gate 3 (Global Rules Sync)**: Ikuti Global Rules untuk disposal lifecycle dan autonomous self-healing 3-loop.

---

## Activation Triggers

- **WHEN**: Runtime errors, exceptions, stack traces, compiler/linter warnings, broken functional behavior, performance bugs.
- **WHEN NOT**: Code works correctly but needs structural cleanup (use smart-refactor), building new features (use feature-builder).
- **COMPOSABILITY**: Usually standalone. May hand off to smart-refactor if root cause is structural.

---

## Workflow Phases

### Phase 1: Stack Trace & Root Cause Diagnosis
1. **Extract Root Symbols & Trace**:
   - Extract exact class, function, or method names from stack traces or runtime logs. Explore callers via `codegraph_explore`.
2. **Investigate Failure Modes**:
   - Asynchronous race conditions, null-safety violations, and unhandled optional types.

### Phase 2: Robust & Simple Autonomous Fix
1. **Implement Direct Fix at Root**:
   - Fix the defect at the actual origin using the cleanest, simplest approach that works.
   - Add defensive guards and default fallbacks.
2. **Anti-Patterns to Avoid**:
   - **NO Band-Aid Fixes**: Never suppress errors with empty `try/catch` blocks.
   - **NO Blind Force-Unwrapping**: Never use force unwrap / non-null assertion (`!`) without proving non-null invariants.

### Phase 3: Testing Rule
- After fixing a bug, verify existing tests pass. If no test covers the fixed behavior, write a regression test.

### Phase 4: Tech-Stack Verification Commands
- **Flutter**: `flutter analyze`, `flutter test`, `FlutterError` handling.
- **Node.js**: `npm test`, `eslint`, `unhandledRejection` handlers.
- **Python**: `pytest -q`, `mypy .`, traceback parsing.
- **Go**: `go vet ./...`, `go test -race ./...`, goroutine dump inspection.
- **Rust**: `cargo clippy`, `cargo test`, backtrace analysis (`RUST_BACKTRACE=1`).
- **Java/Kotlin**: `./gradlew test`, stack trace analysis.
- **C#/.NET**: `dotnet test`, exception middleware inspection.
