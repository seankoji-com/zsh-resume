# shellcheck shell=bash disable=all
# resume uses zsh-only syntax (assoc arrays, ${(@ps:\t:)}, strftime), so this
# suite runs under shellspec's zsh mode. Every CLI it can launch, and gum, are
# replaced by stubs on PATH that echo what they were asked to do; the session
# stores are fixtures built under a throwaway HOME by spec/fixtures.py.
Describe 'zsh-resume.plugin.zsh'
Include ./zsh-resume.plugin.zsh

TOOLS="claude agy codex opencode opencode2 grok kiro-cli"

setup() {
  TMPROOT="$(builtin cd "$(mktemp -d)" && pwd -P)"
  export REAL_HOME="$HOME"
  export HOME="$TMPROOT/home"
  mkdir -p "$HOME" "$TMPROOT/bin" "$TMPROOT/other"
  unset XDG_DATA_HOME OPENCODE2_ROOT RESUME_HOME

  # A repo with one registered worktree, plus a directory that used to exist.
  builtin cd "$TMPROOT" && mkdir repo && builtin cd repo
  git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git worktree add -q "$TMPROOT/repo/.worktrees/wt" -b wt
  REPO="$TMPROOT/repo"; WT="$TMPROOT/repo/.worktrees/wt"; GONE="$TMPROOT/repo/.worktrees/gone"

  python3 "$SHELLSPEC_PROJECT_ROOT/spec/fixtures.py" "$HOME" "$REPO" "$WT" "$TMPROOT/other" "$GONE"

  # Stub CLIs: print name, args and cwd, so a launch can be asserted on.
  local t
  for t in ${=TOOLS}; do
    printf '#!/bin/sh\necho "%s $* cwd=$PWD"\n' "$t" > "$TMPROOT/bin/$t"
    chmod +x "$TMPROOT/bin/$t"
  done
  # Stub gum: `filter` picks the first line containing $RESUME_TEST_PICK,
  # `log` prints to stderr like the real thing.
  cat > "$TMPROOT/bin/gum" <<'STUB'
#!/bin/sh
case "$1" in
  filter) grep -F -m1 -- "${RESUME_TEST_PICK:?}" ;;
  log) shift; while [ $# -gt 0 ]; do case "$1" in --level) printf '%s ' "$2" >&2; shift 2 ;; --time=*) shift ;; *) printf '%s\n' "$1" >&2; shift ;; esac; done ;;
esac
STUB
  chmod +x "$TMPROOT/bin/gum"

  # Only the stubs, python3 and the system bins: a real CLI or gum must never
  # leak into a test.
  ln -s "$(command -v python3)" "$TMPROOT/bin/python3"
  export PATH="$TMPROOT/bin:/usr/bin:/bin"
  hash -r
}
cleanup() {
  export HOME="$REAL_HOME"
  builtin cd "$SHELLSPEC_PROJECT_ROOT"
  rm -rf "$TMPROOT"
}
BeforeEach 'setup'
AfterEach 'cleanup'

Describe 'resume -l'
    It 'lists this repo root and worktree sessions from every tool, newest first'
    run_it() { builtin cd "$REPO"; resume -l; }
    When call run_it
    The status should be success
    The line 1 should include 'Opencode2 one'
    The output should include 'Claude custom title'
    The output should include 'agy first prompt'
    The output should include 'Codex named thread'
    The output should include 'codex unnamed prompt'
    The output should include 'Opencode one'
    The output should include 'Grok summary'
    The output should include 'Kiro gone dir'
    The output should not include 'claude elsewhere'
    The output should not include 'codex subagent'
    The output should not include 'Opencode child'
    The output should not include 'Grok subagent'
    End

    It 'shows the same rows from inside a worktree as from the root'
    run_it() {
      builtin cd "$REPO"; resume -l > "$TMPROOT/root.txt"
      builtin cd "$WT"; resume -l > "$TMPROOT/wt.txt"
      cmp -s "$TMPROOT/root.txt" "$TMPROOT/wt.txt" && print same
    }
    When call run_it
    The output should equal 'same'
    End

    It 'marks a directory that no longer exists'
    run_it() { builtin cd "$REPO"; resume -l | grep 'Kiro gone dir'; }
    When call run_it
    The output should include '(gone)'
    End

    It 'includes other repos with --all'
    run_it() { builtin cd "$TMPROOT/other"; resume -l -a; }
    When call run_it
    The status should be success
    The output should include 'claude elsewhere'
    The output should include 'Claude custom title'
    End

    It 'restricts to the tools named with -t'
    run_it() { builtin cd "$REPO"; resume -l -t grok,agy; }
    When call run_it
    The output should include 'Grok summary'
    The output should include 'agy first prompt'
    The output should not include 'Claude custom title'
    End

    It 'skips a tool that is not on PATH'
    run_it() { builtin cd "$REPO"; rm "$TMPROOT/bin/grok"; hash -r; resume -l; }
    When call run_it
    The output should not include 'Grok summary'
    The output should include 'Claude custom title'
    End

    It 'lists nothing for a tool with no store and says so for a broken one'
    run_it() {
      builtin cd "$REPO"
      rm -rf "$HOME/.grok"
      print 'not a database' > "$HOME/.local/share/opencode/opencode.db"
      resume -l
    }
    When call run_it
    The status should be success
    The output should not include 'Grok summary'
    The output should not include 'Opencode one'
    The output should include 'Claude custom title'
    The stderr should include 'opencode: cannot read'
    End
    End

