# shellcheck shell=bash disable=all
# bin/resume-sessions, one reader at a time, against the fixtures from
# spec/fixtures.py plus the edge cases each store is known to contain. These
# assert the exact TSV so a vendor format drift fails here, naming the tool,
# rather than as "no rows" in the picker specs.
Describe 'bin/resume-sessions'

collect() { python3 "$SHELLSPEC_PROJECT_ROOT/bin/resume-sessions" "$@"; }

setup() {
  TMPROOT="$(builtin cd "$(mktemp -d)" && pwd -P)"
  export REAL_HOME="$HOME"
  export HOME="$TMPROOT/home"
  mkdir -p "$HOME" "$TMPROOT/other"
  unset XDG_DATA_HOME OPENCODE2_ROOT RESUME_HOME
  builtin cd "$TMPROOT" && mkdir repo && builtin cd repo
  git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git worktree add -q "$TMPROOT/repo/.worktrees/wt" -b wt
  REPO="$TMPROOT/repo"; WT="$TMPROOT/repo/.worktrees/wt"; GONE="$TMPROOT/repo/.worktrees/gone"
  python3 "$SHELLSPEC_PROJECT_ROOT/spec/fixtures.py" "$HOME" "$REPO" "$WT" "$TMPROOT/other" "$GONE"
}
cleanup() {
  export HOME="$REAL_HOME"
  builtin cd "$SHELLSPEC_PROJECT_ROOT"
  rm -rf "$TMPROOT"
}
BeforeEach 'setup'
AfterEach 'cleanup'

