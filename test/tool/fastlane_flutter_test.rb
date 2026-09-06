# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

class FastlaneFlutterTest < Minitest::Test
  def setup
    @directory = File.realpath(Dir.mktmpdir("coves-fastlane-flutter-test"))
    %w[bin fake-bin tool].each { |directory| FileUtils.mkdir_p(File.join(@directory, directory)) }
    FileUtils.cp(File.expand_path("../../tool/fastlane_flutter.rb", __dir__), File.join(@directory, "tool/fastlane_flutter.rb"))
    FileUtils.ln_s("/usr/bin/uname", File.join(@directory, "fake-bin/uname"))
    executable("fake-bin/flutter", "#!/bin/sh\nexec pod \"$@\"\n")
    executable("fake-bin/pod", "#!/bin/sh\necho 'untrusted pod invoked' >&2\nexit 99\n")
    executable("bin/pod", <<~RUBY)
      #!/usr/bin/env ruby
      require "json"
      require "rbconfig"
      puts JSON.generate(arguments: ARGV, directory: Dir.pwd, ruby: RbConfig.ruby,
                         environment: ENV.to_h)
      exit ENV.fetch("FIXTURE_POD_STATUS", "0").to_i
    RUBY
    File.write(File.join(@directory, "invoke.rb"), <<~'RUBY')
      # Set inherited fastlane variables after Ruby startup, so this fixture
      # can test cleanup without loading a real bundle or an injected RUBYOPT.
      %w[GEM_HOME GEM_PATH RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLER_VERSION].each do |name|
        ENV[name] = "fixture-bootstrap-value"
      end
      module FastlaneCore
        class UI
          def self.command(_message); end
          def self.user_error!(message)
            abort message
          end
        end
      end
      require_relative "tool/fastlane_flutter"
      flutter(__dir__, "build", "ios")
    RUBY
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_project_pod_uses_current_ruby_with_sanitized_environment
    output, status = invoke

    assert status.success?, output
    result = JSON.parse(output)
    assert_equal %w[build ios], result.fetch("arguments")
    assert_equal @directory, result.fetch("directory")
    assert_equal RbConfig.ruby, result.fetch("ruby")
    environment = result.fetch("environment")
    %w[GEM_HOME GEM_PATH RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLER_VERSION].each do |name|
      refute environment.key?(name), "must clear inherited #{name}"
    end
    assert_equal "preserved", environment.fetch("FIXTURE_APPLICATION_SETTING")
    assert_equal File.join(@directory, "bin"), environment.fetch("PATH").split(File::PATH_SEPARATOR).first
  end

  def test_failed_flutter_process_is_reported
    output, status = invoke("FIXTURE_POD_STATUS" => "1")

    refute status.success?
    assert_includes output, "`flutter build ios` failed"
  end

  private

  def executable(relative_path, source)
    path = File.join(@directory, relative_path)
    File.write(path, source)
    File.chmod(0o755, path)
  end

  def invoke(overrides = {})
    # Apply synthetic fastlane settings inside invoke.rb, never inherit the
    # test runner's bundle and trigger it before the fixture can start.
    environment = ENV.keys.select { |name| name.start_with?("GEM_", "RUBY", "BUNDLE_", "BUNDLER_") }.to_h { |name| [name, nil] }.merge({
      "PATH" => File.join(@directory, "fake-bin"),
      "RUBYOPT" => nil,
      "RUBYLIB" => nil,
      "BUNDLE_GEMFILE" => nil,
      "FIXTURE_APPLICATION_SETTING" => "preserved",
    }).merge(overrides)
    Open3.capture2e(environment, RbConfig.ruby, File.join(@directory, "invoke.rb"), chdir: @directory)
  end
end
