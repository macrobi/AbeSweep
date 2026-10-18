# Contributing to AbeSweep

If something does not work as expected, or you have an idea that would make AbeSweep more useful, please open an issue. I maintain the project in my spare time, so I cannot promise a response date or that every suggestion will become a feature. Small, focused fixes are welcome.

## Reporting a problem

Tell me which versions of macOS and AbeSweep you are using, and whether you downloaded the official app or built it yourself. Describe what you were trying to do, the cleanup mode you selected and the last step that completed. A few clear steps to reproduce the problem and the exact error message are usually the best starting point.

Before sharing a log excerpt or screenshot, remove usernames, personal paths, account details, file contents and anything else you would not want made public. Do not upload a full quarantine, restore manifest or unedited log. Hosts-file contents, credentials and signing information should also stay private. If the problem might be a security vulnerability, use the process in [SECURITY.md](SECURITY.md).

## Proposing a change

Keep a change tied to a specific problem and preserve the app's native macOS design. Avoid adding dependencies, accounts, analytics or network services unless the problem genuinely requires them. Deployment targets, bundle identifiers, dependencies, entitlements, signing and privacy behavior should stay as they are unless changing them is part of the agreed work.

Take particular care with filesystem matching, cancellation, quarantine, restore and permanent deletion. Changes that could affect deletion, overwriting, permissions, path validation or rollback need focused tests. Use synthetic paths such as `/Users/example/...` in tests and documentation, and keep personal data, credentials, build products and release secrets out of commits.

Run `swift test` and the Xcode Debug tests before submitting a code change. If it affects a release build, also run the unsigned Xcode Release build described in [Docs/BUILDING.md](Docs/BUILDING.md). Explain what changed and how you checked it so another person can follow the reasoning.

## License and modified versions

Please read [LICENSE](LICENSE) and the [license summary](LICENSE-STATUS.md) before contributing. Submit only work you are entitled to share under these terms, and identify any third-party code that has a separate license. Unless explicitly agreed otherwise, contributions intentionally submitted for inclusion are offered under the same license. You keep ownership of your work; no copyright assignment is required, and contributing does not make you an official release publisher.

If you distribute a modified version, the license requires a different name, clear change notices and the corresponding source under the same terms. Give the app its own identity and update channel, or disable updates while keeping that separate identity. Make clear that it is an unofficial version, without implying endorsement by AbeSweep or Adobe.
