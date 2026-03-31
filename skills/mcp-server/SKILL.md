---
name: mcp-server
description: >
  Use this skill when creating, modifying, or dockerizing an MCP server. Trigger on any
  request involving MCP server setup, MCP transport configuration (stdio, streamable HTTP),
  MCP Dockerfiles, or docker-compose services for MCP servers. Also trigger when adding new
  tools to an existing MCP server or wiring up dual-transport support. Do NOT trigger for
  MCP client configuration or general Docker work unrelated to MCP.
---

# MCP Server in Docker — Blueprint

## Core Requirement: Dual Transport

Every MCP server MUST support both transports, selectable via `MCP_TRANSPORT` env var:

| Transport | When | Default port |
|-----------|------|-------------|
| `stdio` | Claude Code, local dev, piped processes | n/a |
| `http` | Docker containers, remote clients, `.mcp.json` | 8000 |

`MCP_TRANSPORT` defaults to `stdio` so the server works out of the box for local dev.

---

## Server Structure

Use **FastMCP** for all MCP servers. It handles tool registration, schema generation,
session management, and transport selection automatically.

### Minimal dual-transport server.py

```python
"""<Service Name> MCP server entry point.

Exposes tools via the Model Context Protocol.
Supports stdio and streamable HTTP transports (MCP_TRANSPORT env var).
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
# FastAPI App (HTTP transport)
######################################################################


def create_app():
    """Create FastAPI app with MCP mounted at /mcp."""
    from fastapi import FastAPI
    from fastapi.responses import HTMLResponse

    port = os.environ.get("MCP_PORT", "8000")
    mcp_app = mcp.http_app(path="/")

    app = FastAPI(title=SERVER_NAME, lifespan=mcp_app.lifespan)
    app.mount("/mcp", mcp_app)

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
    """Run the MCP server using the transport selected by MCP_TRANSPORT."""
    transport = os.environ.get("MCP_TRANSPORT", "stdio").lower()

    if transport == "stdio":
        mcp.run()
    elif transport == "http":
        import uvicorn

        host = os.environ.get("MCP_HOST", "0.0.0.0")
        port = int(os.environ.get("MCP_PORT", "8000"))
        app = create_app()
        uvicorn.run(app, host=host, port=port)
    else:
        raise ValueError(f"Unknown MCP_TRANSPORT: {transport!r}. Use 'stdio' or 'http'.")
    # end if
    return


if __name__ == "__main__":
    main()
# end if
```

**Key details:**
- FastMCP handles all transport, session management, and schema generation
- `mcp.run()` for stdio, `mcp.http_app()` for streamable HTTP — zero boilerplate
- `mcp_app.lifespan` passed to FastAPI ensures proper session management
- Landing page at `/` shows connection instructions
- Add your own routes (OAuth callbacks, web UI, etc.) to the FastAPI app as needed

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

## Mounting MCP on an Existing FastAPI App

For servers that already have a FastAPI app (web UI, OAuth, etc.), mount MCP
onto the existing app instead of creating a new one:

```python
from fastapi import FastAPI
from fastmcp import FastMCP

mcp = FastMCP("My Service")

# ... register tools ...

mcp_app = mcp.http_app(path="/")

# Pass mcp_app.lifespan to your existing app — required for session management
app = FastAPI(title="My Service", lifespan=mcp_app.lifespan)
app.mount("/mcp", mcp_app)

# Your existing routes
@app.get("/settings/auth/github")
async def github_auth():
    ...
```

This gives you a single server on one port:
- `/mcp` — MCP streamable HTTP (AI agent access)
- `/` — Web UI or landing page (human access)
- Any other routes you need (OAuth callbacks, etc.)

---

## Dockerfile Pattern

```dockerfile
FROM python:3.12-slim

WORKDIR /app

# Install shared packages first (build context is monorepo root)
COPY shared/ /tmp/shared/
RUN pip install --no-cache-dir /tmp/shared/ && rm -rf /tmp/shared/

# Install server dependencies
COPY <service>-mcp/pyproject.toml ./
RUN pip install --no-cache-dir \
    "fastmcp>=2.0.0" \
    "fastapi>=0.104.0" \
    "uvicorn[standard]>=0.23.0" \
    <additional-deps>

# Copy application source
COPY <service>-mcp/src/ ./src/
RUN pip install --no-cache-dir -e .

# Data volume for credentials / persistent storage
VOLUME ["/data"]

# Streamable HTTP transport port
EXPOSE 8000

ENV PYTHONUNBUFFERED=1
ENV MCP_TRANSPORT=http

CMD ["python", "-m", "<package>.server"]
```

Key points:
- Build context is always the **monorepo root** (so `shared/` can be copied in).
- `fastmcp>=2.0.0` handles MCP protocol, streamable HTTP, and session management.
- `fastapi` and `uvicorn` for the HTTP server.
- `MCP_TRANSPORT=http` is set in the Dockerfile since containers always use HTTP.
- Port 8000 is the standard MCP HTTP port.

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
      - MCP_TRANSPORT=http
      - MCP_PORT=<host-port>
    dns:
      - 8.8.8.8
      - 8.8.4.4
    restart: unless-stopped
```

**Networking:** `network_mode: host` for all containers — no port mapping needed, the
container binds directly to the host network. Set `MCP_PORT` in the environment to
control which port each service listens on. This simplifies connectivity for AI clients
and avoids Docker's NAT layer.

Port allocation convention — each MCP server gets its own `MCP_PORT`.
No `ports:` mapping needed with host networking.

---

## .mcp.json Client Configuration

For Claude Code to connect to a running container:

```json
{
  "mcpServers": {
    "<server-name>": {
      "type": "http",
      "url": "http://localhost:<host-port>/mcp"
    }
  }
}
```

For local dev (no container):

```json
{
  "mcpServers": {
    "<server-name>": {
      "command": "python",
      "args": ["-m", "<package>.server"]
    }
  }
}
```

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
2. Server supports both stdio and streamable HTTP via `MCP_TRANSPORT` env var
3. Default transport is `stdio` (local dev friendly)
4. Dockerfile sets `MCP_TRANSPORT=http`
5. Dockerfile build context is monorepo root
6. `shared/` is copied and installed in Dockerfile
7. `network_mode: host` in docker-compose, unique `MCP_PORT` per service
8. `.mcp.json` entry added with `"type": "http"` and `/mcp` endpoint
9. `fastmcp`, `fastapi`, and `uvicorn` in dependencies
10. Landing page at `/` with MCP connection instructions
11. `mcp_app.lifespan` passed to FastAPI app for session management

### Tool design
12. Tool names follow `<service>_<action>` pattern
13. All tools have type hints and docstrings that explain when/how/what
14. Arguments are flat primitives with sensible defaults — no nested objects
15. `Literal` types used for constrained choices
16. Errors returned as descriptive strings, not exceptions
17. Large results paginated with `limit` parameter (default 20-50)
18. File/document reads have `max_bytes` guard
19. No user input passed directly to shell, SQL, or file system without validation
20. Agent tool selection tested (not just output correctness)
