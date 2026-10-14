# AGENTS.md: equities-core/.github

- `workflows/ci.yml`: checkout, the shared `ox-setup` action, `dune build`, `dune test`,
  then the reusable obj-magic workflow from `winterchill-trading/infra`.
- The pins list must match the sibling dependencies (`fixed-decimal`, `exchange-core`).
- Push once per finished change: concurrency cancels the running job.
- To check a run: one `gh run list --limit 1`, then at most one `gh run watch <id>
  --exit-status`. Never poll.
