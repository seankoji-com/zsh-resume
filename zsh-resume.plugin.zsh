# zsh-resume — pick any AI-CLI session for this repository and resume it.
#
# `resume` lists the sessions that claude, agy, codex, opencode, opencode2,
# grok and kiro-cli have recorded for the current repository — the root
# checkout and every one of its worktrees — in one gum filter picker, then
# launches the owning CLI with that session resumed. The session is relaunched
# from the directory it was started in (or the repo root if that directory is
# gone), in a subshell, so your own shell's cwd never moves.
#
# Session discovery lives in bin/resume-sessions (python3, stdlib only). The
# picker is `gum filter` when gum is installed and a numbered `select` menu
# otherwise.
#
# Configure before loading:
#   RESUME_TOOLS   space-separated tools to look at
#                  (default: claude agy codex opencode opencode2 grok kiro-cli)
#   RESUME_LIMIT   newest N store files inspected per tool (default 200)
#   RESUME_CMDS    assoc array tool -> resume command prefix; the session id
#                  is appended. Override an entry to change how a tool resumes.
#   RESUME_STRICT_CWD
#                  tools that can only resume from the directory the session
#                  was recorded in; a session whose directory is gone is
#                  refused instead of relaunched from the repo root.
#
# Usage:
#   resume [-a|--all] [-t|--tools a,b] [-l|--list] [--] [extra CLI args]

0=${(%):-%N}
ZSH_RESUME_DIR=${0:A:h}

: ${RESUME_TOOLS='claude agy codex opencode opencode2 grok kiro-cli'}
: ${RESUME_LIMIT=500}
: ${RESUME_STRICT_CWD=''}

typeset -gA RESUME_CMDS
(( $+RESUME_CMDS[claude] ))    || RESUME_CMDS[claude]='claude --resume'
(( $+RESUME_CMDS[agy] ))       || RESUME_CMDS[agy]='agy --conversation'
(( $+RESUME_CMDS[codex] ))     || RESUME_CMDS[codex]='codex resume'
(( $+RESUME_CMDS[opencode] ))  || RESUME_CMDS[opencode]='opencode --session'
(( $+RESUME_CMDS[opencode2] )) || RESUME_CMDS[opencode2]='opencode2 --session'
(( $+RESUME_CMDS[grok] ))      || RESUME_CMDS[grok]='grok --resume'
(( $+RESUME_CMDS[kiro-cli] ))  || RESUME_CMDS[kiro-cli]='kiro-cli chat --resume-id'

zmodload zsh/datetime 2>/dev/null

# Emit a log line: `gum log` when available, plain stderr otherwise.
_resume_log() {
  local level="$1" msg="$2"
  if (( $+commands[gum] )); then
    command gum log --level "$level" --time="" "$msg"
  else
    print -u2 "[${(U)level}] $msg"
  fi
}

# Print the main checkout of the current repository: the first entry of
# `git worktree list`, which is the same answer from the root and from any
# worktree.
resume_root() {
  command git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  local line
  command git worktree list --porcelain 2>/dev/null | while IFS= read -r line; do
    [[ "$line" == "worktree "* ]] || continue
    print -r -- "${line#worktree }"
    return 0
  done
}

# Print sessions as TSV (tool, id, updated-epoch, cwd, title), newest first.
# Args are passed straight to bin/resume-sessions (--root DIR | --all, --tools, --limit).
resume_sessions() {
  (( $+commands[python3] )) || {
    _resume_log error "resume: python3 is required for session discovery"
    return 1
  }
  command python3 "$ZSH_RESUME_DIR/bin/resume-sessions" "$@"
}