Describe 'resume (launch)'
    It 'launches the picked CLI with its resume flag from the session directory'
    run_it() { builtin cd "$REPO"; RESUME_TEST_PICK='Claude custom title' resume; }
    When call run_it
    The output should equal "claude --resume c1c1c1c1-0000-0000-0000-000000000001 cwd=$WT"
    The stderr should include 'resuming claude'
    End

    Describe 'per tool'
      Parameters
        'agy first prompt'   "agy --conversation a1a1a1a1-0000-0000-0000-00000000000a"
        'Codex named thread' "codex resume x1x1x1x1-0000-0000-0000-00000000000b"
        'Opencode one'       "opencode --session ses_o1o1o1o1aaaaaaaaaaaaaaaaaa"
        'Opencode2 one'      "opencode2 --session ses_p1p1p1p1cccccccccccccccccc"
        'Grok summary'       "grok --resume g1g1g1g1-0000-0000-0000-00000000000e"
      End
      It "resumes '$1' with the right command"
      run_it() { builtin cd "$REPO"; RESUME_TEST_PICK="$1" resume; }
      When call run_it "$1"
      The output should start with "$2"
      The stderr should include 'resuming'
      End
    End

    It 'falls back to the repo root when the session directory is gone'
    run_it() { builtin cd "$WT"; RESUME_TEST_PICK='Kiro gone dir' resume; }
    When call run_it
    The output should equal "kiro-cli chat --resume-id k1k1k1k1-0000-0000-0000-000000000010 cwd=$REPO"
    The stderr should include 'is gone'
    End

    It 'passes arguments after -- to the CLI'
    run_it() { builtin cd "$REPO"; RESUME_TEST_PICK='Grok summary' resume -- --model fast; }
    When call run_it
    The output should include 'g1g1g1g1-0000-0000-0000-00000000000e --model fast cwd='
    The stderr should include 'resuming grok'
    End

    It 'does not move the calling shell'
    run_it() { builtin cd "$REPO"; RESUME_TEST_PICK='Claude custom title' resume >/dev/null; print -r -- "$PWD"; }
    When call run_it
    The output should equal "$REPO"
    The stderr should include 'resuming claude'
    End

    It 'honours a RESUME_CMDS override'
    run_it() { builtin cd "$REPO"; RESUME_CMDS[grok]='grok -r --fork-session'; RESUME_TEST_PICK='Grok summary' resume; }
    When call run_it
    The output should start with 'grok -r --fork-session g1g1g1g1'
    The stderr should include 'resuming grok'
    End

    It 'refuses a gone directory for a tool listed in RESUME_STRICT_CWD'
    run_it() { builtin cd "$REPO"; RESUME_STRICT_CWD='kiro-cli grok' RESUME_TEST_PICK='Kiro gone dir' resume; }
    When call run_it
    The status should be failure
    The output should equal ''
    The stderr should include 'can only resume from there'
    End

    It 'shows a multi-line, tab-laden title as one row and still launches it'
    run_it() {
      builtin cd "$REPO"
      python3 - "$HOME" "$REPO" <<'PY'
import json, os, sys
home, repo = sys.argv[1:3]
slug = "".join(c if c.isalnum() else "-" for c in repo)
os.makedirs(f"{home}/.claude/projects/{slug}", exist_ok=True)
with open(f"{home}/.claude/projects/{slug}/c7c7c7c7-0000-0000-0000-000000000007.jsonl", "w") as fh:
    fh.write(json.dumps({"type": "user", "cwd": repo, "message": {"content": "messy\ttitle\nsecond line \x1b[1mbold"}}, separators=(",", ":")) + "\n")
PY
      COLUMNS=200 resume -l | grep -c 'messy title second line bold'
      RESUME_TEST_PICK='messy title' resume
    }
    When call run_it
    The line 1 should equal '1'
    The line 2 should equal "claude --resume c7c7c7c7-0000-0000-0000-000000000007 cwd=$REPO"
    The stderr should include 'resuming claude'
    End

    It 'uses a numbered menu when gum is missing'
    run_it() { builtin cd "$REPO"; rm "$TMPROOT/bin/gum"; hash -r; resume -t grok; }
    Data "1"
    When call run_it
    The output should include 'grok --resume g1g1g1g1'
    The stderr should include 'session'
    End
    End

Describe 'resume (errors)'
    It 'rejects unknown options'
    When call resume --bogus
    The status should equal 2
    The stderr should include 'unknown option'
    End

    It 'fails outside a git repository unless -a is given'
    run_it() { builtin cd "$TMPROOT/other"; resume -l; }
    When call run_it
    The status should be failure
    The stderr should include 'not inside a git repository'
    End

    It 'reports when no session matches'
    run_it() { builtin cd "$REPO"; rm -rf "$HOME"; mkdir "$HOME"; resume -l; }
    When call run_it
    The status should be failure
    The stderr should include 'no sessions found'
    End

    It 'explains when python3 is missing'
    run_it() {
      builtin cd "$REPO"
      # Only git and one stub CLI: /bin is left out because on a merged-/usr
      # Linux it is /usr/bin and would bring python3 back.
      mkdir "$TMPROOT/nopy"
      ln -s "$(command -v git)" "$TMPROOT/nopy/git"
      ln -s "$TMPROOT/bin/grok" "$TMPROOT/nopy/grok"
      PATH="$TMPROOT/nopy" resume -l
    }
    When call run_it
    The status should be failure
    The stderr should include 'python3 is required'
    End

    It 'prints usage with -h'
    When call resume -h
    The status should be success
    The output should include 'Usage: resume'
    End
    End
    End
