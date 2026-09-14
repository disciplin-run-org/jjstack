---
name: google-oauth-local-listener
description: "Run a local HTTP server on localhost:1 to auto-catch Google OAuth callbacks instead of copy-pasting redirect URLs."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [google, oauth, auth, callback, localhost]
---

# Google OAuth Local Callback Listener

Instead of asking the user to copy-paste the redirect URL from the browser, spin up a
tiny HTTP server on port 1 (matching `redirect_uri=http://localhost:1`) that catches the
callback automatically.

## Usage

Start the listener BEFORE opening the auth URL, then open the URL. The listener
captures the code and exits.

```python
#!/usr/bin/env python3
"""oauth_listener.py — catch Google OAuth callback on localhost:1"""
import http.server, urllib.parse, threading, json
from pathlib import Path

captured = {}

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        params = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        captured["code"]  = params.get("code",  [""])[0]
        captured["state"] = params.get("state", [""])[0]
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"<h1>Auth complete — you can close this tab.</h1>")
        threading.Thread(target=self.server.shutdown).start()

    def log_message(self, *args):
        pass  # suppress access log

server = http.server.HTTPServer(("127.0.0.1", 1), Handler)
print("Waiting for OAuth callback on http://localhost:1 ...")
server.serve_forever()

print(f"Captured code: {captured['code'][:20]}...")
Path("/tmp/oauth_callback.json").write_text(json.dumps(captured))
```

Run in background, open auth URL, wait for capture:

```bash
python3 oauth_listener.py &
LISTENER_PID=$!
xdg-open "$AUTH_URL"   # or chrome --user-data-dir=... "$AUTH_URL"
wait $LISTENER_PID
cat /tmp/oauth_callback.json
```

## Notes

- Port 1 requires root OR the socket is unrouted (localhost:1 typically works on Linux
  without root because it's loopback — test with `python3 -m http.server 1` first).
- If port 1 is blocked, change `redirect_uri` to `http://localhost:8765` and update
  the OAuth client's Authorized Redirect URIs in Google Cloud Console.
- The `serve_forever` + `shutdown` pattern is thread-safe; the handler shuts the server
  down from its own thread after writing the response.
