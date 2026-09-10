# specimen-recovery — a guard must exhibit text it matches

The companion to DERIVE, DON'T ENUMERATE in `test/smoke.sh`'s header. That
rule says derive the *set* you check from a source of truth. This one says
derive the *specimen* too.

## The defect

> The assertion's subject is text that some other artifact produces, and the
> pattern was written from the author's memory of that text instead of from
> the text.

Five instances shipped in a single pull request (#43), each caught by review
rather than by the suite, and each fix authored the same way as the defect:

| # | The guard | Why it could not fire |
|---|---|---|
| 1 | two negatives anchored on `ok  ` in the verifier's output | the label is colored, so the literal `ok  ` never appears |
| 2 | the boundary-ordering guard anchored on a sentence | the same sentence appears in the QM resume order, so it read the wrong step |
| 3 | "reports what it MEASURED", anchored on `status` after `carried by:` | `status` is part of the label, which prints *before* that phrase |
| 4 | `tm_send\(.*SESSION-BOUNDARY` | the call it guards wraps across two lines |
| 5 | `grep -qF 'since_boundary=True'` | the file contains that string inside a sentence saying never to use it |

Adding a control per instance did not converge, because each control was
written from the same memory as the defect it was meant to police.

## The rule

**The specimen must be derived from the artifact, never authored from the
pattern.**

That is the axis that matters. Recovered-versus-constructed is a proxy for
it: recovery guarantees derivation automatically, which is why it is the
default, but a constructed specimen can satisfy the rule too.

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

```bash
cp -r "$TREE" mutant && patch-the-defect-back-into mutant
run mutant | grep -qE "$PATTERN" || echo "the guard is decorative"
```

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

## Checklist

Before a guard lands:

1. Name the artifact whose text the pattern reads.
2. Get a specimen out of that artifact — a historical blob, the program with
   the defect restored, or a real artifact placed in the forbidden state.
3. Run the pattern at the specimen. It must fire.
4. Run it at the shipped tree. It must not.
5. If the specimen came from git, freeze it as a fixture with its provenance.
6. If you built a mutant, take its text out of the file, never out of a
   listing or your memory of one.
