# Publishing preferences

- Publish releases only when the user explicitly requests publication.
- Whenever publishing a new build, also install that exact build as
  `/Applications/Explorer.app`, replacing the installed copy.
- Quit any running Explorer instance before replacing the app. If it does not
  quit normally, terminate it before copying the replacement.
- Verify that the installed app's version and signing identity match the
  published build. Installing locally is part of the authorized publication;
  do not ask for separate permission for it.
- From 0.1.4 onward, every release must include the signed ZIP and signed
  `appcast.xml` produced by the builder. Use `scripts/publish-release.mjs` to
  verify and upload both, publish, and install the matching app locally.
- Preserve both the code-signing certificate and Sparkle Ed25519 update-signing
  key in the user's Keychain. Never regenerate either silently or include private
  signing keys or `GH_TOKEN` in the app or a release asset.
