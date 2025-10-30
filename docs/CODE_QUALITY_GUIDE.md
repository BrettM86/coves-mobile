# Flutter Code Quality & Formatting Guide

This guide covers linting, formatting, and automated code quality checks for the Coves mobile app.

---

## Tools Overview

### 1. **flutter analyze** (Static Analysis / Linting)
Checks code for errors, warnings, and style issues based on `analysis_options.yaml`.

### 2. **dart format** (Code Formatting)
Auto-formats code to Dart style guide (spacing, indentation, line length).

### 3. **analysis_options.yaml** (Configuration)
Defines which lint rules are enforced.

---

## Quick Start

### Run All Quality Checks
```bash
# Format code
dart format .

# Analyze code
flutter analyze

# Run tests
flutter test
```

---

## 1. Code Formatting with `dart format`

### Basic Usage
```bash
# Check if code needs formatting (exits with 1 if changes needed)
dart format --output=none --set-exit-if-changed .

# Format all Dart files
dart format .

# Format specific directory
dart format lib/

# Format specific file
dart format lib/services/coves_api_service.dart

# Dry run (show what would change without modifying files)
dart format --output=show .
```

### Dart Formatting Rules
- **80-character line limit** (configurable in analysis_options.yaml)
- **2-space indentation**
- **Trailing commas** for better git diffs
- **Consistent spacing** around operators

### Example: Trailing Commas
```dart
// ❌ Without trailing comma (bad for diffs)
Widget build(BuildContext context) {
  return Container(
    child: Text('Hello')
  );
}

// ✅ With trailing comma (better for diffs)
Widget build(BuildContext context) {
  return Container(
    child: Text('Hello'),  // ← Trailing comma
  );
}
```

---

## 2. Static Analysis with `flutter analyze`

### Basic Usage
```bash
# Analyze entire project
flutter analyze

# Analyze specific directory
flutter analyze lib/

# Analyze specific file
flutter analyze lib/services/coves_api_service.dart

# Analyze with verbose output
flutter analyze --verbose
```

### Understanding Output
```
  error • Business logic in widgets • lib/screens/feed.dart:42 • custom_rule
warning • Missing documentation • lib/services/api.dart:10 • public_member_api_docs
   info • Line too long • lib/models/post.dart:55 • lines_longer_than_80_chars
```

