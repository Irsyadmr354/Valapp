---
name: smart-refactor
description: Autonomous code refactoring and cleanup workflow using CodeGraph. Activate when refactoring, simplifying, modularizing, or optimizing WORKING code without breaking existing behavior.
---

# Smart Refactor (Code Health & Self-Healing Specialist)

**Role**: Structural Debt & Complexity Reducer (Optimizing Working Code).

This skill guides the agent to systematically refactor, simplify, and optimize code with zero breaking changes and guaranteed functional equivalence.

---

## Strict Quality Gates

1. **Gate 1 (Dependency Lock)**: Must map all inbound and outbound callers via CodeGraph before modifying signatures.
2. **Gate 2 (Global Rules Sync)**: Ikuti Global Rules untuk KISS, immutability, disposal lifecycle, dan self-healing loop.
3. **Gate 3 (Equivalence)**: Must guarantee 0 compiler warnings and exact behavioral equivalence.

---

## Activation Triggers

- **WHEN**: Refactoring, simplifying, modularizing, or optimizing WORKING code without changing behavior.
- **WHEN NOT**: Code is broken/buggy (use autonomous-debugger), building new features (use feature-builder), pure UI changes (use ui-polisher).
- **COMPOSABILITY**: May be triggered by autonomous-debugger if root cause is structural. Usually standalone.

---

## Workflow Phases

### Phase 1: Call Hierarchy & Dependency Mapping
1. **Map Call Graph**: Run `codegraph_explore` on the target module to map every consumer and caller.
2. **Identify Targets**: Look for over-engineered abstractions, God-classes, deeply nested conditional trees, duplicated logic, and dead code.

### Phase 2: Refactoring Strategy & Simplification
1. **Preserve Public API**: Keep public method signatures and return types backward-compatible with mapped callers.
2. **Performance Rule**: Refactoring MUST NOT degrade runtime performance. Verify no new O(n^2) patterns introduced.
3. **Anti-Patterns to Avoid**:
   - **NO Unplanned API Breaks**: Never change a public signature without updating all callers.
   - **NO Cosmetic-Only Churn**: Do not refactor code purely for aesthetic reasons if it adds no structural value.

### Phase 3: Dead Code Elimination
1. Remove unused imports, deprecated helper functions, and abandoned variables.

### Phase 4: Tech-Stack Verification Commands
- **Flutter**: `flutter analyze`, `flutter test`
- **Node.js**: `npm run lint`, `npm test`
- **Python**: `pytest -q`, `black .` / `ruff check`
- **Go**: `golangci-lint run`, `go test ./...`
- **Rust**: `cargo clippy`, `cargo test`
- **Java/Kotlin**: `./gradlew check`, `./gradlew test`
- **C#/.NET**: `dotnet format --verify-no-changes`, `dotnet test`
