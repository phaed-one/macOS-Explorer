# Network review — November 15, 2026

## Evidence inspected

This review covers the update, server-mount, file-opening, terminal-launching,
and thumbnail code, plus Sparkle 2.10.1's profile-parameter generation and
URLSession downloader. No analytics or custom file-upload client was found in
those paths. This is a focused source review, not proof about all macOS or
third-party file-provider traffic.

The [0.2.7 VirusTotal report](https://www.virustotal.com/gui/file/d312c5a58dc18a862036303a9e6573397cde2b0ab0c9a587b9d8e44b7e515a1a/behavior)
was queried through the VirusTotal API. Its MacOS Mirage behavior report listed:

- `1:2071407`: informational DNS match for GitHub's release-assets domain.
- `1:2071408`: informational TLS SNI match for that domain.

The Zenbox macOS report contains the screenshot's TCP-reset rule, `129:8`, and
returns a `CLEAN` verdict. Its alert context identifies source IP `17.253.83.202`
and source port `443`. An [ARIN registry lookup](https://rdap.arin.net/registry/ip/17.253.83.202)
places that address in Apple's registered `17.0.0.0`–`17.255.255.255` range
(`APPLE-WWNET`, registrant Apple Inc.). The alert therefore identifies
server-originated HTTPS traffic from an Apple address, rather than evidence of
Explorer uploading local files. It does not identify the owning process, the
payload, or why the connection reset.

The initial lookup used the [older report](https://www.virustotal.com/gui/file/a4717f45f801780d167e6a0dee64a4e584197d387001cd284a4add2cefcd30c6/behavior)
linked in the local README, where this reset alert was absent. Syncing GitHub's
subsequent badge commit revealed the newer 0.2.7 report above.

The sandboxes reported available packet captures, but downloading through
`GET /api/v3/file_behaviours/{id}/pcap` returned HTTP 403 with the configured
account, including for the latest Zenbox report. No packet capture was available
to establish which side reset the connection, packet sequence, payload length,
or process attribution. The TCP-reset cause remains
unresolved; it has not been reproduced or fixed.

## Local changes

- Disable Sparkle profile reporting before starting the updater and exclude all
  profile fields through its delegate, including when saved preferences opt in.
- Prepare direct GitHub Pages hosting for the signed feed and ZIP. The release
  publisher preserves older archive URLs and checks the hosted SHA256 hashes
  with redirects disabled before publishing/installing the new release.
- Document ordinary update connection metadata, network shares, and file-provider
  behavior without claiming that the app produces no network traffic.

These changes preserve updates and network-folder features. They do not establish
the cause of the screenshot's TCP-reset alert. This source/report review precedes
the 0.2.8 deployment and its fresh release scan.

## Completing the TCP investigation

Obtain the 0.2.7 Zenbox sandbox packet capture. Match the alert to a TCP stream,
identify which endpoint sent the reset,
and inspect subsequent packet direction and sequence numbers. Correlate that
stream with DNS/TLS hostnames and sandbox process records; a machine-wide
capture alone cannot attribute every connection to Explorer.

For local reproduction, use a disposable macOS account with no private files or
connected shares. Capture a baseline before launch, then separately test startup
update checks, a completed update download, user cancellation, and quitting
during a download. Record the app/build and Sparkle versions. Prefer capture
tools with per-process attribution; HTTPS packet captures alone generally do
not reveal request bodies. Keep captures private because unrelated traffic may
be included.

Compare the same cases after Pages is activated. Fix an updater lifecycle defect
only if the reproduction identifies one. If the reset originates from the host,
network, or sandbox, document that evidence. Repeat the sandbox analysis on the
exact signed release bytes; do not claim a zero-alert result without a new report.
