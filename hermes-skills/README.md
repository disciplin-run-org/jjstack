# hermes-skills — skills written by the Hermes agent

Captured 2026-07-26 from the `hermes-rh` VM, where the Hermes agent (Nous
Research) had been given the full jjstack suite via `guest/steps/65-jjstack.sh`
in the [Hermes repo][hermes], then spent several weeks writing skills of its
own. They existed on that one disk; a VM rebuild would have lost all of them.

Two kinds, kept apart because they are useful for different reasons:

- **[`ports/`](#ports)** — twelve jjstack skills, rewritten for Hermes
- **[`original/`](#original)** — eight skills with no jjstack counterpart (two withheld)

[hermes]: https://github.com/JesperJurcenoks/hermes-rh

---

## ports/

Not copies. Every one differs substantially from its `skills/` counterpart:

| Skill | jjstack | Hermes | What changed |
|---|--:|--:|---|
| `groom` | 482 | 71 | dropped gbrain vector-clustering, cross-project promotion, the graduation ladder |
| `product-manager-review` | 517 | 134 | dropped the LeanSpecs-MCP cleanup half; kept the review framework |
| `python-coder` | 373 | 306 | Hermes tool names; dropped Claude-Code-specific tooling hooks |
| `receiving-code-review` | 253 | 182 | dropped the PR-plumbing assumptions |
| `two-stage-review` | 210 | 173 | condensed |
| `verify-before-done` | 198 | 131 | condensed |
| `save-and-exit` | 188 | 179 | rewritten onto Hermes' memory tool |
| `save-and-clear` | 169 | 181 | rewritten onto Hermes' memory tool — **grew** |
| `council` | 154 | 114 | condensed |
| `work-order` | 141 | 120 | condensed |
| `lean` | 131 | 107 | condensed |
| `kano-model` | 25 | 58 | **expanded** — the fullest of the twelve |

### The pattern

jjstack skills assume Claude Code plus the disciplin-run stack: tubemail
workers, Quartermaster work orders, gbrain vector recall, gstack wrappers,
`/heal`. Hermes has none of that. The ports strip that machinery and rewrite
against Hermes' own primitives — its memory tool, its skills store, its
gateway — with no worker/orchestrator layer to talk to.

`save-and-clear` shows it most clearly. jjstack's version spends most of its
length on the tubemail identity dance: resolve `$TM_WORKER_NAME`, file a QM
resume order to yourself, signal a fresh restart through the manager. The
Hermes port drops all of it and does the thing that actually survives a context
wipe — write to memory, report what was kept versus dropped, hand the `/clear`
back to the user. It came out *longer*, because what remained got said properly.

The two that grew are the interesting ones. `kano-model` more than doubled: on
Claude Code it is a 25-line pointer into the framework, and the Hermes agent
wrote out the model itself rather than assume the reader could go fetch it.

---

## original/

No jjstack counterpart. Roughly half are hard-won operational knowledge — the
kind that gets rediscovered expensively if it is lost.

| Skill | What it knows |
|---|---|
| `google-oauth-local-listener` | Catch the OAuth callback with a localhost listener instead of copy-pasting redirect URLs |
| `google-drive-pdf-ocr` | Read PDF text via Drive's own OCR — no download, no pymupdf |
| `signal-gateway` | Install signal-cli, link a device, run the daemon, point Hermes at it |
| `hermes-config` | Skins, colours, display overrides, UI troubleshooting |
| `llm-cascade-classifier` | Cheap-model-first classification, escalating grey cases upward |
| `always-on-agents` | Push-driven daemons (IMAP IDLE, watchers) rather than polling; monitor→live rollout |
| `pending-skills-triage` | Accept / Probation / Reject triage of the skills queue, bulk-applied |
| `web-status-monitor` | Periodic checks of a public page, alerting through cron + a messaging gateway |

Two of these came out of real incidents rather than design.
`google-oauth-local-listener` exists because that OAuth flow was fought through
by hand; `llm-cascade-classifier` is the pattern extracted from an email
classifier that had to work against a real inbox.

### Two were withheld

Hermes writes its memories as skills, which is much of its power — and it means
some of what it wrote is knowledge about **one machine**, not a technique anyone
can use. Reviewed skill by skill before publishing, two were held back:

| Withheld | Why |
|---|---|
| `google-workspace-pitfalls` | Describes itself as "environment-specific fixes … on this machine": `/vault/` paths, a Chrome process "confirmed via `ps aux`". Accurate about the box it was written on, actively misleading anywhere else. |
| `hermes-security-hardening` | Built around a section titled "Architecture of This Install". The hook patterns generalise; an inventory of what is installed where does not. |

Both remain on the machine that wrote them. If the general parts are worth
extracting later, that is a rewrite, not a copy — which is exactly the
distinction this directory is trying to hold.

The rest were sanitised on the way in: a linked phone number, a named individual
beside a sensitive agreement, one organisation's registry record and trainer
database. Techniques kept, identities removed. `test/smoke.sh` enforces it.

### Deliberately not captured here

- **Radical-Honesty-specific skills** (`rhi-environment`,
  `colorado-sos-registration-check`, `compliance-monitoring`, `sender-vetting`,
  `pr-outreach-vetting`, `osint-investigation`, `email-agent-imap`) stay on the
  VM. They encode one organisation's particulars and belong with it, not in a
  general toolkit.
- **`hermes-install-rules`** describes one install's own permission
  architecture, so it is maintained in the Hermes repo (`guest/skills/`) where
  it can stay in step with the scripts that create those rules. A copy here
  would drift and quietly start lying.

---

## Status

Reference material. Nothing in jjstack's `setup` reads this directory — these
are here so the work survives, and so the next Hermes install can start from
them rather than rediscover them.

Worth reading before editing the `skills/` originals: where a port is markedly
shorter, it is usually because the original had accreted stack-specific
scaffolding that the idea underneath did not need.
