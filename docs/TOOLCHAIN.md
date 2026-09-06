# Toolchain setup

Install [mise](https://mise.jdx.dev/getting-started.html), then from the repo root:

```sh
mise trust
mise install --locked
mise exec -- gem install bundler -v 4.0.3
mise exec -- bundle config set --local path vendor/bundle
mise exec -- bundle install
mise exec -- flutter pub get --enforce-lockfile
```

`mise.toml` pins Flutter 3.47.2 (Dart 3.13.2), Ruby 4.0.1, Maestro 2.10.0,
and Lefthook 2.1.12. `Gemfile.lock` pins Fastlane 2.238.0, CocoaPods 1.17.0,
and their dependencies; Minitest 5.27.0 runs the Ruby regression tests.
Maestro uses its official `cli-2.10.0` release tag.
Android Gradle Plugin 8.11.1, Kotlin 2.2.20, Gradle 8.14.3, and NDK versions
live in `android/`. Keep this compatible AGP 8 toolchain while using stable
`flutter_web_auth_2` 5.x: upstream requires its 6.x line for AGP 9 support.
See the [plugin's migration guide](https://pub.dev/packages/flutter_web_auth_2#built-in-kgpagp-9-support).
`mise.lock` records download URLs and integrity hashes for macOS (ARM64 and
x64) and Linux x64. Regenerate it with `mise lock --platform
macos-arm64,macos-x64,linux-x64` when changing tools.
Android Studio's JDK and the Android SDK, plus Xcode on macOS, are still required.
Maestro requires Java 17 or newer on PATH (or through JAVA_HOME). On macOS
with Android Studio installed, set it before running Maestro:

```sh
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
```

Activate mise in your shell as described in its installation guide, or prefix
commands with `mise exec --`. Mise puts this repository's `bin/` first on PATH;
the `fastlane` and `pod` binstubs load the locked bundle. This also lets CocoaPods
load the correct gems after `tool/fastlane_flutter.rb` clears inherited Ruby
variables for a Flutter build. `tool/release` invokes the project Fastlane
binstub using its current Ruby and checks the bundle before store access;
the build helper explicitly selects project `bin/pod` even without mise's PATH.
Use mise to also select the pinned Flutter and Ruby versions:

```sh
mise exec -- tool/release 1.4.0 --dry-run
mise exec -- flutter test
mise exec -- bundle exec ruby test/tool/release_test.rb
mise exec -- bundle exec ruby test/tool/fastlane_flutter_test.rb
mise exec -- maestro --version
mise exec -- maestro test .maestro/a1_login_session.yaml
```

The release dry run still requires store credentials and signing configuration;
it builds but does not upload. Maestro flows require a running app, a device,
and real backend infrastructure; see [the QA guide](QA_LOOP.md).
Install Git hooks explicitly with `mise exec -- lefthook install` when wanted.

Keep `mise.lock`, `pubspec.lock`, `Gemfile.lock`, `ios/Podfile.lock`, and both tracked
`Package.resolved` files in version control. Update stable packages deliberately;
do not use `flutter pub upgrade --major-versions` indiscriminately, since it can
select prereleases. Sentry remains on the stable 9.x line.

## Secure-storage upgrade constraint

Keep `flutter_secure_storage` on 10.x. Version 11 removes the legacy encryption
backends and cannot read data that has not already been migrated by a v10 build.
Publishing a v10 release alone does not guarantee users opened it: a user can
upgrade directly from an older installation. Establish the supported upgrade
path before raising this constraint, then verify session retention on physical
Android and iOS devices. See the [upstream changelog](https://pub.dev/packages/flutter_secure_storage/changelog).

## Native verification for this refresh

Before release, test on physical Android and iOS devices:

- Login success, cancellation, cold-start session retention, and token refresh.
- HTTPS and custom-scheme deep links, including an OAuth callback into a cold app.
- Avatar and banner cropping: save, cancel, locked aspect ratios, and dark theme.
- Android cropper toolbar, system bars, and controls under edge-to-edge display.
- Feed/detail navigation and back behavior after the go_router upgrade.

The Android auth migration sets empty task affinity on exported activities as
recommended by [flutter_web_auth_2](https://pub.dev/packages/flutter_web_auth_2).
The existing custom cropper theme is retained; there is no v9 edge-to-edge opt-out
resource to remove. iOS resolves cropper and browser-auth plugins through Swift
Package Manager. The cropper's compatible native dependency resolved to
TOCropViewController 3.2.0; Sentry Cocoa remains at the plugin's exact 8.58.4 pin.

Empty task affinity prevents task-affinity hijacking; it does not make the
`social.coves` URI scheme exclusive to this app. Browser fallback paths can
still deliver callbacks through a public intent filter. Treat callback-scheme
hijacking as a separate open security issue; this dependency upgrade does not
resolve it. A backend-issued, short-lived, single-use code bound to the initiating
client and redeemed over HTTPS would avoid putting a reusable session token in
the callback. That protocol change needs coordinated backend and mobile work.
