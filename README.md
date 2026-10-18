# AbeSweep

AbeSweep is a native macOS utility for finding, reviewing, and removing selected
Adobe-related applications, support files, background services, caches, logs,
preferences, and verified hosts-file entries.

The official notarized AbeSweep 1.4 DMG is available from
[macadmin.hu](https://macadmin.hu) and [GitHub Releases](https://github.com/macrobi/AbeSweep/releases/tag/v1.4).
Both channels provide the identical DMG. This repository hosts the source,
issue tracking and contributions. Source builds, forks and third-party packages
are not official releases.

AbeSweep is source-available and free to use, including for business and paid
systems administration. The [license](LICENSE) prohibits software sales and
paid software bundles. Modified distributions must be renamed, marked and
supplied with source. See [LICENSE-STATUS.md](LICENSE-STATUS.md) for a summary.

## What it does

- Scans common system and user locations for narrowly matched Adobe components.
- Explains each result, its size, and its risk before cleanup.
- Offers temporary-file, Creative Cloud infrastructure, full removal, and
  custom selection presets.
- Asks running document applications to quit normally and stops if they remain
  open, so the user can save their work.
- Moves selected items to a local quarantine while preserving their original
  paths, then records a restore manifest and a readable log.
- Can remove verified Adobe entries from `/etc/hosts` while retaining a checked
  copy of the original file in quarantine.
- Supports restore, conflict detection, and best-effort rollback if an operation
  is cancelled or fails.

Opening AbeSweep or running a local scan does not remove files. Cleanup starts
only after the user reviews the selection, confirms the risk, and approves any
macOS authorization request.

## Safety limits

Quarantine and restore reduce risk; they are not a backup and cannot guarantee
recovery in every failure or conflict. Cancellation requests are handled between
safe operation steps, so cancellation may not be immediate. Keep AbeSweep open
until rollback finishes, then inspect the result and log.

Restoration never overwrites a destination that has reappeared. A missing or
changed quarantine item cannot be recreated. **Permanently Delete Quarantine**
is irreversible and makes later restoration impossible. Save active work,
verify Creative Cloud synchronization, and keep a current independent backup
before cleanup.

## Privacy and network access

Scan results, paths, hosts-file contents, logs, quarantine data, and Adobe
account data stay on the Mac.

AbeSweep has two separate network features:

- Sparkle checks the official `macadmin.hu` update feed. Sparkle system profiling
  is disabled.
- The optional Adobe domain review downloads Adobe's public network-endpoint page
  over an ephemeral HTTPS session and compares it locally with the built-in
  catalog. It is off by default on a new installation; manual review or an
  explicitly enabled weekly review can contact Adobe. New domains are review
  candidates only and are never removed automatically.

As with any network request, the destination server can see the connection's IP
address and technical request metadata. See [Docs/USAGE.md](Docs/USAGE.md) for
details.

Source builds retain the official update feed and public update-verification key
unless the builder changes them. Under the license, a
distributed modified build must be renamed and clearly marked. Technically, it also needs
Sparkle disabled or an independent HTTPS feed with its own public verification
key backed by a privately held signing key, so users are not silently moved
between unofficial and official distributions.

## Screenshots

![AbeSweep scan results](Screenshot/1.4/AbeSweep01.png)

![AbeSweep home screen after quarantine deletion](Screenshot/1.4/Abesweep04.png)

Application screenshots supplied by the project owner. The settings and results
shown are examples from that Mac; see the [screenshot notes](Screenshot/1.4/README.md).

## Requirements and development

- macOS 14 or later
- Xcode with Swift 6 support
- Sparkle 2.9.6, resolved through Swift Package Manager

Some protected locations require Full Disk Access, and moving system files or
controlling services may also require separate administrator authorization. See
[Docs/USAGE.md](Docs/USAGE.md) before cleanup.

The current reviewed source version is AbeSweep 1.4, build 10400.

Build instructions are in [Docs/BUILDING.md](Docs/BUILDING.md). Usage and
recovery guidance are in [Docs/USAGE.md](Docs/USAGE.md). Hungarian documentation
is available in [Docs/README.hu.md](Docs/README.hu.md).

Contributions are welcome under the terms described in
[CONTRIBUTING.md](CONTRIBUTING.md). This is a volunteer-maintained project;
issues are reviewed as capacity permits, and a response or fix cannot be
guaranteed.

AbeSweep is an independent, unofficial project. It is not an Adobe Inc. product
and has not been supported, reviewed, or approved by Adobe Inc. Adobe, Creative
Cloud, and related product names may be trademarks of Adobe Inc.; they are used
only to describe interoperability and the utility's purpose.
