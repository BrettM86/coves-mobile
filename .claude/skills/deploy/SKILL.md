---
name: deploy
description: Cut a Coves release and ship it to Google Play and the App Store with tool/release. Handles the judgment calls (release scope, version name, What's New text, backend coupling) and then runs the script, which derives the build number from the stores, builds, verifies, uploads, submits for review, and commits. Use for "deploy", "ship a release", "push to the stores", "release to Play/App Store".
---

# /deploy

Ship a Coves release to Google Play and the App Store.

The mechanics live in `tool/release` and are documented in `RELEASING.md` —
read that file. This skill is the judgment around the script, not a
restatement of it. The script is deterministic on purpose: do not reproduce
its steps by hand with individual fastlane lanes, and do not edit
`pubspec.yaml` yourself. The build number is the script's to choose.

## Step 1: Decide whether this should ship

1. `git status` — the tree must be clean and on `main`. Uncommitted work either
   gets committed first or is not in the release.
2. Read `git log <last release commit>..HEAD --oneline`. Release commits are
   `chore(release): <version>`, so the previous one is easy to find.
3. Check for backend coupling. Coves is federated: a client that ships before
   or after its matching appview deploy can break for users who have not
   updated, and store rollout takes days and is not revertible on the user's
   timeline. Diff `lib/services` and `lib/models` since the last release; if
   anything there depends on an appview change, say so before building.
4. Run `flutter analyze` and `flutter test` yourself only if you have reason to
   think they fail. The script runs both and stops on failure.

## Step 2: Choose the version name

The name half (`1.4.0`) is a judgment call about scope. A release with new
user-visible features is a minor bump; fixes and polish are a patch. Present
the choice and the reasoning to the user and get agreement. Only the user
knows how they want the release line to read.

The build half is not yours to choose. The script asks both stores and goes
one above everything it sees.

## Step 3: Write the release notes

Create `release_notes/<name>.txt`. Draft it from the commit log, in the user's
voice, and show it to them before running the script. Rules the stores
enforce:

- Under 500 characters. Play rejects longer changelogs.
- Do not name other platforms. Apple's precheck flags "Android" in any
  metadata field. Describe the fix, not where it happened.
- Plain text. Bullets with `•` render fine on both stores.

The same text goes to both stores; the script copies it into place.

## Step 4: Run it

```sh
tool/release <name>
```

**Confirm with the user before this step.** It uploads, starts a 100% Play
rollout, submits to Apple for review with automatic release on approval, and
pushes a commit to `origin/main`. All of that is outward-facing.

`tool/release <name> --dry-run` does everything up to and including the
signed builds and artifact verification, then restores the tree. Use it when
the build itself is in doubt.

Watch the output. There is no confirmation prompt: the script prints what
each store reported, picks the build number, and goes straight into the
builds. Nothing is uploaded until the "Shipping Android" step, so if the
store numbers look wrong (a `none` where a value should be, a Play track you
did not expect) interrupt it during the build; the tree is restored on exit.

## Step 5: Hand off

After a successful run tell the user:

- The version that shipped and the commit that recorded it.
- Play: Google's review runs first, then the release goes live at 100%. Halting
  a bad rollout is a console action.
- App Store: in review; goes live on approval without further action. If
  Apple rejects it, the resolution centre in App Store Connect has the reason.
- Screenshots, if the UI changed materially. Android's live under
  `android/fastlane/metadata` and go up with `fastlane supply`; iOS's are
  managed in App Store Connect.

## If it fails part way

Before the first upload the script restores the tree itself. After one, it
prints exactly what is half-shipped and the commands to finish. Follow those;
never re-run `tool/release` after one store has shipped, because it would pick
the next build number.

## Failure modes worth recognizing

| Symptom | Cause |
|---|---|
| `CocoaPods is installed but broken`, iOS archive fails | fastlane's Ruby env leaking into `flutter`. `tool/fastlane_flutter.rb` strips it — if this reappears, that helper was bypassed. |
| `A required agreement is missing or has expired` | Account-level Apple agreement, blocks the **entire** ASC API. Check App Store Connect → Business. For a free app the **Free Apps Agreement** must be Active. |
| Play upload 401s on a freshly created key | Permission propagation. Wait and retry before re-cutting the key. |
| Precheck "unreachable URLs" | coves.social answers 405 to `HEAD`. Precheck runs at warning level in the ship lane; it does not block. |
| Precheck "mentioning competitors" | The notes name another platform. Reword `release_notes/<name>.txt`. |
| `undefined method 'flat_map' for nil` from a Play track | A track with no releases. `store_state` treats it as empty. |

## Guardrails

- Never edit `pubspec.yaml`'s version by hand for a release.
- Never commit credentials. `android/fastlane/play-store-key.json`,
  `android/key.properties`, `ios/fastlane/.env`, `*.p8`, and
  `ios/fastlane/metadata/review_information/` are gitignored; keep it that
  way, and never echo their contents into the transcript.
- Never run `tool/release` without the user's explicit go-ahead in this
  session. Approval to build is not approval to ship.
