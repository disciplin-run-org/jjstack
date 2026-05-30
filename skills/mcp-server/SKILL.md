---
name: mcp-server
description: >
  Use this skill when creating, modifying, or dockerizing an MCP server. Trigger on any
  request involving MCP server setup, MCP transport configuration (streamable HTTP),
  MCP Dockerfiles, or docker-compose services for MCP servers. Also trigger when adding new
  tools to an existing MCP server. Do NOT trigger for MCP client configuration or general
  Docker work unrelated to MCP.
---

# MCP Server in Docker — Blueprint

## Step 0: Pick the server's category (mandatory)

Before touching code, classify the server. The ecosystem standard at `ai-agents/jjstack/20260428-mcp-server-categories.md` defines exactly three categories — pick one before writing any tool. The shared library refuses to boot a server that violates its declared category.

| Category | When to pick | Factory |
|---|---|---|
| `multi_repo` | Server holds per-repo state; each call operates on one named repo | `shared.mcp.app_factory.create_multi_repo_app(...)` |
| `repo_agnostic` | No repo concept; transport, auth, or external-system integration | `shared.mcp.app_factory.create_repo_agnostic_app(...)` |
| `pan_repo` | Global state across all repos; `repo` only as a query filter | `shared.mcp.app_factory.create_pan_repo_app(...)` |

Decision tree:

```
Q1: Does my server hold state about specific user products / projects?
    │
    ├── No → Q2: Does it need to know which repo something belongs to?
    │              │
    │              ├── No  → repo_agnostic
    │              └── Yes → continue to Q3
    │
    └── Yes → Q3: Per-repo state (one product.json per repo) or one global?
                  │
                  ├── per-repo → multi_repo
                  └── global   → pan_repo (also pick pan_repo_writes)
```

Once classified, use the matching factory. Read the standard for the full contract — it specifies exactly which parameters are required, forbidden, or filter-only on each category's tool schemas. Boot-time validation enforces this.

---

## Transport: Streamable HTTP via FastMCP

All MCP servers run as Docker containers with `network_mode: host` and communicate
via **streamable HTTP** on a single `/mcp` endpoint. FastMCP handles session
management, schema generation, and protocol details automatically.

### TLS policy

- **Localhost (development):** plain HTTP. No certs, no openssl, no
  browser warning click-throughs. Self-signed certs add zero security
  on a loopback interface — traffic never leaves the host, and a
  self-signed cert isn't trusted anyway. Skipping TLS removes friction
  with no real security loss.
- **Non-localhost (anything reachable from another machine):** TLS is
  required. Use a real certificate — Let's Encrypt for a public
  hostname, an internal CA for a corporate network, or a reverse
  proxy (Caddy, Traefik, nginx) that terminates TLS in front of the
  MCP server. Do not expose plain HTTP off the loopback.

The server detects TLS material at `/data/server.crt` and
`/data/server.key` at startup — HTTPS if both files exist, HTTP
otherwise. Localhost dev: leave them absent. Production: place real
certs there (or terminate at a reverse proxy and run the MCP server
on HTTP behind it).

Each server gets its own unique port via the `MCP_PORT` environment variable.
There is no default port — you must assign one per service to avoid collisions
when running multiple MCP servers on the same host.

**Port allocation:** Track assigned ports in your docker-compose file. Each new
service gets the next available port. Example:
- leanspecs: 8001
- google-workspace-mcp: 8002
- dayplan: 8003

---

## Mandatory Requirements

Non-negotiable for every MCP server scaffolded by this skill.

### Source code is bind-mounted in dev mode

The container's source path is overridable via a docker-compose volume
mount so code changes take effect on save without an image rebuild.
Required artifacts for every MCP server:

1. A `docker-compose.override.yml` at the project root that mounts the
   source directory over the installed-package path inside the
   container.
2. The override entrypoint runs uvicorn with `--reload --reload-dir`
   pointing at the same path as the mount target.
3. The Dockerfile installs the package at a canonical location so the
   mount target is predictable — either `/app/src/<package>` for
   editable installs (`pip install -e .`) or
   `/usr/local/lib/python<ver>/site-packages/<package>` for
   non-editable installs (`pip install .`).

Without this, the dev loop is "edit → rebuild image → restart
container" (~30s per cycle) instead of "edit → uvicorn auto-reload"
(~1s). Compounded across a dev session, that's hours of pure friction
for zero benefit. Every existing MCP server in the canonical reference
ecosystem uses this pattern.

The Dockerfile does not change between dev and prod — dev mode is
purely a compose-level concern. Prod is selected with
`docker compose -f docker-compose.yml up` (skips the override).

See "Dev Mode — Live Reload" below for the concrete YAML and a
table of dev/prod/rebuild commands.

<HARD-GATE>
Do NOT mark an MCP server scaffold complete until BOTH conditions
hold: a docker-compose.override.yml exists with the bind mount AND
the bind mount has been verified end to end by editing a source
file and observing the uvicorn reload line in the container logs.
A scaffold without working live-reload is the single most expensive
trap this skill prevents and is unacceptable as a deliverable. This
applies to EVERY MCP server scaffolded with this skill regardless of
perceived size or one-off-ness. See
references/hard-gate-convention.md for the semantics of this tag.
</HARD-GATE>

### Frontend dist is bind-mounted in dev mode (servers with a SPA)

