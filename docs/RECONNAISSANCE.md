# Reconnaissance Report

Date: 2026-09-16

This report records the initial state of `ratomic-rack` and the sibling
`../ratomic` repository. The sibling repository was inspected at commit
`db8387e` (`ratomic` 0.4.3). `IMPLEMENTATION.md` is not present under
`.ignoreme/codex`; this report follows `IMPLEMENTATION_PLAN.md`.

## Executive summary

The current repository contains the minimal Phase 1/2 Rack adapter and quality
tooling. The most important finding is that
`Ratomic::LocalPool` is a resource-locality primitive, not an execution or
worker-dispatch pool. It can be used inside Ractor workers to own live clients
or connections, but a request execution layer will require an additional
Ractor worker/dispatch abstraction or a separately verified Ratomic API.

## Existing Ratomic APIs

`Ratomic::LocalPool` is implemented in `../ratomic/lib/ratomic/local_pool.rb`
and declared in `../ratomic/sig/ratomic.rbs`.

- Constructor: `Ratomic::LocalPool.new(size:, timeout:, factory:)`, or a block
  factory. `size` defaults to 5 and `timeout` defaults to 1.0 seconds.
- The factory must respond to `#call` and be Ractor-shareable.
- The `LocalPool` facade is frozen and made Ractor-shareable.
- `#with` checks out a resource from the current Ractor's private,
  thread-safe pool, yields it, and checks it back in.
- `#close`/`#shutdown` close only the current Ractor's local pool.
- `#size` returns the configured per-Ractor pool size.
- Checkout timeout is translated to `Ratomic::Error` with
  `pool checkout timeout`.
- Resources are created, used, and closed within their owning Ractor. Threads
  in one Ractor share that Ractor's local pool; different Ractors do not share
  live resources.

Other relevant Ratomic primitives are:

- `Ratomic::Pool`: ownership-transfer pool for plain mutable Ruby objects.
  Checkout/checkin uses Ractor move semantics and stale references can raise
  `Ractor::MovedError`.
- `Ratomic::Counter`, `Ratomic::Map`, and `Ratomic::Queue`: Ractor-shareable
  shared-state primitives backed by the native extension.

No existing LocalPool API submits arbitrary blocks, acquires an execution
worker, or returns a request result. Do not treat `LocalPool#with` as a Rack
request dispatcher.

## Ractor abstractions

Ratomic uses Ruby's native Ractor primitives directly:

- `Ratomic::Pool` uses a coordinator Ractor and `Ractor::Port` reply paths.
- `Ratomic::LocalPool` stores a per-Ractor resource pool through
  `Ractor.current` storage.
- The Ratomic tests exercise `Ractor.new`, `Ractor#join`, `Ractor#value`,
  `Ractor.shareable?`, `Ractor.make_shareable`, and moved-object behavior.
- The Ratomic factory contract requires the callable itself to cross the
  Ractor boundary safely.

`ratomic-rack` now has a minimal `Ratomic::Rack::Worker` and `Handler`; it does
not yet have a general request boundary representation.

## Fiber scheduler abstractions

Neither repository currently defines or integrates a Fiber scheduler. There
are no scheduler classes, hooks, scheduler dependencies, or scheduler
benchmarks. Fiber scheduling is therefore a later, separate experiment, as
required by the technical decisions.

## Test infrastructure

`ratomic-rack` currently has:

- Minitest through `Rake::TestTask` in `Rakefile`.
- Focused Minitest coverage for dispatch, worker reuse after an application
  error, application shareability, and worker-pool configuration.
- RuboCop with `rubocop-minitest` and `rubocop-rake` plugins.
- Steep checking `lib/` against `sig/` via `Steepfile`.
- YARD generation and a 95% minimum documentation gate; the current library
  reports 100% coverage.
- `bundle exec rake` as the CI/default quality gate.

The sibling Ratomic repository has broader Minitest coverage, including
dedicated LocalPool tests for validation, shareability, thread reuse,
per-Ractor isolation, timeout behavior, resource closing, and factory error
propagation. It also has optional Redis and PostgreSQL smoke tests. Those
tests are correctness demonstrations, not a Rack integration suite.

## Benchmark infrastructure

`ratomic-rack` contains no benchmark scripts, benchmark dependencies, or
benchmark results. The benchmark matrix and workload definitions exist only in
`.ignoreme/codex/BENCHMARK_PLAN.md`.

