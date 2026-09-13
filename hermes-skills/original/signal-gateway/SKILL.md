---
name: signal-gateway
description: "Set up and manage the Signal messaging gateway for Hermes — install signal-cli, link a device, start the daemon, configure Hermes."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [Signal, Messaging, Gateway, Setup]
    related_skills: []
---

# Signal Gateway Setup for Hermes

Hermes connects to Signal via the `signal-cli` daemon running in HTTP mode. The adapter uses `httpx` (already a core Hermes dependency) — no extra Python packages needed.

## Prerequisites

- signal-cli (Java-based, NOT in apt/snap — download from GitHub releases)
- Java 17+ runtime
- A phone with Signal installed (phone becomes primary; signal-cli is a linked secondary device)

## Step 1: Verify signal-cli is installed

```
which signal-cli
signal-cli --version   # need 0.13+
java -version          # need 17+
```

If not installed:
```
VERSION=$(curl -Ls -o /dev/null -w %{url_effective} \
  https://github.com/AsamK/signal-cli/releases/latest | sed 's/^.*\/v//')
curl -L -O "https://github.com/AsamK/signal-cli/releases/download/v${VERSION}/signal-cli-${VERSION}.tar.gz"
sudo tar xf "signal-cli-${VERSION}.tar.gz" -C /opt
sudo ln -sf "/opt/signal-cli-${VERSION}/bin/signal-cli" /usr/local/bin/
```

## Step 2: Link your Signal account

signal-cli works as a **linked device** (like Signal Desktop). Your phone stays primary.

Start the link process in the background:
```
signal-cli link --name "Hermes"
```
This outputs a `sgnl://linkdevice?...` URI. Display it as a QR code for easy scanning:
```
pip3 install qrcode --break-system-packages
python3 -c "
import qrcode
uri = 'sgnl://linkdevice?...'   # paste the full URI here
qr = qrcode.QRCode()
qr.add_data(uri)
qr.make(fit=True)
qr.print_ascii(invert=True)
"
```

On the phone: Signal > Settings > Linked Devices > Link a Device > scan QR code.

Wait for confirmation in the terminal (link process will print success and exit).

Check that account data was created:
```
ls ~/.local/share/signal-cli/data/
```

## Step 3: Start the signal-cli daemon

```
signal-cli -a +1XXXXXXXXXX daemon --http --http-port 8080
```

Run as a background service (systemd recommended for persistence):
```
# Quick background start for testing
nohup signal-cli -a +1XXXXXXXXXX daemon --http --http-port 8080 > /tmp/signal-cli.log 2>&1 &
```

Verify it's up:
```
curl http://localhost:8080/v1/about
```

## Step 4: Configure Hermes

```
hermes config set signal.phone_number +1XXXXXXXXXX
hermes config set signal.daemon_url http://localhost:8080
```

Or edit `~/.hermes/config.yaml` directly and add:
```yaml
signal:
  phone_number: "+1XXXXXXXXXX"
  daemon_url: "http://localhost:8080"
```

Then restart Hermes gateway:
```
hermes setup gateway
```

## Pitfalls

- signal-cli is NOT in apt or snap — must download from GitHub releases manually
- The `link` command must stay running until the phone scans the QR code — run it in background or a separate terminal
- Java 17+ is required; Java 25 works fine
- The daemon must be running for Hermes to send/receive Signal messages
- For persistent daemon, set up a systemd unit or use a process supervisor
- QR code generation: `pip3 install qrcode --break-system-packages` on PEP 668 systems

## Recording your own install

Keep the specifics of a given machine — the number it is linked as, where
signal-cli landed, which device name you used — in that machine's own notes, not
here. This skill is the method; the inventory is per-box and goes stale.

See also: https://hermes-agent.nousresearch.com/docs/user-guide/messaging/signal
