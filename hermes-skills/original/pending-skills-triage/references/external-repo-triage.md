# External Skill Repo Triage — Reference

Methodology for evaluating skills from an external GitHub repo (e.g. jjstack, gstack, community repos)
against the existing Hermes library, as applied in the jjstack/disciplin-run-org evaluation session.

## Discovery Step

Use the GitHub API to enumerate all skill directories in one fast call — far faster than browser navigation:

```bash
curl -s 'https://api.github.com/repos/<owner>/<repo>/contents/skills' \
  | python3 -c "import json,sys; data=json.load(sys.stdin); [print(d['name']) for d in data if d['type']=='dir']"
```

Then bulk-fetch descriptions from raw content:

```bash
for skill in skill1 skill2 skill3; do
  echo "=== $skill ==="
  curl -sf "https://raw.githubusercontent.com/<owner>/<repo>/main/skills/$skill/SKILL.md" | head -30
done
```

## Four-Bucket Classification

**SKIP — already covered:**
The skill's trigger class is already served by an existing Hermes skill. Map by trigger, not by name:
- Same workflow, different name → skip
- Adds marginal depth to existing skill → consider a patch to the existing skill instead

**SKIP — infra mismatch:**
The skill assumes external binaries, daemons, or conventions that don't exist here:
- Wraps a CLI not installed (gstack, agy, opencode, tubemail, quartermaster)
- References paths/conventions specific to the source repo's ecosystem
- Multi-agent orchestration patterns (tubemail workers, QM resume orders) alien to Hermes

**CANDIDATE — standalone, no infra deps:**
The skill works with tools already available, covers a trigger class Hermes lacks,
and its steps are self-contained. These are worth importing.

**DEFER — interesting but needs adaptation:**
The skill's concept is valid but the implementation is too tightly coupled to the source
ecosystem. Note what needs adapting and revisit when the work is worth it.

## Classification Signals

| Signal | Bucket |
|--------|--------|
| Skill body mentions specific CLI names not in Hermes (`gstack`, `agy`, `tubemail`) | infra mismatch |
| Skill is labeled "jjstack wrapper around gstack's X" | infra mismatch |
| Skill describes a decision framework or mental model (Kano, council, lean mode) | standalone candidate |
| Skill describes a template/protocol (work-order shape, verification gate) | standalone candidate |
| Hermes already has a skill in the same trigger class | already covered |
| Skill requires other skills in the same external repo to be installed first | infra mismatch or defer |

## jjstack-Specific Notes (2025-07 evaluation)

jjstack is a wrapper distribution around `gstack`. The majority of its skills fall into two categories:

1. **gstack wrappers** — wrap gstack commands with output-to-repo, quality loop, and DNA injection.
   All require gstack installed. None are portable to Hermes as-is.
   Pattern: description starts with "Enhanced X — saves to repo, injects DNA. jjstack wrapper around gstack's X."

2. **Multi-agent infra skills** — use tubemail (TM), quartermaster (QM), reconnect_mcp, etc.
   These are jjstack's proprietary worker orchestration layer. Skip entirely.

**Standalone candidates from jjstack (no infra deps):**
- `council` — multi-perspective council (CEO/architect/security/PM) with cross-examination + mandatory counterfactual pass
- `kano-model` — 10-level Extended Kano Model for feature prioritization / QA depth
- `lean` — cost-lean mode: explicit tool-call budget, minimum-turn rules, no speculative refactoring
- `work-order` — Context/Deliverables/Verify/Done delegation template
- `groom` — skill/memory grooming via vector-cluster + human-review cycle (needs path adaptation)
- `council` — structured multi-voice deliberation, works standalone
- `product-manager-review` — adversarial PM review (4P:90, OKR, JTBD, Kano)
- `verify-before-done` — pre-completion gate (tests, linters, health endpoints)
- `two-stage-review` — spec-correctness then code-quality as two separate passes
- `receiving-code-review` — being on the receiving end of a review: triage, agree/disagree/pushback
- `plan-edit` — surgical plan editing without re-reading the whole plan
- `state-doc` — live STATE.md per working directory for in-flight tracking
