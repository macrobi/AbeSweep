# Third-party notices

AbeSweep depends on [Sparkle](https://github.com/sparkle-project/Sparkle), version **2.9.6**, pinned at revision `ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a` in both package resolution files.

The complete upstream [Sparkle license and bundled external notices](Licenses/Sparkle-2.9.6.txt) are retained unchanged. They include Sparkle's MIT permission notice, bsdiff/bspatch and signature-verifier BSD-style notices, sais-lite's MIT notice, and the Ed25519 notice. Those components retain their own permissions; AbeSweep's sale restriction does not replace them.

The source package does not vendor the Sparkle binary or checkout. Swift Package Manager retrieves the pinned binary dependency when building; network access is required for the first resolution. AbeSweep's compiled application bundle includes `Sparkle-2.9.6.txt` in its resources so the complete reviewed notice remains with the distributed app. Distributors of compiled applications must preserve all notices required by the components they actually ship, including resources in the Sparkle framework. Recheck the notice inventory when updating dependencies.

Apple platform frameworks and SDKs are build/runtime prerequisites, not vendored source in this package. AbeSweep's artwork is a project resource, not licensed by the Sparkle notice.

Adobe, Acrobat, Creative Cloud, InDesign, and Photoshop are either registered trademarks or trademarks of Adobe in the United States and/or other countries. Product names identify the software being maintained. AbeSweep is independent and is not affiliated with, sponsored, approved or supported by Adobe.
