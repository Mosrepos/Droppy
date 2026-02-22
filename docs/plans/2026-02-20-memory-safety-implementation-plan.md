# Memory Safety Sweep Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Apply low-risk, behavior-preserving memory leak fixes and memory optimizations across the app.

**Architecture:** Perform a static leak-risk audit, prioritize long-lived components first, then implement minimal lifecycle-safe fixes (observer/timer/task cancellation and cache bounds) without altering feature behavior.

**Tech Stack:** Swift, SwiftUI, AppKit, Foundation, Combine.

---

### Task 1: Inventory Leak-Prone Patterns

**Files:**
- Modify: `Droppy/` Swift sources identified by search output

**Step 1: Identify observer usage**
Run: `rg "NotificationCenter\\.default\\.(addObserver|removeObserver)" Droppy -n`
Expected: list of explicit observer lifecycle sites

**Step 2: Identify timers/display links**
Run: `rg "Timer\\.|CADisplayLink|DispatchSourceTimer" Droppy -n`
Expected: timer creation and invalidation sites

**Step 3: Identify escaping closures with potential strong captures**
Run: `rg "Task \\{|\\.sink|\\.onReceive|addObserver\\(forName" Droppy -n`
Expected: async callback sites that may retain owners

**Step 4: Identify cache structures**
Run: `rg "NSCache|Dictionary<|\\[.*:.*\\].*cache|Cache" Droppy -n`
Expected: in-memory cache candidates for safe bounds

### Task 2: Fix Lifecycle Leaks in Long-Lived Components

**Files:**
- Modify: specific manager/controller files found in Task 1

**Step 1: Add deterministic teardown for observer tokens**
- Store closure-based observer tokens if missing.
- Remove them in `deinit` or shutdown path.

**Step 2: Cancel/invalidate timers and background tasks**
- Ensure `invalidate()` / `cancel()` is called on lifecycle end.

**Step 3: Add weak capture where ownership is not required**
- Convert risky escaping captures to `[weak self]` with safe early return.

### Task 3: Apply Safe Cache Bounds

**Files:**
- Modify: cache-related files found in Task 1 (e.g. image/thumbnail/link preview caches)

**Step 1: Add conservative limits**
- Add `countLimit`/`totalCostLimit` for `NSCache` where absent.

**Step 2: Preserve semantics**
- Keep existing cache keys, values, and lookup behavior unchanged.

### Task 4: Consistency Verification (No Build)

**Files:**
- Review touched files

**Step 1: Re-scan cleanup symmetry**
Run: `rg "addObserver\\(|scheduledTimer|Task \\{" Droppy -n`
Expected: each long-lived registration has a matching teardown path.

**Step 2: Review patch scope**
Run: `git diff --stat && git diff`
Expected: only low-risk memory lifecycle/cache edits.

### Task 5: Final Notes

**Step 1: Prepare release-note summary**
- Summarize leak fixes and memory optimizations in plain language.

