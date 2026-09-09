#!/usr/bin/env python3
"""Build a fake HOME holding one or two sessions per tool for the specs.

usage: fixtures.py HOME REPO WORKTREE OTHER GONE
  REPO      the repo root;   WORKTREE  a registered worktree of it
  OTHER     a directory outside the repo;   GONE  a path under REPO that no longer exists
"""
import json, os, sqlite3, sys, urllib.parse

home, repo, wt, other, gone = sys.argv[1:6]
T = 1788900000  # epoch seconds used for every timestamp


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


def jsonl(path, records, mtime=T - 100):
    write(path, "".join(json.dumps(r, separators=(",", ":")) + "\n" for r in records))
    os.utime(path, (mtime, mtime))


def slug(path):
    return "".join(c if c.isalnum() else "-" for c in path)


# claude: one in the worktree with a custom title, one outside the repo
jsonl(f"{home}/.claude/projects/{slug(wt)}/c1c1c1c1-0000-0000-0000-000000000001.jsonl", [
    {"type": "user", "cwd": wt, "sessionId": "c1", "message": {"role": "user", "content": "<system-reminder>skip me</system-reminder>"}},
    {"type": "user", "cwd": wt, "sessionId": "c1", "message": {"role": "user", "content": "first claude prompt"}},
    {"type": "custom-title", "customTitle": "Claude custom title", "sessionId": "c1"},
])
jsonl(f"{home}/.claude/projects/{slug(other)}/c2c2c2c2-0000-0000-0000-000000000002.jsonl", [
    {"type": "user", "cwd": other, "sessionId": "c2", "message": {"role": "user", "content": [{"type": "text", "text": "claude elsewhere"}]}},
])

# agy: history log, conversation a1 in the repo root
jsonl(f"{home}/.gemini/antigravity-cli/history.jsonl", [
    {"display": "agy first prompt", "timestamp": T * 1000, "workspace": repo, "conversationId": ""},
    {"display": "agy first prompt", "timestamp": (T - 60) * 1000, "workspace": repo, "conversationId": "a1a1a1a1-0000-0000-0000-00000000000a"},
    {"display": "agy second prompt", "timestamp": T * 1000, "workspace": repo, "conversationId": "a1a1a1a1-0000-0000-0000-00000000000a"},
])

# codex: a user thread in the worktree (named in the index) and a subagent thread to skip
jsonl(f"{home}/.codex/session_index.jsonl", [{"id": "x1x1x1x1-0000-0000-0000-00000000000b", "thread_name": "Codex named thread"}])
jsonl(f"{home}/.codex/sessions/2026/09/09/rollout-2026-09-09T09-00-00-x1x1x1x1-0000-0000-0000-00000000000b.jsonl", [
    {"type": "session_meta", "payload": {"id": "x1x1x1x1-0000-0000-0000-00000000000b", "cwd": wt, "thread_source": "user"}},
])
jsonl(f"{home}/.codex/sessions/2026/09/09/rollout-2026-09-09T09-00-01-x2x2x2x2-0000-0000-0000-00000000000c.jsonl", [
    {"type": "session_meta", "payload": {"id": "x2x2x2x2-0000-0000-0000-00000000000c", "cwd": repo, "thread_source": "subagent"}},
    {"type": "response_item", "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "codex subagent"}]}},
])
jsonl(f"{home}/.codex/sessions/2026/09/09/rollout-2026-09-09T09-00-02-x3x3x3x3-0000-0000-0000-00000000000d.jsonl", [
    {"type": "session_meta", "payload": {"id": "x3x3x3x3-0000-0000-0000-00000000000d", "cwd": repo}},
    {"type": "response_item", "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "codex unnamed prompt"}]}},
])


def opencode_db(path, rows, table="session_v2"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    db = sqlite3.connect(path)
    db.execute(f"create table {table} (id text primary key, project_id text, parent_id text, directory text, title text, time_updated integer)")
    db.executemany(f"insert into {table} values (?, 'p', ?, ?, ?, ?)", rows)
    db.commit(); db.close()


opencode_db(f"{home}/.local/share/opencode/opencode.db", [
    ("ses_o1o1o1o1aaaaaaaaaaaaaaaaaa", None, repo, "Opencode one", T * 1000),
    ("ses_o2o2o2o2bbbbbbbbbbbbbbbbbb", "ses_o1o1o1o1aaaaaaaaaaaaaaaaaa", repo, "Opencode child", T * 1000),
])
opencode_db(f"{home}/.local/share/opencode2/share/opencode/opencode.db", [
    ("ses_p1p1p1p1cccccccccccccccccc", None, wt, "Opencode2 one", (T + 5) * 1000),
])

# grok: one real session in the repo root, one subagent scratch worktree to skip
def grok(sid, cwd, title):
    write(f"{home}/.grok/sessions/{urllib.parse.quote(cwd, safe='')}/{sid}/summary.json", json.dumps({
        "info": {"id": sid, "cwd": cwd}, "session_summary": title,
        "updated_at": "2026-09-08T20:00:00Z", "last_active_at": "2026-09-08T20:00:00Z"}))


grok("g1g1g1g1-0000-0000-0000-00000000000e", repo, "Grok summary")
grok("g2g2g2g2-0000-0000-0000-00000000000f", f"{home}/.grok/worktrees/x/subagent-1", "Grok subagent")

# kiro-cli, current layout: <dirkey>/sess_<uuid>/session.json in the worktree
write(f"{home}/.kiro/sessions/ef01/sess_k2k2k2k2-0000-0000-0000-000000000011/session.json", json.dumps({
    "schemaVersion": "1.0.0", "id": "sess_k2k2k2k2-0000-0000-0000-000000000011", "title": "Kiro current layout",
    "workspacePaths": [wt], "rootPaths": [wt],
    "createdAt": "2026-09-08T18:00:00Z", "lastModifiedAt": "2026-09-08T18:30:00Z"}))

# kiro-cli, older layout: a session whose directory has since been deleted
write(f"{home}/.kiro/sessions/abcd/k1k1k1k1-0000-0000-0000-000000000010.json", json.dumps({
    "session_id": "k1k1k1k1-0000-0000-0000-000000000010", "cwd": gone, "title": "Kiro gone dir",
    "created_at": "2026-09-08T19:00:00Z", "updated_at": "2026-09-08T19:00:00Z", "session_created_reason": "subagent"}))
