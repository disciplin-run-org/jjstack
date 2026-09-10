#!/usr/bin/env python3
"""Unit tests for bin/jjstack-review-daemon, driven by frozen real specimens.

The daemon's I/O is five adapters: gh, the hub roster, the hub message
channel, the terminal spawner and the clock. Every test here replaces all
five with fakes, so nothing touches GitHub, the hub, or a real terminal.
The fixtures under test/fixtures/review-daemon/ are real responses, frozen
with their recovery commands in PROVENANCE.md. The fakes hand the daemon
those raw objects, so its own field paths are exercised.

Exit 0 = every test passed and the suite is not vacuous.
Exit 1 = a test failed (unittest prints which).
Exit 2 = the suite cannot fail: a fixture is missing, or fewer tests ran
         than the floor below. That is louder than a failure, not quieter.
Prints `TESTS=<n> FAILURES=<n>` last, which smoke.sh reads.
"""

from __future__ import annotations

import copy
import importlib.util
import io
import json
import os
import re
import sys
import tempfile
import unittest
import uuid
from importlib.machinery import SourceFileLoader

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# REVIEW_DAEMON_BIN points the suite at a mutant copy; the mutation proof uses it.
BIN = os.environ.get("REVIEW_DAEMON_BIN") or os.path.join(REPO, "bin", "jjstack-review-daemon")
FIX = os.path.join(REPO, "test", "fixtures", "review-daemon")
MIN_TESTS = 62
FIXTURES = (
    "notifications-200.txt", "notifications-304.txt", "search.json",
    "search-empty.json", "pull-open.json", "pull-merged.json",
    "pull-closed.json", "reviews.json", "workers.json",
    "transcript-mixed.jsonl", "transcript-fable-last.jsonl",
    "transcript-boot.jsonl", "transcript-synthetic.jsonl",
)
_MISSING = [f for f in FIXTURES if not os.path.exists(os.path.join(FIX, f))]
if _MISSING:  # before the module-level loads below, which would crash on it
    print("missing fixtures: %s" % ", ".join(_MISSING))
    print("TESTS=0 FAILURES=0")
    sys.exit(2)

_loader = SourceFileLoader("review_daemon", BIN)
_spec = importlib.util.spec_from_loader("review_daemon", _loader)
rd = importlib.util.module_from_spec(_spec)
sys.modules["review_daemon"] = rd  # dataclasses resolve annotations through sys.modules
_loader.exec_module(rd)


def fx(name):
    # newline="" keeps the CRLF gh prints on header lines; text mode would
    # quietly turn it into LF and the parser's CRLF path would never run.
    with open(os.path.join(FIX, name), encoding="utf-8", newline="") as fh:
        return fh.read()


def fxj(name):
    return json.loads(fx(name))


NOTIF_200 = fx("notifications-200.txt")
NOTIF_304 = fx("notifications-304.txt")
# Test data comes from the fixture's bytes, never from the parser under test:
# a broken parser must fail tests, not crash the suite before any can run.
THREADS = json.loads(NOTIF_200.partition("\r\n\r\n")[2])
PULL_OPEN = fxj("pull-open.json")
PULL_MERGED = fxj("pull-merged.json")
PULL_CLOSED = fxj("pull-closed.json")
REVIEWS = fxj("reviews.json")
T0 = rd.parse_iso("2026-09-10T18:00:00Z")
MIN = 60.0
HOUR = 3600.0
DAY = 86400.0


def thread_for(repo, number):
    """A real thread from the specimen, re-pointed at repo/number only."""
    base = next(t for t in THREADS if t["reason"] == "review_requested"
                and t["repository"]["owner"]["login"] == "disciplin-run-org")
    t = copy.deepcopy(base)
    owner = t["repository"]["owner"]["login"]
    t["repository"]["full_name"] = "%s/%s" % (owner, repo)
    t["subject"]["url"] = "https://api.github.com/repos/%s/%s/pulls/%d" % (owner, repo, number)
    t["id"] = "9%s%d" % (repo.replace("-", ""), number)
    return t


def headers_200(last_modified="Thu, 10 Sep 2026 16:08:34 GMT"):
    status, hdrs, _ = rd.parse_gh_include(NOTIF_200)
    hdrs = dict(hdrs)
    hdrs["last-modified"] = last_modified
    return hdrs


def pull(state_src, number, **over):
    p = copy.deepcopy(state_src)
    p["number"] = number
    p.update(over)
    return p


# ── fakes ────────────────────────────────────────────────────────────────

class FakeGH:
    """Routes (method, path) to canned responses; records every call."""

    def __init__(self):
        self.calls = []
        self.threads = []          # served on a 200
        self.not_modified = False  # serve a 304 instead
        self.last_modified = "Thu, 10 Sep 2026 16:08:34 GMT"
        self.pulls = {}            # "owner/repo/N" -> pull object
        self.reviews = {}          # "owner/repo/N" -> list
        self.search = {"total_count": 0, "incomplete_results": False, "items": []}
        self.login_as = rd.REVIEWER
        self.login_calls = 0

    def login(self):
        self.login_calls += 1
        return self.login_as

    def api(self, path, method="GET", fields=(), headers=(), include=False):
        self.calls.append((method, path, tuple(fields), tuple(headers)))
        if path.startswith("notifications?"):
            if self.not_modified:
                return rd.parse_gh_include(NOTIF_304)
            return 200, headers_200(self.last_modified), json.dumps(self.threads)
        if path.startswith("notifications/threads/") and method == "PATCH":
            return 205, {}, ""
        if path == "search/issues":
            return 200, {}, json.dumps(self.search)
        m = re.match(r"repos/([^/]+)/([^/]+)/pulls/(\d+)(/reviews)?", path)
        if m:
            key = "%s/%s/%s" % (m.group(1), m.group(2), m.group(3))
            if m.group(4):
                return 200, {}, json.dumps(self.reviews.get(key, []))
            if key not in self.pulls:
                raise AssertionError("no pull stubbed for " + key)
            return 200, {}, json.dumps(self.pulls[key])
        raise AssertionError("unexpected gh call %s %s" % (method, path))

    def patched(self):
        return [p for (m, p, _, _) in self.calls if m == "PATCH"]

    def searched(self):
        return [p for (m, p, _, _) in self.calls if p == "search/issues"]


