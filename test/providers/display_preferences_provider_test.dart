import 'package:coves_flutter/providers/display_preferences_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// A store whose writes fail: by returning false, or by throwing.
class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore({required this.throws}) : super.empty();

  final bool throws;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (throws) {
      throw Exception('disk full');
    }
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DisplayPreferencesProvider show software logos', () {
    test('defaults to on before initialize', () {
      expect(DisplayPreferencesProvider().showSoftwareLogos, isTrue);
    });

    test('defaults to on when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = DisplayPreferencesProvider();
      await provider.initialize();
      expect(provider.showSoftwareLogos, isTrue);
    });

    test('reads a stored off value', () async {
      SharedPreferences.setMockInitialValues({
        DisplayPreferencesProvider.showSoftwareLogosKey: false,
      });
      final provider = DisplayPreferencesProvider();
      await provider.initialize();
      expect(provider.showSoftwareLogos, isFalse);
    });

    test('a change notifies and survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = DisplayPreferencesProvider();
      await provider.initialize();
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setShowSoftwareLogos(false);

      expect(provider.showSoftwareLogos, isFalse);
      expect(notifications, 1);
      final restarted = DisplayPreferencesProvider();
      await restarted.initialize();
      expect(restarted.showSoftwareLogos, isFalse);

      await restarted.setShowSoftwareLogos(true);
      final restartedAgain = DisplayPreferencesProvider();
      await restartedAgain.initialize();
      expect(restartedAgain.showSoftwareLogos, isTrue);
    });
  });

  test('a stored value of the wrong type keeps the default', () async {
    SharedPreferences.setMockInitialValues({
      DisplayPreferencesProvider.showSoftwareLogosKey: 'no',
    });
    final provider = DisplayPreferencesProvider();
    await provider.initialize();
    expect(provider.showSoftwareLogos, isTrue);
  });

  for (final throws in [false, true]) {
    test('a save that ${throws ? 'throws' : 'returns false'} keeps the '
        'new value for this run without throwing', () async {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = _FailingStore(throws: throws);
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final provider = DisplayPreferencesProvider();
      await provider.initialize();
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setShowSoftwareLogos(false);

      expect(provider.showSoftwareLogos, isFalse);
      expect(notifications, 1);
    });
  }
}
