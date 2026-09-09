#!/usr/bin/env python3
"""jjstack permission floor — a PreToolUse hook that DENIES, deterministically.

This is the whole safety story for Bash. There is no rater, no API key, no
network call and no human prompt: a command either matches a rule here and is
refused with a reason Claude can act on, or it runs.

Why it is shaped this way
-------------------------
The gate it replaces asked a Haiku model to rate each command and, when the
answer was anything but LOW, deferred — which surfaces the normal permission
dialog. Over 2026-09-07..09 that produced 183 human prompts, 147 of them
because the rater's reply was `LOW\\n\\n**Rationale:**...` truncated at
max_tokens and the parser accepted only a bare one-word answer. Every one of
those prompts was approved. A gate a human approves 100% of the time is not a
gate, it is latency, and an LLM in the hot path is a second failure mode
guarding against nothing.

So the judgement is gone and only the floor remains. `deny` is used rather
than `ask` on purpose: `deny` hands Claude the reason and it reroutes inside
the same turn, while `ask` stops the session and waits for a person. `deny`
also works in `bypassPermissions` mode, which `allow` rules do not.

Two families of rule
--------------------
FLOOR   unbounded reach or unreviewable content. `rm -rf ~` names no target;
        `curl … | sh` cannot be specific about code nobody has read. These
        are refused whatever the stated purpose.

SHAPE   one command per Bash call. This has been a standing instruction in
        CLAUDE.md for months and prose did not carry it: 391 of 393 prompted
        commands in the audit were compound. It is not a style rule. A
        compound command is opaque to every prefix rule the permission system
        has (`S=/tmp/x; rm -rf $S` starts with an assignment, so `Bash(rm *)`
        never sees it) and it is what made the audit log unreadable. Split
        into sequential calls and each one is judged on what it actually does.

Floor is evaluated first: when a command is both unbounded and compound, the
unbounded reach is the more serious thing to say.

Contract
--------
stdin  PreToolUse hook payload (tool_name, tool_input.command, ...).
stdout on a match, a PreToolUse `deny` decision with a reason. Otherwise
       nothing at all, which lets the call proceed.
exit   always 0. A hook that crashes must not be able to block work, so any
       unexpected error falls through to "allow" — the deny rules are a floor
       under a system that is already permissive by design, not a sandbox.

`--rules` prints the rule names, one per line, so the test suite can derive
the set that needs fixtures instead of enumerating one by hand.
"""

from __future__ import annotations

import json
import os
import re
import sys

# ── FLOOR ────────────────────────────────────────────────────────────────────
# Ported verbatim in intent from the rated gate's floor, including the two
# holes its own fixtures exposed: `rm -rf ~` (the old rule required a trailing
# slash) and `curl -d @<key>` (only the pipe-to-shell spelling was caught).
#
# ROOT_TARGET is every spelling of "a root", and the trailing (space|;|end) is
# what separates `rm -rf $HOME` from the ordinary `rm -rf $HOME/project/build`.
ROOT_TARGET = r'("?\$\{?HOME\}?"?/?\*?|~/?\*?|/\*?|\.\.?/?\*?)'

