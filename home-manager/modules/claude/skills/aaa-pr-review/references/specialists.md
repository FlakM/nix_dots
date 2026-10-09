# Specialists (fan-out path only, > 500 changed lines)

Main Claude picks specialists from the changed files and spawns them in parallel as `general-purpose` agents. Each gets only its files and only its lens (sections of `review-agent.md`). Skip a specialist when no file matches.

| Specialist | Lens sections in review-agent.md | Assign files |
| --- | --- | --- |
| correctness | Correctness, Error handling, Simplification & docs | all non-test `.rs` |
| concurrency | Async & concurrency | `.rs` touching `async`, `tokio`, `Mutex`, `RwLock`, `Arc`, channels, `spawn` |
| data | Database | `.rs` with `sqlx`/`query`, `migrations/**`, `*.sql` |
| security | Security & authz | handlers/services/grpc/api/auth/pdp code, anything with permission/team/org checks |
| performance | Performance, Observability | hot paths: services, caches, evaluators, grpc handlers |
| api | Idiomatic Rust / API design, Config, deps, proto | `lib.rs`, `pub` API changes, `*.proto`, `Cargo.toml`, config/helm/yaml |
| tests | Tests | test files plus the production files they cover |

Rules:

- Cap at 6 specialists. Merge small ones (e.g. concurrency into correctness) when they'd get < 3 files.
- A file may go to several specialists.
- Always include `correctness`.
