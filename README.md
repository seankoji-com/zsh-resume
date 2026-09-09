# zsh-resume

<img width="1727" height="647" alt="image" src="https://github.com/user-attachments/assets/d615831a-9178-49fe-80dc-488d3f6671b1" />


Pick any AI-CLI session for the current repository and resume it.

`resume` gathers the sessions that [Claude Code](https://docs.claude.com/en/docs/claude-code),
Antigravity (`agy`), [Codex](https://github.com/openai/codex),
[opencode](https://opencode.ai) (plus an isolated `opencode2` install),
[Grok CLI](https://x.ai) and [Kiro CLI](https://kiro.dev) have recorded for the
repository you are in — the root checkout **and every one of its worktrees** —
and shows them in one [`gum filter`](https://github.com/charmbracelet/gum#filter)
picker: tool, last activity, directory, title, id. Pick one and the owning CLI
is launched with that session resumed, from the directory the session was
started in. Your own shell never changes directory.

```
$ resume
resume · my-project
> _
▶ codex     09 Sep 09:41  …/worktrees/6f9b/poc                Harden the end-to-end journey          29081b02
  claude    08 Sep 22:49  .claude/worktrees/imps-discussion   Test plan quality review               e3497216
  grok      08 Sep 20:00  .                                   Research AU price plan.                9153e8f6
  opencode2 08 Sep 19:47  .worktrees/scraper                  Improve safety references              6be9gw
```

Titles are the session name when the tool keeps one (Claude `/rename`, Codex
thread names, opencode/Grok/Kiro titles) and the first prompt otherwise.

## Installation

Requires `python3` (standard library only) and `git`. [gum](https://github.com/charmbracelet/gum)
is optional: without it the picker is a numbered `select` menu.

### Manual

```
git clone https://github.com/seankoji-com/zsh-resume ~/.zsh/zsh-resume
echo 'source ~/.zsh/zsh-resume/zsh-resume.plugin.zsh' >> ~/.zshrc
```

### zinit

```
zinit light seankoji-com/zsh-resume
```

### oh-my-zsh

```
git clone https://github.com/seankoji-com/zsh-resume \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-resume
```

Then add it to the `plugins` array in your `.zshrc`:

```
plugins=(... zsh-resume)
```

## Usage

```
resume                 # pick a session for this repo (root + worktrees) and resume it
resume -a              # every session on this machine, any repo
resume -t claude,codex # only these tools
resume -l              # print the table, launch nothing
resume -- --model x    # pass extra arguments to the resumed CLI
```

Sessions belong to the repo when their working directory is the main checkout,
anything under it, or any path listed by `git worktree list` — so worktrees
kept outside the checkout (Codex's `~/.codex/worktrees/…`) are included too. A
session whose directory has since been deleted is marked `(gone)` and is
relaunched from the repo root.

`resume_sessions` and `resume_root` are exposed for scripting: the first prints
the raw rows as TSV (`tool  id  updated-epoch  cwd  title`, newest first, same
flags as `bin/resume-sessions`), the second prints the main checkout of the
current repo.

## How sessions are found

| Tool | Store read | Resume command |
| --- | --- | --- |
| claude | `~/.claude/projects/*/*.jsonl` | `claude --resume <id>` |
| agy | `~/.gemini/antigravity-cli/history.jsonl` | `agy --conversation <id>` |
| codex | `~/.codex/sessions/**/rollout-*.jsonl`, `session_index.jsonl` | `codex resume <id>` |
| opencode | `~/.local/share/opencode/opencode.db` | `opencode --session <id>` |
| opencode2 | `$OPENCODE2_ROOT/share/opencode/opencode.db` | `opencode2 --session <id>` |
| grok | `~/.grok/sessions/*/*/summary.json` | `grok --resume <id>` |
| kiro-cli | `~/.kiro/sessions/*/sess_*/session.json` (and the older `*/*.json`) | `kiro-cli chat --resume-id <id>` |

Subagent threads (Codex, Grok scratch worktrees, opencode child sessions,
Claude subagent transcripts) are left out. Stores are only ever read: SQLite
files are opened read-only (falling back to immutable when the directory
cannot take a shared-memory file), and a running CLI is never blocked. Tools
that are not on `PATH` are skipped unless named with `-t`. Titles are
flattened to one clean line, so pasted logs or escape codes in a first prompt
cannot break the picker.

Scoping is exact on real paths: `~/repos/my-project` never picks up
`~/repos/my-other-project`, and a session recorded through a symlink still
matches. One limitation: a session from a worktree that lived *outside* the
checkout and has since been pruned can no longer be tied to the repo, so it
only shows under `-a`.

Listing the whole machine takes about two seconds here (500+ Claude
transcripts, 700+ Codex rollouts); a single repo is well under a second.
Claude transcripts are read as a head and a tail window rather than in full.

## Configuration

Set before loading the plugin:

| Variable | Default | Description |
| --- | --- | --- |
| `RESUME_TOOLS` | `claude agy codex opencode opencode2 grok kiro-cli` | Tools to look at, space-separated. |
| `RESUME_LIMIT` | `500` | Most rows shown, after sorting by last activity. Scanning itself is never capped, so an old repo's sessions are never silently dropped. |
| `RESUME_STRICT_CWD` | *(empty)* | Space-separated tools that can only resume from the directory the session was recorded in. For those, a session whose directory is gone is refused rather than relaunched from the repo root. |
| `RESUME_CMDS` | see table above | Associative array `tool → command prefix`; the session id is appended. Override an entry to change how a tool resumes, e.g. `RESUME_CMDS[grok]='grok -r --fork-session'`. |
| `OPENCODE2_ROOT` | `~/.local/share/opencode2` | Data root of the isolated opencode2 install (same variable its launcher uses). |

## License

MIT — see [LICENSE](/LICENSE).
