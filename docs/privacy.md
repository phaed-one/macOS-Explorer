# Privacy and network activity

Explorer has no analytics service or custom crash-report uploader. It does not
send local file contents, folder listings, search terms, or navigation history
to the developer. Preferences, saved tabs, navigation state, and Trash recovery
metadata are stored locally on your Mac.

## Software updates

Explorer checks for updates when it starts and when you choose **Check for
Updates**. It uses Sparkle to request the signed update feed and, when you choose
**Update**, download a signed app archive. The update action may also open
release information hosted by GitHub.

Explorer 0.2.8 and later use `https://phaed-one.github.io/macOS-Explorer/` for the feed
and archives. Older releases check the feed through GitHub Releases; they move
to the new address after installing the new version. Both the feed and archives
retain their Sparkle Ed25519 signatures, using the existing signing key.

The hosting service receives normal connection information, including your IP
address, request time, requested URL, and HTTP headers. Sparkle's default user
agent includes Explorer's version and Sparkle's version. Explorer disables
Sparkle's optional system-profile reporting before startup and excludes every
system-profile field, including when an older saved preference enabled it.
Update checks do not attach your filenames, searches, or navigation history.

## Network folders and other apps

Connecting to a server, browsing a mounted share, or copying files to it causes
macOS to communicate with that server. Restoring a saved tab on a network share
can also access it. This traffic goes to the server you use, rather than an
Explorer data-collection service.

Explorer uses macOS file APIs and Quick Look thumbnails. Accessing files managed
by iCloud or another file provider may cause that provider to fetch or sync data.
Opening files and terminals hands them to the selected application; those
applications and macOS have their own network and privacy behavior.

## Understanding VirusTotal results

An informational GitHub-domain alert identifies a connection to GitHub's release
CDN. A TCP-reset alert describes packet ordering around a closed connection.
Neither observation establishes that personal files were uploaded.

The app's antivirus-engine detection count and sandbox network observations are
different results. A clean engine scan is not a complete privacy audit. For the
current investigation and its evidence limits, see
[the network review](network-review.md).
