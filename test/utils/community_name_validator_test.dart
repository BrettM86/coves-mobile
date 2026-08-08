// Unit tests for the extracted community-name validator.
//
// Two of these branches could not be reached while the logic lived inside
// the admin panel: the empty-name message (the submit button is disabled
// while any field is blank) and the length-before-charset precedence. They
// had shipped uncovered.
//
// The trap worth stating out loud: the validator NORMALIZES - trims and
// LOWERCASES - before it matches, so an uppercase name is VALID even though
// the charset message talks about lowercase. A validator that rejected
// uppercase would break the panel's happy path.
//
// DELIBERATELY NOT PINNED: the exact wording of the length and charset
// messages. Those are user-facing copy and are expected to be reworded - the
// charset one especially, since it currently promises something the code
// does not enforce. So the tests below identify an error by comparing
// against what the validator ITSELF returns for a known-bad input of that
// class, and anchor each class with a stable fragment plus a
// distinct-from-the-others check. Rewording the copy keeps them green;
// misrouting an input to the wrong branch does not.
//
// The one message asserted literally is 'Name is required', which is the
// precise contract for the empty case and is not slated to change.

import 'package:coves_flutter/utils/community_name_validator.dart';
import 'package:flutter_test/flutter_test.dart';

const String requiredMessage = 'Name is required';

/// One character past the limit, built from the production constant so the
/// cases move automatically if the limit ever does.
String overLongName() => 'a' * (CommunityNameValidator.maxLength + 1);

String maxLengthName() => 'a' * CommunityNameValidator.maxLength;

