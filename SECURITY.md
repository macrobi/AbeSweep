# Reporting a security problem

If you find a possible security vulnerability in AbeSweep, please help keep the details private while it is being reviewed. Use GitHub's private vulnerability-reporting option in the **Security** tab if it is available. If it is not, open a short issue asking how to get in touch privately, without including the exploit or sensitive data.

A useful report explains which macOS and AbeSweep versions are affected, what you expected the app to prevent and how to reproduce the problem safely. Please say whether you used an official download, a local build or a modified version. Personal paths, logs, quarantine contents, hosts-file contents, credentials and signing information do not belong in a public issue. Only test on systems and data you have permission to use.

I review reports as time allows and cannot promise an acknowledgement, fix or release by a particular date. Security work focuses on the current source and official release; older or modified builds may not receive fixes. The official notarized 1.4 DMG is available from [macadmin.hu](https://macadmin.hu) and [GitHub Releases](https://github.com/macrobi/AbeSweep/releases/tag/v1.4), with the same file at both locations.

## Areas that need particular care

AbeSweep can move and permanently delete files, restore quarantined content, change selected `/etc/hosts` entries and control validated background jobs. It can also access protected application containers when the user has granted Full Disk Access. Problems involving path validation, symlinks, files being replaced during an operation, authorization, rollback or unintended overwriting are therefore especially relevant.

Update signature checks and unintended data disclosure also deserve attention. Sparkle contacts the official update feed, while the optional Adobe domain review downloads a public Adobe page through a separate, ephemeral HTTPS session. Neither feature is intended to upload local scan data.
