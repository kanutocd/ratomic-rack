## [Unreleased]

### Added

- Added a minimal Rack handler backed by reusable Ractor workers and
  `Ratomic::LocalPool`.
- Added focused tests for request dispatch, worker reuse, error propagation,
  application shareability, and pool configuration.
- Added the Phase 0 reconnaissance report.

### Limitations

- Streaming, Rails integration, Fiber scheduling, and performance
  optimizations remain out of scope for this phase.
