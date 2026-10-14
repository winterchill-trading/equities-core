# AGENTS.md: equities-core

## Purpose

Shared semantics for the traditional-finance venue simulators: US equities trading
calendars, tick and lot rules, symbology, auctions, order attributes, volatility halts and
fee schedules. It is pure OCaml with no I/O; matching stays in `exchange-core-engine`.

## Layout

| Path | Holds |
| --- | --- |
| `src/` | The library `equities-core` (module `Equities_core`): `Session`, `Tick_size`, `Lot`, `Symbol`, `Auction`, `Order_types`, `Halts`, `Fees` (see `src/AGENTS.md`) |
| `test/` | Expect and property tests, one file per module (see `test/AGENTS.md`) |
| `docs/` | Specification summaries for the venues this library models (see `docs/AGENTS.md`) |
| `.github/` | CI workflow and the shared obj-magic check (see `.github/AGENTS.md`) |
| `README.md` | Module table, scope (modelled and not modelled), planned simulators |
| `dune-project` | Package metadata; edit this, not the generated `equities-core.opam` |

There are no binaries. The simulators (`../cboe-sim`, `../cme-sim`, `../nyse-sim`) use this
library.

## Build, test

Run from this repository. The workspace root is one level up, so every command takes
`--root ..`.

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @equities-core/all
opam exec --switch 5.2.0+ox -- dune build --root .. @equities-core/runtest
```

Parallel work with another agent: prefix both with `DUNE_BUILD_DIR=_build-equities-core`.

Standalone (outside the workspace): the org opam repository is the target for published
packages (see `../specs/repos/opam-repository.md`). Until a package is there, pin
`fixed-decimal` and `exchange-core` from the CI list, then
`opam install . --deps-only --with-test` and `dune build`.

## Conventions

- Format only this repository: `dune build --root .. @equities-core/fmt --auto-promote`.
  Never run `dune fmt` at the workspace root.
- Every module has an `.mli`. Consume siblings by public opam name.
- The scope table in `README.md` is the contract: a feature moves from "not modelled" to
  "modelled" only with a test in the same commit.
- Fee schedules are illustrative, not current published prices; say so in any comment.
- Comments for humans wherever a rule comes from a venue document: name the rule and the
  document section.

## Dependencies and dependents

Sibling checkouts: `fixed-decimal` and `exchange-core`, pinned in that order in
`.github/workflows/ci.yml`. Dependents are the TradFi simulators named above.

## CI

`.github/workflows/ci.yml`: checkout, the shared `ox-setup` action (opam switch cache keyed on
the pins), `dune build`, `dune test`, then the reusable obj-magic workflow from `../infra`.
Pushes cancel the running job; push once per finished change.

To check a run: one `gh run list --limit 1`, then at most one `gh run watch <id>
--exit-status`. Never poll in a loop.

## Pitfalls

- `Session` has no time zone database. New York and Chicago offsets (including DST rules
  since 2007) are computed in code; a new year needs its holiday list added and tested.
- The 2026 NYSE holiday list is the only one modelled. Calendars for other years are
  missing, so a test that rolls past 2026 will fail for that reason, not a bug.
- Tick tables: the $0.005 tier from the 2024 amendment is not modelled. Do not assume it.
- Auctions model the single-price uncross and imbalance only; collars, freeze periods and
  imbalance-offset orders are absent.
- The simulators have their own `Session`-like modules. Name a simulator module so that it
  does not collide with this library's module names (`Boe_session`, not `Session`).
## Where to read more

- `README.md`: module table and the scope table.
- `docs/`: the venue specification summaries the modules follow.
- `../specs/repos/equities-core.md`: status and planned simulators.
- `../cboe-sim/`, `../cme-sim/`: consumers of this library.
- `../oxcaml-claude-skills/AGENTS.md`: workspace-wide guide.
- `../oxcaml-claude-skills/GOTCHAS.md`: the TradFi simulators section.

## Never do

- Install opam packages that change the compiler or `core`, `base`, `async`, `ppx_jane`
  on the shared `5.2.0+ox` switch. Dry-run first: `opam install --switch 5.2.0+ox --dry-run <pkg>`.
- Publish, tag or release.
- Poll CI in loops.
