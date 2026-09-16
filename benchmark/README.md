# Fiber scheduler experiment

This is a separate experiment. It does not change the Rack adapter, worker, or
LocalPool baseline.

Run it with:

```sh
ruby benchmark/fiber_scheduler.rb
```

The script starts one Ractor per sample and compares:

- `without_scheduler`: the Ractor performs the waits sequentially.
- `with_scheduler`: the Ractor installs `TimerFiberScheduler` and schedules one
  non-blocking Fiber per wait.

The workload is intentionally limited to independent `sleep` calls. The
timer scheduler is a controlled test double, not a production scheduler: it
does not implement socket, file, process, or external-service I/O hooks. The
result therefore measures this experiment's scheduling behavior only; it does
not establish a benefit for Rack requests or application I/O.

Useful parameters:

```sh
ruby benchmark/fiber_scheduler.rb --fibers 8 --sleep 0.010 --samples 20 --warmup 5
```

Record Ruby, operating-system, CPU, and configuration alongside any results.
Do not compare runs made with different workload or warmup parameters.

## Puma workload matrix

Run the end-to-end matrix with:

```sh
bundle exec ruby benchmark/puma_workloads.rb \
  --requests 40 --concurrency 4 --samples 3 --warmup 10 \
  --threads 4 --pool-size 4 \
  --output benchmark/results/puma-workloads.jsonl
```

The runner starts a fresh Puma server for each workload and runs modes in this
order: `baseline`, `ratomic`, then `ratomic_scheduler`. It covers:

- `trivial`: returns `OK`.
- `cpu`: deterministic integer work.
- `blocking_io`: one controlled blocking wait per request.
- `concurrent_io`: multiple independent controlled waits; only the scheduler
  mode overlaps them.

Each JSONL record is raw output and includes the complete configuration,
startup/shutdown timings, requests per second, error rate, p50/p95/p99, every
successful request latency, and errors. `puma_workers: 1` means one Puma
server process created by `Puma::Server`; this runner does not use cluster
workers.

The blocking workloads use local sleeps to avoid external services and make
runs reproducible. They are controlled blocking-wait experiments, not a claim
about database, socket, or HTTP-client scheduler behavior. The custom scheduler
does not implement those I/O hooks.
