# AbeSweep

AbeSweep is a free, native macOS utility for maintaining Adobe installations. It helps you see what is installed, remove selected components and prepare a Mac for a fresh installation. You can use it on your own Mac or as part of your work as a systems administrator.

Download the official, notarized **AbeSweep 1.4** from [macadmin.hu](https://macadmin.hu) or [GitHub Releases](https://github.com/macrobi/AbeSweep/releases/tag/v1.4). Both offer the same DMG, which runs on Apple Silicon and Intel Macs with **macOS 14 or later**. This repository is where you can read the source, report a problem or suggest an improvement. [Magyar ismertető](Docs/README.hu.md).

## Using AbeSweep

A scan brings together Adobe applications and related support files, background services, caches, logs and preferences. Each result includes its size and an explanation of why it was found, with a warning where personal settings or creative work may be involved. You can choose temporary files, Creative Cloud components, a full removal or your own selection. Scanning does not remove anything: you review the results and confirm before cleanup begins.

AbeSweep asks running document applications to close normally and stops if they stay open, giving you a chance to save your work. It then moves the selected files into a local quarantine and records their original locations in a restore manifest and log. It can also remove verified Adobe entries from `/etc/hosts`, keeping a checked copy of the original file. Some locations need Full Disk Access; macOS may also ask for administrator authorization.

The quarantine lets you attempt a restore if something is still needed, but it cannot replace a backup. Restore will not overwrite a file that has reappeared, and missing or changed quarantine items cannot be recovered by the app. Cancellation takes effect between safe steps and may take a little time; leave AbeSweep open while it tries to undo the operation, then check the result and log. Once you choose **Permanently Delete Quarantine**, those files can no longer be restored through AbeSweep. Save your work, check Creative Cloud synchronization and keep an independent backup before cleanup. The [usage guide](Docs/USAGE.md) explains recovery and its limits in more detail.

## Privacy and updates

Scans and cleanup run locally. Your scan results, paths, logs, hosts-file contents, quarantine and Adobe account data stay on your Mac. Sparkle checks for updates through macadmin.hu, with system profiling disabled.

There is also an optional Adobe domain review. When you run it, or enable the weekly check, AbeSweep downloads Adobe's public network-endpoint page and compares it with its own list on your Mac. This is off by default on a new installation, and newly found addresses are never removed automatically. As with other web requests, the server can see your IP address and connection metadata. The [usage guide](Docs/USAGE.md) covers both network features.

## Screenshots

The scan results show what AbeSweep has found and let you review the selection before making changes.

![AbeSweep scan results](Screenshot/1.4/AbeSweep01.png)

The home screen below shows the confirmation after the quarantine has been permanently deleted. The log is retained.

![AbeSweep home screen after quarantine deletion](Screenshot/1.4/Abesweep04.png)

These are screenshots from the project owner's Mac, so the settings and results reflect that installation. [About the screenshots](Screenshot/1.4/README.md).

## Source, license and contributions

The source is available to read, modify and share under the [AbeSweep Free Use and Redistribution License](LICENSE). Personal, business and institutional use is free, including paid systems administration. You may charge for genuine installation, maintenance or support work, but you may not sell the software or include it in a paid software bundle. If you distribute a modified version, you must give it a different name, identify your changes and include the corresponding source under the same terms. See the [license summary](LICENSE-STATUS.md) for details.

To build version 1.4 (build 10400), you need Xcode with Swift 6 support. Swift Package Manager resolves the pinned Sparkle 2.9.6 dependency. The [build guide](Docs/BUILDING.md) includes build and test commands, and the [contribution guide](CONTRIBUTING.md) explains how to propose changes. Source builds and forks are unofficial; anyone distributing a modified build must also disable Sparkle or set up their own update feed and signing keys. The source otherwise retains the official feed and public verification key.

I maintain AbeSweep in my spare time. Bug reports and suggestions are welcome, though I cannot promise a response or fix by a particular date. Please remove private information from logs before posting an issue. For a possible security vulnerability, follow the [security reporting guide](SECURITY.md).

AbeSweep is an independent project and is not made, supported, reviewed or approved by Adobe Inc. Adobe, Creative Cloud and related product names belong to their respective trademark owners and are used here to describe what the utility works with.
