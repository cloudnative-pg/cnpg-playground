# Testing

cnpg-playground's automated tests are split into three tiers:

1. **Static analysis** — `shellcheck` and `shfmt` over every shell script.
2. **Unit tests** (`tests/unit/`) — [bats-core](https://bats-core.readthedocs.io/)
   tests for the pure bash helpers in `scripts/funcs_regions.sh` and
   `demo/funcs_render.sh`. No external tools required.
3. **Dry-run/golden tests** (`tests/dryrun/`) — drive `demo/setup.sh` with
   `DRY_RUN=true OUTPUT_DIR=...` across the plugin/legacy × single/multi-region
   matrix and diff the rendered YAML against committed fixtures in
   `tests/dryrun/golden/`. `demo/setup.sh` checks for `kind`, `kubectl`,
   `kubectl-cnpg`, and `cmctl` on `PATH` but never actually invokes them in
   `DRY_RUN` mode, so these tests run against the no-op stand-ins in
   `tests/helpers/stubs/` instead of requiring the real tools.

Tier 4 (full integration tests against real Kind clusters) is intentionally
out of scope — those are exercised manually.

## Running locally

```sh
./scripts/test.sh
```

Runs shellcheck, `shfmt -d`, and the full bats suite, in that order, failing
fast on the first stage that doesn't pass.

Required tools: `shellcheck`, `shfmt`, `bats` (bats-core), `yq` (the
[mikefarah/yq](https://github.com/mikefarah/yq) Go version — `yq-go` in
nixpkgs). All four are in `flake.nix`'s dev shell. Outside of Nix, install via
Homebrew:

```sh
brew install shellcheck shfmt bats-core yq
```

## Updating golden fixtures

If you intentionally change a `demo/templates/*.yaml` fragment or
`demo/setup.sh`'s rendering logic, regenerate the fixtures and review the
diff before committing:

```sh
./tests/dryrun/update-golden.sh
git diff tests/dryrun/golden/
```
