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

## Labels

| Label | Meaning |
|---|---|
| `good first issue` | Small, well described, a good way to learn the codebase |
| `bug` | Something that does not work as intended |
| `enhancement` | New capability |
| `area: …` | Which part of the app (orb, dashboard, connections, ai, voice, release) |
| `size: S / M / L` | Rough effort: under 1 hour / an evening / a weekend |

## Asking for help

Stuck? Comment on the issue with what you tried and the error you saw. With Claude Code, you can also open the repo and say "help me with issue #42".
