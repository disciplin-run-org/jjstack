#!/usr/bin/env python3
"""Mutation proof for the permission floor.

Remove one rule at a time and require that the fixture table notices — and
notices for the right reason: the rows that go red must be exactly the rows
that name the removed rule. A rule whose deletion leaves the suite green has
no assertion behind it; a rule whose deletion reddens somebody else's rows is
being covered by a neighbour.

The mutation is applied to the LOADED MODULE, not to the source text. The
first attempt rewrote the file with a regex, which syntax-errored the hook so
it failed open on every command — that produces false kills (every row breaks,
for the wrong reason) and false survivals (the edit silently missed). Editing
the object graph cannot half-apply.

Section 0 below tests this harness before it is trusted, the same way
test/smoke.sh does: an unmutated run must be green, and a deliberately broken
rule must be caught.
"""
import importlib.util
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "hooks", "permission-floor.py")
TSV = os.path.join(REPO, "test", "fixtures", "permission-policy.tsv")


def load():
    spec = importlib.util.spec_from_file_location("floor", SRC)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def rows():
    out = []
    for n, raw in enumerate(open(TSV, encoding="utf-8"), 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        expect, rule, command = line.split("\t")
        out.append((n, expect, rule, command.replace("\\t", "\t").replace("\\n", "\n")))
    return out


def red_rows(mod, table):
    """Line numbers whose verdict or rule disagrees with the table."""
    bad = []
    for n, expect, rule, command in table:
        verdict = mod.evaluate(command)
        got, got_rule = ("allow", "-") if verdict is None else ("deny", verdict[0])
        if got != expect or (expect == "deny" and got_rule != rule):
            bad.append(n)
    return bad


def mutate(mod, rule):
    if rule == "SHAPE":
        mod.COMPOUND_OPERATORS = ()
    else:
        mod.FLOOR = [r for r in mod.FLOOR if r[0] != rule]


table = rows()

print("== 0. the mutation harness tests itself ==")
base = load()
clean = red_rows(base, table)
if clean:
    print("  FAIL an UNMUTATED run is already red at lines %s" % clean)
    sys.exit(2)
print("  ok   an unmutated run is green, so a red run means the mutation")
control = load()
mutate(control, "FORKBOMB")
if not red_rows(control, table):
    print("  FAIL removing a rule with a fixture did not redden anything")
    sys.exit(2)
print("  ok   removing a known-covered rule really does redden the table")

print("\n== 1. one rule at a time ==")
killed = survived = misattributed = 0
for rule in load().RULES:
    mod = load()
    mutate(mod, rule)
    red = set(red_rows(mod, table))
    owned = {n for n, expect, r, _ in table if expect == "deny" and r == rule}
    if not red:
        print("  SURVIVED  %-14s the suite stayed green without it" % rule)
        survived += 1
    elif red != owned:
        print(
            "  MISATTRIB %-14s red=%s but this rule owns %s"
            % (rule, sorted(red), sorted(owned))
        )
        misattributed += 1
    else:
        print("  killed    %-14s %d rows, all of them its own" % (rule, len(red)))
        killed += 1

print("\nkilled=%d survived=%d misattributed=%d" % (killed, survived, misattributed))
sys.exit(0 if survived == 0 and misattributed == 0 else 1)