FLOOR = [
    (
        "UNBOUNDED",
        # chmod and chown are spelled separately because they take a mode or an
        # owner before the target: `chmod -R 777 /` puts `777` where the other
        # verbs put the path, so the shared pattern walked straight past the
        # widest-reaching command in the set.
        re.compile(
            r"(^|[\s;&|])("
            r"(rm|rmdir|shred)(\s+-[^\s]+)*"
            r"|(chmod|chown)(\s+-[^\s]+)*(\s+[^\s-][^\s]*)?"
            r")\s+" + ROOT_TARGET + r"(\s|;|$)"
        ),
        "the target is a filesystem root, a home directory or a bare wildcard, "
        "so the command has no bound. Name the directory you mean.",
    ),
    (
        "PIPE_TO_SHELL",
        # `sh\b` and not `sh`: without the boundary this refuses the entirely
        # ordinary `curl -s <url> | sha256sum`.
        re.compile(r"(curl|wget)[^|;&]*\|\s*(sudo\s+)?(ba|z|k)?sh\b"),
        "this pipes fetched code straight into a shell, so nobody reads what "
        "runs. Download it to a file, read it, then run the file.",
    ),
    (
        "UPLOAD_FILE",
        re.compile(
            r"(curl|wget)[^;&|]*"
            r"(-d|--data|--data-binary|--data-raw|-T|--upload-file|-F|--form)"
            r"[\s=]*[^;&|]*@"
        ),
        "this sends a local file to the network, which is the shape of "
        "credential exfiltration. Post an inline literal instead of @file.",
    ),
    (
        "SECRET_PATH",
        re.compile(
            r"(curl|wget|nc|ncat|scp|rsync|ftp)[^;&|]*"
            r"(\.ssh/|\.aws/credentials|\.netrc|anthropic_api_key|id_rsa|"
            r"id_ed25519|\.env(\s|$)|credentials\.json|\.git-credentials)"
        ),
        "a network command naming a well-known secret path. Secrets do not "
        "leave the machine.",
    ),
    (
        "DEVICE",
        re.compile(r"(^|\s)(dd\s+[^;&|]*of=/dev/|mkfs(\.[a-z0-9]+)?\s|fdisk\s|parted\s)"),
        "this writes to a block device, which destroys a filesystem rather "
        "than a file. Ask a person to run it.",
    ),
    (
        "FORKBOMB",
        re.compile(r":\(\)\s*\{"),
        "this is a fork bomb.",
    ),
    (
        "POWER",
        re.compile(r"(^|\s)(shutdown|reboot|halt|poweroff)(\s|$)"),
        "this powers down or reboots the machine other sessions are running "
        "on. Ask a person to run it.",
    ),
    (
        "SUDO_ROOT",
        re.compile(r"(^|\s)sudo\s+(rm|dd|mkfs|shutdown|reboot)(\s|$)"),
        "a destructive command as root. Run it without sudo, or ask a person.",
    ),
    (
        "PUSH_TO_TRUNK",
        # A force-push whose refspec is the trunk. `\b` keeps a branch named
        # `feat/maintenance` out of it: the `n` of `main` is followed by a word
        # character there, so there is no boundary.
        re.compile(
            r"git\s+(-C\s+\S+\s+)?push\b[^;&|]*"
            r"(--force\b|--force-with-lease\b|\s-f\b)[^;&|]*\b(main|master)\b"
        ),
        "a force-push to the trunk rewrites history other checkouts are on. "
        "Force-push a feature branch and open a PR.",
    ),
    (
        "PUSH_MIRROR",
        re.compile(r"git\s+(-C\s+\S+\s+)?push\b[^;&|]*--mirror\b"),
        "--mirror replaces every remote ref, including branches this "
        "checkout has never seen. Push the one branch you mean.",
    ),
]

SHAPE_REASON = (
    "one command per Bash call. This call chains several. Split it into "
    "sequential Bash calls so each is judged on what it does: use `git -C "
    "<dir> ...` instead of `cd <dir> && git ...`, run a command directly "
    "instead of assigning its output with $(...), and when you need a "
    "multi-line script, write it to the scratchpad with the Write tool and "
    "run the file as one command."
)

RULES = [name for name, _, _ in FLOOR] + ["SHAPE"]

# Operators that make a call more than one command. A pipe is deliberately
# absent: `grep x src | head -3` is one thought and reads as one line in the
# audit log. Redirection is absent for the same reason.
COMPOUND_OPERATORS = ("&&", "||", ";", "\n", "$(", "<(", ">(", "`", "&")