rows() { collect --root "$REPO" --tools "$1" | cut -f1,2,4,5; }

    It 'claude: id from the filename, cwd from the first user line, custom title wins, subagent transcripts ignored'
    When call rows claude
    The output should equal "claude	c1c1c1c1-0000-0000-0000-000000000001	$WT	Claude custom title"
    End

    It 'claude: falls back to the first real prompt, flattened to one clean line'
    run_it() {
      # A prompt with newlines, a tab and an ANSI escape, plus a corrupt line.
      python3 - "$HOME" "$REPO" <<'PY'
import json, os, sys
home, repo = sys.argv[1:3]
slug = "".join(c if c.isalnum() else "-" for c in repo)
p = f"{home}/.claude/projects/{slug}/c3c3c3c3-0000-0000-0000-000000000003.jsonl"
os.makedirs(os.path.dirname(p), exist_ok=True)
with open(p, "w") as fh:
    fh.write("{not json\n")
    fh.write(json.dumps({"type": "user", "cwd": repo, "message": {"content": "line one\nline\ttwo \x1b[31mred\x1b[0m"}}, separators=(",", ":")) + "\n")
PY
      rows claude | grep c3c3c3c3
    }
    When call run_it
    The output should equal "claude	c3c3c3c3-0000-0000-0000-000000000003	$REPO	line one line two red"
    End

    It 'agy: one row per conversation, first prompt as title, latest timestamp'
    When call collect --root "$REPO" --tools agy
    The output should equal "agy	a1a1a1a1-0000-0000-0000-00000000000a	1788900000	$REPO	agy first prompt"
    End

    It 'codex: index name when present, first prompt otherwise, subagent threads dropped'
    When call rows codex
    The line 1 should equal "codex	x3x3x3x3-0000-0000-0000-00000000000d	$REPO	codex unnamed prompt"
    The line 2 should equal "codex	x1x1x1x1-0000-0000-0000-00000000000b	$WT	Codex named thread"
    The lines of output should equal 2
    End

    It 'opencode: session_v2 rows without a parent, ms timestamps converted'
    When call collect --root "$REPO" --tools opencode
    The output should equal "opencode	ses_o1o1o1o1aaaaaaaaaaaaaaaaaa	1788900000	$REPO	Opencode one"
    End

    It 'opencode: also reads the legacy session table without duplicating ids'
    run_it() {
      python3 - "$HOME/.local/share/opencode/opencode.db" "$REPO" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute("create table session (id text primary key, project_id text, parent_id text, directory text, title text, time_updated integer)")
db.execute("insert into session values ('ses_o1o1o1o1aaaaaaaaaaaaaaaaaa','p',NULL,?, 'dup of v2', 1)", (sys.argv[2],))
db.execute("insert into session values ('ses_legacy0000000000000000000','p',NULL,?, 'Legacy only', 1788899000000)", (sys.argv[2],))
db.commit()
PY
      rows opencode
    }
    When call run_it
    The line 1 should equal "opencode	ses_o1o1o1o1aaaaaaaaaaaaaaaaaa	$REPO	Opencode one"
    The line 2 should equal "opencode	ses_legacy0000000000000000000	$REPO	Legacy only"
    The lines of output should equal 2
    End

    It 'opencode: sees a row that is still only in the write-ahead log'
    run_it() {
      python3 - "$HOME/.local/share/opencode/opencode.db" "$REPO" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute("pragma journal_mode=wal")
db.execute("insert into session_v2 values ('ses_walonly000000000000000000','p',NULL,?, 'In the WAL', 1788900001000)", (sys.argv[2],))
db.commit()  # no checkpoint: the row lives in opencode.db-wal
PY
      rows opencode
    }
    When call run_it
    The output should include 'In the WAL'
    End

    It 'opencode2: reads the isolated install under OPENCODE2_ROOT'
    run_it() {
      mv "$HOME/.local/share/opencode2" "$TMPROOT/oc2root"
      OPENCODE2_ROOT="$TMPROOT/oc2root" rows opencode2
    }
    When call run_it
    The output should equal "opencode2	ses_p1p1p1p1cccccccccccccccccc	$WT	Opencode2 one"
    End

    It 'grok: summary.json per session, subagent scratch worktrees dropped'
    When call collect --root "$REPO" --tools grok
    The output should equal "grok	g1g1g1g1-0000-0000-0000-00000000000e	1788897600	$REPO	Grok summary"
    End

    It 'kiro-cli: current sess_ directories and the older per-file layout'
    When call collect --root "$REPO" --tools kiro-cli
    The line 1 should equal "kiro-cli	k1k1k1k1-0000-0000-0000-000000000010	1788894000	$GONE	Kiro gone dir"
    The line 2 should equal "kiro-cli	sess_k2k2k2k2-0000-0000-0000-000000000011	1788892200	$WT	Kiro current layout"
    The lines of output should equal 2
    End

    It 'keeps a sibling repo whose path shares a prefix out of scope'
    run_it() {
      mkdir -p "$TMPROOT/repo-sibling"
      python3 - "$HOME" "$TMPROOT/repo-sibling" <<'PY'
import json, os, sys
home, sib = sys.argv[1:3]
slug = "".join(c if c.isalnum() else "-" for c in sib)
os.makedirs(f"{home}/.claude/projects/{slug}")
with open(f"{home}/.claude/projects/{slug}/c9c9c9c9-0000-0000-0000-000000000009.jsonl", "w") as fh:
    fh.write(json.dumps({"type": "user", "cwd": sib, "message": {"content": "sibling session"}}, separators=(",", ":")) + "\n")
PY
      collect --root "$REPO" --tools claude
    }
    When call run_it
    The output should not include 'sibling session'
    The output should include 'Claude custom title'
    End

    It 'matches a session recorded through a symlinked path'
    run_it() {
      ln -s "$TMPROOT/repo" "$TMPROOT/link"
      python3 - "$HOME" "$TMPROOT/link" <<'PY'
import json, os, sys
home, link = sys.argv[1:3]
slug = "".join(c if c.isalnum() else "-" for c in link)
os.makedirs(f"{home}/.claude/projects/{slug}")
with open(f"{home}/.claude/projects/{slug}/c8c8c8c8-0000-0000-0000-000000000008.jsonl", "w") as fh:
    fh.write(json.dumps({"type": "user", "cwd": link, "message": {"content": "via symlink"}}, separators=(",", ":")) + "\n")
PY
      collect --root "$REPO" --tools claude
    }
    When call run_it
    The output should include 'via symlink'
    End

    It 'ignores deeper claude files (subagent transcripts)'
    run_it() {
      d="$HOME/.claude/projects/$(python3 -c 'import sys; print("".join(c if c.isalnum() else "-" for c in sys.argv[1]))' "$REPO")/c1c1c1c1-0000-0000-0000-000000000001/subagents"
      mkdir -p "$d"
      printf '{"type":"user","cwd":"%s","message":{"content":"agent transcript"}}\n' "$REPO" > "$d/agent-1.jsonl"
      collect --root "$REPO" --tools claude
    }
    When call run_it
    The output should not include 'agent transcript'
    End

    It '--limit caps rows after sorting, --all ignores the repo'
    When call collect --all --limit 1
    The lines of output should equal 1
    The output should include 'Opencode2 one'
    End

    It 'rejects an unknown tool'
    When call collect --all --tools nope
    The status should be failure
    The stderr should include 'unknown tool'
    End
    End
