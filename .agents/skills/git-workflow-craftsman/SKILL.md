---
name: git-workflow-craftsman
description: Autonomous Git workflow, diff review, conventional commit authoring, and PR changelog generator. Activate when preparing clean commits, writing semantic commit messages, grouping staged changes, or drafting PR summaries.
---

# Git Workflow Craftsman (Version Control Specialist)

**Role**: Git Staging & Semantic Commit Author.

This skill guides the agent to review git diffs, stage atomic changes cleanly, craft semantic Conventional Commit messages, and generate PR summaries.

---

## Strict Quality Gates

1. **Gate 1 (Secret Leakage Filter)**: Must verify that no `.env`, credentials, tokens, or build artifacts are staged.
2. **Gate 2 (Atomic Separation)**: Must separate unrelated changes into distinct, logical commits.
3. **Gate 3 (Global Rules Sync)**: Ikuti batasan Git di Global Rules Section 4.

---

## Activation Triggers

- **WHEN**: Preparing clean commits, writing semantic commit messages, grouping staged changes, drafting PR summaries, reviewing diffs.
- **WHEN NOT**: Actual code implementation (use feature-builder/autonomous-debugger), code review feedback implementation.
- **COMPOSABILITY**: Usually the final step after any other skill completes work.

---

## Workflow Phases

### Phase 1: Diff & Status Inspection
1. **Inspect Status**: Run `git status` and `git diff` to inspect modified, created, and deleted files.
2. **Group Changes Atomically**: Group files by purpose (e.g. `feat(auth)`, `fix(api)`, `refactor(ui)`).

### Phase 2: Conventional Commit Authoring
1. **Standard Format**: `<type>(<optional scope>): <imperative summary in present tense>`. Types: `feat`, `fix`, `refactor`, `perf`, `docs`, `style`, `test`, `chore`, `ci`.
2. **Detailed Body**: Provide concise bullet points explaining technical rationale and impact when applicable.

### Phase 3: Staging & Local Commit
1. **Stage Logical Files**: Stage only files belonging to the target commit.
2. **Execute Local Commit**: Run `git commit -m "..."`.

### Phase 4: PR Summary / Changelog Generation (If requested)
1. Generate structured GitHub PR markdown: `Summary of Changes`, `Breaking Changes (if any)`, `Verification Steps`.
