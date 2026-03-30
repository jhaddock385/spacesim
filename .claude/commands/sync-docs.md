Sync the project documentation with the current state of the codebase. Do all three steps:

## 1. Update the File Index in CLAUDE.md

Scan the actual file tree (all `.lua` files under `src/`, plus `main.lua`, `conf.lua`, and the `docs/`, `assets/`, `lib/` directories). Update the `## File Index` section in `CLAUDE.md` to reflect the current files, maintaining the tree hierarchy format with `├──`, `│`, and `└──` connectors. Each file gets a one-line description of what it contains. Read any new files you haven't seen before to write accurate descriptions. Preserve descriptions for files that haven't changed.

## 2. Check for undocumented systems

Compare the modules that exist under `src/sim/`, `src/core/`, and `src/agents/` against the architecture docs listed in `docs/architecture/INDEX.md`. Flag any systems or modules that exist in code but don't have an architecture doc covering them. Report what's missing but don't write the docs automatically — just tell the user what needs documenting.

## 3. Update architecture and design indexes

Check if any new `.md` files exist in `docs/architecture/` or `docs/design/` that aren't listed in their respective `INDEX.md`. If so, add them to the index with a one-line description based on reading the file.
