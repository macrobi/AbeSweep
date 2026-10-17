# Building AbeSweep

## Requirements

- macOS 14 or later
- Xcode with the Swift 6 toolchain and macOS SDK
- Internet access for the first Swift Package Manager resolution

The project pins Sparkle 2.9.6 in both `Package.resolved` files. Keep those
resolution files synchronized and do not upgrade dependencies as part of an
unrelated change.

## Xcode

Open `AbeSweep.xcodeproj`, select the shared `AbeSweep` scheme and the **My Mac**
destination, then use **Product > Build** or **Product > Test**.

The public source export removes the original developer-team identifier from
its copy of `project.pbxproj`. This transform does not modify the canonical
project. Choose your own development team in Xcode only when a signed local run
requires it. Do not commit personal team or account metadata.

For an unsigned command-line verification with all durable output kept inside
the repository, use an explicit destination architecture. The examples below
use `arm64`, matching the verified host; use `x86_64` on an Intel Mac.

```sh
mkdir -p Output/verification/DerivedData Output/verification/SourcePackages
xcodebuild test \
  -project AbeSweep.xcodeproj \
  -scheme AbeSweep \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath Output/verification/DerivedData \
  -clonedSourcePackagesDirPath Output/verification/SourcePackages \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project AbeSweep.xcodeproj \
  -scheme AbeSweep \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath Output/verification/DerivedData \
  -clonedSourcePackagesDirPath Output/verification/SourcePackages \
  CODE_SIGNING_ALLOWED=NO
```

The tests use `@testable import`, while a normal Release build keeps testability
disabled. To test the Release configuration without changing the project, add
an invocation-only override:

```sh
xcodebuild test \
  -project AbeSweep.xcodeproj \
  -scheme AbeSweep \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath Output/verification/DerivedData \
  -clonedSourcePackagesDirPath Output/verification/SourcePackages \
  ENABLE_TESTABILITY=YES \
  CODE_SIGNING_ALLOWED=NO
```

Do not carry `ENABLE_TESTABILITY=YES` into a distributed Release build.

Signing, Archive, Developer ID distribution, and notarization are owner-run
release steps. A local unsigned or ad-hoc build is not an official download.

## Swift Package Manager

The same application and tests can be built through SwiftPM:

```sh
swift build
swift test
```

To keep build products out of the source tree's default `.build` folder, pass a
project-local scratch path:

```sh
swift test --scratch-path Output/verification/SwiftPMBuild
```

