---
name: deploy
description: Cut a Coves release and upload it to the Play Store and App Store Connect via fastlane. Handles the store-truth version check, builds signed artifacts for both platforms, and uploads them as drafts. Use for "deploy", "ship a release", "push to the stores", "release to Play/App Store". Never publishes or submits for review.
---

# /deploy

Ship a Coves release to Google Play and/or App Store Connect.

Accepts an optional platform argument: `/deploy android`, `/deploy ios`, or
`/deploy` for both.

The mechanics live in `RELEASING.md` — read it. This skill is the procedure and
the judgment calls around it.

## The one rule that matters

**`pubspec.yaml` is not the source of truth for the build number. The stores
are.** A build uploaded from a working copy leaves no trace in git, so the
pubspec can silently sit *behind* what is live. This has already happened once:
production was serving `1.0.5+7` while the committed pubspec said `1.0.5+6`, and
the artifacts built from it would have been rejected as a duplicate version
code.

Always query the stores before choosing a version.

## Step 1: Preflight

1. `git status` — the tree must be clean. Uncommitted work either gets committed
   first or is not in the release; do not build a release from a dirty tree.
2. Confirm the branch is `main` and note whether it is pushed.
3. `flutter analyze` — 0 errors. There is a standing tail of ~470 info-level
   lints and 4 warnings in test files; those are pre-existing, not a blocker.
   New errors are.
4. `flutter test` — the full suite must pass (943 tests at time of writing).
5. Skim `git log <last release tag or bump>..HEAD --oneline` and check whether
   anything in the release is coupled to a backend change. Coves is federated:
   a client that ships before or after its matching appview deploy can break
   for users who have not updated. Flag any coupling to the user before
   building — store rollout takes days and is not revertible on their timeline.

## Step 2: Ask the stores what is live

```sh
cd android && fastlane run google_play_track_version_codes track:production
cd android && fastlane run google_play_track_release_names  track:production
cd ios     && fastlane latest_builds
```

Repeat the Play query for `internal` and `alpha` if anything might be parked
there.

The two stores do not agree and never have — at the time of writing Play
production was on `1.0.5+7` while the App Store was live on `1.0.6+8`. Read
both; do not infer one from the other.

The rules differ by platform:

- **Play**: the version code is global to the app. It must exceed the highest
  code on *any* track, full stop.
- **App Store**: `CFBundleVersion` uniqueness is scoped to the
  `CFBundleShortVersionString` train. Build 8 under a new `1.1.0` does not
  collide with build 8 under `1.0.6`. This is why `latest_builds` reports the
  live *version string* and not just the number — the number alone cannot
  decide the question.

Taking the highest build number seen anywhere and going above it is always
safe. Reusing one is only safe on iOS, only under a new version string, and
never on Play.

Known non-problems:

- A Play track with no releases fails with `undefined method 'flat_map' for
  nil` instead of returning empty. That is a fastlane bug, not a permissions
  problem.
- `fastlane latest_builds` returning `none` for both values is ambiguous — it
  means either a genuine first release or a swallowed API error. Re-run with
  `--verbose` and read the `app_store_build_number(...) failed:` debug line
  before believing it.

## Step 3: Choose and set the version

Present the version to the user and get agreement before bumping — the name
half is a judgment call about scope (a 50-commit release with new features is a
minor bump, not a patch), and only the user knows how they want the release
line to read.

Then set `version: <name>+<build>` in `pubspec.yaml`.

## Step 4: Build

Order matters. Every lane starts with `flutter clean`, which wipes `build/` for
*both* platforms; the lanes copy their output to `dist/<version>/` precisely so
the second build does not destroy the first. Build Android first, then iOS, and
verify both artifacts are in `dist/<version>/` before uploading anything.

```sh
cd android && fastlane build
cd ios     && fastlane build
```

Verify what came out, do not assume:

- AAB is signed with the upload key, not a debug key:
  `keytool -printcert -jarfile <aab>` should show `Owner: CN=Coves`. `keytool`
  is not on `PATH` — use
  `/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool`.
- The iOS build log prints Version Number / Build Number / Bundle Identifier.
  Confirm all three.
- The IPA carries a distribution profile: extract
  `Payload/*/embedded.mobileprovision`, `security cms -D -i` it, and check
  `get-task-allow` is `false`.

## Step 5: Upload

**Confirm with the user before this step.** Uploading is outward-facing.

```sh
cd android && fastlane production   # or `internal` to stage it first
cd ios     && fastlane release      # or `beta` for TestFlight only
```

Both upload lanes deliberately stop short of shipping — Play lands as a
**draft**, iOS passes `submit_for_review: false`. **Do not circumvent this.**
Starting a rollout or submitting for review is the user's decision, always.

Verify the upload landed rather than trusting the success message:

```sh
cd android && fastlane run google_play_track_version_codes track:production
```

The new build number should now appear alongside the previously live one.

## Step 6: Hand off

Tell the user precisely what is left, because none of it can be done from here:

- **Play**: open the draft, write "What's New", set the rollout percentage
  (suggest a staged rollout for large releases), click *Start rollout*.
- **App Store Connect**: attach the build to a version, write release notes,
  answer export compliance, click *Submit for Review*.
- Screenshots, if the UI changed materially.

## Failure modes worth recognizing

| Symptom | Cause |
|---|---|
| `CocoaPods is installed but broken`, iOS archive fails | fastlane's Ruby env leaking into `flutter`. `tool/fastlane_flutter.rb` strips it — if this reappears, that helper was bypassed. |
| `A required agreement is missing or has expired` | Account-level Apple agreement, blocks the **entire** ASC API. Check App Store Connect → Business. For a free app the **Free Apps Agreement** must be Active; Paid Apps showing *Pending User Info* is about bank/tax details and is irrelevant. Acceptance takes time to propagate. |
| Play upload 401s on a freshly created key | Permission propagation. Wait and retry before re-cutting the key. |
| Play rejects a duplicate version code | Step 2 was skipped. |

## Guardrails

- Never start a rollout, publish, or submit for review.
- Never commit credentials. `android/fastlane/play-store-key.json`,
  `ios/fastlane/.env`, and `*.p8` are gitignored; keep it that way, and never
  echo their contents into the transcript.
- Never bump the version without checking the stores first.
- If only one platform can ship, say so plainly and ship it — but surface the
  federation risk from Step 1 before the user rolls out a half release.
