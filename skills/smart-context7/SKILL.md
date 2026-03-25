---
name: smart-context7
description: >
  Automatically invokes Context7 MCP tools to fetch up-to-date library documentation
  ONLY when it would genuinely help — avoiding wasted API calls on stable/basic topics.
  Triggers when working with third-party libraries, frameworks, or APIs where version-specific
  accuracy matters. Use when: coding with external libraries, debugging version-specific issues,
  setting up new dependencies, upgrading packages, or when unsure about current API surface.
  Do NOT trigger for: language fundamentals, algorithms, general architecture, own-code debugging,
  or libraries already documented in the current session context.
disable-model-invocation: false
---

# Smart Context7 — Intelligent Documentation Fetching

## Purpose

Conserve Context7 free-tier API calls (1,000/month) by invoking documentation
lookups only when they provide clear value over training knowledge.

## Graceful Failure

Before invoking any Context7 MCP tools, check if they are available. If the
`resolve-library-id` or `get-library-docs` tools are not available (MCP server
not configured or not responding):

1. **Do not error out.** Continue with the task using training knowledge.
2. **Inform the user once per session:** "Context7 is not configured — using training
   knowledge instead. To enable live documentation lookups, run `/github-setup` or add
   Context7 to your `.mcp.json`:"
   ```json
   {
     "context7": {
       "command": "npx",
       "args": ["-y", "@upstash/context7-mcp"]
     }
   }
   ```
3. **Do not repeat the warning.** After the first notice, silently fall back to training
   knowledge for the rest of the session.

## Decision Framework

Before ANY library-related coding task, evaluate whether a Context7 lookup is needed.

### INVOKE Context7 when:

1. **Version-sensitive work** — The task depends on API signatures, config options, or
   behaviors that change between major versions (e.g., Next.js 14 vs 15, React 18 vs 19,
   Tailwind v3 vs v4, LangChain, Prisma, tRPC).

2. **Initial setup / configuration** — Installing or configuring a library for the first
   time in a project. Config formats and defaults change frequently.

3. **Unfamiliar or rarely-used APIs** — Working with library features not commonly used,
   where training data is sparse or likely outdated.

4. **Debugging version mismatch errors** — Error messages suggesting a wrong API call,
   missing export, or deprecated feature.

5. **Dependency upgrades** — Migrating to a new major version where breaking changes exist.

6. **Fast-moving libraries** — Any library known to ship breaking changes frequently:
   Next.js, SvelteKit, Astro, LangChain, Bun, Deno, effect-ts, drizzle-orm, etc.

### DO NOT invoke Context7 when:

1. **Language fundamentals** — Core JavaScript/TypeScript/Python/Rust syntax, data
   structures, algorithms, control flow. These do not change.

2. **Stable, mature APIs** — Libraries with long-stable surfaces: lodash, Express basics,
   jQuery, moment.js, standard SQL syntax.

3. **Already fetched this session** — If documentation for the same library+topic was
   already retrieved earlier in this conversation, reuse that context. Do not re-fetch.

4. **Own-code debugging** — Logic errors in the user's own code that don't involve
   misunderstanding a library API.

5. **General architecture / design patterns** — Questions about MVC, SOLID, microservices,
   etc. are not library-specific.

6. **Simple, well-known operations** — e.g., `npm install`, `git commit`, `pip install`.
   No docs needed.

7. **Reading/reviewing code** — Just understanding existing code does not require fresh docs
   unless a specific API call is ambiguous.

## Invocation Protocol

When a Context7 lookup IS warranted, follow this exact sequence:

### Step 1: Resolve the library ID

Call the `resolve-library-id` MCP tool:
- `libraryName`: The library name (e.g., "next.js", "prisma", "langchain")
- `query`: The specific question or task context

Pick the most relevant result from the returned list.

If the tool call fails or is unavailable, fall back to training knowledge per the
Graceful Failure section above.

### Step 2: Fetch targeted documentation

Call the `get-library-docs` MCP tool:
- `libraryId`: The ID from Step 1 (e.g., `/vercel/next.js`)
- `query`: A focused query describing exactly what information is needed
- Keep the query specific to minimize token usage and maximize relevance
- Use `topic` filter if available and applicable

### Step 3: Apply and cite

- Use the fetched documentation to inform the response
- Briefly note which library version the docs correspond to
- Do not dump raw docs — synthesize into actionable guidance

## Call Conservation Tactics

- **Batch related lookups**: If working with multiple aspects of the same library,
  craft one broad query rather than multiple narrow ones.
- **Cache mentally**: After fetching docs for a library, remember the key details
  for the rest of the session. Do not re-fetch for follow-up questions on the same topic.
- **Prefer specificity**: "Next.js App Router middleware configuration" is better than
  "Next.js docs" — it returns more relevant results in fewer tokens.
- **Skip the obvious**: If 90%+ confident in the answer from training data and the
  library hasn't had a major release recently, skip the lookup.

## Transparency

When making the decision, briefly note it:
- If invoking: "Let me grab the current docs for [library] since [reason]."
- If skipping: No announcement needed — just proceed with the answer.

## Budget Awareness

At ~1,000 calls/month on the free tier:
- ~33 calls/day if spread evenly
- Each resolve + fetch = 2 API calls
- Target: ~15 documentation lookups per day maximum
- Prioritize lookups that prevent real errors over nice-to-have confirmations
