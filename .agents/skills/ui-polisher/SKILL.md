---
name: ui-polisher
description: Specialized UI/UX refinement workflow using CodeGraph. Activate when refining visual styling, fixing responsive layout overflows, optimizing dark/light themes, or adding shimmer states.
---

# UI Polisher (Specialized Design, UX & Self-Healing Specialist)

**Role**: Pixel-Perfect Presentation & Overflow Guard Specialist.

This skill guides the agent to craft responsive, pixel-perfect user interfaces with smooth UX, proper themes, and simple modular widget trees.

---

## Strict Quality Gates

1. **Gate 1 (Design Token Alignment)**: Must inspect existing theme tokens, typography, and color schemes via CodeGraph.
2. **Gate 2 (Global Rules Sync)**: Ikuti Global Rules untuk resource disposal, immutability, dan self-healing loop.
3. **Gate 3 (Overflow Guard)**: Must guard all dynamic text against overflow.

---

## Activation Triggers

- **WHEN**: Refining visual styling, fixing responsive layout overflows, optimizing dark/light themes, adding shimmer/loading states, accessibility improvements.
- **WHEN NOT**: Building complete new features from scratch (use feature-builder), fixing logic bugs (use autonomous-debugger), headless/backend/CLI projects (UI polisher tidak relevan untuk server-side/CLI).
- **COMPOSABILITY**: Can be invoked by feature-builder for presentation layer refinement. Usually standalone for polish tasks.

---

## Workflow Phases

### Phase 1: Design Tokens & Theme Discovery
1. **Inspect Existing UI System**: Use `codegraph_explore` to examine theme definitions, color palettes, font styles, and elevation curves.
2. **Anti-Patterns to Avoid**:
   - **NO Widget Over-Nesting (Deep Pyramid of Doom)**: Keep widget trees shallow; extract reusable components cleanly.
   - **NO Hardcoded Colors**: Always reference theme context.
   - **NO Fixed-Height Containers for Dynamic Content**: Prevent overflow errors.

### Phase 2: Responsive & Accessibility Rules
1. **Accessibility Rule**: All interactive widgets MUST have semantic labels. Minimum touch target 48x48dp. Text MUST meet WCAG AA contrast ratio.
2. **i18n Rule**: User-facing strings MUST NOT be hardcoded. Use localization framework.
3. **Layout Guarding**: Wrap variable-length text appropriately and make vertical forms scrollable.

### Phase 3: Micro-Interactions & Loading States
1. Replace jarring spinners with skeleton shimmer loaders.
2. Implement clean empty state illustrations and error retry cards.

### Phase 4: Tech-Stack Implementations
- **Flutter**: `Theme.of(context)`, `Semantics` widget, `MediaQuery`, `LayoutBuilder`.
- **React / Next.js**: Tailwind CSS / CSS Modules, `aria-*` attributes, responsive utility classes.
- **Android (Jetpack Compose)**: MaterialTheme, `Modifier.semantics`, `Modifier.fillMaxWidth()`.
- **iOS (SwiftUI)**: `.accessibilityLabel()`, dynamic type, responsive stacks (`VStack`/`HStack`).
- **Desktop (.NET MAUI / WPF / Qt)**: Responsive grids, dynamic resource styles, accessibility peers.