void main() {
  // Reference errors, taken from the validator itself rather than copied
  // from the source. A branch that stopped firing makes these null and every
  // test that uses them fails loudly.
  final lengthError = CommunityNameValidator.validate(overLongName());
  final charsetError = CommunityNameValidator.validate('world_news');

  group('the three error classes are distinct and identifiable', () {
    test('each bad input class produces a non-null, distinct message', () {
      expect(CommunityNameValidator.validate(''), requiredMessage);
      expect(lengthError, isNotNull);
      expect(charsetError, isNotNull);

      expect(lengthError, isNot(requiredMessage));
      expect(charsetError, isNot(requiredMessage));
      expect(charsetError, isNot(lengthError));
    });

    test('the length message names the actual limit', () {
      // Asserted on the validator's OWN output, so hardcoding the template
      // in this file could not keep it green.
      expect(lengthError, contains('${CommunityNameValidator.maxLength}'));
    });

    test('the charset message mentions hyphens and does not name a limit', () {
      // A stable fragment: every candidate rewording of this copy still
      // has to say which characters are allowed.
      expect(charsetError, contains('hyphens'));
      expect(
        charsetError,
        isNot(contains('${CommunityNameValidator.maxLength}')),
      );
    });
  });

  group('normalize', () {
    test('trims then lowercases', () {
      expect(
        CommunityNameValidator.normalize('  MyCommunity  '),
        'mycommunity',
      );
    });

    test('leaves an already-normal name alone', () {
      expect(CommunityNameValidator.normalize('worldnews'), 'worldnews');
    });

    test('collapses a whitespace-only name to empty', () {
      expect(CommunityNameValidator.normalize('   '), '');
      expect(CommunityNameValidator.normalize('\t\n '), '');
    });

    test('does not touch interior whitespace', () {
      expect(CommunityNameValidator.normalize(' World News '), 'world news');
    });
  });

  group('validate - required', () {
    test('an empty name is required', () {
      expect(CommunityNameValidator.validate(''), requiredMessage);
    });

    test('a whitespace-only name is required, not a charset error', () {
      // It normalizes to empty, so the required branch wins - this is NOT
      // reported as a charset problem.
      expect(CommunityNameValidator.validate('   '), requiredMessage);
      expect(CommunityNameValidator.validate('\t\n'), requiredMessage);
    });
  });

  group('validate - length', () {
    test('a name exactly at the limit is valid', () {
      expect(CommunityNameValidator.validate(maxLengthName()), isNull);
    });

    test('one character past the limit is rejected', () {
      expect(CommunityNameValidator.validate(overLongName()), lengthError);
    });

    test('length is measured on the TRIMMED name', () {
      // Four characters of padding around a name that is exactly at the
      // limit: still valid, because trimming happens first.
      final padded = '  ${maxLengthName()}  ';
      expect(padded.length, CommunityNameValidator.maxLength + 4);
      expect(CommunityNameValidator.validate(padded), isNull);
    });

    test('length is measured after lowercasing, which cannot change it', () {
      expect(
        CommunityNameValidator.validate(overLongName().toUpperCase()),
        lengthError,
      );
    });

    test('length is measured in UTF-16 code units, not grapheme clusters', () {
      // Each emoji is 2 code units, so this is over the limit in units while
      // being well under it in characters. Reported as too long rather than
      // as a charset problem - and a switch to characters.length would flip
      // this, which is exactly why it is pinned.
      final emoji = '😀' * CommunityNameValidator.maxLength;
      expect(emoji.length, greaterThan(CommunityNameValidator.maxLength));
      expect(CommunityNameValidator.validate(emoji), lengthError);
    });
  });

  group('validate - charset', () {
    test('a leading hyphen is rejected', () {
      expect(CommunityNameValidator.validate('-worldnews'), charsetError);
    });

    test('a trailing hyphen is rejected', () {
      expect(CommunityNameValidator.validate('worldnews-'), charsetError);
    });

    test('a lone hyphen is rejected', () {
      expect(CommunityNameValidator.validate('-'), charsetError);
    });

    test('underscores are rejected', () {
      expect(CommunityNameValidator.validate('world_news'), charsetError);
    });

    test('interior spaces are rejected', () {
      expect(CommunityNameValidator.validate('world news'), charsetError);
    });

    test('dots are rejected', () {
      expect(CommunityNameValidator.validate('world.news'), charsetError);
    });

    test('non-ASCII letters are rejected', () {
      expect(CommunityNameValidator.validate('wörldnews'), charsetError);
    });
  });

  group('validate - accepted names', () {
    test('a plain lowercase name is valid', () {
      expect(CommunityNameValidator.validate('worldnews'), isNull);
    });

    test('an UPPERCASE name is VALID, because it normalizes first', () {
      // The charset copy talks about lowercase; the code does not enforce
      // it. The create request normalizes the same way, so what is sent
      // always matches what was validated.
      expect(CommunityNameValidator.validate('MyCommunity'), isNull);
      expect(CommunityNameValidator.validate('WORLDNEWS'), isNull);
    });

    test('surrounding whitespace is accepted and trimmed away', () {
      expect(CommunityNameValidator.validate('  worldnews  '), isNull);
    });

    test('a single character is valid', () {
      expect(CommunityNameValidator.validate('a'), isNull);
      expect(CommunityNameValidator.validate('7'), isNull);
    });

    test('a digits-only name is valid', () {
      expect(CommunityNameValidator.validate('2026'), isNull);
    });

    test('interior hyphens are valid', () {
      expect(CommunityNameValidator.validate('world-news'), isNull);
      expect(CommunityNameValidator.validate('a-b-c-d'), isNull);
      // Consecutive interior hyphens are allowed too.
      expect(CommunityNameValidator.validate('world--news'), isNull);
    });
  });

  group('validate - precedence between the rules', () {
    test('length beats charset when an input violates both', () {
      // Over the limit AND containing an underscore: the length rule is
      // checked first, so that is the message the user sees.
      final tooLongAndBadCharset = '${maxLengthName()}_';
      expect(
        tooLongAndBadCharset.length,
        greaterThan(CommunityNameValidator.maxLength),
      );
      expect(
        CommunityNameValidator.validate(tooLongAndBadCharset),
        lengthError,
      );
    });

    test('required beats everything for a whitespace-only name', () {
      expect(CommunityNameValidator.validate(' ' * 100), requiredMessage);
    });
  });
}
