# Security

- API keys stay in Keychain on Mac and iPhone. They are not written to Project files, pair snapshots, or git.
- Pair links are capability URLs. Anyone with the token can sync that store and send chats to the Mac while Joyflow is open. Rotate the code if a link leaks.
- Pair mailbox traffic is HTTPS to ntfy.sh and AES-GCM sealed with the pair token. The relay never sees plaintext.
- iOS allows local HTTP only so same-network pair can use `http://192.168…` as a fallback. The default path is the HTTPS mailbox.
- Computer tools default to **Ask every time**. A built-in denylist cannot be disabled.
- The local computer is jailed to the Project `workspace/` plus folders you attach. User paths are allowed when you say so. SIP-style prefixes are not.
- Cloud sandboxes are disposable. The local Project folder remains the source of truth.
- Mac updates come from GitHub Releases and are EdDSA-verified by Sparkle. The private signing key is not in this repository.

Report issues at [github.com/robzilla1738/joyflow-bot/issues](https://github.com/robzilla1738/joyflow-bot/issues). Do not include secrets in the report.
