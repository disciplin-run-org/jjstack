# specimen-recovery — a guard must exhibit text it matches

The companion to DERIVE, DON'T ENUMERATE in `test/smoke.sh`'s header. That
rule says derive the *set* you check from a source of truth. This one says
derive the *specimen* too.

## The defect

> The assertion's subject is text that some other artifact produces, and the
> pattern was written from the author's memory of that text instead of from
> the text.

Six instances across two pull requests (#43 and its follow-up), every one
caught by review rather than by the suite, and every fix authored the same way
as the defect it replaced. Adding a control per instance did not converge,
because each control was written from the same memory as the defect it was
meant to police.

Each row gives the pattern and the text it got wrong, inline. A citation is
useless the moment the commit goes: the #43 branch was deleted on merge, so
none of its shas resolves any more — which is the durability point below,
demonstrated on this very table.

| # | The pattern | What the artifact actually said | How it failed |
|---|---|---|---|
| 1 | `ok  [a-z-]+ \(2\)` | `ok<ESC>[0m  alpha (2)` — `ok()` prints `'  %bok%b  %s'`, so the literal `ok  ` is never there | could not fire |
| 2 | `you are the rolled-over continuation` | the same sentence appears in the QM resume order *above* the step being located, so `head -1` found that one | fired on a **correct** file |
| 3 | `status.*` searched *after* `carried by:` | the pattern label prints `…status([[:space:]]\|$) — carried by: …`, so `status` is before the phrase, never after | could not fire |
| 4 | `tm_send\(.*SESSION-BOUNDARY` | `tm_send(worker="<name>",` ⏎ `    message="SESSION-BOUNDARY …` — the call wraps (fixture: `test/fixtures/guard-tm-send-boundary.md`) | could not fire |
| 4b | `tm_send\([^)]*SESSION-BOUNDARY` — the repair | `[^)]*` cannot cross a `)`, so a nested call or a parenthetical in the arguments hid the same defect; and it fired on prose *forbidding* the call | both, in one pattern |
| 5 | `grep -qF 'since_boundary=True'` | the file still contained that string, inside the sentence saying never to use it | fired on prose saying the opposite |

Row 4b is the one that matters most, and it is not another instance of the
same mistake. Its specimen was recovered correctly. It is the second half of
the rule, below.

## The rule

**Derive the specimen from the artifact, and the pattern from the
mechanism.**

Two halves, and the first alone is not enough.

**The specimen must be derived from the artifact, never authored from the
pattern.** Recovered-versus-constructed is a proxy for that: recovery
guarantees derivation automatically, which is why it is the default, but a
constructed specimen can satisfy the rule too.

**The pattern must key on the mechanism, not on one spelling of it.** Row 4b
above recovered its specimen correctly and still encoded one spelling —
arguments containing no parenthesis — because the pattern was derived from
that one specimen. A single-specimen control cannot see this: it certifies the
guard against the spelling it was built from. Ask what the code *does* that the
lawful version does not. A delivering call takes `message=`; the marker tool
takes `reason=`. Keying on the argument catches every spelling and stays silent
on prose that merely names the call:

```bash
grep -qE 'message[[:space:]]*=[[:space:]]*"SESSION-BOUNDARY'   # what it does
tm_send\([^)]*SESSION-BOUNDARY                                 # how it looks
```

Where you cannot key on a mechanism, use a **battery** rather than one
specimen: the same defect in every spelling the codebase actually uses.

### Guarding a file's content

The specimen is the blob at the commit where the defect lived.

```bash
git show <sha>:<path> > specimen
grep -qE "$PATTERN" specimen || echo "the guard is decorative"
```

If the pattern does not fire on the historical blob, you have written a
sentence, not a test. In this repo the specimen is nearly always available,
because a guard usually exists to stop the recurrence of something removed in
the same change: **the defect is sitting in your own history.**

### Guarding a program's output

The specimen is that program run with the defect restored.

Copy the directories the program reads, **never the repository root**. A
worktree's `.git` is a pointer file, so a copy of the root shares the ORIGINAL
index: the copy reports its own toplevel and the original's git dir, and a
git-invoking mutation writes to the real repository. `test/smoke.sh` says the
same thing about `cp -a`, and `cp -r` has the identical hazard.

```bash
d=$(mktemp -d)
cp -r "$REPO/bin" "$REPO/skills" "$REPO/references" "$REPO/hooks" "$d/"
sed -i 's|^RSLOT=|#RSLOT=|' "$d/hooks/shared-memory.sh"   # restore the defect
bash "$d/bin/jjstack-verify-skills" | grep -q 'FAIL.*RSLOT' || echo "the guard is decorative"
```

That is a real mutation from this suite, not a placeholder: it disables the
plain-session handover carrier, which check 8's hook row used to report as
present anyway.

**Anchor on the FAILURE, not on the row name.** An earlier version of this very
example ended `grep -q RSLOT`, and the healthy output contains the row name:

```
  ok  RSLOT=.*jjstack-rollover-slot [hooks/shared-memory.sh] — carried by: …
```

So it matched whether the guard fired or not — the defect this document
teaches, in the document's own demonstration of how to avoid it. Measured:
`grep RSLOT` matches both trees, `grep 'FAIL.*RSLOT'` matches only the mutated
one, and so does the exit code. **The test of a specimen is itself a guard, and
gets no exemption from step 4.**

### Guarding a structural invariant

Some properties have never been violated, so there is nothing to recover, and
demanding recovery is cargo cult. Construct the specimen out of real material
instead: take a real artifact and place it in the state the invariant forbids.

```bash
cp "$ADRD/AR-7.md" "$FIX/AR-99.md"   # a real record under a wrong filename
```

The mismatch comes out of the structure. Nothing was typed to match the
pattern. Contrast the version that fails the rule: a heredoc writing
`id: AR-99` into a file named `AR-7.md` proves only that your pattern matches
text you wrote to match your pattern.

**Say what a reader can check.** "This specimen is constructed" tells them
nothing. "The specimen is AR-7 itself under a wrong filename, so the mismatch
is structural" is a claim they can verify.

## The rule has three surfaces, not one

**Assertions.** The pattern must fire on the specimen.

**Controls.** The control must fire on the specimen and stay silent on the
shipped tree. Both directions, or a control that always fires is
indistinguishable from a guard that works.

**Mutants.** An invented mutant proves nothing about a guard, exactly as an
invented specimen proves nothing about a pattern — and it is the more
dangerous of the two. A false positive from a bad specimen reads as "my
pattern is too loose". A false *negative* from a bad mutant reads as "the
guard is broken", and invites someone to rewrite a guard that was fine.

Field instance: while mutation-testing the duplicate-title guard on PR #43,
the reviewer retyped a decision title from a listing truncated at 72 columns.
The titles differed, the guard correctly stayed silent, and the run read
`ALL 618 PASS`. They were one step from reporting a working guard as dead.
Taking the title verbatim out of the file gave `1 FAIL, 617 pass`, naming
that assertion alone.

**Reset between mutants.** A staged rename leaking through `git checkout -- .`
contaminated three results in that same session. `git reset --hard` to a known
commit between mutants, or mutate a copy and throw it away.

## Durability: a recovered specimen outlives its commit only if you make it

CI is a shallow clone. `actions/checkout` fetches depth 1 by default, so
`git show <old-sha>:<path>` finds nothing there and a run-time recovery fails
— loudly, which is the right direction, but a control that works only on a
full clone is not a control.

Deepening CI is not the whole fix. A specimen recovered from a commit on a
feature branch dies when that branch is squash-merged: the control goes green
in CI and then breaks on `main` forever, pointing at a sha nobody can look up.

**So freeze the specimen as a fixture**, extracted from the artifact at the
time you write the guard, carrying the command that re-derives it while the
history still exists:

```
test/fixtures/adr-duplicated-titles.txt   # the two identical titles 7836454 had
test/fixtures/adr-drifted-last-id.txt     # the counter as shipped at 68cac1e
```

That is still derivation. Nothing was authored to match a pattern; the
extraction simply happened once instead of on every run.
`test/fixtures/permission-policy.tsv` makes the same argument for the same
reason.

## Why this is worth the trouble

A guard that cannot fire does not merely fail to catch a future regression.
**It hides what is already wrong.** The moment row 4's guard was repaired it
found a live defect nobody had noticed: `/save-and-clear`'s prose was teaching
the droppable `since_boundary` form that the same change had just documented as
unsafe. The guard had been sitting over that text, green, since the day it was
written.

## Checklist

Before a guard lands:

1. Name the artifact whose text the pattern reads.
2. Get a specimen out of that artifact — a historical blob, the program with
   the defect restored, or a real artifact placed in the forbidden state.
3. Run the pattern at the specimen. It must fire.
4. Run it at the shipped tree, and know which polarity you have. A guard
   asserting a mechanism is ABSENT must stay silent there; a guard asserting
   one is PRESENT must fire. Getting this backwards is failure mode 2 in the
   table — a guard that fires on a correct file — and it is the reason step 3
   alone is not enough.
5. If the specimen came from git, freeze it as a fixture with its provenance.
6. If you built a mutant, take its text out of the file, never out of a
   listing or your memory of one.
