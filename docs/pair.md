# Pairing

A phone and a Mac become one teammate. After pair, the same project ids and messages exist on both sides. Chats sent from the phone run on the Mac’s computer. API keys never leave the device that stored them.

## What the user does

1. On the Mac: account menu → **Pair iPhone**. Leave the window open.
2. Copy the link, or scan the QR code with the phone.
3. On the phone: **Pair desktop** → **Paste and pair**.

The 6-character code only finds a Mac on the same Wi-Fi. The full link works from any network.

## How it works

Default path — any network, no extra install:

```
Phone  --HTTPS-->  ntfy.sh mailbox (AES-GCM)  <--HTTPS--  Mac
```

The pair link is `joyflow://pair?code=&token=`. The Mac publishes an encrypted snapshot when you open Pair iPhone. The phone fetches that snapshot. Later chats are posted as encrypted jobs; the Mac runs them and publishes a new snapshot.

Optional faster paths when they work: LAN `http://` (iOS allows local loads) and a `cloudflared` HTTPS tunnel.

- The Mac listens on `127.0.0.1:8742`.
- If `cloudflared` is installed, it opens a temporary `https://*.trycloudflare.com` tunnel so the phone can reach that listener from another network.
- The pair URL is `joyflow://pair?code=&token=&origin=&host=&port=`. The token is the capability. The 6-character code is only a human handle.
- After the tunnel URL changes (Mac relaunch), the Mac publishes the new origin to `ntfy.sh` on a topic derived from the token. The phone looks that up if the stored origin is dead.
- Snapshots, pull/push, and remote control (`/v1/control/*`) all require the token.
- Snapshots never include `settings.json`, API keys, or Composio accounts.

## Remote control

When **Run chats on the Mac** is on (the default after pair):

1. The phone writes the user message locally.
2. If the Mac is reachable on LAN or the public tunnel, the phone `POST`s `/v1/control/chat` and polls `/v1/control/status`.
3. Otherwise it publishes an encrypted mailbox job (chat / allow / deny / stop). The Mac creates the project if it is missing, runs `AgentLoop`, and publishes sealed status plus a snapshot.
4. The phone shows streamed text, steps, and approval cards from that status. Allow / deny / stop go back the same way.
5. On finish, the phone pulls a snapshot so both stores match.

## Offline / no tunnel

Same Wi-Fi still works without `cloudflared` (LAN IP + Bonjour). Install the tunnel for off-network pair:

```bash
brew install cloudflared
```

## Self-hosting the rendezvous

`PairRendezvous.serviceURL` defaults to `https://ntfy.sh`. Point it at any ntfy-compatible server. Payloads are AES-GCM sealed with a key derived from the pair token. The relay never sees plaintext.

## Files

| File | Role |
| --- | --- |
| `JoyflowKit/Pair/PairSession.swift` | Offer, URL, snapshot, binding |
| `JoyflowKit/Pair/PairNet.swift` | LAN listener + HTTP client |
| `JoyflowKit/Pair/PairRemote.swift` | Tunnel, rendezvous, control types |
| `Joyflow/Features/Projects/PairRemoteController.swift` | Mac inbox → `ChatRuntime` |
