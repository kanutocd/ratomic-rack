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
