import 'package:coves_flutter/models/bluesky_profile_import.dart';
import 'package:flutter_test/flutter_test.dart';

typedef FieldViewValues = (
  BlueskyProfileField field,
  String? bluesky,
  String? blueskyImageUrl,
  bool covesIsEmpty,
);

List<FieldViewValues> _fieldValues(BlueskyProfileImport profileImport) => [
  for (final view in profileImport.fields)
    (view.field, view.bluesky, view.blueskyImageUrl, view.covesIsEmpty),
];

List<(BlueskyProfileField, bool)>? _choiceValues(
  List<BlueskyImportChoice>? choices,
) => choices
    ?.map((choice) => (choice.view.field, choice.initiallyChecked))
    .toList();

const _avatarUrl =
    'https://cdn.bsky.app/img/avatar/plain/did:plc:alice/bafkreiavatar@jpeg';
const _bannerUrl =
    'https://cdn.bsky.app/img/banner/plain/did:plc:alice/bafkreibanner@jpeg';

void main() {
  group('BlueskyProfileImport.fromJson', () {
    test('parses status and field entries, skipping unknown fields', () {
      final rows =
          <
            ({
              String label,
              Map<String, dynamic> json,
              BlueskyProfileImportStatus status,
              List<FieldViewValues> fields,
            })
          >[
            (
              label: 'offer with text, image and an unknown field',
              json: {
                'status': 'offer',
                'fields': [
                  {
                    'field': 'displayName',
                    'bluesky': 'Alice <b>Bold</b>',
                    'covesIsEmpty': true,
                  },
                  {
                    'field': 'pronouns',
                    'bluesky': 'she/her',
                    'covesIsEmpty': true,
                  },
                  {
                    'field': 'avatar',
                    'blueskyImageUrl': _avatarUrl,
                    'covesIsEmpty': false,
                  },
                ],
              },
              status: BlueskyProfileImportStatus.offer,
              fields: [
                (
                  BlueskyProfileField.displayName,
                  'Alice <b>Bold</b>',
                  null,
                  true,
                ),
                (BlueskyProfileField.avatar, null, _avatarUrl, false),
              ],
            ),
            (
              label: 'noBlueskyProfile with no fields',
              json: {'status': 'noBlueskyProfile', 'fields': <Object>[]},
              status: BlueskyProfileImportStatus.noBlueskyProfile,
              fields: [],
            ),
            (
              label: 'nothingToImport',
              json: {'status': 'nothingToImport', 'fields': <Object>[]},
              status: BlueskyProfileImportStatus.nothingToImport,
              fields: [],
            ),
            (
              label: 'dismissed',
              json: {
                'status': 'dismissed',
                'fields': [
                  {
                    'field': 'description',
                    'bluesky': 'Bio text',
                    'covesIsEmpty': false,
                  },
                ],
              },
              status: BlueskyProfileImportStatus.dismissed,
              fields: [
                (BlueskyProfileField.description, 'Bio text', null, false),
              ],
            ),
            (
              label: 'complete',
              json: {
                'status': 'complete',
                'fields': [
                  {
                    'field': 'banner',
                    'blueskyImageUrl': _bannerUrl,
                    'covesIsEmpty': true,
                  },
                ],
              },
              status: BlueskyProfileImportStatus.complete,
              fields: [(BlueskyProfileField.banner, null, _bannerUrl, true)],
            ),
          ];

      for (final row in rows) {
        final parsed = BlueskyProfileImport.fromJson(row.json);
        expect(parsed.status, row.status, reason: row.label);
        expect(_fieldValues(parsed), row.fields, reason: row.label);
      }
    });

    test('malformed shapes throw FormatException', () {
      final rows = <String, Map<String, dynamic>>{
        'unknown status': {'status': 'later', 'fields': <Object>[]},
        'missing status': {'fields': <Object>[]},
        'non-list fields': {'status': 'offer', 'fields': <String, Object>{}},
        'missing covesIsEmpty': {
          'status': 'offer',
          'fields': [
            {'field': 'displayName', 'bluesky': 'Alice'},
          ],
        },
        'non-bool covesIsEmpty': {
          'status': 'offer',
          'fields': [
            {
              'field': 'displayName',
              'bluesky': 'Alice',
              'covesIsEmpty': 'true',
            },
          ],
        },
        'non-string bluesky': {
          'status': 'offer',
          'fields': [
            {'field': 'displayName', 'bluesky': 42, 'covesIsEmpty': true},
          ],
        },
        'non-string blueskyImageUrl': {
          'status': 'offer',
          'fields': [
            {'field': 'avatar', 'blueskyImageUrl': 42, 'covesIsEmpty': true},
          ],
        },
      };

      for (final MapEntry(key: label, value: json) in rows.entries) {
        expect(
          () => BlueskyProfileImport.fromJson(json),
          throwsFormatException,
          reason: label,
        );
      }
    });
  });

  group('import choices', () {
    // One mixed fixture: displayName and avatar are empty on Coves,
    // description and banner are already set.
    const mixedFields = [
      BlueskyProfileImportFieldView(
        field: BlueskyProfileField.displayName,
        bluesky: 'Alice',
        covesIsEmpty: true,
      ),
      BlueskyProfileImportFieldView(
        field: BlueskyProfileField.description,
        bluesky: 'Bio text',
        covesIsEmpty: false,
      ),
      BlueskyProfileImportFieldView(
        field: BlueskyProfileField.avatar,
        blueskyImageUrl: _avatarUrl,
        covesIsEmpty: true,
      ),
      BlueskyProfileImportFieldView(
        field: BlueskyProfileField.banner,
        blueskyImageUrl: _bannerUrl,
        covesIsEmpty: false,
      ),
    ];

    test('automaticImportChoices offers only empty fields, all checked, '
        'and only for an offer', () {
      final rows =
          <
            ({
              String label,
              BlueskyProfileImport profileImport,
              List<(BlueskyProfileField, bool)>? expected,
            })
          >[
            (
              label: 'offer',
              profileImport: const BlueskyProfileImport(
                status: BlueskyProfileImportStatus.offer,
                fields: mixedFields,
              ),
              expected: [
                (BlueskyProfileField.displayName, true),
                (BlueskyProfileField.avatar, true),
              ],
            ),
            for (final status in [
              BlueskyProfileImportStatus.noBlueskyProfile,
              BlueskyProfileImportStatus.nothingToImport,
              BlueskyProfileImportStatus.dismissed,
              BlueskyProfileImportStatus.complete,
            ])
              (
                label: status.name,
                profileImport: BlueskyProfileImport(
                  status: status,
                  fields: mixedFields,
                ),
                expected: null,
              ),
            (
              label: 'offer with every Coves field already set',
              profileImport: const BlueskyProfileImport(
                status: BlueskyProfileImportStatus.offer,
                fields: [
                  BlueskyProfileImportFieldView(
                    field: BlueskyProfileField.description,
                    bluesky: 'Bio text',
                    covesIsEmpty: false,
                  ),
                ],
              ),
              expected: null,
            ),
          ];

      for (final row in rows) {
        expect(
          _choiceValues(automaticImportChoices(row.profileImport)),
          row.expected,
          reason: row.label,
        );
      }
    });

    test('settingsImportChoices lists every field checked when empty on '
        'Coves, and nothing when there is no Bluesky profile or nothing to '
        'import', () {
      const allFields = [
        (BlueskyProfileField.displayName, true),
        (BlueskyProfileField.description, false),
        (BlueskyProfileField.avatar, true),
        (BlueskyProfileField.banner, false),
      ];
      final rows =
          <(BlueskyProfileImportStatus, List<(BlueskyProfileField, bool)>?)>[
            (BlueskyProfileImportStatus.noBlueskyProfile, null),
            (BlueskyProfileImportStatus.nothingToImport, null),
            (BlueskyProfileImportStatus.dismissed, allFields),
            (BlueskyProfileImportStatus.complete, allFields),
            (BlueskyProfileImportStatus.offer, allFields),
          ];

      for (final (status, expected) in rows) {
        expect(
          _choiceValues(
            settingsImportChoices(
              BlueskyProfileImport(status: status, fields: mixedFields),
            ),
          ),
          expected,
          reason: status.name,
        );
      }
    });
  });
}