class FakeHub:
    def __init__(self):
        self.rows = {}
        self.down = False

    def workers(self):
        if self.down:
            raise rd.HubError("connection refused")
        return copy.deepcopy(self.rows)

    def set(self, name, online=True, state="idle", exited_cleanly=False):
        self.rows[name] = {"name": name, "online": online, "state": state,
                           "last_activity": T0, "exited_cleanly": exited_cleanly}


class FakeMCP:
    """Records sends. Deliberately has no stop(): a daemon that reached for
    one would raise AttributeError here."""

    def __init__(self):
        self.sent = []

    def send(self, worker, text):
        self.sent.append((worker, text))
        return {"event_id": len(self.sent)}

    def texts(self, worker=None):
        return [t for (w, t) in self.sent if worker is None or w == worker]


class FakeSpawner:
    def __init__(self):
        self.argvs = []
        self.alive = set()

    def spawn(self, argv):
        self.argvs.append(list(argv))

    def pid_alive(self, worker):
        return worker in self.alive


class FakeClock:
    def __init__(self, t=T0):
        self.t = t

    def now(self):
        return self.t


class World:
    """One daemon with fakes, a sandboxed HOME, cwd and state dir."""

    def __init__(self, **cfg):
        self.tmp = tempfile.TemporaryDirectory()
        root = self.tmp.name
        self.home = os.path.join(root, "home")
        self.cwd = os.path.join(root, "Code-Review")
        os.makedirs(self.home)
        os.makedirs(self.cwd)
        self.gh, self.hub, self.mcp = FakeGH(), FakeHub(), FakeMCP()
        self.spawner, self.clock = FakeSpawner(), FakeClock()
        self.lines = []
        opts = dict(owners=("JesperJurcenoks", "disciplin-run-org"),
                    cwd=self.cwd, home=self.home, claude_tm="/opt/bin/claude-tm",
                    terminal="gnome-terminal", reconcile_every=15)
        opts.update(cfg)
        self.cfg = rd.Config(**opts)
        self.ledger = rd.Ledger(os.path.join(self.cwd, ".review-daemon"))
        self.d = rd.Daemon(self.cfg, self.gh, self.hub, self.mcp, self.spawner,
                           self.ledger, self.clock,
                           out=lambda level, text: self.lines.append((level, text)))

    def close(self):
        self.tmp.cleanup()

    def poll(self, minutes=2.0):
        self.clock.t += minutes * MIN
        self.lines.clear()
        self.d.poll_once()
        return list(self.lines)

    def text(self):
        return "\n".join(t for (_, t) in self.lines)

    def request(self, repo, number, reason="review_requested", pr=None, updated="2026-09-10T18:00:00Z"):
        t = thread_for(repo, number)
        t["reason"] = reason
        t["updated_at"] = updated
        self.gh.threads = [x for x in self.gh.threads if x["id"] != t["id"]] + [t]
        self.gh.pulls["disciplin-run-org/%s/%d" % (repo, number)] = pr or pull(PULL_OPEN, number)
        return t

    def record(self, repo, number):
        return self.ledger.records.get(rd.record_key("disciplin-run-org", repo, number))

    def say(self, worker_uuid, model, when=None, sidechain=False):
        """Append an assistant line to the worker's transcript."""
        path = rd.transcript_path(self.home, self.cwd, worker_uuid)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        ts = rd.iso(when if when is not None else self.clock.t + 1)
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"type": "assistant", "isSidechain": sidechain,
                                 "timestamp": ts, "message": {"model": model}}) + "\n")

    def boot(self, repo, number, model="claude-opus-5", state="idle"):
        """Spawn → online → handshake → model line: the record is ready to dispatch."""
        self.request(repo, number)
        self.poll()
        rec = self.record(repo, number)
        self.hub.set(rec["worker"], state="idle")
        self.poll()  # handshake
        self.say(rec["session_uuid"], model)
        self.hub.set(rec["worker"], state=state)
        return rec


def argv_value(argv, flag):
    return argv[argv.index(flag) + 1]


# ── tests ────────────────────────────────────────────────────────────────

