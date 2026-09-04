# Shared helper for the android/ and ios/ Fastfiles.
#
# fastlane runs under its own Ruby and exports GEM_HOME, GEM_PATH, RUBYOPT and
# the BUNDLE_* family to everything it spawns. The Homebrew `pod` shim resolves
# its gems through those same variables, so a `flutter build` launched from a
# fastlane lane inherits fastlane's gem paths and CocoaPods fails to load --
# Flutter reports it as "CocoaPods is installed but broken" and skips
# `pod install`, which then breaks the iOS archive.
#
# Stripping the Ruby/Bundler variables for the child process makes `flutter`
# behave exactly as it does in a plain shell.

require "fileutils"
require "json"
require "tmpdir"

# Passing nil as a value to Kernel#system removes the variable from the child
# environment rather than setting it to an empty string.
CLEAN_RUBY_ENV = ENV.keys.select { |k|
  k.start_with?("GEM_", "RUBY", "BUNDLE_", "BUNDLER_")
}.to_h { |k| [k, nil] }.freeze

# Copies a freshly built artifact into dist/, returning the new path.
#
# Every lane starts with `flutter clean`, which wipes build/ for *both*
# platforms -- so building Android and then iOS would otherwise leave only the
# IPA behind. dist/ sits outside build/, so artifacts accumulate there across
# platforms and survive the next lane's clean.
def stash_artifact(project_root, artifact, version)
  dist = File.join(project_root, "dist", version)
  FileUtils.mkdir_p(dist)
  dest = File.join(dist, File.basename(artifact))
  FileUtils.cp(artifact, dest)
  FastlaneCore::UI.success("Stashed #{File.basename(dest)} in dist/#{version}/")
  dest
end

# Finds the artifact a `build` lane stashed for this version, e.g.
# stashed_artifact(root, "1.3.0+10", "*.ipa"). The upload lanes read from
# here so that both platforms can be built before either is uploaded.
def stashed_artifact(project_root, version, glob)
  matches = Dir[File.join(project_root, "dist", version, glob)]
  if matches.empty?
    FastlaneCore::UI.user_error!(
      "No #{glob} in dist/#{version}/ -- run the build lane first"
    )
  end
  matches.max_by { |f| File.mtime(f) }
end

# Records what a store reported so tool/release can pick the next build
# number without parsing lane output. Written to dist/store/<name>.json.
def write_store_state(project_root, name, state)
  dir = File.join(project_root, "dist", "store")
  FileUtils.mkdir_p(dir)
  path = File.join(dir, "#{name}.json")
  File.write(path, JSON.pretty_generate(state))
  FastlaneCore::UI.message("Wrote dist/store/#{name}.json")
  path
end

# Reads `version: <name>+<build>` out of pubspec.yaml, e.g. "1.1.0+7".
def pubspec_version(project_root)
  pubspec = File.read(File.join(project_root, "pubspec.yaml"))
  match = pubspec[/^version:\s*(\S+)/, 1]
  FastlaneCore::UI.user_error!("No version: line in pubspec.yaml") if match.nil?
  match
end

# Runs `flutter <args>` from the Flutter project root with a clean Ruby
# environment, raising a fastlane error if it exits non-zero.
def flutter(project_root, *args)
  Dir.chdir(project_root) do
    # Required from a Fastfile, so `UI` is not in scope here the way it is
    # inside a lane -- reach for the fully qualified constant.
    FastlaneCore::UI.command("flutter #{args.join(' ')}")
    ok = system(CLEAN_RUBY_ENV, "flutter", *args)
    FastlaneCore::UI.user_error!("`flutter #{args.join(' ')}` failed") unless ok
  end
end
