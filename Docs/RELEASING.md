# Release Process

TourBox Micro currently publishes source releases. Do not attach a development-
signed, ad-hoc-signed, or unnotarized application bundle to a GitHub Release.

## Prepare

1. Create a focused branch from the latest `main`.
2. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`.
3. Update the version references in both READMEs.
4. Move user-facing entries from `Unreleased` into a dated CHANGELOG section.
5. Update `THIRD_PARTY_NOTICES.md` and `Package.resolved` when dependencies
   change.
6. Run the complete local release gate:

   ```sh
   swift package resolve
   git diff --exit-code -- Package.resolved
   swift package dump-package > /dev/null
   swift test
   swift build -c release
   git diff --check
   ```

7. Open a pull request and wait for required CI checks.

## Publish a source release

After the pull request is merged, update local `main` and confirm the release
commit is exactly the reviewed merge result. Then create an annotated tag and a
GitHub Release without uploaded assets:

```sh
git tag -a vX.Y.Z -m "TourBox Micro X.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z \
  --repo MJYKIM99/tourbox-micro \
  --title "TourBox Micro X.Y.Z" \
  --notes-file /path/to/release-notes.md
```

Verify the tag target, release notes, compare links, README release badge, and
post-merge CI before announcing the release.

## Binary distribution gate

A downloadable app requires all of the following before it is considered an
official project artifact:

- a dedicated Developer ID Application identity;
- hardened runtime and an appropriate entitlements review;
- Apple notarization and stapling;
- reproducible packaging and SHA-256 checksums;
- protected CI secrets and a least-privilege release workflow;
- installation and upgrade testing on a clean supported macOS account.

Until that pipeline exists, users build from source and sign locally through
`Scripts/build-app.sh`.