def strip_heredocs(command: str) -> str:
    """Remove heredoc BODIES, keeping the line that opens them.

    A heredoc body is data the shell never interprets, so `;`, `&&` and `$(`
    inside one say nothing about how many commands the call runs. Writing a
    commit message or a fixture file with `cat > f <<'EOF'` has to stay a
    single call, otherwise the shape rule bans the very thing it tells Claude
    to do instead of chaining.
    """
    lines = command.split("\n")
    out: list[str] = []
    i = 0
    opener = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
    while i < len(lines):
        line = lines[i]
        out.append(line)
        delims = [(m.group(2), "<<-" in m.group(0)) for m in opener.finditer(line)]
        i += 1
        for delim, dashed in delims:
            while i < len(lines):
                candidate = lines[i]
                stripped = candidate.lstrip("\t") if dashed else candidate
                i += 1
                if stripped.strip() == delim:
                    break
    return "\n".join(out)


def bare_text(command: str) -> str:
    """Blank out quoted spans and backslash escapes, keeping length and layout.

    `echo "a && b"` is one command; the `&&` is an argument. Scanning with
    quote state is the only way to tell that from `a && b`. Escapes are blanked
    too, so `find . -name '*.tmp' -exec rm {} \\;` keeps its terminator out of
    the operator search.
    """
    out = []
    quote = None  # None, "'" or '"'
    i = 0
    while i < len(command):
        ch = command[i]
        if quote is None and ch == "\\" and i + 1 < len(command):
            out.append("  ")
            i += 2
            continue
        if quote == '"' and ch == "\\" and i + 1 < len(command):
            out.append("  ")
            i += 2
            continue
        if quote is None and ch in ("'", '"'):
            quote = ch
            out.append(" ")
        elif quote is not None and ch == quote:
            quote = None
            out.append(" ")
        elif quote is not None:
            # Quoted newlines are blanked with everything else, so a multi-line
            # commit message stays one command. An unterminated quote therefore
            # hides the rest of the call from the SHAPE scan — which is safe,
            # because FLOOR is matched against the raw command, never this.
            out.append(" ")
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def evaluate(command: str):
    """Return (rule, reason) for a command that must be refused, else None."""
    if not command.strip():
        return None

    for name, pattern, reason in FLOOR:
        if pattern.search(command):
            return name, reason

    scan = bare_text(strip_heredocs(command))
    # Redirection is not chaining. `2>&1`, `&>log` and `>&2` all carry a bare
    # `&` that would otherwise read as "run this in the background", and
    # `cmd 2>&1 | tail` is the single most common line in this codebase.
    scan = re.sub(r"\d*>&\d*|&>{1,2}", " ", scan)
    # A single trailing `;` or `&` terminates one command rather than joining
    # two, so it is not evidence of chaining.
    scan = re.sub(r"[;&]\s*$", "", scan)
    for op in COMPOUND_OPERATORS:
        if op in scan:
            return "SHAPE", SHAPE_REASON
    return None


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--rules":
        print("\n".join(RULES))
        return 0

    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    if payload.get("tool_name") != "Bash":
        return 0
    command = (payload.get("tool_input") or {}).get("command") or ""

    verdict = evaluate(command)
    if verdict is None:
        return 0
    rule, reason = verdict

    log_path = os.environ.get("JJSTACK_FLOOR_LOG", "")
    if log_path and log_path != "/dev/null":
        try:
            os.makedirs(os.path.dirname(log_path), exist_ok=True)
            with open(log_path, "a", encoding="utf-8") as fh:
                fh.write(
                    "%s worker=%s rule=%s\n"
                    % (
                        __import__("datetime").datetime.now().astimezone().isoformat(
                            timespec="seconds"
                        ),
                        os.environ.get("TM_WORKER_NAME", "<none>"),
                        rule,
                    )
                )
        except Exception:
            pass

    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": "%s: %s" % (rule, reason),
            }
        },
        sys.stdout,
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Never let a bug here stop work. See the module docstring.
        sys.exit(0)
