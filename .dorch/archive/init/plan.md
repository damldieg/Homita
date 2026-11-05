# Plan — init

## Tasks

- [x] (a) Repo `AGENTS.md` (create): `## Project` section with stack, commands (install, build, test, lint), structure, conventions, sourced from `findings.md`; no `Decisions:` line (no decision log found)
- [x] (b) `.gitignore`: add `.dorch/changes/` exactly once (not present today)

## Verification

- `grep -c '^\.dorch/changes/$' .gitignore` == 1
- `AGENTS.md` has `## Project` and no `Decisions:` line
- `git status --short` shows only `AGENTS.md`, `.gitignore`, `.dorch/`