- **error**: Must fix (breaks build in CI)
- **warning**: Should fix (may break CI depending on config)
- **info**: Optional suggestions (won't break build)

---

## 3. Upgrading to Stricter Lint Rules

### Option A: Use Recommended Rules (Recommended)
Replace your current `analysis_options.yaml` with the stricter version:

```bash
# Backup current config
cp analysis_options.yaml analysis_options.yaml.bak

# Use recommended config
cp analysis_options_recommended.yaml analysis_options.yaml

# Test it
flutter analyze
```

### Option B: Use Very Good Analysis (Most Strict)
For maximum code quality, use Very Good Ventures' lint rules:

```yaml
# pubspec.yaml
dev_dependencies:
  very_good_analysis: ^6.0.0
```

```yaml
# analysis_options.yaml
include: package:very_good_analysis/analysis_options.yaml
```

### Option C: Customize Incrementally
Start with your current rules and add these high-value rules:

```yaml
# analysis_options.yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    # High-value additions
    - prefer_const_constructors
    - prefer_const_literals_to_create_immutables
    - prefer_final_locals
    - avoid_print
    - require_trailing_commas
    - prefer_single_quotes
    - lines_longer_than_80_chars
    - unawaited_futures
```

---

## 4. IDE Integration

### VS Code
Add to `.vscode/settings.json`:

```json
{
  "dart.lineLength": 80,
  "editor.formatOnSave": true,
  "editor.formatOnType": false,
  "editor.rulers": [80],
  "dart.showLintNames": true,
  "dart.previewFlutterUiGuides": true,
  "dart.previewFlutterUiGuidesCustomTracking": true,
  "[dart]": {
    "editor.formatOnSave": true,
    "editor.selectionHighlight": false,
    "editor.suggest.snippetsPreventQuickSuggestions": false,
    "editor.suggestSelection": "first",
    "editor.tabCompletion": "onlySnippets",
    "editor.wordBasedSuggestions": "off"
  }
}
```

### Android Studio / IntelliJ
1. **Settings → Editor → Code Style → Dart**
   - Set line length to 80
   - Enable "Format on save"
2. **Settings → Editor → Inspections → Dart**
   - Enable all inspections

---

## 5. Pre-Commit Hooks (Recommended)

Automate quality checks before every commit using `lefthook`.

### Setup
```bash
# Install lefthook
brew install lefthook  # macOS
# or
curl -1sLf 'https://dl.cloudsmith.io/public/evilmartians/lefthook/setup.deb.sh' | sudo -E bash
sudo apt install lefthook  # Linux

# Initialize
lefthook install
```

### Configuration
Create `lefthook.yml` in project root:

```yaml
# lefthook.yml
pre-commit:
  parallel: true
  commands:
    # Format Dart code
    format:
      glob: "*.dart"
      run: dart format {staged_files} && git add {staged_files}

    # Analyze Dart code
    analyze:
      glob: "*.dart"
      run: flutter analyze {staged_files}

    # Run quick tests (optional)
    # test:
    #   glob: "*.dart"
    #   run: flutter test

pre-push:
  commands:
    # Full test suite before push
    test:
      run: flutter test

    # Full analyze before push
    analyze:
      run: flutter analyze
```

### Alternative: Simple Git Hook
Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash

echo "Running dart format..."
dart format .

echo "Running flutter analyze..."
flutter analyze

if [ $? -ne 0 ]; then
  echo "❌ Analyze failed. Fix issues before committing."
  exit 1
fi

echo "✅ Pre-commit checks passed!"
```

Make it executable:
```bash
chmod +x .git/hooks/pre-commit
```

---

## 6. CI/CD Integration

### GitHub Actions
Create `.github/workflows/code_quality.yml`:

```yaml
name: Code Quality

on:
  pull_request:
    branches: [main, develop]
  push:
    branches: [main, develop]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
          channel: 'stable'

      - name: Install dependencies
        run: flutter pub get

      - name: Verify formatting
        run: dart format --output=none --set-exit-if-changed .

      - name: Analyze code
        run: flutter analyze

      - name: Run tests
        run: flutter test
```

### GitLab CI
```yaml
# .gitlab-ci.yml
stages:
  - quality
  - test

format:
  stage: quality
  image: cirrusci/flutter:stable
  script:
    - flutter pub get
    - dart format --output=none --set-exit-if-changed .

analyze:
  stage: quality
  image: cirrusci/flutter:stable
  script:
    - flutter pub get
    - flutter analyze

test:
  stage: test
  image: cirrusci/flutter:stable
  script:
    - flutter pub get
    - flutter test
```

---

## 7. Common Issues & Solutions

### Issue: "lines_longer_than_80_chars"
**Solution:** Break long lines with trailing commas
```dart
// Before
final user = User(name: 'Alice', email: 'alice@example.com', age: 30);

// After
final user = User(
  name: 'Alice',
  email: 'alice@example.com',
  age: 30,
);
```

### Issue: "prefer_const_constructors"
**Solution:** Add const where possible
```dart
// Before
return Container(child: Text('Hello'));

// After
return const Container(child: Text('Hello'));
```

### Issue: "avoid_print"
**Solution:** Use debugPrint with kDebugMode
```dart
// Before
print('Error: $error');

// After
if (kDebugMode) {
  debugPrint('Error: $error');
}
```

### Issue: "unawaited_futures"
**Solution:** Either await or use unawaited()
```dart
// Before
someAsyncFunction();  // Warning

// After - Option 1: Await
await someAsyncFunction();

// After - Option 2: Explicitly ignore
import 'package:flutter/foundation.dart';
unawaited(someAsyncFunction());
```

---

## 8. Project-Specific Rules

### Current Configuration
We use `flutter_lints: ^5.0.0` with default rules.

### Recommended Upgrade Path
1. **Week 1:** Add format-on-save to IDEs
2. **Week 2:** Add pre-commit formatting hook
3. **Week 3:** Enable stricter analysis_options.yaml
4. **Week 4:** Add CI/CD checks
5. **Week 5:** Fix all existing violations
6. **Week 6:** Enforce in CI (fail builds on violations)

### Custom Rules for Coves
Add these to `analysis_options.yaml` for Coves-specific quality:

```yaml
analyzer:
  errors:
    # Treat these as errors (not warnings)
    missing_required_param: error
    missing_return: error

  exclude:
    - '**/*.g.dart'
    - '**/*.freezed.dart'
    - 'packages/atproto_oauth_flutter/**'

linter:
  rules:
    # Architecture enforcement
    - avoid_print
    - prefer_const_constructors
    - prefer_final_locals

    # Code quality
    - require_trailing_commas
    - lines_longer_than_80_chars

    # Safety
    - unawaited_futures
    - close_sinks
    - cancel_subscriptions
```

---

## 9. Quick Reference

### Daily Workflow
```bash
# Before committing
dart format .
flutter analyze
flutter test

# Or use pre-commit hook (automated)
```

### Before PR
```bash
# Full quality check
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --coverage
```

### Fix Formatting Issues
```bash
# Auto-fix all formatting
dart format .

# Fix specific file
dart format lib/screens/home/feed_screen.dart
```

### Ignore Specific Warnings
```dart
// Ignore for one line
// ignore: avoid_print
print('Debug message');

// Ignore for entire file
// ignore_for_file: avoid_print

// Ignore for block
// ignore: lines_longer_than_80_chars
final veryLongVariableName = 'This is a very long string that exceeds 80 characters';
```

---

## 10. Resources

### Official Documentation
- [Dart Linter Rules](https://dart.dev/lints)
- [Flutter Lints Package](https://pub.dev/packages/flutter_lints)
- [Effective Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)

### Community Resources
- [Very Good Analysis](https://pub.dev/packages/very_good_analysis)
- [Lint Package](https://pub.dev/packages/lint)
- [Flutter Analyze Best Practices](https://docs.flutter.dev/testing/best-practices)

---

## Next Steps

1. ✅ Review `analysis_options_recommended.yaml`
2. ⬜ Decide on strictness level (current / recommended / very_good)
3. ⬜ Set up IDE format-on-save
4. ⬜ Create pre-commit hooks
5. ⬜ Add CI/CD quality checks
6. ⬜ Schedule time to fix existing violations
7. ⬜ Enforce in team workflow
