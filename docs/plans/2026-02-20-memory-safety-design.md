# Memory Safety and Optimization Design (Low Risk)

**Date:** 2026-02-20  
**Scope:** Entire app (`Droppy/`)  
**Constraint:** Only low-risk, behavior-preserving changes.

## Goals
- Remove likely memory leaks caused by retain cycles and missed lifecycle cleanup.
- Reduce avoidable memory growth from unbounded caches and long-lived transient buffers.
- Preserve existing user-facing behavior and timing.

## Non-Goals
- No architectural rewrites.
- No fallback behavior paths.
- No feature changes.
- No build/test verification in this pass (per project instruction).

## Approach Options
1. Static audit and targeted patching (recommended)
2. Runtime instrumentation then patching
3. Hybrid static+runtime

Selected: **Option 1** for maximum safety and speed.

## Allowed Change Types
- Add weak captures in escaping closures where ownership is not required.
- Ensure deterministic observer/timer/task teardown in `deinit` or explicit lifecycle exits.
- Add safe cache limits/eviction for in-memory caches without changing cache key/value semantics.
- Use tighter temporary object lifetimes in hot loops where applicable.

## Risk Controls
- One-file, one-concern edits.
- No public API shape changes.
- No control-flow rewrites.
- Re-read each touched file post-edit for lifecycle symmetry.

## Deliverables
- Code changes in leak-prone managers/views/controllers.
- Short release-note-ready summary.
