---
name: code-review
description: Review priorities for zsh-resume pull requests — what deserves real scrutiny versus what to skip. Use for every PR review.
---

# Review priorities

Two files carry all the real logic: `bin/resume-sessions` (python3, one
reader per tool that turns an on-disk session store into TSV rows, plus the
repo-scoping filter) and `zsh-resume.plugin.zsh` (flag parsing, the gum /
`select` picker, mapping a picked line back to its row, and the launch).
`spec/fixtures.py` is the third: it is the executable description of what
each tool's store looks like, so a store-format change must land there too.

## Spend real attention here

- Every reader in `bin/resume-sessions` mirrors a format nobody controls. A
  diff that changes a field name, a glob, or a skip rule (`thread_source`,
  `parent_id`, `/.grok/worktrees/`) needs the matching fixture in
  `spec/fixtures.py` changed in the same PR, or the spec is no longer testing
  the real shape. Real-world samples are documented in the reader docstrings
  and the README table — compare against them.
- Readers must never write. `ro_connect` opens SQLite with `immutable=1` on
  purpose (a running CLI holds these files; `mode=ro` fails on WAL stores
  and sandboxed dirs). A PR that "simplifies" it to a plain `connect` is a
  regression.
- One broken store must not hide the others: each reader is wrapped so it
  warns and continues. Check that a new code path keeps that property.
- `RESUME_CMDS` entries are the resume flag per tool (`--resume`,
  `--conversation`, `resume`, `--session`, `--resume-id`). These were
  verified against each CLI's `--help`; a change needs the new help text
  quoted in the PR.
- The launch: `( builtin cd -- "$dir" && exec ... )`. The subshell is what
  keeps the caller's cwd unchanged, and `--dir` fallback to the root is what
  makes `(gone)` sessions resumable. `spec/zsh-resume_spec.sh` covers both.
- The picked line maps back by exact match (`${lines[(ie)$pick]}`); any
  change to the display format must keep lines unique per row.
- The spec restricts `PATH` to stubs + python3 + system bins. A test that
  needs a real CLI or real gum on PATH is testing the wrong thing.

## Do not spend attention here

- `.github/workflows/*.yml` diffs from `chore(ci): sync caller templates
  from seankoji-com/.github` PRs — authored in the hub repo, not here.
- `README.md` / `LICENSE` — prose and license text, no logic.
- Shell formatting with no lint config to violate — only flag it if it
  actually breaks under `zsh`.

## Comment style

- One comment per real issue, not one per file or line it repeats in.
- Before flagging a test gap, check `spec/zsh-resume_spec.sh` — it covers
  listing, scoping, launch per tool, `--` passthrough, gone dirs, missing
  gum/python3, and broken stores.
