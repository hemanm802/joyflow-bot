# App updates

Joyflow uses [Sparkle 2](https://sparkle-project.org) for Mac updates. The feed URL and EdDSA public key live in `Joyflow/Resources/Info.plist`.

Public feed:

```text
https://github.com/robzilla1738/joyflow-bot/releases/latest/download/appcast.xml
```

The public key baked into the app is:

```text
3LBPx8Uv5L5ptqRqdCWovmUIPLxcDEPnivy8cOpIlH8=
```

The matching private key stays in the maintainer login Keychain. It is never committed.

Forking? Generate your own pair and replace `SUPublicEDKey` + `SUFeedURL`:

```bash
# after a Release resolve, Sparkle's tools land under DerivedData SourcePackages
generate_keys
```

`generate_keys` stores the private key in Keychain and prints the public key to paste into Info.plist.

## Cutting a release

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Archive and export a Developer ID app:

   ```bash
   scripts/build-release.sh
   ```

3. Notarize and staple the app (needs a `notarytool` keychain profile, default `AC_PASSWORD`):

   ```bash
   scripts/notarize.sh
   ```

4. Wrap the stapled app in a DMG and staple the image:

   ```bash
   SKIP_BUILD=1 APP=build/export/Joyflow.app scripts/package-dmg.sh
   xcrun stapler staple dist/Joyflow.dmg
   ```

5. Sign the DMG for Sparkle (`scripts/sign-appcast.sh` finds `sign_update` and writes `appcast.xml`).
6. Tag `v1.0.0` (or whatever you bumped to), push, and attach **both** `dist/Joyflow.dmg` and `appcast.xml` to the GitHub Release.

The copy of `appcast.xml` in the repo is a seed. The live feed is the file attached to the latest Release.

Automatic checks run once a day. **Joyflow → Check for Updates…** runs one immediately.
