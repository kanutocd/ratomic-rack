# Ratomic::Rack

[![Gem Version](https://badge.fury.io/rb/ratomic-rack.svg)](https://badge.fury.io/rb/ratomic-rack)
[![CI](https://github.com/kanutocd/ratomic-rack/actions/workflows/ci.yml/badge.svg)](https://github.com/kanutocd/ratomic-rack/actions/workflows/ci.yml)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%204.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.txt)

Ratomic::Rack is an experimental Rack integration for investigating whether
Ratomic's `LocalPool` can provide a prewarmed, Ractor-based execution layer
behind Puma.

The project preserves Puma as the HTTP server and explores this boundary:

```text
Puma → Rack adapter → Ratomic LocalPool → Ractor → Rack application
```

The experiment is intentionally starting at the Rack boundary. It does not
replace Puma, modify Puma internals, or claim compatibility with Rails,
streaming responses, hijacking, WebSockets, or arbitrary Rack applications.
Those capabilities must be verified experimentally before they are supported.

This repository is currently in its reconnaissance and scaffolding phase. The
adapter API is not ready for production use.

## Requirements

- Ruby 4.0 or newer
- Bundler

## Installation

The gem is not yet intended for production use. To develop against the current
repository, add it from GitHub:

```ruby
gem "ratomic-rack", github: "kanutocd/ratomic-rack"
```

The runtime dependency on [`ratomic`](https://github.com/mperham/ratomic) is
declared by the gemspec.

## Development

Install the dependencies and run the complete quality gate:

```bash
bin/setup
bundle exec rake quality
```

The default task runs the tests, RuboCop, Steep, and YARD documentation checks.
Use `bin/console` to open an interactive Ruby session with the gem loaded.

## Project status

Compatibility and benchmark results are recorded as the experiment progresses.
See the project documents under `.ignoreme/codex/` for the architecture,
technical decisions, implementation phases, benchmark plan, and compatibility
matrix.

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/kanutocd/ratomic-rack). Please read the
[Code of Conduct](CODE_OF_CONDUCT.md) before participating.

## License

Ratomic::Rack is available under the [MIT License](LICENSE.txt).
