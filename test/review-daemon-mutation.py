#!/usr/bin/env python3
"""Mutation proof for bin/jjstack-review-daemon: every guard is load-bearing.

Each mutant disables exactly one guard in a copy of the daemon, and the unit
suite (test/review-daemon-check.py) is run against that copy through
REVIEW_DAEMON_BIN. The suite must go red on every mutant. A mutant that
survives names a guard no test can see.

An anchor is matched exactly once, or the mutant is BROKEN: an edit to the
daemon that moves a guard must move its mutant too, or the proof would go on
passing over a guard it no longer touches. A mutant killed by a crash on
import would prove nothing either, so a kill counts only when the suite ran
(its TESTS= line is present).

Exit 0 = every mutant killed. 1 = a survivor. 2 = a broken anchor or a mutant
that crashed the suite instead of failing it.
Prints `mutants=<n> killed=<n> survived=<n> broken=<n>` last.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(REPO, "bin", "jjstack-review-daemon")
TEST = os.path.join(REPO, "test", "review-daemon-check.py")

# name, anchor (must occur exactly once), replacement
MUTANTS = [
    ("opus-check-off", 'return bool(model) and model.startswith("claude-opus")', "return True"),
    ("allowlist-off", 'return (owner or "").lower() in {o.lower() for o in owners}', "return True"),
    ("no-mark-read", 'self.gh.api("notifications/threads/%s" % t["thread_id"], method="PATCH")', "pass"),
    ("no-thread-dedup", 'if self.ledger.seen_threads.get(t["thread_id"]) == t["updated_at"]:', "if False:"),
    ("dispatch-while-busy", 'if state == "busy":', "if False:"),
    ("no-cap", "if self._live_count(now, roster) >= self.cfg.max_sessions:\n                break",
     "if False:\n                break"),
    ("spawn-closed-pr", 'if pr.get("state") != "open":', "if False:"),
    ("never-resume", '"--resume" if resume else "--session-id"', '"--session-id"'),
    ("no-handshake", 'if rec.get("handshake_at") is None:', "if False:"),
    ("model-before-handshake", 'since=rec["handshake_at"])', "since=None)"),
    ("sidechain-counts", 'if rec.get("type") != "assistant" or rec.get("isSidechain"):',
     'if rec.get("type") != "assistant":'),
    ("synthetic-counts", 'if not model or model.startswith("<"):', "if not model:"),
    ("exit-while-busy",
     'if row.get("state") != "idle":\n            return\n        if rec.get("exit_sent_at") is None:',
     'if rec.get("exit_sent_at") is None:'),
    ("resend-forever", 'rec["exit_sends"] < 2 and', "True and"),
    ("token-allowed", 'for k in ("GH_TOKEN", "GITHUB_TOKEN"):', "for k in ():"),
    ("never-idle", "if marks and now - max(marks) > self.cfg.idle_days * DAY:", "if False:"),
    ("crlf-unhandled", 'text.replace("\\r\\n", "\\n")', "text"),
    ("304-is-error",'        if status == 304:\n            return "304"\n', ""),
    ("crash-not-redispatched", "if not clean and d and", "if False and"),
    ("respawn-over-live-pid",
     'if self.spawner.pid_alive(worker):\n            self.note_every(rec, "unregistered"',
     'if False:\n            self.note_every(rec, "unregistered"'),
    ("no-adoption", 'if row and row.get("online"):\n            sid = find_session_for_worker',
     'if False:\n            sid = find_session_for_worker'),
    ("red-passes", "    text = scrub_red(text)\n", ""),
    ("ending-takes-rerequest",
     'if rec["status"] == "ending":\n                self.say("info", "%s: %s, ignored',
     'if False:\n                self.say("info", "%s: %s, ignored'),
    ("dry-run-patches",
     'if not self.cfg.dry_run:\n                try:\n                    self.gh.api("notifications/threads',
     'if True:\n                try:\n                    self.gh.api("notifications/threads'),
    ("review-logged-every-poll", 'newest.get("id") != rec.get("last_review_id") and', "True and"),
    ("retry-same-model", "model_flag=self.cfg.retry_model)", 'model_flag=rec["model_flag"])'),
    ("queued-closed-kept", 'if rec["status"] == "queued":\n                if closed_as:',
     'if rec["status"] == "queued":\n                if False:'),
    ("hub-down-still-acts", "if roster is not None:\n            self._transitions(now, roster)",
     "if roster is not None or True:\n            self._transitions(now, roster or {})"),
    ("no-worker-name-check", 'if "#" in name or not WORKER_RE.match(name):', "if False:"),
    ("booting-respawned",
     "        if self._booting(rec, now):\n            return\n        if self.spawner.pid_alive(worker):",
     "        if self.spawner.pid_alive(worker):"),
    ("dormant-respawned", 'if not rec["pending_dispatch"]:\n            self.note_once(rec, "dormant"',
     'if False:\n            self.note_once(rec, "dormant"'),
]


def run_one(src, out_dir, name, old, new):
    if src.count(old) != 1:
        return name, "broken", "anchor found %d times" % src.count(old)
    path = os.path.join(out_dir, "mutant-" + name)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src.replace(old, new, 1))
    env = dict(os.environ, REVIEW_DAEMON_BIN=path)
    p = subprocess.run([sys.executable, TEST], env=env, capture_output=True, text=True, timeout=300)
    m = re.search(r"^TESTS=(\d+) FAILURES=(\d+)$", p.stdout, re.M)
    if not m:
        return name, "broken", "the suite crashed instead of failing (rc=%d)" % p.returncode
    if p.returncode == 0:
        return name, "survived", "TESTS=%s FAILURES=0" % m.group(1)
    return name, "killed", "FAILURES=%s" % m.group(2)


def main():
    src = open(BIN, encoding="utf-8").read()
    with tempfile.TemporaryDirectory() as out_dir:
        with ThreadPoolExecutor(max_workers=min(8, os.cpu_count() or 2)) as pool:
            results = list(pool.map(lambda m: run_one(src, out_dir, *m), MUTANTS))
    counts = {"killed": 0, "survived": 0, "broken": 0}
    for name, verdict, detail in results:
        counts[verdict] += 1
        if verdict != "killed":
            print("%-26s %s: %s" % (name, verdict.upper(), detail))
    print("mutants=%d killed=%d survived=%d broken=%d" % (
        len(MUTANTS), counts["killed"], counts["survived"], counts["broken"]))
    if counts["broken"]:
        return 2
    return 1 if counts["survived"] else 0


if __name__ == "__main__":
    sys.exit(main())
