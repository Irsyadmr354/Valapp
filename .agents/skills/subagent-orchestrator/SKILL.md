---
name: subagent-orchestrator
description: Multi-agent parallel task orchestration and delegation workflow. Activate when handling massive multi-module projects, concurrent architectural investigations, parallel refactoring across independent packages, or complex multi-agent workflows.
---

# Subagent Orchestrator (Multi-Agent Parallelism Specialist)

**Role**: Multi-Agent Dispatcher & Parallel Workflow Coordinator.

This skill guides the agent to systematically decompose massive tasks into independent work streams, spawn and coordinate specialized subagents in parallel, and synthesize their results.

---

## Strict Quality Gates

1. **Gate 1 (Task Independence)**: Subagents must only be spawned for independent or loosely-coupled subtasks to prevent merge collisions.
2. **Gate 2 (Global Rules Sync)**: Ikuti Global Rules Section 8 untuk delegasi proaktif dan koordinasi reaktif (no polling loops).
3. **Gate 3 (Synthesis Verification)**: The parent agent must verify and compile all changes produced by subagents, ensuring zero merge conflicts or compiler errors.

---

## Activation Triggers

- **WHEN**: Tasks spanning 3+ independent modules, massive multi-file refactoring across decoupled packages, concurrent investigation needs.
- **WHEN NOT**: Single-file edits, quick lookups, sequential tasks with dependencies between steps.
- **COMPOSABILITY**: Meta-skill that orchestrates other skills. Each subagent can use any other skill.

---

## Workflow Phases

### Phase 1: Work Breakdown Structure (WBS)
1. **Deconstruct the Objective**: Split the overarching task into 2–4 decoupled, autonomous scopes.
2. **Define Clear Contracts**: Provide each subagent with exact file paths, expected signatures, and boundary constraints.

### Phase 2: Role Definition & Parallel Invocation
1. **Select Subagent Types**: `research` for read-only codebase exploration, `self` for full write isolation, or custom subagents.
2. **Invoke Concurrently**: Call `invoke_subagent` with the list of configured subagent prompts in a single batch.

### Phase 3: Monitoring & Communication
1. **Inter-Agent Communication**: Use `send_message` with the recipient's `conversationID` if instructions need updating.

### Phase 4: Synthesis & Verification
1. **Merge & Review Changes**: Inspect all modifications made across subagent workspaces.
2. **Run Global Verification**: Execute project linter and build check (`flutter analyze`, `npm run build`, `pytest`). Provide a unified completion summary.