The sibling Ratomic repository has performance-oriented tests and recorded
smoke-test output, but no checked-in benchmark harness matching this project’s
Puma-versus-Ratomic comparison. A reproducible benchmark harness remains to be
built after the minimal adapter works.

## Ruby and dependency constraints

- Both gemspecs require Ruby `>= 4.0`.
- The current runtime is Ruby 4.0.6.
- `ratomic-rack` depends on `ratomic ~> 0.4.3`.
- Ratomic's LocalPool relies on Ruby 4 Ractor behavior, including Ractor-local
  storage and the Ractor ownership model.
- The current Rack repository has no runtime Rack or Puma dependency yet.

## Likely Rack integration points

The adapter boundary should be a callable Rack object implementing:

```ruby
status, headers, body = adapter.call(env)
```

The likely flow is:

1. Puma invokes the adapter on a Puma thread.
2. The adapter creates an explicit, validated request envelope.
3. A dedicated Ractor worker executes the Rack application.
4. The worker returns a deliberately transferable response envelope.
5. The adapter returns the Rack response to Puma and applies body lifecycle
   semantics in the supported subset.

Ratomic `LocalPool` is a likely resource-management component inside each
worker Ractor, for example for a Ractor-local database or HTTP client. It is
not currently the worker scheduler itself.

The first implementation should therefore establish a minimal worker
protocol separately from LocalPool and keep the Rack application and its
Ractor-local dependencies explicit.

## Architectural risks

- **API mismatch:** the planned “LocalPool execution layer” does not exist in
  the inspected Ratomic API; LocalPool manages resources, not jobs.
- **Ractor boundary:** Rack `env` can contain mutable, thread-bound,
  non-shareable, or framework-owned objects. Passing it wholesale is unsafe.
- **Response bodies:** Enumerable, closeable, streaming, hijacked, SSE, and
  WebSocket bodies may retain resources or execution context and cannot be
  assumed transferable.
- **Application state:** a Rack application may capture constants, globals,
  mutexes, database clients, loggers, or other state that is not Ractor-safe.
- **Resource ownership:** clients and connections must be created and used in
  the owning Ractor; moving them across the boundary can produce isolation or
  moved-object failures.
- **Lifecycle and failure:** worker exceptions, pool timeouts, shutdown, body
  close behavior, and cancellation must not leak resources or poison workers.
- **Backpressure:** Puma threads may block while waiting for a worker; queue
  capacity, timeout behavior, and fairness need an explicit policy.
- **Concurrency layering:** Puma threads plus Ractor workers can increase
  memory and scheduling overhead without improving throughput.
- **Protocol features:** hijacking and WebSockets may require Puma-owned socket
  access and may be outside the adapter’s supported boundary.

## Unknowns requiring experiments

The following must be tested rather than inferred:

- Which minimal Rack environment fields can safely cross the Ractor boundary?
- What request envelope best preserves method, path, query, headers, body, and
  required CGI variables without copying unsafe objects?
- Can the application be initialized once per worker Ractor, and what state
  must be initialized inside that Ractor?
- What response representation safely supports status, headers, strings,
  arrays, enumerables, and closeable bodies?
- How should application exceptions and Ractor failures be propagated while
  keeping workers reusable?
- What happens under pool exhaustion, repeated requests, concurrent requests,
  and shutdown during activity?
- Does a worker Ractor use `LocalPool` correctly for Ractor-local resources?
- What are the supported Rack version and middleware compatibility boundaries?
- Are thread-local and fiber-local values preserved, isolated, or lost?
- Can a real Puma integration support ordinary requests without violating
  streaming, hijacking, SSE, or WebSocket semantics?
- What are the throughput, latency, RSS, startup, shutdown, and allocation
  costs versus a direct Puma/Rack baseline?
- Does adding a Fiber scheduler provide measurable value after the basic
  Ractor path is stable?

## Recommended next experiment

Implement only a minimal callable Rack adapter plus a small explicit Ractor
worker protocol. Support a simple immutable request envelope and a response of
`[Integer, Hash<String, String>, Array<String>]`. Add focused tests for
request transfer, response transfer, exceptions, worker reuse, and shutdown.
Keep LocalPool usage out of the dispatch path until the worker protocol is
proven; then test LocalPool separately for Ractor-local resource ownership.
