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

# Passing nil as a value to Kernel#system removes the variable from the child
# environment rather than setting it to an empty string.
CLEAN_RUBY_ENV = ENV.keys.select { |k|
  k.start_with?("GEM_", "RUBY", "BUNDLE_", "BUNDLER_")
}.to_h { |k| [k, nil] }.freeze

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