class Parsing(unittest.TestCase):
    def test_304_specimen_is_quiet_not_an_error(self):
        status, hdrs, body = rd.parse_gh_include(NOTIF_304)
        self.assertEqual(status, 304)
        self.assertEqual(hdrs["x-poll-interval"], "60")
        self.assertEqual(body.strip(), "")

    def test_specimens_keep_the_crlf_gh_prints(self):
        # .gitattributes marks these -text; without it git would store LF and
        # this parser would only ever be shown a shape gh never produces.
        # The shape gh 2.4.0 really prints: a bare-LF status line, then CRLF
        # header lines, then a CRLF blank line before the body.
        for text in (NOTIF_200, NOTIF_304):
            status_line, _, rest = text.partition("\n")
            self.assertRegex(status_line, r"^HTTP/2\.0 \d{3} [A-Za-z ]+$")  # no \r on it
            head, sep, _ = rest.partition("\r\n\r\n")
            self.assertEqual(sep, "\r\n\r\n")
            self.assertGreater(head.count("\r\n"), 5)
            self.assertNotIn("\n", head.replace("\r\n", ""))  # every header line is CRLF

    def test_200_specimen_carries_last_modified_and_threads(self):
        status, hdrs, body = rd.parse_gh_include(NOTIF_200)
        self.assertEqual(status, 200)
        self.assertEqual(hdrs["last-modified"], "Thu, 10 Sep 2026 16:08:34 GMT")
        self.assertEqual(len(json.loads(body)), 14)

    def test_parse_pr_url_accepts_api_and_html_rejects_issues(self):
        self.assertEqual(rd.parse_pr_url("https://api.github.com/repos/disciplin-run-org/jjstack/pulls/48"),
                         ("disciplin-run-org", "jjstack", 48))
        self.assertEqual(rd.parse_pr_url("https://github.com/JesperJurcenoks/inboundsavvy-cms/pull/584"),
                         ("JesperJurcenoks", "inboundsavvy-cms", 584))
        self.assertIsNone(rd.parse_pr_url("https://api.github.com/repos/o/r/issues/3"))
        self.assertIsNone(rd.parse_pr_url("not a url"))

    def test_real_notifications_yield_review_requests_only(self):
        triggers, ignored = rd.select_triggers(THREADS, ("JesperJurcenoks", "disciplin-run-org"))
        self.assertEqual(len(triggers), 9)
        self.assertEqual({t["reason"] for t in triggers}, {"review_requested"})
        pairs = {(t["repo"], t["number"]) for t in triggers}
        self.assertIn(("inboundsavvy-cms", 573), pairs)
        self.assertIn(("jjstack", 48), pairs)
        self.assertNotIn(("jjstack", 34), pairs)  # a `comment` thread
        self.assertEqual(ignored, [])

    def test_mention_kept_issue_read_and_outsider_split(self):
        base = thread_for("jjstack", 1)
        mention = dict(copy.deepcopy(base), id="m1", reason="mention")
        issue = copy.deepcopy(base)
        issue["id"] = "i1"
        issue["subject"]["type"] = "Issue"
        read = dict(copy.deepcopy(base), id="r1", unread=False)
        outsider = copy.deepcopy(base)
        outsider["id"] = "o1"
        outsider["repository"]["owner"]["login"] = "someone-else"
        outsider["repository"]["full_name"] = "someone-else/freeloader"
        outsider["subject"]["url"] = "https://api.github.com/repos/someone-else/freeloader/pulls/7"
        triggers, ignored = rd.select_triggers([mention, issue, read, outsider],
                                               ("JesperJurcenoks", "disciplin-run-org"))
        self.assertEqual([t["thread_id"] for t in triggers], ["m1"])
        self.assertEqual(triggers[0]["reason"], "mention")
        self.assertEqual([i["thread_id"] for i in ignored], ["o1"])
        self.assertEqual(ignored[0]["owner"], "someone-else")

    def test_allowlist_is_case_insensitive(self):
        owners = ("JesperJurcenoks", "disciplin-run-org")
        self.assertTrue(rd.is_allowlisted("jesperjurcenoks", owners))
        self.assertTrue(rd.is_allowlisted("DISCIPLIN-RUN-ORG", owners))
        self.assertFalse(rd.is_allowlisted("disciplin-run", owners))

    def test_drafts_are_not_filtered(self):
        t = thread_for("jjstack", 5)
        triggers, _ = rd.select_triggers([t], ("disciplin-run-org",))
        self.assertEqual(len(triggers), 1)  # a draft flag lives on the PR, never read here

    def test_parse_search_real_page(self):
        trig, ign = rd.parse_search(fxj("search.json"), ("JesperJurcenoks", "disciplin-run-org"))
        self.assertEqual([(t["repo"], t["number"], t["reason"]) for t in trig],
                         [("jjstack", 48, "reconcile"), ("jjstack", 47, "reconcile")])
        trig, ign = rd.parse_search(fxj("search.json"), ("JesperJurcenoks",))
        self.assertEqual(trig, [])
        self.assertEqual(len(ign), 2)
        self.assertEqual(rd.parse_search(fxj("search-empty.json"), ("JesperJurcenoks",)), ([], []))

    def test_parse_env_file(self):
        with tempfile.NamedTemporaryFile("w", suffix=".env", delete=False) as fh:
            fh.write("# reviewer identity\n\nGH_CONFIG_DIR=/x/gh-ai\nQ=\"quoted value\"\nS='single'\nnoequals\n")
        try:
            env = rd.parse_env_file(fh.name)
        finally:
            os.unlink(fh.name)
        self.assertEqual(env, {"GH_CONFIG_DIR": "/x/gh-ai", "Q": "quoted value", "S": "single"})


