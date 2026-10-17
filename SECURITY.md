# Security Policy

## Supported version

Security review focuses on the current source and the current official AbeSweep
release. The official notarized version 1.4 DMG is available from [macadmin.hu](https://macadmin.hu) and as the identical file on
this repository's GitHub Releases page. Older or modified builds may not
receive fixes.

## Reporting a vulnerability

Prefer GitHub's private vulnerability-reporting flow under the repository's
**Security** tab when it is enabled. If private reporting is unavailable, open a
minimal issue asking for a private contact channel. Do not publish exploit
details, personal paths, logs, quarantine contents, hosts-file contents,
credentials, signing material, or other sensitive data in a public issue.

Include the affected version, macOS version, expected security boundary, and the
smallest safe reproduction. State whether the application was an official
macadmin.hu or GitHub Releases download, a local source build, or a modified
distribution.

This project is volunteer-maintained. Reports are evaluated as capacity permits;
an acknowledgement time, fix, or release date cannot be guaranteed. Do not test
against another person's Mac, data, accounts, or services without permission.

## Relevant boundaries

AbeSweep moves and permanently deletes files, edits selected `/etc/hosts`
entries with authorization, controls validated background jobs, opens protected
application containers with user-granted Full Disk Access, restores quarantine
content, and consumes signed Sparkle update metadata. Reports involving path
validation, symlink or identity replacement, authorization boundaries, update
signatures, rollback, destination overwrites, or unintended data disclosure are
especially useful.

The Adobe domain-review feature downloads one public Adobe page over an
ephemeral HTTPS session. Sparkle separately contacts the official AbeSweep
update feed. Neither feature is intended to upload local scan data.
