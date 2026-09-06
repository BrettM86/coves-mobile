# Shared helper for the android/ and ios/ Fastfiles.
#
# fastlane exports GEM_*, RUBY*, and BUNDLE* variables to child processes.
# Clear them before Flutter runs the project's bin/pod: that binstub must
# derive BUNDLE_GEMFILE and load its own locked CocoaPods dependencies rather
# than inherit fastlane's Ruby bootstrap settings. Keep bin/ on PATH so Flutter
# cannot fall back to a globally installed CocoaPods executable.

require "fileutils"
require "json"
require "tmpdir"
require "rbconfig"

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
    environment = CLEAN_RUBY_ENV.merge(
      "PATH" => [File.join(project_root, "bin"), File.dirname(RbConfig.ruby), ENV["PATH"]].compact.join(File::PATH_SEPARATOR)
    )
    ok = system(environment, "flutter", *args)
    FastlaneCore::UI.user_error!("`flutter #{args.join(' ')}` failed") unless ok
  end
end
