# Contributing to Friday

Friday is built in small, independent steps. Each GitHub issue should take **one sitting**.

## Picking an issue

1. Open [Issues](../../issues) and filter by a milestone, e.g. `Phase 4 — AI & Backend`.
2. New to Swift? Start with **`good first issue`**. Those issues say which file to open and what "done" looks like.
3. Comment "I'm on it" so nobody else picks it up.

## Making the change

```sh
git checkout -b issue-42-short-name   # one branch per issue
make run                              # build and launch Friday
make check                            # lint + tests + no-network check (must pass)
```

- Keep each pull request to **one issue**, and write "Closes #42" in the description.
- Add or update a test in `FridayTests/` for any logic change.
- Never add networking code: `Scripts/check-no-network.sh` will fail the build.

## How pull requests get merged

`main` is protected, so nobody (including the owner) can push to it directly. To merge, a pull request must:

1. **Pass CI.** That means the `build-and-test` job: no-network check, lint, tests and DMG build.
2. **Be approved by the owner.** See [CODEOWNERS](.github/CODEOWNERS). If you push new commits after the approval, you need a fresh approval.
3. **Have every review conversation resolved.**
4. **Be up to date with `main`.** If it isn't, use **Update branch**.

If this is your first pull request, CI waits until the owner approves the run. Fork pull requests run with a read-only token and no secrets.

Please also:
- Target **`main`**, not another pull request's branch.
- Never commit secrets. Secret scanning blocks pushes that contain them.
- Report security problems privately. See [SECURITY.md](SECURITY.md).

## Releasing

1. Make sure `CHANGELOG.md` lists the changes under `## [Unreleased]`.
2. Run `make bump VERSION=x.y.z` (add `DRY=--dry-run` to preview). It updates `project.yml`, adds a dated changelog section and regenerates the project.
3. Review, commit and open a pull request.
4. After it merges, a maintainer tags `vx.y.z` and publishes the release.

## Labels

| Label | Meaning |
|---|---|
| `good first issue` | Small, well described, a good way to learn the codebase |
| `bug` | Something that does not work as intended |
| `enhancement` | New capability |
| `area: …` | Which part of the app (orb, dashboard, connections, ai, voice, release) |
| `size: S / M / L` | Rough effort: under 1 hour / an evening / a weekend |

## Asking for help

Stuck? Comment on the issue with what you tried and the error you saw.