class Naming(unittest.TestCase):
    def test_role_and_worker_name_real_example(self):
        self.assertEqual(rd.role_name("jjstack", 12), "jjstack-pr12")
        self.assertEqual(rd.worker_name("Code-Review", "inboundsavvy-cms", 570),
                         "Code-Review-inboundsavvy-cms-pr570-tm")

    def test_worker_name_refuses_what_the_hub_refuses(self):
        with self.assertRaises(ValueError):
            rd.worker_name("Code-Review", "r" * 60, 1)       # over 64 chars
        with self.assertRaises(ValueError):
            rd.worker_name("Code-Review", "pr#34", 1)        # '#' never registers
        with self.assertRaises(ValueError):
            rd.worker_name("Code-Review", "a;rm -rf", 1)     # shell metacharacters

    def test_dispatch_and_handshake_text(self):
        self.assertEqual(rd.dispatch_text("disciplin-run-org", "jjstack", 12),
                         "/review disciplin-run-org/jjstack pr 12")
        hs = rd.handshake_text("disciplin-run-org", "jjstack", 12)
        self.assertIn("READY", hs)
        self.assertIn("disciplin-run-org/jjstack", hs)
        self.assertFalse(hs.startswith("/"))  # a channel message, never a harness command


class Transcripts(unittest.TestCase):
    def test_latest_model_on_real_mixed_trail_is_opus(self):
        self.assertEqual(rd.latest_model(os.path.join(FIX, "transcript-mixed.jsonl")), "claude-opus-5")

    def test_latest_model_fable_last_is_not_opus(self):
        m = rd.latest_model(os.path.join(FIX, "transcript-fable-last.jsonl"))
        self.assertEqual(m, "claude-fable-5-1")
        self.assertFalse(rd.is_opus(m))
        self.assertTrue(rd.is_opus("claude-opus-5"))
        self.assertFalse(rd.is_opus(None))

    def test_boot_transcript_has_no_model_yet(self):
        self.assertIsNone(rd.latest_model(os.path.join(FIX, "transcript-boot.jsonl")))
        self.assertIsNone(rd.latest_model(os.path.join(FIX, "no-such-file.jsonl")))

    def test_latest_model_since(self):
        path = os.path.join(FIX, "transcript-mixed.jsonl")
        cut = rd.parse_iso("2026-09-09T15:29:30Z")  # just after the last fable line
        self.assertEqual(rd.latest_model(path, since=cut), "claude-opus-5")
        self.assertIsNone(rd.latest_model(path, since=rd.parse_iso("2026-09-11T00:00:00Z")))

    def test_synthetic_and_sidechain_lines_are_not_the_model(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "t.jsonl")
            with open(path, "w") as fh:
                fh.write(fx("transcript-fable-last.jsonl"))
                fh.write(fx("transcript-synthetic.jsonl"))
                fh.write(json.dumps({"type": "assistant", "isSidechain": True,
                                     "timestamp": "2026-09-10T12:00:00Z",
                                     "message": {"model": "claude-haiku-4-5-20251001"}}) + "\n")
            self.assertEqual(rd.latest_model(path), "claude-opus-5")

    def test_transcript_path_dashes_the_cwd(self):
        p = rd.transcript_path("/h", "/home/x/Code-Review", "u1")
        self.assertEqual(p, "/h/.claude/projects/-home-x-Code-Review/u1.jsonl")
        self.assertEqual(rd.transcript_path("/h", "/p/a.b_c", "u"), "/h/.claude/projects/-p-a-b-c/u.jsonl")

    def test_find_session_for_worker_reads_the_agent_name_line(self):
        with tempfile.TemporaryDirectory() as d:
            proj = os.path.dirname(rd.transcript_path(d, "/w/Code-Review", "x"))
            os.makedirs(proj)
            with open(os.path.join(proj, "aaa.jsonl"), "w") as fh:
                fh.write(fx("transcript-boot.jsonl"))
            with open(os.path.join(proj, "bbb.jsonl"), "w") as fh:
                fh.write(fx("transcript-boot.jsonl").replace("auto-review", "other"))
            self.assertEqual(rd.find_session_for_worker(d, "/w/Code-Review", "Code-Review-auto-review-tm"), "aaa")
            self.assertIsNone(rd.find_session_for_worker(d, "/w/Code-Review", "Code-Review-none-tm"))


class LedgerTests(unittest.TestCase):
    def test_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            lg = rd.Ledger(os.path.join(d, "s"))
            lg.records["k"] = {"status": "queued", "number": 3}
            lg.last_modified = "x"
            lg.save()
            lg2 = rd.Ledger(os.path.join(d, "s"))
            self.assertEqual(lg2.records, {"k": {"status": "queued", "number": 3}})
            self.assertEqual(lg2.last_modified, "x")

    def test_save_is_atomic(self):
        with tempfile.TemporaryDirectory() as d:
            lg = rd.Ledger(os.path.join(d, "s"))
            lg.records["k"] = {"status": "queued"}
            lg.save()
            before = open(lg.path).read()
            lg.records["k"] = {"status": "active", "bad": object()}  # not JSON-serialisable
            with self.assertRaises(TypeError):
                lg.save()
            self.assertEqual(open(lg.path).read(), before)
            self.assertEqual(sorted(os.listdir(os.path.dirname(lg.path))), ["ledger.json"])

    def test_history_and_ignored_are_append_only(self):
        with tempfile.TemporaryDirectory() as d:
            lg = rd.Ledger(os.path.join(d, "s"))
            lg.append_history({"k": 1})
            lg.append_history({"k": 2})
            self.assertEqual(len(open(os.path.join(d, "s", "history.jsonl")).readlines()), 2)
            self.assertTrue(lg.append_ignored({"thread_id": "o1", "updated_at": "t"}))
            self.assertFalse(lg.append_ignored({"thread_id": "o1", "updated_at": "t"}))
            self.assertTrue(lg.append_ignored({"thread_id": "o1", "updated_at": "t2"}))
            self.assertEqual(len(open(os.path.join(d, "s", "ignored.jsonl")).readlines()), 2)


