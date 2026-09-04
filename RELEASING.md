# Releasing Coves

> **This is for maintainers publishing the official Coves builds.** You do not
> need any of it to build or run Coves from source -- see the README for that.
> Every step below requires access to the project's own store accounts and
> signing identity. A fork that wants to publish its own builds needs its own
> Apple and Google Play accounts, its own signing keys, and its own bundle
> identifier; the automation here is reusable, the credentials are not.

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
6. Grant only what the upload lanes need: *Release to production, exclude
   devices, and use Play App Signing* + *Release apps to testing tracks* +
   *View app information*. **Admin (all permissions)** also works and is what
   most guides suggest, but it hands a CI-shaped credential far more authority
   than uploading a build requires.

Verify with `cd android && fastlane run validate_play_store_json_key`.

Two things that look like broken credentials but are not: newly granted
permissions take a few minutes to propagate, so retry a first-run 401 before
re-cutting the key; and the API refuses uploads for an app that has never been
published manually (not an issue here -- Coves has shipped since 1.0.4+4).

### App Store Connect

1. App Store Connect > **Users and Access > Integrations > App Store Connect
   API** > generate a key with the **App Manager** role.
2. Download the `AuthKey_<KEY_ID>.p8` -- Apple only serves it once.
3. Export the three values fastlane needs, or put the same three lines
   (without `export`) in `ios/fastlane/.env`, which is gitignored and which
   fastlane loads automatically:

   ```sh
   export ASC_KEY_ID=XXXXXXXXXX
   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   export ASC_KEY_PATH=/secure/path/AuthKey_XXXXXXXXXX.p8
   ```

Keep the `.p8` outside the repo. `ios/fastlane/*.p8` is gitignored as a
backstop, not as an invitation.

### Android signing

The upload keystore is the third credential. `android/key.properties`
(gitignored) names it via `storeFile`, relative to `android/app/`, plus
`storePassword`, `keyPassword` and `keyAlias`; `app/build.gradle.kts` reads
those four keys. The keystore itself (`*.jks`, also gitignored) is maintainer
provided. `tool/release` verifies every AAB is signed by `CN=Coves` before
uploading.

## Cutting a release

One command ships both stores:

```sh
tool/release 1.4.0            # the version name is the only argument
tool/release 1.4.0 --dry-run  # everything up to and including the builds
```

Before running it, write the "What's New" text to `release_notes/<name>.txt`.
Plain text, at most 500 characters (Play's limit), and do not name other
platforms -- Apple's precheck flags "Android" in metadata.

There is no confirmation prompt. The store numbers are printed before the
builds start, and nothing is uploaded until step 5, so Ctrl-C is safe until
then; any exit before the first upload restores the tree. A dry run may be
run from any branch (the `main`/`origin` checks are skipped) but still needs
both stores' credentials.

The script, in order:

1. **Preflight.** Clean tree on `main`, exactly in sync with `origin/main`
   (neither behind nor ahead), `flutter analyze` with no errors (the standing
   tail of infos and test-file warnings does not block), `flutter test` green. `--skip-tests` skips the suite; use it only when the
   same tree has just passed it.
2. **Ask the stores.** `fastlane store_state` (Android: the production, beta,
   alpha and internal tracks) and `fastlane latest_builds` (iOS: every build
   ever uploaded) each write `dist/store/<store>.json`. Any App Store Connect
   error other than "no live version yet" stops the release here. The build
   number is one above the highest number seen anywhere, including the
   committed pubspec. **`pubspec.yaml` is never the source of truth for the
   build number** -- a build uploaded from a working copy leaves no git trace,
   and production once served `1.0.5+7` while the pubspec said `1.0.5+6`.
   Play version codes are global to the app; iOS scopes build numbers to the
   version string. Going above everything is always safe on both, so that is
   what happens. The name must be above the App Store's live version and not
   below the committed pubspec, and if App Store Connect already has a
   *different* version in preparation or review the script refuses to start.
3. **Write.** `version: <name>+<build>` into `pubspec.yaml`; the notes into
   `android/fastlane/metadata/android/en-US/changelogs/<build>.txt` and
   `ios/fastlane/metadata/en-US/release_notes.txt`.
4. **Build and verify.** `fastlane build` on Android, then iOS. Each lane
   starts with `flutter clean`, which wipes `build/` for *both* platforms, so
   each copies its artifact to `dist/<version>/` (gitignored) first. The AAB
   must be signed by `CN=Coves` and the IPA must carry a distribution profile
   (`get-task-allow` false) or the script stops here.
5. **Ship.** `fastlane ship` on each platform, reading from `dist/<version>/`:
   - Play: production track, `release_status: completed`, 100% rollout, with
     the changelog. Google's review runs first; the release goes live when it
     passes.
   - App Store: uploads the build, pushes the whole text listing from
     `ios/fastlane/metadata` (not screenshots), creates the version, submits
     for review, releases automatically on approval, and then checks that the
     version is actually in a submitted state. Export compliance is answered
     by `ITSAppUsesNonExemptEncryption` in `Info.plist`. Precheck runs at
     warning level: its URL rule sends `HEAD` and coves.social answers 405,
     so it reports the listing links as broken when they are not.
6. **Record.** Commits `chore(release): <version>` with the pubspec and notes
   and pushes to `origin`.

If it fails after one store has shipped, the script prints exactly what is
half-done and how to finish: `cd ios && fastlane ship` if needed, then commit
`pubspec.yaml` and the two notes files and push. Do not re-run
`tool/release`; it would pick the next build number and leave the shipped one
uncommitted. If only the final push failed, the commit is local: push it.

The pre-automation lanes still exist for staging: `android internal`,
`android production` (draft), `ios beta` (TestFlight), `ios release` (upload
only). `fastlane build` on either platform produces the artifact without
uploading.

### Store listings live in the repo

`android/fastlane/metadata` and `ios/fastlane/metadata` hold the listing
text, and Android's also holds the images; iOS screenshots are managed in App
Store Connect and are never pushed from here. Both were seeded from the
consoles. Android's `ship` pushes only the changelog; iOS's `ship` pushes the
full text listing, so a console-side edit to the iOS listing is overwritten
on the next release. Edit the files, not the console:

```sh
cd android && fastlane supply                   # text + images
cd ios     && fastlane push_metadata            # text, no build
cd ios     && fastlane pull_metadata            # re-seed from ASC
cd ios     && fastlane precheck                 # Apple's metadata rules
```

`ios/fastlane/metadata/review_information/` comes down with `pull_metadata`
and holds the App Review contact and demo login. It is gitignored; keep it that
way.

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
