# Releasing Coves

Release automation lives in `android/fastlane` and `ios/fastlane`, driven by
[fastlane](https://fastlane.tools) (installed via Homebrew; verified against
2.231.1). Both platforms share `tool/fastlane_flutter.rb`.

## One-time credential setup

Neither credential is in git, and neither can be created from the CLI -- both
require a session in the respective web console.

### Google Play

The service account is created in **Google Cloud Console**; the Play Console
only grants it access. Play Console's old *Setup > API access* page is being
retired, and the named roles it used (*Release manager* and friends) no longer
exist -- permissions are individual checkboxes now.

In [Google Cloud Console](https://console.cloud.google.com):

1. Select or create a project, then enable the **Google Play Android Developer
   API** under *APIs & Services*.
2. **IAM & Admin > Service Accounts > Create service account** (e.g.
   `fastlane-supply`). Click *Done* -- skip the optional role grants.
3. On that account: **Actions (⋮) > Manage keys > Add key > Create new key >
   JSON**.
4. Save the download as `android/fastlane/play-store-key.json` (already
   gitignored), or point `PLAY_STORE_JSON_KEY` at it elsewhere.

Then in Play Console, at the **account** level (not inside an app):

5. **Users and permissions > Invite new users**, paste the service account
   email (`...@<project>.iam.gserviceaccount.com`).
6. Grant **Admin (all permissions)**, or the narrower set: *Release to
   production, exclude devices, and use Play App Signing* + *Release apps to
   testing tracks* + *View app information*.

Verify with `cd android && fastlane run validate_play_store_json_key`.

Two things that look like broken credentials but are not: newly granted
permissions take a few minutes to propagate, so retry a first-run 401 before
re-cutting the key; and the API refuses uploads for an app that has never been
published manually (not an issue here -- Coves has shipped since 1.0.4+4).

### App Store Connect

1. App Store Connect > **Users and Access > Integrations > App Store Connect
   API** > generate a key with the **App Manager** role.
2. Download the `AuthKey_<KEY_ID>.p8` -- Apple only serves it once.
3. Export the three values fastlane needs:

   ```sh
   export ASC_KEY_ID=XXXXXXXXXX
   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   export ASC_KEY_PATH=/secure/path/AuthKey_XXXXXXXXXX.p8
   ```

Keep the `.p8` outside the repo. `ios/fastlane/*.p8` is gitignored as a
backstop, not as an invitation.

## Cutting a release

1. **Check what is actually live first -- do not trust `pubspec.yaml`.** A build
   uploaded straight from a working copy leaves no trace in git, so the pubspec
   can sit *behind* the store. This has already happened once: production was
   serving `1.0.5+7` while the committed pubspec still said `1.0.5+6`.

   ```sh
   cd android && fastlane run google_play_track_version_codes track:production
   cd android && fastlane run google_play_track_release_names  track:production
   ```

   (A track with no releases fails with `undefined method 'flat_map' for nil`
   rather than returning empty -- that is a fastlane bug, not a permissions
   problem.)

2. Bump `version:` in `pubspec.yaml` to **above the highest build number live on
   any track**. The format is `<name>+<build>`; the build number must strictly
   increase and is shared across both stores here. Neither store accepts a
   reused build number.
3. `flutter analyze && flutter test`
4. Build and upload:

   ```sh
   cd android && fastlane internal      # or: fastlane production
   cd ios     && fastlane beta          # or: fastlane release
   ```

   Use `fastlane build` on either platform to produce the artifact without
   uploading anything.

Every lane starts with `flutter clean`, which wipes `build/` for *both*
platforms. So each `build` lane copies its finished artifact into
`dist/<version>/` (gitignored) and the upload lanes read from there --
otherwise building Android and then iOS would leave you holding only the IPA.

Both upload lanes deliberately stop short of shipping: Play uploads land as a
**draft** release and `ios release` passes `submit_for_review: false`. Store
listing copy, screenshots, "What's New", and the actual submit stay manual
clicks in the two consoles.

## Platform notes

- **Android** builds the `prod` flavor. Signing comes from
  `android/key.properties` + the keystore it references, both untracked.
- **iOS** builds with **no** `--flavor`. The Xcode project only defines
  Debug/Profile/Release with a single `Runner` scheme -- the `Prod-*`/`Dev-*`
  xcconfigs exist but are not wired into it. A plain release build resolves to
  bundle id `social.coves`, and `EnvironmentConfig` defaults to production. If
  iOS flavors are ever wired up properly, revisit `ios/fastlane/Fastfile`.
- `ios/fastlane/ExportOptions.plist` is a near-copy of `ios/ExportOptions.plist`
  with `destination` set to `export` rather than `upload`, so xcodebuild leaves
  an IPA on disk for fastlane to upload instead of shipping it directly.
- `tool/fastlane_flutter.rb` strips `GEM_*`/`RUBY*`/`BUNDLE*` from the
  environment before invoking `flutter`. Without it, fastlane's Ruby leaks into
  the Homebrew `pod` shim and Flutter reports "CocoaPods is installed but
  broken", skips `pod install`, and the iOS archive fails.