resume() {
  local all=0 list=0 tools="${RESUME_TOOLS// /,}" tools_explicit=0
  local -a extra
  while (( $# )); do
    case "$1" in
      -a|--all) all=1 ;;
      -l|--list) list=1 ;;
      -t|--tools)
        shift
        [[ -n "$1" ]] || { _resume_log error "resume: -t/--tools needs a value"; return 2; }
        tools="${1// /,}"; tools_explicit=1
        ;;
      -h|--help)
        print -rl -- \
          "resume: pick an AI-CLI session for this repo (root + worktrees) and resume it" \
          "Usage: resume [-a|--all] [-t|--tools a,b] [-l|--list] [--] [extra CLI args]" \
          "  -a, --all     every session on this machine, not just this repo's" \
          "  -t, --tools   only these tools (comma-separated); default: $RESUME_TOOLS" \
          "  -l, --list    print the table and exit without launching anything" \
          "  --            pass the remaining args to the resumed CLI" \
          "Tools: ${(k)RESUME_CMDS}"
        return 0
        ;;
      --) shift; extra=("$@"); break ;;
      -*) _resume_log error "resume: unknown option: $1"; return 2 ;;
      *) _resume_log error "resume: unexpected argument: $1"; return 2 ;;
    esac
    shift
  done

  local root
  if (( all )); then
    root=$(resume_root 2>/dev/null) || root=$PWD
  else
    root=$(resume_root) || {
      _resume_log error "resume: not inside a git repository (use -a for all sessions)"
      return 1
    }
  fi

  # Tools that are not on PATH cannot resume anything; drop them unless the
  # user named them explicitly.
  if (( ! tools_explicit )); then
    local -a present
    local t
    for t in ${(s:,:)tools}; do
      (( $+commands[${${=RESUME_CMDS[$t]}[1]:-$t}] )) && present+=("$t")
    done
    tools="${(j:,:)present}"
    [[ -n "$tools" ]] || { _resume_log error "resume: none of $RESUME_TOOLS is installed"; return 1; }
  fi

  local -a scope
  (( all )) && scope=(--all) || scope=(--root "$root")
  local -a rows
  rows=("${(@f)$(resume_sessions $scope --tools "$tools" --limit "$RESUME_LIMIT")}") || return 1
  (( ${#rows} )) && [[ -n "$rows[1]" ]] || {
    _resume_log warn "resume: no sessions found for ${root:t}"
    return 1
  }

  # One display line per row: tool, time, where, title, id tail. Lines and
  # rows share indexes; the picked line is mapped back by exact match. The
  # title takes whatever width the terminal has left so gum never wraps a row.
  local -a lines parts
  local row when where title line
  # Fixed columns: tool 9, time 12, id 8, separators and gum's indicator ≈ 38.
  # The rest is split between the directory (at most 36) and the title.
  local free=$(( ${COLUMNS:-120} - 38 ))
  (( free < 40 )) && free=40
  local ww=$(( free * 2 / 5 ))
  (( ww > 36 )) && ww=36
  local tw=$(( free - ww - 2 ))
  for row in "${rows[@]}"; do
    parts=("${(@ps:\t:)row}")
    strftime -s when '%d %b %H:%M' "${parts[3]:-0}" 2>/dev/null || when='?'
    where=$parts[4]
    if [[ "$where" == "$root" ]]; then where='.'
    elif [[ "$where" == "$root"/* ]]; then where=${where#$root/}
    else where=${where/#$HOME/\~}
    fi
    [[ -d "$parts[4]" ]] || where+=' (gone)'
    # Keep the tail of a long path: the worktree name is the part that matters.
    (( ${#where} > ww )) && where="…${where[-$(( ww - 1 )),-1]}"
    title=${parts[5]:-(untitled)}
    printf -v line "%-9s %s  %-${ww}s  %-${tw}.${tw}s  %s" "$parts[1]" "$when" "$where" "$title" "${parts[2][-8,-1]}"
    lines+=("$line")
  done

  if (( list )); then
    print -l -- "${lines[@]}"
    return 0
  fi

  local pick
  if (( $+commands[gum] )); then
    local height=$(( ${LINES:-40} - 6 ))
    (( height > 25 )) && height=25
    (( height < 5 )) && height=5
    pick=$(print -l -- "${lines[@]}" | command gum filter \
      --header="resume · ${root:t}" --placeholder='Filter sessions…' \
      --height="$height" --no-strict --indicator='▶') || return
  else
    PS3='session ❯ '
    select pick in "${lines[@]}"; do [[ -n "$pick" ]] && break; done
  fi
  [[ -n "$pick" ]] || return 1

  # The picked line is one of ours verbatim, so its index is the row's index.
  local idx=${lines[(ie)$pick]}
  (( idx <= ${#lines} )) || { _resume_log error "resume: could not map selection back to a session"; return 1; }
  parts=("${(@ps:\t:)rows[idx]}")
  local tool=$parts[1] sid=$parts[2] dir=$parts[4]

  [[ -d "$dir" ]] || {
    if (( ${${=RESUME_STRICT_CWD}[(Ie)$tool]} )); then
      _resume_log error "resume: $dir no longer exists and $tool can only resume from there"
      return 1
    fi
    _resume_log warn "resume: $dir is gone; launching from ${root}"
    dir=$root
  }
  local -a cmd
  cmd=(${=RESUME_CMDS[$tool]})
  (( ${#cmd} )) || { _resume_log error "resume: no resume command configured for $tool"; return 1; }
  _resume_log info "resuming $tool ${sid[-8,-1]} in $dir"
  ( builtin cd -- "$dir" && exec "${cmd[@]}" "$sid" "${extra[@]}" )
}
