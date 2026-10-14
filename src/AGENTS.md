# AGENTS.md: equities-core/src

The `equities-core` library (module `Equities_core`). Each module has an `.mli`.

| Module | Holds |
| --- | --- |
| `Session` | Time zones without a tz database, the US equities day, the CME Globex week, holidays |
| `Tick_size` | Equity, option and futures tick rules |
| `Lot` | Round, odd and mixed lots; CME contract units |
| `Symbol` | Equity tickers, test symbols, futures codes and expiries, OCC option symbols |
| `Auction` | Call auction clearing price, imbalance and allocation |
| `Order_types` | Time in force, display, attributes, validation and mapping to the engine |
| `Halts` | LULD bands, the trading pause machine, market-wide circuit breakers |
| `Fees` | Per-share and per-contract fee schedules |

Build: `opam exec --switch 5.2.0+ox -- dune build --root .. @equities-core/all`.

Rules:
- No I/O and no clock reads; pass the time in.
- Do not add matching logic here; it belongs in `exchange-core-engine`.
- A rule taken from a venue document carries a comment naming the section.
