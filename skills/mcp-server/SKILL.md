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

**Streamable HTTP** replaces SSE as the standard network transport. It supports
session management, resumability, and both SSE and JSON response modes over a
single `/mcp` endpoint.

---

## Server Structure

Use the low-level `mcp.server.Server` class (not `FastMCP`). This keeps tool registration
explicit and matches the existing codebase pattern.

### Minimal dual-transport server.py

```python
"""<Service Name> MCP server entry point.

Exposes tools via the Model Context Protocol.
Supports stdio and streamable HTTP transports (MCP_TRANSPORT env var).
"""

# Standard Libraries
import asyncio
import logging
import os

# 3rd party
import mcp.server.stdio
import mcp.types as types
from mcp.server import NotificationOptions, Server
from mcp.server.models import InitializationOptions

# Local
from <package>.tools import <module>

log = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

server = Server("<server-name>")

SERVER_NAME = "<server-name>"
SERVER_VERSION = "0.1.0"


######################################################################
# Tool Handlers
######################################################################


@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    """Return all available tools."""
    all_tools: list[types.Tool] = []
    all_tools.extend(<module>.get_tools())
    return all_tools


@server.call_tool()
async def handle_call_tool(
    name: str,
    arguments: dict | None,
) -> list[types.TextContent]:
    """Route a tool call to the appropriate handler."""
    args = arguments or {}
    log.info("Tool called: %s with args: %s", name, list(args.keys()))

    if name.startswith("<prefix>_"):
        return await <module>.handle_tool(name, args)
    # end if
    raise ValueError(f"Unknown tool: {name}")


######################################################################
# Transport
######################################################################


def _init_options() -> InitializationOptions:
    """Build MCP initialization options."""
    return InitializationOptions(
        server_name=SERVER_NAME,
        server_version=SERVER_VERSION,
        capabilities=server.get_capabilities(
            notification_options=NotificationOptions(),
            experimental_capabilities={},
        ),
    )


async def _run_stdio() -> None:
    """Run MCP server over stdin/stdout."""
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, _init_options())
    # end with
    return


######################################################################
# Streamable HTTP Transport
######################################################################

# Active sessions — keyed by mcp-session-id header
_transports: dict[str, "StreamableHTTPServerTransport"] = {}


async def _run_session(transport: "StreamableHTTPServerTransport") -> None:
    """Run MCP server for a session's lifetime in the background."""
    async with transport.connect() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, _init_options())
    # end with
    return


async def _mcp_asgi_app(scope: dict, receive, send) -> None:
    """ASGI app that handles streamable HTTP MCP requests."""
    from mcp.server.streamable_http import StreamableHTTPServerTransport
    from starlette.requests import Request
    from uuid import uuid4

    request = Request(scope, receive)
    session_id = request.headers.get("mcp-session-id")

    # Reuse existing session
    if session_id and session_id in _transports:
        transport = _transports[session_id]
        await transport.handle_request(scope, receive, send)
        if transport.is_terminated:
            del _transports[session_id]
        # end if
        return
    # end if

    # Create new session
    new_sid = uuid4().hex
    transport = StreamableHTTPServerTransport(
        mcp_session_id=new_sid,
        is_json_response_enabled=True,
    )

    # Start server in background
    asyncio.create_task(_run_session(transport))
    await asyncio.sleep(0.05)  # Let connect() initialize

    # Handle first request
    await transport.handle_request(scope, receive, send)

    # Store for subsequent requests
    if transport.mcp_session_id:
        _transports[transport.mcp_session_id] = transport
    # end if
    return


async def _run_http(host: str, port: int) -> None:
    """Run MCP server over streamable HTTP with Starlette + uvicorn."""
    from starlette.applications import Starlette
    from starlette.routing import Mount
    import uvicorn

    app = Starlette(
        routes=[
            Mount("/mcp", app=_mcp_asgi_app),
        ],
    )

    config = uvicorn.Config(app, host=host, port=port, log_level="info")
    uvicorn_server = uvicorn.Server(config)
    log.info("Streamable HTTP transport listening on %s:%d/mcp", host, port)
    await uvicorn_server.serve()
    return


async def main() -> None:
    """Run the MCP server using the transport selected by MCP_TRANSPORT."""
    transport = os.environ.get("MCP_TRANSPORT", "stdio").lower()

    if transport == "stdio":
        await _run_stdio()
    elif transport == "http":
        host = os.environ.get("MCP_HOST", "0.0.0.0")
        port = int(os.environ.get("MCP_PORT", "8000"))
        await _run_http(host, port)
    else:
        raise ValueError(f"Unknown MCP_TRANSPORT: {transport!r}. Use 'stdio' or 'http'.")
    # end if
    return


if __name__ == "__main__":
    asyncio.run(main())
# end if
```

**Key details:**
- Sessions are tracked server-side in `_transports` dict, keyed by `mcp-session-id` header
- Each session gets a background task running `_run_session`
- Terminated sessions are automatically cleaned up
- `is_json_response_enabled=True` returns JSON instead of SSE streams (simpler for clients)
- Single endpoint: `/mcp` handles all MCP traffic (GET, POST, DELETE)

---

## Tool Module Pattern

Each tool module (`tools/<service>.py`) exports exactly two things:

```python
def get_tools() -> list[types.Tool]:
    """Tool definitions with JSON schema."""
    ...

async def handle_tool(name: str, arguments: dict) -> list[types.TextContent]:
    """Dispatch to private _<action> handlers."""
    ...
```

Private handlers are named `_<service>_<action>(arguments)`.

Tool names use the pattern `<service>_<action>` (e.g., `docs_read`, `sheets_update`).
The server routes by prefix.

---

## Dockerfile Pattern

```dockerfile
FROM python:3.10-slim

WORKDIR /app

# Install shared packages first (build context is monorepo root)
COPY shared/ /tmp/shared/
RUN pip install --no-cache-dir /tmp/shared/ && rm -rf /tmp/shared/

# Install server dependencies
COPY <service>-mcp/pyproject.toml ./
RUN pip install --no-cache-dir \
    "mcp>=1.26.0" \
    "starlette>=0.27.0" \
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
- `mcp>=1.26.0` required for streamable HTTP support.
- `starlette` and `uvicorn` are required dependencies for HTTP transport.
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

**Note:** Streamable HTTP uses a single `/mcp` endpoint (unlike SSE which needed
separate `/sse` and `/messages/` routes). The client handles session management
transparently via the `mcp-session-id` header.

---

## pyproject.toml Dependencies

Streamable HTTP transport requires these dependencies:

```toml
dependencies = [
    "mcp>=1.26.0",
    "starlette>=0.27.0",
    "uvicorn[standard]>=0.23.0",
    # ... service-specific deps
]
```

---

## Checklist — New MCP Server

1. Server supports both stdio and streamable HTTP via `MCP_TRANSPORT` env var
2. Default transport is `stdio` (local dev friendly)
3. Dockerfile sets `MCP_TRANSPORT=http`
4. Dockerfile build context is monorepo root
5. `shared/` is copied and installed in Dockerfile
6. `network_mode: host` in docker-compose, unique `MCP_PORT` per service
7. Tool modules export `get_tools()` and `handle_tool()`
8. Tool names follow `<service>_<action>` pattern
9. `.mcp.json` entry added with `"type": "http"` and `/mcp` endpoint
10. `mcp>=1.26.0`, `starlette`, and `uvicorn` in dependencies
11. Session tracking via `_transports` dict with cleanup on termination
