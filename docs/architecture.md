# Architecture

Joyflow is a native SwiftUI Mac app plus a native iPhone app. The engine lives in `JoyflowKit` and is UI-free.

```
Joyflow / JoyflowiOS (SwiftUI)  →  JoyflowKit  →  AI Gateway / Composio / local / cloud
                                      ↓
                         Application Support/Joyflow/  +  pair binding
```

- **Filesystem is source of truth.** Projects are Eve-shaped folders (`SOUL.md`, `instructions.md`, `knowledge/`, `resources/`, `workspace/`).
- **Commons** is a sibling library any Project can link.
- **Gateway** speaks OpenAI-compatible Chat Completions at `https://ai-gateway.vercel.sh/v1` by default.
- **PolicyEngine** defaults to Ask. The denylist always wins.
- **LocalComputer** is the default sandbox. Vercel, E2B, and Modal are opt-in HTTP providers.
- **Composio** uses REST v3.1 Connect Links (`POST /connected_accounts/link`).
- **Pair/handoff** is an explicit `joyflow://pair` capability (code + token + origin). `PairSession` snapshots projects and threads. The Mac can publish a public HTTPS origin via `cloudflared` so the phone is not limited to the same Wi-Fi. Chats from a paired phone run on the Mac. Settings and API keys are never in the snapshot. See [pair.md](pair.md).
