# Contributing

You need macOS 26+, a full Xcode (26+), [XcodeGen](https://github.com/yonaskolb/XcodeGen), SwiftLint, and swift-format. The iOS target deploys to iOS 18+.

```bash
git clone https://github.com/robzilla1738/joyflow-bot.git
cd joyflow-bot
scripts/test.sh
scripts/lint.sh
scripts/build.sh
scripts/build-ios.sh
scripts/package-dmg.sh
```

Kit tests do not need live API keys. Optional live sandbox calls use `JOYFLOW_LIVE_SANDBOX=1`.

Device install: `DEVELOPMENT_TEAM=YOURTEAMID DEVICE=1 scripts/build-ios.sh`. Off-network pair needs `cloudflared` on the Mac (`brew install cloudflared`). See [docs/pair.md](docs/pair.md).

Release builds (Developer ID, notarize, Sparkle appcast) are documented in [docs/updates.md](docs/updates.md).

Please keep tool names in `^[a-zA-Z0-9_-]+$` and never commit `.env` files or Sparkle private keys.
