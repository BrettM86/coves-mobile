// The name budget is the PDS handle-label cap (18 characters before the
// first dot) minus the handle prefix, because the created handle label is
// `<handlePrefix><name>`. 16/17/18 are literals on purpose so a wrong
// constant cannot pass its own regression test.

import 'package:coves_flutter/utils/community_name_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommunityNameValidator handle label budget', () {
    test('handlePrefix is the c- prefix the created handle label carries', () {
      expect(CommunityNameValidator.handlePrefix, 'c-');
    });

    test('maxLength is 16', () {
      expect(CommunityNameValidator.maxLength, 16);
    });

    test('a 17-character name is rejected with a message naming 16', () {
      final error = CommunityNameValidator.validate('a' * 17);

      expect(error, isNotNull);
      expect(error, contains('16'));
    });

    test('a 16-character name is accepted and makes an 18-character label', () {
      final name = 'a' * 16;

      expect(CommunityNameValidator.validate(name), isNull);
      expect(CommunityNameValidator.pdsHandleLabelMaxLength, 18);
    });
  });
}
