# equities-core

Shared semantics for the TradFi venue simulators: US equities trading calendars, tick and
lot rules, symbology, auctions, order attributes, volatility halts and fee schedules.
Pure OCaml (OxCaml, Jane Street Core), no I/O. It sits on top of `exchange-core` and
reuses its `Price`, `Side`, `Usd`, `Symbol` and `Order_request` types; matching stays in
`exchange-core-engine`.

## Planned simulators

| Simulator | Order entry | Market data | Spec summary |
| --- | --- | --- | --- |
| `nyse-sim` | Pillar Gateway binary (stream protocol, TG/GT/REF streams) | Pillar Integrated Feed (XDP) | [gateway](docs/nyse-pillar-gateway.md), [feed](docs/nyse-xdp-integrated-feed.md) |
| `cboe-sim` | BOE v2 | Multicast PITCH 2.X (with spin) | [BOE](docs/cboe-boe.md), [PITCH](docs/cboe-pitch.md) |
| `cme-sim` | iLink 3 (SBE over FIXP) | MDP 3.0 (SBE) | [iLink 3 and MDP 3.0](docs/cme-ilink3-mdp3.md) |

All three speak their binary protocols over TCP (multicast feeds are delivered over TCP
in the simulators), plus a JSON/HTTP and websocket convenience surface so that the
`market-data` live feeds and the `market-maker` can reuse the existing plumbing. Each spec
summary ends with the minimal message set a simulator must implement.

## Modules

| Module | Scope |
| --- | --- |
| `Session` | New York and Chicago time without a tz database; US equities day (pre-market 04:00, core 09:30-16:00, post-market to 20:00, early closes at 13:00/17:00), NYSE 2026 holidays; CME Globex week (Sunday 17:00 to Friday 16:00 CT, daily 16:00-17:00 maintenance) and trade dates |
| `Tick_size` | Equity ticks ($0.01, $0.0001 below $1), Cboe option ticks (standard, penny, penny-all), CME products ES, NQ, CL, GC with multipliers and tick values |
| `Lot` | Round, odd and mixed lots, price-tiered round lots, CME contract units and notional |
| `Symbol` | Equity tickers with suffixes (NYSE and dotted forms), test symbols; futures codes with month codes and expiry rules (third Friday, crude oil, third last business day); OCC OSI option symbols |
| `Auction` | Call auction clearing price (max volume, min imbalance, nearest reference), imbalance information, MOO/LOO/MOC/LOC participation, price-time allocation |
| `Order_types` | TIF (Day, IOC, FOK, GTC, OPG, CLO), display (visible, hidden, reserve), ISO, post-only, minimum quantity, self-trade prevention, short sale sides and Rule 201 state; validation and mapping to the engine |
| `Halts` | LULD bands with tiers and closing doubling, limit state and trading pause machine, market-wide circuit breakers (7/13/20%) |
| `Fees` | Per-share maker/taker schedules with rebates and sub-dollar pricing, per-contract futures fees |

## Scope

| Topic | Modelled | Not modelled |
| --- | --- | --- |
| Calendars | 2026 NYSE holidays and early closes, DST rules since 2007 | other years' holidays, CME holiday schedules |
| Ticks | Rule 612 penny/sub-penny, option tick classes, four CME products | $0.005 tick tier (2024 amendment), other CME products |
| Auctions | single-price uncross, imbalance at reference price | collars, freeze periods, imbalance-offset orders, extensions |
| Orders | attribute validation, engine mapping for visible Day/GTC/IOC/post-only | pegs, discretion, routing, stops, hidden and reserve matching |
| Halts | LULD Amendment 18 parameters, MWCB levels | reopening auction details, straddle states, pause extensions |
| Fees | illustrative schedules | tiered and current published prices |

## Build

```sh
opam exec --switch 5.2.0+ox -- dune build @all @runtest
```

Depends on `core`, `fixed-decimal` and `exchange-core`.