Every MCP server that ships a React/Vue/etc. SPA must also overlay
the built `frontend/dist` directory over the container's static path
in the same `docker-compose.override.yml`. Without this, Python
hot-reloads via uvicorn but the SPA is frozen at whatever the image
was last built with — "edit → npm run build → docker compose build
→ docker compose up" (~30-60s) instead of "edit → npm run build"
(~1s, container picks up the new bundle on next request because the
mount is live).

Required artifacts for every MCP server with a SPA:

1. The override mounts the host-side `<service>/frontend/dist`
   directory over the container's static directory read-only:
   `- ./<service>/frontend/dist:/app/static:ro`
   (path-target may differ — match whatever the Dockerfile's `COPY
   --from=frontend ... /app/static` line wrote to; e.g. tubemail
   uses `/app/frontend/dist`).
2. The host-side `<service>/frontend/dist` must exist before the
   container starts. If it does not, Docker silently creates an empty
   directory and the SPA returns 404 or a blank index. Build once
   on first checkout: `npm install --prefix <service>/frontend &&
   npm --prefix <service>/frontend run build`.
3. `<service>/frontend/dist/` belongs in `.gitignore` — it is a
   per-developer build artifact, not source.

The dev loop for SPA changes becomes:

```
# Edit .tsx/.ts/.css
npm --prefix <service>/frontend run build   # ~1s
# Refresh the browser — new bundle is live, no container restart.
```

The image is still production-self-contained: the Dockerfile's
`COPY --from=frontend /build/dist /app/static` continues to bake the
SPA into the image so `docker compose -f docker-compose.yml up`
(prod, no override) ships a working SPA without any host build.

<HARD-GATE>
Do NOT mark an MCP server scaffold complete if the server has a SPA
and the `frontend/dist` overlay is missing from
`docker-compose.override.yml`. A SPA-bearing server without the dist
overlay is a guaranteed dev-loop trap: every frontend tweak forces a
30-60s container rebuild, the AI assistant ends up looking at stale
SPA code while it iterates, and the resulting "why doesn't my change
show up" wastes hours per week. This applies to EVERY SPA-bearing MCP
server regardless of perceived rebuild frequency.
</HARD-GATE>

---

## Server Structure

Use **FastMCP** for all MCP servers.

### Minimal server.py

```python
"""<Service Name> MCP server entry point.

Exposes tools via the Model Context Protocol over streamable HTTP.
"""

# Standard Libraries
import os

# 3rd party
from fastmcp import FastMCP

# Local
from <package>.tools import <module>

SERVER_NAME = "<server-name>"
SERVER_INSTRUCTIONS = """\
<Service Name>: <one-line description of what the server does>.

Recommended workflow:
1. <typical first step>
2. <typical second step>
3. <typical third step>

Call get_instructions() to re-read these instructions at any time.
"""

mcp = FastMCP(SERVER_NAME, instructions=SERVER_INSTRUCTIONS)


######################################################################
# Tools
######################################################################

# Import and register tools from tool modules
<module>.register_tools(mcp)


######################################################################
# FastAPI App
######################################################################


def create_app():
    """Create FastAPI app with MCP mounted at /mcp."""
    from fastapi import FastAPI
    from fastapi.responses import HTMLResponse
    from pathlib import Path

    port = os.environ.get("MCP_PORT")
    if not port:
        raise RuntimeError("MCP_PORT environment variable is required")
    # end if

    mcp_app = mcp.http_app(path="/")

    app = FastAPI(title=SERVER_NAME, lifespan=mcp_app.lifespan)
    app.mount("/mcp", mcp_app)

    # Read version from VERSION file (baked into Docker image)
    _version = "dev"
    for vpath in [Path("/app/VERSION"), Path(__file__).parents[2] / "VERSION"]:
        if vpath.exists():
            _version = vpath.read_text().strip()
            break

    @app.get("/health")
    async def health():
        """Health check for Docker, load balancers, and monitoring."""
        return {"status": "ok", "service": SERVER_NAME, "version": _version}
    # end def

    @app.get("/", response_class=HTMLResponse)
    async def root():
        """Landing page with MCP connection instructions."""
        return f"""
        <h1>{SERVER_NAME}</h1>
        <p>MCP endpoint: <code>/mcp</code></p>
        <pre>{{"mcpServers": {{"{SERVER_NAME}": {{"type": "http", "url": "http://localhost:{port}/mcp"}}}}}}</pre>
        """
    # end def

    return app


######################################################################
# Main
######################################################################


def main() -> None:
    """Run the MCP server over streamable HTTP(S).

    Serves HTTPS if /data/server.crt and /data/server.key exist,
    otherwise falls back to HTTP.
    """
    import uvicorn
    from pathlib import Path

    host = os.environ.get("MCP_HOST", "0.0.0.0")
    port = int(os.environ["MCP_PORT"])
    app = create_app()

    ssl_certfile = Path("/data/server.crt")
    ssl_keyfile = Path("/data/server.key")

    if ssl_certfile.exists() and ssl_keyfile.exists():
        uvicorn.run(
            app,
            host=host,
            port=port,
            ssl_certfile=str(ssl_certfile),
            ssl_keyfile=str(ssl_keyfile),
        )
    else:
        uvicorn.run(app, host=host, port=port)
    # end if
    return


if __name__ == "__main__":
    main()
# end if
```

**Key details:**
- FastMCP handles all session management and schema generation
- `mcp.http_app()` creates the streamable HTTP(S) transport — zero boilerplate
- `mcp_app.lifespan` passed to FastAPI ensures proper session management
- `MCP_PORT` is mandatory — no default, prevents port collisions
- TLS auto-detected from `/data/server.crt` + `/data/server.key` — no config flag needed

**⚠️ Never pass `stateless_http=True` to `http_app()`.**

FastMCP's default is stateful (`stateless_http=False`), which is what you want.
Stateless mode looks attractive ("new transport per request, no session bookkeeping")
but silently breaks two critical features:

1. **`refresh_tools` stops delivering `notifications/tools/list_changed`.** Stateless
   mode rejects `GET /mcp` with 405 — there's no persistent SSE channel for the
   server to push notifications onto. `ctx.send_notification()` queues into a
   dead transport and returns success, but nothing ever reaches the client.
2. **Claude Code can't detect server restarts.** In stateful mode, CC keeps a
   long-lived `GET /mcp` open. When the server dies (e.g., a container rebuild),
   that connection closes, CC notices, and silently re-initializes the session.
   In stateless mode there's no channel to break, so CC keeps sending tool
   calls with a dead session ID until the user manually runs `/mcp`.

Verified in `leanspecs/debug/refresh_test/` — a 4×2 matrix of
`stateless_http × json_response` across the real `register_refresh_tool`
implementation. Only stateful configs deliver notifications. Re-run that
harness after any FastMCP upgrade to catch regressions.

**Session contextvars caveat.** Stateful mode means one MCP session corresponds
to one logical client, living across many HTTP requests. If your server uses
`contextvars.ContextVar` to track per-request state (e.g., the current user
or workspace), make sure the lifecycle matches FastMCP's session boundaries
rather than individual POSTs — otherwise state leaks across tool calls in the
same session. LeanSpecs' `state.py` is the canonical example to study before
writing your own session-scoped state.

**What to serve at `/`:**
- **New/API-only server** (no web UI): use the landing page template above. It shows
  MCP connection instructions so humans who hit the URL know what the service is and
  how to connect an AI client.
- **Server with a web UI**: replace the landing page with your SPA (see "Serving a
  Web UI" section below). The MCP endpoint at `/mcp` works the same either way.

---

## Tool Module Pattern

Each tool module registers tools directly on the FastMCP instance using the
`@mcp.tool` decorator. Type hints and docstrings become the tool's schema and
description automatically.

```python
"""tools/<service>.py — Tool definitions for <service>."""

from fastmcp import FastMCP, Context


def register_tools(mcp: FastMCP) -> None:
    """Register all <service> tools on the MCP server."""

    @mcp.tool
    def <service>_read(item_id: str) -> dict:
        """Read a <service> item by ID."""
        # implementation
        return {"id": item_id, "name": "example"}
    # end def

    @mcp.tool
    def <service>_create(name: str, description: str = "") -> dict:
        """Create a new <service> item."""
        # implementation
        return {"id": "new-id", "name": name}
    # end def

    @mcp.tool
    def <service>_list(limit: int = 50) -> list[dict]:
        """List all <service> items."""
        # implementation
        return []
    # end def

    @mcp.tool
    def get_instructions() -> str:
        """Return server usage instructions, recommended workflows, and best
        practices. Call this to re-read instructions at any time — especially
        after compaction or when unsure how to use the server's tools."""
        from <package>.server import SERVER_INSTRUCTIONS
        return SERVER_INSTRUCTIONS
    # end def

    @mcp.tool
    async def refresh_tools(ctx: Context) -> str:
        """Refresh the tool list in Claude Code. Call this after the server
        has been rebuilt or restarted to pick up new or changed tools.
        Must be called instead of falling back to curl requests."""
        from mcp import types as mcp_types
        await ctx.send_notification(mcp_types.ToolListChangedNotification())
        return "Tool list refreshed. New and changed tools are now available."
    # end def
    # ⚠️ The `ctx: Context` annotation is mandatory on FastMCP 3.x.
    # Without it, FastMCP treats ctx as a required user argument and pydantic
    # rejects every call with "Missing required argument". The tool will look
    # registered but every invocation will fail silently with isError=true.
    # Also: for this notification to reach the client, the server MUST be
    # mounted with stateful transport — see http_app() guidance above.

    return
```

**Key rules:**
- Tool names follow `<service>_<action>` pattern (e.g., `docs_read`, `sheets_update`)
- Type hints on parameters and return values are mandatory — FastMCP generates JSON schema from them
- Docstrings are mandatory — they become the tool description the LLM sees
- One `register_tools(mcp)` function per module, called from `server.py`
- No manual schema definitions, no `get_tools()` / `handle_tool()` boilerplate

---

## Four layers of AI integration

Every MCP server must teach the AI how to use it through three complementary layers:

| Layer | Mechanism | When the AI sees it | Purpose |
|-------|-----------|-------------------|---------|
| **1. Tool docstrings** | `@mcp.tool` docstrings and type hints | Always — included in every tool schema | Per-tool: when to use, argument formats, what to expect back |
| **2. Server instructions** | `FastMCP(name, instructions=...)` | At connection time — injected into context automatically | Server-wide: recommended workflows, domain concepts, tool relationships |
| **3. get_instructions tool** | A tool that returns the instructions string | On demand — AI calls it after compaction or when confused | Recovery: re-read instructions lost to context compaction |
| **4. refresh_tools tool** | A tool that sends `ToolListChangedNotification` | After server rebuild/restart — AI calls it to update cached tool list | Development: pick up new tools without manual `/mcp reconnect` |

**All four are mandatory.** Layer 1 alone is insufficient — the AI needs to understand
workflows and tool relationships, not just individual tools. Layer 2 solves this but
gets lost during context compaction. Layer 3 is the safety net. Layer 4 prevents
the AI from falling back to curl after a server restart.

**Layer 4 has two non-obvious prerequisites** — both must be true or the tool is
a silent no-op:
1. The `ctx` parameter on the `refresh_tools` function must be annotated as
   `ctx: Context` (FastMCP 3.x injection requirement)
2. `mcp.http_app()` must NOT pass `stateless_http=True` (stateful mode is the
   only one with a GET SSE channel that can carry the notification)

Both are covered by following the templates in this skill exactly. If you copy
patterns from older MCP servers, double-check those two things first.

**The instructions content** should include:
- One-line description of what the server does
- Recommended workflow (numbered steps for the most common task)
- Key domain concepts the AI needs to understand
- Relationships between tools ("call X before Y", "use Z to check results of W")
- A reminder that `get_instructions()` and `refresh_tools()` exist

---

## Tool Design Principles

These principles are validated against real production MCP servers (leanspecs, PagerDuty,
Block/Square). They apply to how you design the tools themselves, not the server plumbing.

### Design for outcomes, not operations

Don't mirror REST APIs 1:1. Design tools around what the agent wants to accomplish.
One tool that orchestrates three internal API calls is better than three tools the
agent has to chain.

**Exception:** CRUD tools for domain objects (like `spec_create`, `spec_update`,
`spec_delete`) are necessary when the agent needs granular control. The rule is about
avoiding unnecessary granularity, not banning all simple operations.

### Flatten arguments

Use top-level primitives with sensible defaults. No nested objects.

```python
# Good — flat, with defaults and Literal constraints
@mcp.tool
def search_orders(
    email: str,
    status: Literal["pending", "shipped", "delivered"] = "pending",
    limit: int = 20,
) -> list[dict]:
    """Search orders by customer email. Defaults to pending orders, 20 results."""
```

```python
# Bad — nested object, no defaults, no constraints
@mcp.tool
def search_orders(filters: dict) -> list[dict]:
    """Search orders."""
```

Use `Literal` types to constrain choices — the agent sees valid options directly
in the schema instead of guessing.

### Docstrings are instructions

Every piece of text in a tool definition consumes agent context tokens. Make them count.
Docstrings should specify:
- **When** to use the tool (not just what it does)
- **How** to format arguments (especially IDs, dates, enums)
- **What** to expect back

```python
@mcp.tool
def spec_create(parent_id: str, owner: str, rationale: str) -> str:
    """Add a new item. Create capabilities first (no parent_id), then features
    under them (parent_id='1'), then behaviors under features (parent_id='1.2').
    Requires owner and rationale."""
```

### Return descriptive errors, not exceptions

Agents treat errors as observations and self-correct. Return error strings that
explain what went wrong and what to do instead.

```python
# Good — agent can recover
if item is None:
    return f"Item '{item_id}' not found. Use spec_list() to see available IDs."

# Bad — agent gets a stack trace with no guidance
raise ValueError(f"Not found: {item_id}")
```

### Manage response sizes

Large responses bloat the agent's context window. Guard against this:
- Add `limit` parameters with sensible defaults (20-50 items)
- For file/document reads, add `max_bytes` parameter
- Return pagination metadata: `has_more`, `total_count`
- Prefer summaries over raw data dumps

```python
@mcp.tool
def audit_log(limit: int = 50) -> str:
    """Return recent audit entries. Default 50, max 200."""

@mcp.tool
def docs_read(path: str, max_bytes: int = 60000) -> str:
    """Read a document. Truncates at max_bytes with a note if exceeded."""
```

### Tool count guidance

- **Single-domain servers** (like leanspecs): 20-50 tools is fine. The agent owns
  the entire context and needs the full surface area.
- **Multi-server setups** (agent connects to 5+ servers): keep each server to 5-15
  tools. Total tool descriptions across all servers compete for context tokens.
- **If in doubt:** start with fewer tools. You can always split one tool into two;
  merging two tools into one is harder.

### Long-running tools — one canonical pattern

Claude Code's MCP timeout is 60 seconds and is not reliably configurable.
Any tool that **could occasionally** exceed 30 seconds — even if the
typical case is fast — must use FastMCP's background-task support. The
threshold is tail-latency, not average. A tool that runs in 5s normally
and 45s on the slow path qualifies.

**Definition.** A tool is long-running if it does any of:
- Calls an external AI API (LLMs, embeddings, generation)
- Calls another network service whose latency you don't control
- Processes a dataset whose size scales with input
- Runs batch operations over N items
- Performs file I/O on potentially-large files
- Anything else where you cannot bound the worst case under 30s

When in doubt, treat it as long-running. The cost of using `task=True`
on a tool that always completes in 5s is one extra round-trip; the cost
of NOT using it on a tool that occasionally takes 45s is a hard timeout
the agent cannot recover from.

<HARD-GATE>
Do NOT register a synchronous (`@mcp.tool`, no `task=True`) handler for
any operation that could occasionally exceed 30s — including any
external-AI call, any unbounded loop over input items, and any network
call to a service whose latency is not strictly controlled. Async with
`task=True` is the only correct pattern for these cases. This applies
to EVERY tool regardless of perceived typical-case speed. See
references/hard-gate-convention.md for the semantics of this tag.
</HARD-GATE>

**The one canonical pattern: `@mcp.tool(task=True)`.**

```python
from fastmcp import FastMCP
from fastmcp.dependencies import Progress

mcp = FastMCP("MyServer")

@mcp.tool(task=True)
async def ai_prompt(action: str, scope: str = "all", progress: Progress = Progress()) -> str:
    """Run an AI-powered batch operation.

    Returns a task ID immediately; the client polls for the final result
    via the standard MCP task-status protocol.
    """
    items = await get_items(scope)
    await progress.set_total(len(items))
    results = []
    for item in items:
        await progress.set_message(f"Processing {item.name}")
        result = await process_with_ai(item, action)
        results.append(result)
        await progress.increment()
    return format_results(results)
```

That is it. No manual `start_xxx` / `check_xxx_status` pair, no custom
job table, no hand-rolled polling protocol. The `task=True` decorator
returns a task ID inside the 60s budget, runs the work in the background
via Docket, and exposes the standard MCP task-status interface that
Claude Code already speaks. One pattern, one review heuristic, one
agent-side contract.

**Why this skill no longer documents a "manual start/poll pair":**

- The old justification ("older FastMCP versions") is dead — pyproject
  pins `fastmcp[tasks]>=2.14.0`, which always supports `task=True`.
- The other old justification ("custom job storage") is covered by
  Docket's pluggable backend — keep the same `task=True` surface, swap
  the storage layer underneath.
- Two patterns means every reviewer has to evaluate which is correct
  for the case and every author has to relearn the difference. One
  pattern eliminates that tax.

Existing services on the manual start/poll pair from before this rule
should migrate when next touched. New tools use only `task=True`.

**Backend for task persistence:**
- Default: in-memory (Docket's default — lost on restart, single-process only). Fine for dev.
- Production: Redis/Valkey via `FASTMCP_DOCKET_URL=redis://localhost:6379`. Required for any service that must survive a container restart with jobs in flight.
- Custom storage (postgres, custom DB, etc.): implement a Docket backend; the `task=True` surface stays the same.

### Common mistakes this pattern protects against

1. **Treating `ctx.report_progress()` as a keep-alive.** Claude Code
   silently drops progress notifications — they do not extend the 60s
   timeout. Use `task=True` and let polling drive progress visibility.
2. **In-memory persistence in production.** Default Docket storage is
   in-memory. A container restart loses every in-flight job. Set
   `FASTMCP_DOCKET_URL` for anything that ships.
3. **Polling at 1-second intervals.** Burns your 60s budget on
   overhead. First poll ≥ the tool's `estimated_seconds`, then
   exponential backoff (e.g., 5s → 10s → 20s → 30s).
4. **Faking long-running with whitespace streaming.** Some libraries
   keep a connection alive by streaming spaces. Claude Code does not
   honor that pattern — you will race the 60s timeout regardless.

---

### Security: validate all inputs

Never pass user-supplied input directly to shell commands, database queries, or
file system operations. Validate every parameter against its expected type and range.

```python
@mcp.tool
def docs_read(path: str, max_bytes: int = 60000) -> str:
    """Read a document from the docs directory."""
    # Validate path — prevent directory traversal
    safe_path = Path(path).resolve()
    if not str(safe_path).startswith(str(DOCS_ROOT)):
        return f"Access denied: path must be within {DOCS_ROOT}"
    # end if
```

### Test agent tool selection

Don't just test that tools return correct results. Test that agents **pick the right
tool** for a given scenario. Feed the agent a user question and verify it selects the
expected tool with appropriate arguments. This catches naming and description problems
that unit tests miss.

---

## Serving a Web UI (SPA or static files)

When your server has a frontend (React, Vue, plain HTML), serve it at `/` alongside
MCP at `/mcp`. This is the pattern used by leanspecs — one server, one port, both
AI agents and humans access the same service.

```python
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

# Do NOT pass stateless_http=True here — it silently breaks refresh_tools
# and CC auto-reconnect. See "Never pass stateless_http=True" above.
mcp_app = mcp.http_app(path="/")
app = FastAPI(title=SERVER_NAME, lifespan=mcp_app.lifespan)
app.mount("/mcp", mcp_app)

# Serve React/Vue SPA — html=True makes index.html the fallback for all routes
app.mount("/", StaticFiles(directory="static", html=True), name="static")
```

The `html=True` flag serves `index.html` for any unmatched route — standard SPA
behavior. The `/mcp` mount takes priority since it's registered first.

**When to use which pattern:**

| Situation | What to serve at `/` |
|-----------|---------------------|
| Pure MCP service (no humans use it directly) | Landing page with connection instructions |
| Service with a web UI (leanspecs, dashboards) | SPA via `StaticFiles(html=True)` |
| Service needing OAuth callbacks | Landing page or SPA, plus explicit routes for `/auth/*` |

All three patterns use the same MCP mount at `/mcp` — the only difference is
what humans see when they open the URL in a browser.

### SPA cache headers (prevent stale frontends)

After a container rebuild, users may see the old frontend because the browser
cached `index.html`. Fix this with cache-control middleware:

```python
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi import Request

class NoCacheIndexMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        path = request.url.path
        if path == "/" or path.endswith(".html"):
            # Always revalidate — users get the new frontend after rebuild
            response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        elif "/assets/" in path:
            # Vite hashed filenames — changed code gets a new URL, safe to cache forever
            response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
        return response

app.add_middleware(NoCacheIndexMiddleware)
app.mount("/", StaticFiles(directory="static", html=True), name="static")
```

**Why this works:** `index.html` always revalidates (no-cache), so the browser
fetches the latest after every rebuild. JS/CSS assets under `/assets/` have
content hashes in their filenames (Vite default) — changed code gets a new
filename, unchanged assets are cached forever. Users never need to hard-refresh.

### Adding extra routes (OAuth, webhooks, etc.)

Mount MCP and any explicit routes **before** the SPA catch-all:

```python
app.mount("/mcp", mcp_app)

@app.get("/settings/auth/github")
async def github_auth():
    """OAuth callback — can't go through MCP (browser redirect)."""
    ...

# SPA catch-all last — matches everything else
app.mount("/", StaticFiles(directory="static", html=True), name="static")
```

---

## Dockerfile Pattern

```dockerfile
FROM python:3.12-slim

WORKDIR /app

# Install server dependencies
COPY pyproject.toml ./
RUN pip install --no-cache-dir \
    "fastmcp>=2.0.0" \
    "fastapi>=0.104.0" \
    "uvicorn[standard]>=0.23.0" \
    <additional-deps>

# Copy application source and version
COPY src/ ./src/
COPY VERSION /app/VERSION
RUN pip install --no-cache-dir -e .

# Data volume for credentials / persistent storage
VOLUME ["/data"]

ENV PYTHONUNBUFFERED=1

CMD ["python", "-m", "<package>.server"]
```

Key points:
- `fastmcp>=2.0.0` handles MCP protocol, streamable HTTP, and session management.
- `fastapi` and `uvicorn` for the HTTP server.
- No `EXPOSE` or default port — port is set via `MCP_PORT` in docker-compose.
- Healthcheck added in docker-compose (not Dockerfile, since port is dynamic).

---

## docker-compose.yml Pattern

```yaml
services:
  <service>-mcp:
    build:
      context: .
      dockerfile: <service>-mcp/Dockerfile
    network_mode: host
    volumes:
      - ./data/<service>:/data
    environment:
      - PYTHONUNBUFFERED=1
      - MCP_PORT=<unique-port>
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:<unique-port>/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    dns:
      - 8.8.8.8
      - 8.8.4.4
    restart: unless-stopped
```

**Networking:** `network_mode: host` for all containers — no port mapping needed, the
container binds directly to the host network. `MCP_PORT` is mandatory and must be
unique per service.

**Port allocation:** Each MCP server gets its own port. Track them in docker-compose
and never reuse. No `ports:` mapping needed with host networking.

---

## Dev Mode — Live Reload (required)

This is the concrete implementation of the bind-mount requirement above.
Every MCP server scaffolded with this skill ships with a working
override file out of the gate.

Volume-mount the source code over the installed package and run uvicorn
with `--reload`. Save a file, the server restarts automatically. No
container rebuild needed.

**How it works:** Docker Compose automatically merges `docker-compose.override.yml`
on top of `docker-compose.yml` when you run `docker compose up` with no `-f` flags.
Dev overrides live in the override file and the default workflow is dev mode.

### docker-compose.override.yml

```yaml
# Dev mode: volume-mount source + uvicorn --reload
# Applied automatically by `docker compose up` (no flags needed).
# Skip with: docker compose -f docker-compose.yml up
services:
  <service>-mcp:
    volumes:
      - ./<service>-mcp/src/<package>:/app/src/<package>
      # SPA dist overlay — required for every server that ships a web UI.
      # Without this, frontend edits force a full image rebuild and the AI
      # ends up iterating on stale SPA code. Build dist once on checkout:
      #   npm install --prefix <service>-mcp/frontend
      #   npm --prefix <service>-mcp/frontend run build
      - ./<service>-mcp/frontend/dist:/app/static:ro
    entrypoint: >-
      sh -c "uvicorn <package>.server:create_app --factory
      --host 0.0.0.0 --port $${MCP_PORT}
      --reload --reload-dir /app/src/<package>"
```

### Running dev vs prod

| Mode | Command | What happens |
|------|---------|-------------|
| **Dev** (default) | `docker compose up` | Override auto-applied: source mounted, `--reload` active |
| **Prod** | `docker compose -f docker-compose.yml up` | Override skipped: baked image, no mounts |
| **Rebuild** | `docker compose up --build` | Rebuild image, then run in dev mode |

### Key details

- **Volume mount target** must match where the Dockerfile puts the source. The
  skill template uses `COPY src/ ./src/` with `pip install -e .`, so the target
  is `/app/src/<package>`. If your Dockerfile installs to site-packages instead,
  mount to `/usr/local/lib/python3.12/site-packages/<package>`.

- **`--reload-dir`** must point to the same directory as the mount target. Without
  it, uvicorn watches the entire container filesystem and reloads on unrelated
  file changes (like writes to `/data`).

- **`--factory`** flag is needed when the app is created by a factory function
  (`create_app`). The skill template uses a factory, so include it. If your
  server exports the app directly as a module-level variable, drop `--factory`.

- **`$$` escaping:** Docker Compose interprets `$` as variable substitution.
  To pass `${MCP_PORT}` to the shell inside the container, write `$${MCP_PORT}`
  in the YAML.

- **The Dockerfile does not change** between dev and prod. Dev mode is purely a
  compose-level concern — the image is always production-ready.

- **SPA dist overlay path** must match the directory the Dockerfile's
  `COPY --from=frontend ... <target>` line wrote to. Most ecosystem services
  use `/app/static`; tubemail uses `/app/frontend/dist`. Read the runtime
  stage of the Dockerfile to confirm the target before adding the overlay.

- **The dist directory must exist on the host** before `docker compose up`,
  or Docker silently creates an empty one and the SPA returns 404 / blank
  index. First-checkout bootstrap is `npm install --prefix
  <service>/frontend && npm --prefix <service>/frontend run build`. Add
  `<service>/frontend/dist/` to `.gitignore` — it is a build artifact.

---

## .mcp.json Client Configuration

```json
{
  "mcpServers": {
    "<server-name>": {
      "type": "http",
      "url": "http://localhost:<port>/mcp"
    }
  }
}
```

Use `http://` for localhost (the default — no certs, no warnings, no
friction; loopback traffic never leaves the host). Use `https://` only
when the MCP server is exposed off the loopback interface (in which
case TLS termination is mandatory; see the Transport section's TLS
policy). Add to `~/.mcp.json` for global access across all Claude
sessions, or to `{project}/.mcp.json` for project-scoped access.

---

## pyproject.toml Dependencies

```toml
dependencies = [
    "fastmcp[tasks]>=2.14.0",
    "fastapi>=0.104.0",
    "uvicorn[standard]>=0.23.0",
    # ... service-specific deps
]
```

The `[tasks]` extra includes Docket for background task support. If your server
has no long-running tools, `fastmcp>=2.14.0` (without `[tasks]`) is sufficient.

---

## Version Tracking

Every MCP server tracks its version via a `VERSION` file at the repo root containing
a semver string (e.g., `1.0.0`). This is the single source of truth. Version bumps
are automated via GitHub Actions on merge to main.

```
VERSION          ← semver string, e.g., "1.0.0" (single source of truth)
pyproject.toml   ← updated automatically by CI
Dockerfile       ← COPY VERSION /app/VERSION
/health          ← returns {"version": "1.0.0", ...}
UI sidebar       ← shows "v1.0.0" below Settings (if server has a web UI)
```

### Automatic version bumps (GitHub Action)

Create `.github/workflows/version-bump.yml`:

```yaml
name: Version Bump

on:
  push:
    branches: [main]

permissions:
  contents: write

jobs:
  bump:
    runs-on: ubuntu-latest
    # Skip if the push was from the version bump itself
    if: "!contains(github.event.head_commit.message, '[skip ci]')"
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Determine bump type from commits
        id: bump
        run: |
          # Get commits since last tag (or all commits if no tags)
          LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
          if [ -z "$LAST_TAG" ]; then
            COMMITS=$(git log --format="%s" --no-merges)
          else
            COMMITS=$(git log "$LAST_TAG"..HEAD --format="%s" --no-merges)
          fi

          # No commits since last tag = no bump needed
          if [ -z "$COMMITS" ]; then
            echo "bump=none" >> "$GITHUB_OUTPUT"
            exit 0
          fi

          # Check for breaking changes first
          if echo "$COMMITS" | grep -qiE "^.*!:|BREAKING CHANGE"; then
            echo "bump=major" >> "$GITHUB_OUTPUT"
          elif echo "$COMMITS" | grep -qE "^feat(\(.*\))?:"; then
            echo "bump=minor" >> "$GITHUB_OUTPUT"
          elif echo "$COMMITS" | grep -qE "^(fix|refactor|perf|style|docs|chore)(\(.*\))?:"; then
            echo "bump=patch" >> "$GITHUB_OUTPUT"
          else
            echo "bump=none" >> "$GITHUB_OUTPUT"
          fi

      - name: Bump version
        if: steps.bump.outputs.bump != 'none'
        run: |
          CURRENT=$(cat VERSION 2>/dev/null || echo "0.0.0")
          IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

          case "${{ steps.bump.outputs.bump }}" in
            major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
            minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
            patch) PATCH=$((PATCH + 1)) ;;
          esac

          NEW="$MAJOR.$MINOR.$PATCH"
          echo "$NEW" > VERSION

          # Sync pyproject.toml if it exists
          if [ -f pyproject.toml ]; then
            sed -i "s/^version = \".*\"/version = \"$NEW\"/" pyproject.toml
          fi

          echo "Bumped $CURRENT -> $NEW (${{ steps.bump.outputs.bump }})"

      - name: Commit and tag
        if: steps.bump.outputs.bump != 'none'
        run: |
          NEW=$(cat VERSION)
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add VERSION pyproject.toml
          git commit -m "chore: bump version to $NEW [skip ci]"
          git tag "v$NEW"
          git push origin main --tags
```

**How it works:**
1. On every push to main, scans commit messages since the last `vX.Y.Z` tag
2. `feat:` commits trigger a minor bump, `fix:`/`refactor:`/etc. trigger a patch bump
3. `BREAKING CHANGE` or `!:` in commit message triggers a major bump
4. Updates `VERSION` file and `pyproject.toml`, commits with `[skip ci]` to prevent loops
5. Creates a git tag (`v1.2.3`) for the new version
6. If no conventional commits found, does nothing

**Bump rules:**
- `fix:`, `refactor:`, `perf:`, `style:`, `docs:`, `chore:` -> **patch** (1.0.0 -> 1.0.1)
- `feat:` -> **minor** (1.0.0 -> 1.1.0)
- `BREAKING CHANGE` or `!:` -> **major** (1.0.0 -> 2.0.0)
- No conventional prefix -> no bump

**Health endpoint** must include the version:
```python
return {"status": "ok", "service": SERVER_NAME, "version": _version}
```

**Web UI** (if present) should display the version in the sidebar below Settings,
styled as subtle gray text (e.g., `v1.0.0`). Fetch from `/health` on page load.

---

## Checklist — New MCP Server

### AI integration
1. `instructions=` parameter set on `FastMCP()` with workflows and domain concepts
2. `get_instructions()` tool registered, returns the same instructions string
3. `refresh_tools()` tool registered, sends `ToolListChangedNotification` to update cached tool list
4. `refresh_tools` parameter is typed `ctx: Context` — untyped ctx fails silently on FastMCP 3.x
5. All tool docstrings explain when/how/what (not just "does X")

### Infrastructure
5. Uses FastMCP with `@mcp.tool` decorator for all tools
6. Streamable HTTP transport via FastMCP `http_app()`. Auto-upgrades to HTTPS only if both `/data/server.crt` and `/data/server.key` are present (production deployments behind a real cert or a reverse proxy)
7. Localhost dev: no cert files. Production-only: real certs, never self-signed
8. `MCP_PORT` set in docker-compose (unique per service, no default)
9. `network_mode: host` in docker-compose
10. `/health` endpoint returns `{"status": "ok", "service": "<name>", "version": "<semver>"}`
11. Docker healthcheck configured in docker-compose against `/health`
12. `.mcp.json` entry added with `"type": "http"` and `http://localhost:<port>/mcp` URL (https only for non-loopback deployments)
13. `fastmcp`, `fastapi`, and `uvicorn` in dependencies
14. Landing page at `/` with MCP connection instructions
15. `mcp_app.lifespan` passed to FastAPI app for session management
15a. `http_app()` called WITHOUT `stateless_http=True` (stateful default required for refresh_tools and CC auto-reconnect)
16. `VERSION` file at repo root with semver string (e.g., `1.0.0`)
17. `VERSION` copied into Docker image at `/app/VERSION`
18. `pyproject.toml` version field matches `VERSION` file
19. `.github/workflows/version-bump.yml` installed for automatic semver bumps
20. Web UI (if present) displays version in sidebar below Settings
21. `docker-compose.override.yml` with volume mount + `--reload` for dev mode
21a. **`frontend/dist:/app/static:ro` overlay in `docker-compose.override.yml` (mandatory for any server with a SPA — see HARD-GATE in Mandatory Requirements)**
21b. `frontend/dist/` listed in `.gitignore` and built once on first checkout (`npm install --prefix <service>/frontend && npm --prefix <service>/frontend run build`)
22. SPA cache headers: index.html no-cache, /assets/* immutable (if server has web UI)

### Tool design
23. Tool names follow `<service>_<action>` pattern
24. Arguments are flat primitives with sensible defaults — no nested objects
25. `Literal` types used for constrained choices
26. Errors returned as descriptive strings, not exceptions
27. Large results paginated with `limit` parameter (default 20-50)
28. File/document reads have `max_bytes` guard
29. No user input passed directly to shell, SQL, or file system without validation
30. Agent tool selection tested (not just output correctness)
31. Tools that may exceed 30 seconds use `task=True` or manual start/poll pattern
32. Long-running tools include estimated completion time in initial response

---

## Follow-up: consolidate `mcp.http_app()` into shared helper

**Status:** not started — park until no service is mid-task  
**Why:** leanspecs, iris-qa, and google-workspace-mcp each call `mcp.http_app()`
directly with their own kwargs. Two of them shipped `stateless_http=True` which
silently broke `refresh_tools` and CC auto-reconnect (see `leanspecs/debug/
refresh_test/README.md` for the 2026-04-11 postmortem). The fix was a 1-line
drop in each service, but the trap remains — any future service (or a revert)
can reintroduce it.

**Proposed change:** add `shared/mcp/http_app.py`:

```python
"""Shared FastMCP http_app constructor with safe defaults."""
from __future__ import annotations
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from fastmcp import FastMCP

def create_http_app(mcp: FastMCP, *, path: str = "/", json_response: bool = True):
    """Build the FastMCP streamable-HTTP ASGI app.

    Intentionally does NOT expose stateless_http. Stateless mode breaks
    refresh_tools notification delivery and Claude Code auto-reconnect.
    If you think you need it, read leanspecs/debug/refresh_test/README.md.
    """
    return mcp.http_app(path=path, json_response=json_response)
```

Then each service collapses from:

```python
def get_mcp_app():
    return mcp.http_app(path="/", json_response=True)
```

to:

```python
from shared.mcp.http_app import create_http_app

def get_mcp_app():
    return create_http_app(mcp)
```

**Scope:** 4 files across 3 repos + 1 new file in shared
- `shared/mcp/http_app.py` (new)
- `leanspecs/src/leanspecs/mcp_server.py`
- `iris-qa/iris_qa/mcp_server.py`
- `google-workspace-mcp/src/google_workspace_mcp/server.py`

**When to do it:** next time all three services are idle (no in-progress feature
branches touching mcp_server.py). Single sweep, one commit per repo, test with
`debug/refresh_test/run_matrix.py` after.

**Also update this skill:** replace the bare `mcp.http_app(path="/")` examples
with `create_http_app(mcp)` once the shared helper exists.
