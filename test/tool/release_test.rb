# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

# Exercise release preflight in an isolated fixture. Every external command is
# replaced, and the first store lane always fails before any release mutation.
class ReleaseTest < Minitest::Test
  def setup
    @directory = File.realpath(Dir.mktmpdir("coves-release-test"))
    %w[tool bin fake-bin release_notes android ios lib test].each do |directory|
      FileUtils.mkdir_p(File.join(@directory, directory))
    end
    @log = File.join(@directory, "commands.jsonl")
    # Apple's system Ruby asks uname for the host architecture at startup.
    FileUtils.ln_s("/usr/bin/uname", File.join(@directory, "fake-bin/uname"))
    keytool = File.join(@directory, "fake-bin/keytool")
    File.write(keytool, "#!/bin/sh\nexit 0\n")
    File.chmod(0o755, keytool)
    source = File.read(File.expand_path("../../tool/release", __dir__))
    source.sub!(/^KEYTOOL = .*$/, "KEYTOOL = #{keytool.inspect}")
    File.write(File.join(@directory, "tool/release"), source)
    File.write(File.join(@directory, "release_notes/1.2.3.txt"), "Release test fixture\n")
    File.write(File.join(@directory, "pubspec.yaml"), "version: 1.2.2+1\n")

    executable("git", 'exit 0')
    executable("flutter", <<~'RUBY')
      if ARGV.first == "analyze"
        exit ENV.fetch("ANALYZE_STATUS", "0").to_i
      elsif ARGV.first == "test"
        # Dependency resolution and application logs are not reporter events.
        puts "Resolving dependencies..."
        puts '{application logger: not valid reporter JSON}'
        puts JSON.generate(type: "done", success: false)
        reporter = ARGV.find { |argument| argument.start_with?("--file-reporter=json:") }
        if reporter
          File.open(reporter.delete_prefix("--file-reporter=json:"), "w") do |report|
            report.puts "invalid report" if ENV["MALFORMED_TEST_REPORT"] == "1"
            report.puts "[]" if ENV["INVALID_EVENT_SHAPE"] == "1"
            unless ENV["EMPTY_TEST_SUITE"] == "1"
              report.puts JSON.generate(type: "testStart", test: {id: 1, name: "fixture test", metadata: {skip: false}})
              report.puts JSON.generate(type: "testDone", testID: 1, result: "success", skipped: ENV["SKIPPED_TEST"] == "1", hidden: false)
            end
            report.puts JSON.generate(type: "done", success: ENV["FAILED_TEST_COMPLETION"] != "1") unless ENV["MISSING_TEST_COMPLETION"] == "1"
          end
        end
        exit 0
      end
      abort "unexpected Flutter operation"
    RUBY
    executable("dart", 'exit ENV.fetch("FORMAT_STATUS", "0").to_i')
    executable("fastlane", 'abort "untrusted PATH fastlane invoked"')
    executable("bundle", 'exit ENV.fetch("BUNDLE_STATUS", "0").to_i')
    bundle_path = File.join(@directory, "fake-bin/bundle")
    hook = <<~RUBY
      require "rubygems"
      module FixtureBundlerPath
        def bin_path(name, executable = nil, *requirements)
          return #{bundle_path.inspect} if name == "bundler" && executable == "bundle"
          super
        end
      end
      Gem.singleton_class.prepend(FixtureBundlerPath)
    RUBY
    File.write(File.join(@directory, "bundle_hook.rb"), hook)
    # Intentionally no executable bit: the release must use its current Ruby.
    File.write(File.join(@directory, "bin/fastlane"), command_source('abort "fixture stops before store access"'))
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_uses_pinned_fastlane_under_current_ruby_after_all_checks
    output, status = release

    refute status.success?
    assert_includes output, "fixture stops before store access"
    pinned = commands.find { |command| command.fetch("path") == File.join(@directory, "bin/fastlane") }
    refute_nil pinned, "must invoke project bin/fastlane, not PATH fastlane"
    assert_equal RbConfig.ruby, pinned.fetch("ruby")
    assert_equal ["store_state"], pinned.fetch("arguments")
    assert_equal File.join(@directory, "android"), pinned.fetch("directory")
    assert_equal %w[git bundle flutter dart flutter fastlane], commands.map { |command| File.basename(command.fetch("path")) }
    assert_equal ["check"], command("bundle").fetch("arguments")
    assert_equal RbConfig.ruby, command("bundle").fetch("ruby")
    assert_equal ["analyze"], command("flutter").fetch("arguments")
    assert_equal %w[format --output=none --set-exit-if-changed lib test], command("dart").fetch("arguments")
    test_arguments = commands.select { |entry| File.basename(entry.fetch("path")) == "flutter" }.last.fetch("arguments")
    assert test_arguments.any? { |argument| argument.start_with?("--file-reporter=json:") }, "must use a dedicated report file independent of application stdout"
  end

  def test_missing_bundle_fails_with_recovery_before_store_access
    output, status = release("BUNDLE_STATUS" => "1")

    refute status.success?
    assert_match(/bundle install/i, output)
    assert_no_store_access
    refute commands.any? { |entry| File.basename(entry.fetch("path")) == "flutter" }
  end

  def test_analyzer_findings_prevent_store_access
    _output, status = release("ANALYZE_STATUS" => "1")

    refute status.success?
    assert_equal ["analyze"], command("flutter").fetch("arguments")
    assert_no_store_access
  end

  def test_formatter_drift_prevents_store_access_without_rewriting_files
    _output, status = release("FORMAT_STATUS" => "1")

    refute status.success?
    formatter = command("dart")
    refute_nil formatter, "must check formatting before stores"
    assert_includes formatter.fetch("arguments"), "--output=none"
    assert_includes formatter.fetch("arguments"), "--set-exit-if-changed"
    assert_no_store_access
  end

  def test_successful_flutter_exit_with_a_skipped_test_prevents_store_access
    output, status = release("SKIPPED_TEST" => "1")

    refute status.success?
    assert_match(/skip/i, output)
    assert_no_store_access
  end

  def test_incomplete_test_report_prevents_store_access
    _output, status = release("MISSING_TEST_COMPLETION" => "1")

    refute status.success?
    assert_no_store_access
  end

  def test_test_gate_cannot_be_bypassed
    output, status = release({}, "--skip-tests")

    assert_equal 2, status.exitstatus
    assert_match(/usage/i, output)
    assert_empty commands
  end

  def test_failed_completion_prevents_store_access_even_with_successful_process_exit
    _output, status = release("FAILED_TEST_COMPLETION" => "1")

    refute status.success?
    assert_no_store_access
  end

  def test_malformed_report_prevents_store_access
    output, status = release("MALFORMED_TEST_REPORT" => "1")

    refute status.success?
    assert_match(/invalid machine report/i, output)
    assert_no_store_access
  end

  def test_empty_suite_prevents_store_access
    _output, status = release("EMPTY_TEST_SUITE" => "1")

    refute status.success?
    assert_no_store_access
  end

  def test_invalid_event_shape_fails_gracefully_before_store_access
    output, status = release("INVALID_EVENT_SHAPE" => "1")

    refute status.success?
    assert_match(/invalid machine report/i, output)
    refute_match(/TypeError|NoMethodError/, output)
    assert_no_store_access
  end

  private

  def command_source(body)
    <<~RUBY
      require "json"
      require "rbconfig"
      File.open(ENV.fetch("COMMAND_LOG"), "a") do |log|
        log.puts JSON.generate(path: File.expand_path($PROGRAM_NAME), arguments: ARGV, directory: Dir.pwd, ruby: RbConfig.ruby)
      end
      #{body}
    RUBY
  end

  def executable(name, body)
    path = File.join(@directory, "fake-bin", name)
    File.write(path, "#!#{RbConfig.ruby}\n#{command_source(body)}")
    File.chmod(0o755, path)
  end

  def release(overrides = {}, *arguments)
    # The fixture must also be isolated when this suite runs under bundle exec.
    environment = ENV.keys.select { |name| name.start_with?("GEM_", "RUBY", "BUNDLE_", "BUNDLER_") }.to_h { |name| [name, nil] }.merge({
      "PATH" => File.join(@directory, "fake-bin"),
      "COMMAND_LOG" => @log,
      "RUBYOPT" => "-r#{File.join(@directory, 'bundle_hook.rb')}",
      "BUNDLE_GEMFILE" => nil,
      "ASC_KEY_ID" => "fixture", "ASC_ISSUER_ID" => "fixture", "ASC_KEY_PATH" => "fixture",
    }).merge(overrides)
    Open3.capture2e(environment, RbConfig.ruby, File.join(@directory, "tool/release"), "1.2.3", "--dry-run", *arguments, chdir: @directory)
  end

  def commands
    File.exist?(@log) ? File.readlines(@log).map { |line| JSON.parse(line) } : []
  end

  def command(name)
    commands.find { |entry| File.basename(entry.fetch("path")) == name }
  end

  def assert_no_store_access
    refute commands.any? { |entry| File.basename(entry.fetch("path")) == "fastlane" }, "must fail before any fastlane lane"
  end
end
