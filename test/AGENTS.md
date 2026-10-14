# AGENTS.md: equities-core/test

One test file per module (`test_session.ml`, `test_tick_size.ml`, and so on), plus
`test_auction.ml`, `test_fees.ml`, `test_halts.ml`, `test_lot.ml`, `test_order_types.ml`,
`test_symbol.ml`.

Run: `opam exec --switch 5.2.0+ox -- dune build --root .. @equities-core/runtest`.

Rules:
- Promote expect output only after reading the diff and after a successful `@runtest` build.
- Calendar tests state the date they check; a holiday test must not depend on today's date.
