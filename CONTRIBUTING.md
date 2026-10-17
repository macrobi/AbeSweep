# Contributing

AbeSweep is volunteer-maintained. Reports and focused contributions are welcome,
but response times and acceptance cannot be guaranteed.

Before contributing, read [LICENSE](LICENSE) and [LICENSE-STATUS.md](LICENSE-STATUS.md).
Submit only material you are authorized to provide
under this license, and clearly identify separately licensed third-party code.
Unless explicitly agreed otherwise, intentionally submitted contributions to
the covered Material are offered under the same license. Contributors retain
ownership; no copyright assignment is required. A contribution does not make
its author an official release publisher.

## Issues

Use the GitHub issue template and include:

- macOS and AbeSweep versions;
- whether the build came from macadmin.hu or was built from source;
- the selected cleanup mode and the last safe step completed;
- concise reproduction steps and the exact visible error.

Remove usernames, home-directory paths, account identifiers, file contents,
hosts entries, logs, quarantine manifests, signing data, tokens, and other
private information before posting. Do not attach a full quarantine or an
unedited log.

For a suspected security vulnerability, follow [SECURITY.md](SECURITY.md).

## Changes

Keep changes small and tied to a concrete user problem. Preserve the existing
native macOS design, minimum deployment target, bundle identifiers, privacy
behavior, dependency versions, entitlements, and signing settings unless the
issue explicitly requires a change.

- Avoid new dependencies, network services, analytics, tracking, accounts, and
  data collection.
- Do not broaden filesystem matching or deletion rules without focused tests.
- Treat cancellation, quarantine, restore, and permanent deletion as
  data-safety code.
- Use synthetic `/Users/example/...` paths in fixtures and documentation.
- Keep credentials, personal paths, user data, build products, and release
  secrets out of commits.
- Add tests for behavior that could cause deletion, overwrite, privilege, path
  validation, or rollback regressions.

Run `swift test` and the Xcode Debug test suite before proposing a change. For a
release-affecting change, also perform an unsigned Xcode Release build as shown
in [Docs/BUILDING.md](Docs/BUILDING.md).

Modified distributions are unofficial. The license requires a distinct
name, clear change notices and corresponding source under the same terms.
Use a separate application identity and a separate update channel, or disable
updating while retaining the separate identity. Do not imply endorsement by
AbeSweep or Adobe. Consult the licensing status before any redistribution.
