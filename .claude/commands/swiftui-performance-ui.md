---
description: Design and review SwiftUI screens with performance-first constraints. Use for UI tasks where smooth scrolling, fast launch, low memory, and predictable rendering are more important than visual polish.
argument-hint: Describe the screen/flow, data size, and performance target (fps, memory, launch time).
---

# SwiftUI Performance-First UI

## When To Use
- New SwiftUI screens where performance is the primary quality goal
- UI refactors that currently stutter, over-render, or allocate too much memory
- Lists/grids with medium to large datasets
- Flows where startup speed and interaction latency matter more than advanced styling

## Operating Principle
Prioritize runtime behavior over visual complexity:
- Prefer simple composition over deeply nested decorative hierarchies
- Minimize body recomputation and view invalidation scope
- Keep memory footprint predictable and bounded
- Use visuals only when they are cheap and do not degrade frame pacing
- Prefer native platform behavior by default so macOS-provided UI functionality works automatically (Light Mode, Dark Mode, accessibility contrast, standard controls)

## Inputs To Gather First
1. Device class and OS target (e.g., older Intel Mac vs Apple Silicon)
2. Dataset size and update frequency
3. Performance budget:
   - target interaction latency
   - target frame pacing (e.g., stable 60 fps)
   - memory ceiling
4. Current symptom: slow launch, scroll hitching, typing lag, or high memory

## Procedure
1. Define a small performance budget for the requested screen and restate it.
2. Design the UI structure around data flow first:
   - keep state local where possible
   - avoid broad `@State`/`@ObservedObject` invalidation
   - split heavy sections into smaller views with stable identities
3. Build with low-cost primitives first:
   - prefer `List`/lazy containers for large collections
   - prefer semantic system colors/materials and standard controls so Light/Dark Mode support comes for free
   - avoid expensive visual effects by default (blur, layered materials, excessive shadows)
4. Guard rendering performance:
   - use stable `id` values for dynamic content
   - avoid computed work directly in `body`
   - precompute formatting/mapping in view models or cached helpers
5. Guard async/image/PDF loading paths:
   - load incrementally
   - cancel work when views disappear
   - cache with explicit bounds and invalidation strategy
6. Validate and report:
   - note expected hot paths
   - propose profiling steps with Instruments (Time Profiler, Allocations)
   - list trade-offs where design polish was intentionally reduced

## Output Contract
When executing this skill, provide:
1. Performance budget and assumptions
2. Proposed SwiftUI structure (state ownership + rendering boundaries)
3. Specific optimizations applied
4. Trade-offs accepted for performance
5. Validation checklist and what to measure next

## Performance Review Checklist
- Is any heavy transform or sort happening inside `body`?
- Are object graphs causing wide redraws?
- Are list/grid rows lightweight and identity-stable?
- Are animations intentional and limited?
- Are caches bounded and eviction-aware?
- Is work cancellation implemented for disappearing views?
- Does the screen adapt automatically to Light/Dark Mode without custom theme branching?
- Are system semantic colors used instead of hardcoded fixed colors?

## Performance Heuristics

### Keep Recompute Cheap
- Avoid expensive computed properties in `body`
- Precompute derived data before rendering
- Use fine-grained child views to reduce invalidation blast radius

### Large Collections
- Prefer lazy containers (`List`, `LazyVStack`, `LazyVGrid`) for larger datasets
- Ensure each item has stable identity
- Keep row views small and avoid deep modifier chains

### State And Observation
- Store state at the narrowest scope that still works
- Avoid single observable objects that trigger whole-screen redraws
- Use immutable value snapshots for rendering where practical

### Async Work
- Start async work as late as possible and cancel as early as possible
- De-duplicate identical in-flight requests
- Cap concurrency when loading previews/thumbnails

### Memory Discipline
- Bound cache sizes; never rely on unbounded growth
- Prefer lightweight placeholders while loading
- Release large temporary buffers quickly

### Motion And Effects
- Default to no animation unless it conveys meaning
- Avoid expensive effects in scrolling regions
- Use transitions sparingly and measure before keeping them

### Native macOS Behavior
- Use semantic system colors so Light/Dark Mode adapts automatically
- Prefer standard AppKit/SwiftUI controls and materials before custom styling
- Avoid hardcoded appearance-specific colors unless there is a strict product requirement

### Profiling Sequence
1. Reproduce with representative data
2. Measure with Time Profiler
3. Check allocations and retain growth
4. Verify improvements and regressions with before/after notes
