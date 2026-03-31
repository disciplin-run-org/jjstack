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

## Transport: Streamable HTTP via FastMCP

All MCP servers run as Docker containers with `network_mode: host` and communicate
via **streamable HTTP** on a single `/mcp` endpoint. FastMCP handles session
management, schema generation, and protocol details automatically.

Each server gets its own unique port via the `MCP_PORT` environment variable.
There is no default port — you must assign one per service to avoid collisions
when running multiple MCP servers on the same host.

**Port allocation:** Track assigned ports in your docker-compose file. Each new
service gets the next available port. Example:
- leanspecs: 8001
- google-workspace-mcp: 8002
- dayplan: 8003

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

mcp = FastMCP(SERVER_NAME)


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

    port = os.environ.get("MCP_PORT")
    if not port:
        raise RuntimeError("MCP_PORT environment variable is required")
    # end if

    mcp_app = mcp.http_app(path="/")

    app = FastAPI(title=SERVER_NAME, lifespan=mcp_app.lifespan)
    app.mount("/mcp", mcp_app)

    @app.get("/health")
    async def health():
        """Health check for Docker, load balancers, and monitoring."""
        return {"status": "ok", "service": SERVER_NAME}
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
    """Run the MCP server over streamable HTTP."""
    import uvicorn

    host = os.environ.get("MCP_HOST", "0.0.0.0")
    port = int(os.environ["MCP_PORT"])
    app = create_app()
    uvicorn.run(app, host=host, port=port)
    return


if __name__ == "__main__":
    main()
# end if
```

**Key details:**
- FastMCP handles all session management and schema generation
- `mcp.http_app()` creates the streamable HTTP transport — zero boilerplate
- `mcp_app.lifespan` passed to FastAPI ensures proper session management
- `MCP_PORT` is mandatory — no default, prevents port collisions

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

from fastmcp import FastMCP


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

    return
```

**Key rules:**
- Tool names follow `<service>_<action>` pattern (e.g., `docs_read`, `sheets_update`)
- Type hints on parameters and return values are mandatory — FastMCP generates JSON schema from them
- Docstrings are mandatory — they become the tool description the LLM sees
- One `register_tools(mcp)` function per module, called from `server.py`
- No manual schema definitions, no `get_tools()` / `handle_tool()` boilerplate

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

# Copy application source
COPY src/ ./src/
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

Add to `~/.mcp.json` for global access across all Claude sessions, or to
`{project}/.mcp.json` for project-scoped access.

---

## pyproject.toml Dependencies

```toml
dependencies = [
    "fastmcp>=2.0.0",
    "fastapi>=0.104.0",
    "uvicorn[standard]>=0.23.0",
    # ... service-specific deps
]
```

---

## Checklist — New MCP Server

### Infrastructure
1. Uses FastMCP with `@mcp.tool` decorator for all tools
2. Streamable HTTP transport via FastMCP `http_app()`
3. `MCP_PORT` set in docker-compose (unique per service, no default)
4. `network_mode: host` in docker-compose
5. `/health` endpoint returns `{"status": "ok", "service": "<name>"}`
6. Docker healthcheck configured in docker-compose against `/health`
7. `.mcp.json` entry added with `"type": "http"` and `/mcp` endpoint
8. `fastmcp`, `fastapi`, and `uvicorn` in dependencies
9. Landing page at `/` with MCP connection instructions
10. `mcp_app.lifespan` passed to FastAPI app for session management

### Tool design
11. Tool names follow `<service>_<action>` pattern
12. All tools have type hints and docstrings that explain when/how/what
13. Arguments are flat primitives with sensible defaults — no nested objects
14. `Literal` types used for constrained choices
15. Errors returned as descriptive strings, not exceptions
16. Large results paginated with `limit` parameter (default 20-50)
17. File/document reads have `max_bytes` guard
18. No user input passed directly to shell, SQL, or file system without validation
19. Agent tool selection tested (not just output correctness)