class Identity(unittest.TestCase):
    def test_gh_token_is_refused_before_any_call(self):
        gh = FakeGH()
        with self.assertRaises(rd.IdentityError):
            rd.check_identity({"GH_TOKEN": "x", "GH_CONFIG_DIR": "/d"}, gh)
        with self.assertRaises(rd.IdentityError):
            rd.check_identity({"GITHUB_TOKEN": "x", "GH_CONFIG_DIR": "/d"}, gh)
        self.assertEqual(gh.login_calls, 0)

    def test_missing_config_dir_is_refused(self):
        with self.assertRaises(rd.IdentityError):
            rd.check_identity({}, FakeGH())

    def test_wrong_login_is_refused(self):
        gh = FakeGH()
        gh.login_as = "JesperJurcenoks"
        with self.assertRaises(rd.IdentityError):
            rd.check_identity({"GH_CONFIG_DIR": "/d"}, gh)

    def test_reviewer_login_passes(self):
        rd.check_identity({"GH_CONFIG_DIR": "/d"}, FakeGH())


class Polling(unittest.TestCase):
    def setUp(self):
        self.w = World()

    def tearDown(self):
        self.w.close()

    def test_quiet_poll_prints_nothing_and_logs_one_line(self):
        self.w.gh.not_modified = True
        self.assertEqual(self.w.poll(), [])
        log = open(os.path.join(self.w.cwd, ".review-daemon", "daemon.log")).read().splitlines()
        self.assertEqual(len(log), 1)
        self.assertIn("poll=1", log[0])

    def test_if_modified_since_is_sent_after_a_200(self):
        self.w.poll()
        self.w.gh.not_modified = True
        self.w.poll()
        notif = [h for (m, p, f, h) in self.w.gh.calls if p.startswith("notifications?")]
        self.assertEqual(notif[0], ())
        self.assertIn("If-Modified-Since: Thu, 10 Sep 2026 16:08:34 GMT", notif[1])

    def test_closed_prs_are_not_spawned_but_are_marked_read_once(self):
        self.w.gh.threads = THREADS
        triggers, _ = rd.select_triggers(THREADS, self.w.cfg.owners)
        for t in triggers:
            self.w.gh.pulls["%s/%s/%d" % (t["owner"], t["repo"], t["number"])] = pull(PULL_MERGED, t["number"])
        out = self.w.poll()
        self.assertEqual(self.w.spawner.argvs, [])
        self.assertEqual(len(self.w.gh.patched()), 9)
        self.assertEqual(self.w.ledger.records, {})
        # Skipped at the door: never queued, so never in history, and said so.
        self.assertEqual(len(out), 9)
        self.assertTrue(all("skipped: the PR is already merged" in t for _, t in out))
        self.assertFalse(os.path.exists(os.path.join(self.w.cwd, ".review-daemon", "history.jsonl")))
        self.w.poll()
        self.assertEqual(len(self.w.gh.patched()), 9)  # same threads, same updated_at: no second PATCH

    def test_new_request_spawns_opus_with_a_session_id(self):
        thread = self.w.request("jjstack", 48)
        self.w.poll()
        self.assertEqual(len(self.w.spawner.argvs), 1)
        argv = self.w.spawner.argvs[0]
        self.assertEqual(argv[0], "gnome-terminal")
        self.assertIn("--title=Code-Review-jjstack-pr48-tm", argv)
        self.assertIn("--working-directory=" + self.w.cwd, argv)
        self.assertIn("/opt/bin/claude-tm", argv)
        self.assertIn("--role=jjstack-pr48", argv)
        self.assertEqual(argv_value(argv, "--model"), "opus[1m]")
        sid = argv_value(argv, "--session-id")
        self.assertEqual(str(uuid.UUID(sid)), sid)
        self.assertNotIn("--resume", argv)
        rec = self.w.record("jjstack", 48)
        self.assertEqual((rec["status"], rec["pending_dispatch"], rec["session_uuid"]), ("active", True, sid))
        self.assertEqual(rec["threads"], [thread["id"]])
        self.assertEqual(self.w.gh.patched(), ["notifications/threads/" + thread["id"]])

    def test_nothing_is_sent_before_the_worker_is_online(self):
        self.w.request("jjstack", 48)
        self.w.poll()
        self.w.poll()
        self.assertEqual(self.w.mcp.sent, [])

    def test_handshake_then_dispatch_exact_string(self):
        rec = self.w.boot("jjstack", 48)
        self.assertEqual(len(self.w.mcp.sent), 1)
        self.assertIn("READY", self.w.mcp.sent[0][1])
        self.w.poll()
        self.assertEqual(self.w.mcp.texts(rec["worker"])[-1], "/review disciplin-run-org/jjstack pr 48")
        self.assertFalse(self.w.record("jjstack", 48)["pending_dispatch"])

    def test_no_dispatch_before_a_model_line_after_the_handshake(self):
        self.w.request("jjstack", 48)
        self.w.poll()
        rec = self.w.record("jjstack", 48)
        self.w.say(rec["session_uuid"], "claude-opus-5", when=self.w.clock.t - 10)  # older than the handshake
        self.w.hub.set(rec["worker"])
        self.w.poll()
        self.w.poll()
        self.assertNotIn("/review disciplin-run-org/jjstack pr 48", self.w.mcp.texts())

    def test_no_dispatch_while_busy_then_dispatch_on_idle(self):
        rec = self.w.boot("jjstack", 48, state="busy")
        self.w.poll()
        self.assertEqual(len(self.w.mcp.texts()), 1)  # the handshake only
        self.w.hub.set(rec["worker"], state="idle")
        self.w.poll()
        self.assertEqual(self.w.mcp.texts()[-1], "/review disciplin-run-org/jjstack pr 48")

    def test_wrong_model_is_refused_exited_and_retried_once(self):
        rec = self.w.boot("jjstack", 48, model="claude-fable-5-1")
        out = self.w.poll()
        self.assertNotIn("/review disciplin-run-org/jjstack pr 48", self.w.mcp.texts())
        self.assertEqual(self.w.mcp.texts()[-1], "/exit")
        self.assertTrue(any(level == "warn" and "claude-fable-5-1" in text for level, text in out))
        first_sid = rec["session_uuid"]
        self.w.hub.set(rec["worker"], online=False, exited_cleanly=True)
        self.w.poll()
        argv = self.w.spawner.argvs[-1]
        self.assertEqual(len(self.w.spawner.argvs), 2)
        self.assertEqual(argv_value(argv, "--model"), "claude-opus-5[1m]")
        self.assertNotIn("--resume", argv)
        self.assertNotEqual(argv_value(argv, "--session-id"), first_sid)
        rec = self.w.record("jjstack", 48)
        self.w.hub.set(rec["worker"])
        self.w.poll()  # handshake to the new session
        self.w.say(rec["session_uuid"], "claude-fable-5-1")
        out = self.w.poll()
        self.assertEqual(self.w.mcp.texts().count("/exit"), 1)
        self.assertTrue(any(level == "error" for level, _ in out))
        self.w.poll()
        self.assertNotIn("/review disciplin-run-org/jjstack pr 48", self.w.mcp.texts())

    def test_cap_of_four_then_fifo(self):
        for n in (1, 2, 3, 4, 5):
            self.w.request("jjstack", n, updated="2026-09-10T18:0%d:00Z" % n)
        self.w.poll()
        self.assertEqual(len(self.w.spawner.argvs), 4)
        self.assertEqual(self.w.record("jjstack", 5)["status"], "queued")
        first = self.w.record("jjstack", 1)
        self.w.gh.pulls["disciplin-run-org/jjstack/1"] = pull(PULL_MERGED, 1)
        self.w.hub.set(first["worker"])
        self.w.poll()
        self.assertIn("/save-and-exit", self.w.mcp.texts(first["worker"]))
        self.w.hub.set(first["worker"], online=False, exited_cleanly=True)
        self.w.poll()
        self.assertIsNone(self.w.record("jjstack", 1))
        self.assertEqual(self.w.record("jjstack", 5)["status"], "active")
        self.assertIn("--role=jjstack-pr5", self.w.spawner.argvs[-1])

    def test_a_queued_pr_that_closes_is_dropped_unspawned(self):
        w = World(max_sessions=1)
        try:
            w.request("jjstack", 1, updated="2026-09-10T18:01:00Z")
            w.request("jjstack", 2, updated="2026-09-10T18:02:00Z")
            w.poll()
            self.assertEqual(w.record("jjstack", 2)["status"], "queued")
            w.gh.pulls["disciplin-run-org/jjstack/2"] = pull(PULL_MERGED, 2)
            out = w.poll()
            self.assertIsNone(w.record("jjstack", 2))
            self.assertEqual(len(w.spawner.argvs), 1)
            hist = [json.loads(l) for l in open(os.path.join(w.cwd, ".review-daemon", "history.jsonl"))]
            self.assertEqual((hist[-1]["number"], hist[-1]["end_reason"]), (2, "merged"))
            self.assertTrue(any("dropped from the queue" in t for _, t in out))
        finally:
            w.close()

    def test_re_request_goes_to_the_same_worker(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.request("jjstack", 48, updated="2026-09-10T19:00:00Z")
        self.w.hub.set(rec["worker"], state="busy")
        self.w.poll()
        self.assertEqual(self.w.mcp.texts().count("/review disciplin-run-org/jjstack pr 48"), 1)
        self.w.hub.set(rec["worker"], state="idle")
        self.w.poll()
        self.assertEqual(self.w.mcp.texts().count("/review disciplin-run-org/jjstack pr 48"), 2)
        self.assertEqual(len(self.w.spawner.argvs), 1)
        self.assertEqual(len(self.w.gh.patched()), 2)

    def test_mention_behaves_like_a_request(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.request("jjstack", 48, reason="mention", updated="2026-09-10T19:00:00Z")
        self.w.poll()
        self.assertEqual(self.w.mcp.texts().count("/review disciplin-run-org/jjstack pr 48"), 2)
        self.assertEqual(len(self.w.spawner.argvs), 1)

    def test_reconcile_does_not_redispatch_an_active_pr(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.gh.search = fxj("search.json")
        self.w.gh.pulls["disciplin-run-org/jjstack/47"] = pull(PULL_OPEN, 47)
        self.w.d.poll_count = self.w.cfg.reconcile_every - 1
        self.w.poll()
        self.assertEqual(self.w.mcp.texts(rec["worker"]).count("/review disciplin-run-org/jjstack pr 48"), 1)
        self.assertEqual(self.w.record("jjstack", 47)["status"], "active")  # the one it had not seen

    def test_reconcile_cadence(self):
        w = World(reconcile_every=3)
        try:
            w.gh.not_modified = True
            searched_on = []
            for n in range(1, 7):
                before = len(w.gh.searched())
                w.poll()
                if len(w.gh.searched()) > before:
                    searched_on.append(n)
            self.assertEqual(searched_on, [1, 3, 6])
        finally:
            w.close()

    def test_crash_resumes_the_same_session_and_redispatches(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        sid = rec["session_uuid"]
        self.w.hub.set(rec["worker"], online=False, exited_cleanly=False)
        self.w.poll(minutes=10)
        argv = self.w.spawner.argvs[-1]
        self.assertEqual(argv_value(argv, "--resume"), sid)
        self.assertNotIn("--session-id", argv)
        self.assertTrue(self.w.record("jjstack", 48)["pending_dispatch"])

    def test_live_pid_without_hub_row_is_never_respawned(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.hub.set(rec["worker"], online=False)
        self.w.spawner.alive.add(rec["worker"])
        out = self.w.poll(minutes=10)
        self.assertEqual(len(self.w.spawner.argvs), 1)
        self.assertTrue(any(level == "warn" for level, _ in out))

    def test_a_booting_worker_is_not_respawned(self):
        self.w.request("jjstack", 48)
        self.w.poll()
        self.w.poll(minutes=1)
        self.assertEqual(len(self.w.spawner.argvs), 1)

    def test_clean_exit_without_work_stays_dormant_until_a_request(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.hub.set(rec["worker"], online=False, exited_cleanly=True)
        self.w.poll(minutes=10)
        self.assertEqual(len(self.w.spawner.argvs), 1)
        self.w.request("jjstack", 48, updated="2026-09-10T20:00:00Z")
        self.w.poll()
        self.assertEqual(argv_value(self.w.spawner.argvs[-1], "--resume"), rec["session_uuid"])

    def test_merged_ends_only_when_idle_and_is_recorded(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.gh.pulls["disciplin-run-org/jjstack/48"] = pull(PULL_MERGED, 48)
        self.w.hub.set(rec["worker"], state="busy")
        self.w.poll()
        self.assertEqual(self.w.record("jjstack", 48)["status"], "ending")
        self.assertNotIn("/save-and-exit", self.w.mcp.texts())
        self.w.hub.set(rec["worker"], state="idle")
        self.w.poll()
        self.assertEqual(self.w.mcp.texts()[-1], "/save-and-exit")
        self.w.hub.set(rec["worker"], online=False, exited_cleanly=True)
        out = self.w.poll()
        self.assertIsNone(self.w.record("jjstack", 48))
        hist = [json.loads(l) for l in open(os.path.join(self.w.cwd, ".review-daemon", "history.jsonl"))]
        self.assertEqual(hist[-1]["end_reason"], "merged")
        self.assertTrue(any("ended" in text for _, text in out))

    def test_closed_unmerged_ends(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.gh.pulls["disciplin-run-org/jjstack/48"] = pull(PULL_CLOSED, 48)
        self.w.poll()
        self.assertEqual(self.w.record("jjstack", 48)["end_reason"], "closed")
        self.assertEqual(self.w.mcp.texts()[-1], "/save-and-exit")

    def test_idle_days_end_the_session(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.clock.t += 8 * DAY
        self.w.poll()
        self.assertEqual(self.w.record("jjstack", 48)["end_reason"], "idle")

    def test_recent_pr_activity_keeps_it_alive(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.clock.t += 8 * DAY
        self.w.gh.pulls["disciplin-run-org/jjstack/48"] = pull(PULL_OPEN, 48, updated_at=rd.iso(self.w.clock.t - DAY))
        self.w.poll()
        self.assertEqual(self.w.record("jjstack", 48)["status"], "active")

    def test_exit_is_resent_once_then_never_again(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.gh.pulls["disciplin-run-org/jjstack/48"] = pull(PULL_MERGED, 48)
        self.w.poll()
        self.w.poll(minutes=16)
        self.w.poll(minutes=16)
        self.w.poll(minutes=16)
        self.assertEqual(self.w.mcp.texts().count("/save-and-exit"), 2)

    def test_posted_review_is_logged_once(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.record("jjstack", 48)["last_dispatch_at"] = rd.parse_iso("2026-09-10T12:00:00Z")
        self.w.gh.reviews["disciplin-run-org/jjstack/48"] = REVIEWS
        out = self.w.poll()
        posted = [t for _, t in out if "review posted" in t]
        self.assertEqual(len(posted), 1)
        self.assertIn("APPROVED", posted[0])
        self.assertEqual([t for _, t in self.w.poll() if "review posted" in t], [])

    def test_new_commits_are_logged_once(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.gh.pulls["disciplin-run-org/jjstack/48"] = pull(PULL_OPEN, 48, head={"sha": "b" * 40})
        self.assertEqual(len([t for _, t in self.w.poll() if "new commits" in t]), 1)
        self.assertEqual([t for _, t in self.w.poll() if "new commits" in t], [])

    def test_long_review_gets_an_hourly_note_and_is_never_interrupted(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.hub.set(rec["worker"], state="busy")
        notes = []
        for _ in range(70):  # 140 minutes of polls
            notes += [t for _, t in self.w.poll() if "still running" in t]
        self.assertEqual(len(notes), 2)
        self.assertEqual(self.w.mcp.texts(), [self.w.mcp.texts()[0], "/review disciplin-run-org/jjstack pr 48"])

    def test_waiting_permission_warns(self):
        rec = self.w.boot("jjstack", 48, state="waiting_permission")
        out = self.w.poll()
        self.assertTrue(any(level == "warn" and "permission" in text for level, text in out))

    def test_outsider_goes_to_ignored_log_only(self):
        t = thread_for("jjstack", 9)
        t["repository"]["owner"]["login"] = "someone-else"
        t["subject"]["url"] = "https://api.github.com/repos/someone-else/freeloader/pulls/9"
        self.w.gh.threads = [t]
        out = self.w.poll()
        self.assertEqual(out, [])
        self.assertEqual(self.w.gh.patched(), [])
        self.assertEqual(self.w.spawner.argvs, [])
        ign = open(os.path.join(self.w.cwd, ".review-daemon", "ignored.jsonl")).read()
        self.assertIn("someone-else/freeloader", ign)

    def test_hub_down_warns_once_and_changes_nothing(self):
        self.w.request("jjstack", 48)
        self.w.hub.down = True
        out1 = self.w.poll()
        out2 = self.w.poll()
        self.assertEqual(self.w.spawner.argvs, [])
        self.assertEqual(len([1 for level, _ in out1 if level == "warn"]), 1)
        self.assertEqual([1 for level, _ in out2 if level == "warn"], [])
        self.w.hub.down = False
        self.w.poll()
        self.assertEqual(len(self.w.spawner.argvs), 1)

    def test_a_session_started_by_hand_is_adopted_not_duplicated(self):
        worker = "Code-Review-jjstack-pr48-tm"
        proj = os.path.dirname(rd.transcript_path(self.w.home, self.w.cwd, "x"))
        os.makedirs(proj)
        with open(os.path.join(proj, "hand-made.jsonl"), "w") as fh:
            fh.write(fx("transcript-boot.jsonl").replace("Code-Review-auto-review-tm", worker))
        self.w.hub.set(worker)
        self.w.request("jjstack", 48)
        self.w.poll()
        self.assertEqual(self.w.spawner.argvs, [])
        rec = self.w.record("jjstack", 48)
        self.assertEqual(rec["session_uuid"], "hand-made")
        self.w.poll()  # handshake
        self.w.say("hand-made", "claude-opus-5")
        self.w.poll()
        self.assertEqual(self.w.mcp.texts()[-1], "/review disciplin-run-org/jjstack pr 48")

    def test_a_request_on_an_ending_pr_is_ignored(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        self.w.gh.pulls["disciplin-run-org/jjstack/48"] = pull(PULL_MERGED, 48)
        self.w.hub.set(rec["worker"], state="busy")
        self.w.poll()
        self.w.request("jjstack", 48, updated="2026-09-10T21:00:00Z", pr=pull(PULL_MERGED, 48))
        self.w.hub.set(rec["worker"], state="idle")
        out = self.w.poll()
        self.assertEqual(self.w.mcp.texts().count("/review disciplin-run-org/jjstack pr 48"), 1)
        self.assertTrue(any("ignored: the session is closing (merged)" in t for _, t in out))
        self.assertFalse(self.w.record("jjstack", 48)["pending_dispatch"])

    def test_ledger_survives_a_restart(self):
        rec = self.w.boot("jjstack", 48)
        self.w.poll()
        again = rd.Ledger(os.path.join(self.w.cwd, ".review-daemon"))
        key = rd.record_key("disciplin-run-org", "jjstack", 48)
        self.assertEqual(again.records[key]["session_uuid"], rec["session_uuid"])
        self.assertEqual(again.records[key]["status"], "active")

    def test_dry_run_changes_nothing(self):
        w = World(dry_run=True)
        try:
            w.request("jjstack", 48)
            out = w.poll()
            self.assertEqual(w.spawner.argvs, [])
            self.assertEqual(w.mcp.sent, [])
            self.assertEqual(w.gh.patched(), [])
            self.assertFalse(os.path.exists(os.path.join(w.cwd, ".review-daemon", "ledger.json")))
            self.assertTrue(any("[dry-run]" in t and "Code-Review-jjstack-pr48-tm" in t for _, t in out))
        finally:
            w.close()


class Console(unittest.TestCase):
    def test_render_never_emits_red(self):
        for level in ("info", "warn", "error", "note"):
            line = rd.render(level, "x \033[31mred\033[0m \033[91mbright\033[0m", color=True)
            self.assertNotRegex(line, "\033\\[(?:[0-9;]*;)?(?:31|91|41|101)(?:;[0-9;]*)?m")
        self.assertIn("\033[93m", rd.render("warn", "w", color=True))
        self.assertNotIn("\033", rd.render("warn", "w", color=False))


def main():
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=1).run(suite)
    failures = len(result.failures) + len(result.errors)
    if failures:
        print(stream.getvalue())
    print("TESTS=%d FAILURES=%d" % (result.testsRun, failures))
    if result.testsRun < MIN_TESTS:
        print("only %d tests ran; the floor is %d" % (result.testsRun, MIN_TESTS))
        return 2
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
