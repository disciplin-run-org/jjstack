---
name: mcp-server
description: >
  Use this skill when creating, modifying, or dockerizing an MCP server. Trigger on any
  request involving MCP server setup, MCP transport configuration (stdio, SSE, streamable HTTP),
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
| `sse` | Docker containers, remote clients, `.mcp.json` | 8000 |

`MCP_TRANSPORT` defaults to `stdio` so the server works out of the box for local dev.

---

## Server Structure

Use the low-level `mcp.server.Server` class (not `FastMCP`). This keeps tool registration
explicit and matches the existing codebase pattern.

### Minimal dual-transport server.py

```python
"""<Service Name> MCP server entry point.

Exposes tools via the Model Context Protocol.
Supports stdio and SSE transports (MCP_TRANSPORT env var).
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


async def _run_sse(host: str, port: int) -> None:
    """Run MCP server over SSE with Starlette + uvicorn."""
    from mcp.server.sse import SseServerTransport
    from starlette.applications import Starlette
    from starlette.routing import Mount, Route
    import uvicorn

    sse_transport = SseServerTransport("/messages/")

    async def handle_sse(request):
        async with sse_transport.connect_sse(
            request.scope, request.receive, request._send,
        ) as (read_stream, write_stream):
            await server.run(read_stream, write_stream, _init_options())
        # end with
        return

    app = Starlette(
        routes=[
            Route("/sse", endpoint=handle_sse),
            Mount("/messages/", app=sse_transport.handle_post_message),
        ],
    )

    config = uvicorn.Config(app, host=host, port=port, log_level="info")
    uvicorn_server = uvicorn.Server(config)
    log.info("SSE transport listening on %s:%d", host, port)
    await uvicorn_server.serve()
    return


async def main() -> None:
    """Run the MCP server using the transport selected by MCP_TRANSPORT."""
    transport = os.environ.get("MCP_TRANSPORT", "stdio").lower()

    if transport == "stdio":
        await _run_stdio()
    elif transport == "sse":
        host = os.environ.get("MCP_HOST", "0.0.0.0")
        port = int(os.environ.get("MCP_PORT", "8000"))
        await _run_sse(host, port)
    else:
        raise ValueError(f"Unknown MCP_TRANSPORT: {transport!r}. Use 'stdio' or 'sse'.")
    # end if
    return


if __name__ == "__main__":
    asyncio.run(main())
# end if
```

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
    "mcp>=1.0.0" \
    "starlette>=0.27.0" \
    "uvicorn[standard]>=0.23.0" \
    <additional-deps>

# Copy application source
COPY <service>-mcp/src/ ./src/
RUN pip install --no-cache-dir -e .

# Data volume for credentials / persistent storage
VOLUME ["/data"]

# SSE transport port
EXPOSE 8000

ENV PYTHONUNBUFFERED=1
ENV MCP_TRANSPORT=sse

CMD ["python", "-m", "<package>.server"]
```

Key points:
- Build context is always the **monorepo root** (so `shared/` can be copied in).
- `starlette` and `uvicorn` are required dependencies for SSE transport.
- `MCP_TRANSPORT=sse` is set in the Dockerfile since containers always use SSE.
- Port 8000 is the standard MCP SSE port.

---

## docker-compose.yml Pattern

```yaml
services:
  <service>-mcp:
    build:
      context: .
      dockerfile: <service>-mcp/Dockerfile
    ports:
      - "<host-port>:8000"
    volumes:
      - ./data/<service>:/data
    environment:
      - PYTHONUNBUFFERED=1
      - MCP_TRANSPORT=sse
    dns:
      - 8.8.8.8
      - 8.8.4.4
    restart: unless-stopped
```

Port allocation convention — each MCP server gets its own host port.
All containers listen internally on 8000.

---

## .mcp.json Client Configuration

For Claude Code to connect to a running container:

```json
{
  "mcpServers": {
    "<server-name>": {
      "type": "sse",
      "url": "http://localhost:<host-port>/sse"
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

SSE transport requires these additional dependencies beyond the base `mcp` package:

```toml
dependencies = [
    "mcp>=1.0.0",
    "starlette>=0.27.0",
    "uvicorn[standard]>=0.23.0",
    # ... service-specific deps
]
```

---

## Checklist — New MCP Server

1. Server supports both stdio and SSE via `MCP_TRANSPORT` env var
2. Default transport is `stdio` (local dev friendly)
3. Dockerfile sets `MCP_TRANSPORT=sse`
4. Dockerfile build context is monorepo root
5. `shared/` is copied and installed in Dockerfile
6. Port 8000 exposed in Dockerfile, mapped to unique host port in docker-compose
7. Tool modules export `get_tools()` and `handle_tool()`
8. Tool names follow `<service>_<action>` pattern
9. `.mcp.json` entry added for SSE endpoint
10. `starlette` and `uvicorn` in dependencies
