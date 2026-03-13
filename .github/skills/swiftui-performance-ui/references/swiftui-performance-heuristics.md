# SwiftUI Performance Heuristics

## Keep Recompute Cheap
- Avoid expensive computed properties in `body`
- Precompute derived data before rendering
- Use fine-grained child views to reduce invalidation blast radius

## Large Collections
- Prefer lazy containers (`List`, `LazyVStack`, `LazyVGrid`) for larger datasets
- Ensure each item has stable identity
- Keep row views small and avoid deep modifier chains

## State And Observation
- Store state at the narrowest scope that still works
- Avoid single observable objects that trigger whole-screen redraws
- Use immutable value snapshots for rendering where practical

## Async Work
- Start async work as late as possible and cancel as early as possible
- De-duplicate identical in-flight requests
- Cap concurrency when loading previews/thumbnails

## Memory Discipline
- Bound cache sizes; never rely on unbounded growth
- Prefer lightweight placeholders while loading
- Release large temporary buffers quickly

## Motion And Effects
- Default to no animation unless it conveys meaning
- Avoid expensive effects in scrolling regions
- Use transitions sparingly and measure before keeping them

## Native macOS Behavior
- Use semantic system colors so Light/Dark Mode adapts automatically
- Prefer standard AppKit/SwiftUI controls and materials before custom styling
- Avoid hardcoded appearance-specific colors unless there is a strict product requirement

## Profiling Sequence
1. Reproduce with representative data
2. Measure with Time Profiler
3. Check allocations and retain growth
4. Verify improvements and regressions with before/after notes
