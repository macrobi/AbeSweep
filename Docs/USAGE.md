# Using AbeSweep

## Before cleanup

1. Save open documents.
2. Verify that any Creative Cloud content you rely on has finished syncing.
3. Make a current backup independent of AbeSweep's quarantine.
4. Read the first-launch notice and review every selected item.

Some protected Adobe application containers require Full Disk Access. AbeSweep
checks a protected location without reading its contents. If access is missing,
macOS System Settings must grant it; AbeSweep cannot grant the permission to
itself. The permission can be removed after cleanup. Full Disk Access is separate
from administrator authorization: macOS may also request an administrator name,
password, or Touch ID before AbeSweep moves protected system files, controls
background services, or changes `/etc/hosts`.

## Scan and selection

**Start Scan** reads known application and support locations and inspects
`/etc/hosts`. It does not remove anything. Results include the detected path,
size, reason, and risk level.

The presets are starting points:

- **Temporary files only** selects regenerable caches and logs.
- **Creative Cloud only** targets Creative Cloud infrastructure while preserving
  installed Adobe applications and protected user content.
- **Full Adobe removal** selects detected Adobe product and infrastructure items,
  while protected user content remains excluded.
- **Custom selection** lets the user make the final item-by-item choice.

Hosts cleanup is separate and off by default. It removes only verified Adobe
hostnames, or the contents of an exact recognized managed block. Unknown or
malformed entries stop or narrow the operation rather than being guessed.

## Cleanup and cancellation

Cleanup starts only after a second confirmation. Adobe document applications
receive a normal quit request. AbeSweep does not force them to close; if one
remains open, save the document, close the application, and try again.

Before requesting application or service changes, AbeSweep validates the whole
selection. A launch service is rejected if its plist, executable, or Adobe code
signature cannot be validated. Selected files must also be on the same
filesystem volume as the quarantine. If either check fails, no selected item is
moved.

Selected files are moved to:

```text
~/Library/Application Support/AbeSweep/Quarantine
```

Logs are written to:

```text
~/Library/Logs/AbeSweep
```

**Cancel Operation** requests cancellation. The current safe step may finish
before the request is observed. AbeSweep then attempts to move already
quarantined items back. Keep the application open and wait for rollback to
finish. If a destination has reappeared or a path has changed, AbeSweep does not
overwrite it; it retains remaining quarantine data and reports the conflict.
Cancellation and rollback are best-effort recovery, not a guarantee.

## Restore

Use **Manage Quarantine Records** to select a session. A manifest or log entry by
itself is not a restorable copy; restore is available only while actual
quarantined content remains.

Restore checks paths and identities again and refuses to overwrite a destination
that has been recreated. If `/etc/hosts` changed after cleanup, AbeSweep leaves
it untouched. A missing hosts backup does not block other remaining files, but
missing content cannot be recreated. Review the log after any partial or failed
restore.

Every available quarantine payload must be on the same filesystem volume as the
nearest existing parent of its restore destination. AbeSweep checks all of these
pairs before moving a payload and rejects the restore if safe rollback across
the boundary cannot be guaranteed.

## Permanent deletion

**Permanently Delete Quarantine** rechecks the selected session path and folder
identity, then removes that quarantine. This action is irreversible, frees the
space occupied by the quarantined files, and makes later restoration impossible.
The separate log is retained.

## Network behavior

Sparkle manages checks against the official HTTPS update feed on `macadmin.hu`.
System profiling is disabled. Depending on the user's Sparkle preferences, a
check can be scheduled or started with **Check for Updates**.

Adobe domain review is independent of Sparkle. It is off by default on a new
installation. A manual review or an explicitly enabled weekly review downloads
Adobe's public network-endpoint page through an ephemeral HTTPS session with no
persistent cache or cookie storage, then compares domain families locally. New
candidates are displayed for review and do not change the hosts file.

Neither network feature uploads scan results, paths, logs, quarantine contents,
the hosts file, or Adobe account data. The contacted server can still see the IP
address and ordinary request metadata, including an AbeSweep user-agent for the
domain review.

The official notarized AbeSweep 1.4 DMG is available
from [macadmin.hu](https://macadmin.hu) and as the identical file on this
repository's GitHub Releases page. Sparkle continues to use the official
`macadmin.hu` feed. Source builds retain that configuration unless changed.
Under the license, fork maintainers must rename and
clearly mark distributed modified builds. They also need to disable updates or configure
and sign their own feed so users are not silently moved between unofficial and
official distributions.
