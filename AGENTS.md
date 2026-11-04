# Publishing preferences

- Publish releases only when the user explicitly requests publication.
- Whenever publishing a new build, also install that exact build as
  `/Applications/Explorer.app`, replacing the installed copy.
- Quit any running Explorer instance before replacing the app. If it does not
  quit normally, terminate it before copying the replacement.
- Verify that the installed app's version and signing identity match the
  published build. Installing locally is part of the authorized publication;
  do not ask for separate permission for it.
