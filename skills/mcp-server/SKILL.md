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

1. Uses FastMCP with `@mcp.tool` decorator for all tools
2. Server supports both stdio and streamable HTTP via `MCP_TRANSPORT` env var
3. Default transport is `stdio` (local dev friendly)
4. Dockerfile sets `MCP_TRANSPORT=http`
5. Dockerfile build context is monorepo root
6. `shared/` is copied and installed in Dockerfile
7. `network_mode: host` in docker-compose, unique `MCP_PORT` per service
8. Tool names follow `<service>_<action>` pattern
9. All tools have type hints and docstrings (FastMCP generates schema from them)
10. `.mcp.json` entry added with `"type": "http"` and `/mcp` endpoint
11. `fastmcp`, `fastapi`, and `uvicorn` in dependencies
12. Landing page at `/` with MCP connection instructions
13. `mcp_app.lifespan` passed to FastAPI app for session management
