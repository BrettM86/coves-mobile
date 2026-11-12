enum BlueskyProfileImportStatus {
  noBlueskyProfile,
  nothingToImport,
  dismissed,
  complete,
  offer,
}

enum BlueskyProfileField {
  displayName,
  description,
  avatar,
  banner;

  /// The field's name in the import lexicon.
  String get wireName => name;

  /// The field named [wireName], or null for a field this client doesn't know.
  static BlueskyProfileField? fromWireName(String wireName) {
    for (final field in values) {
      if (field.wireName == wireName) {
        return field;
      }
    }
    return null;
  }
}

class BlueskyProfileImportFieldView {
  const BlueskyProfileImportFieldView({
    required this.field,
    required this.covesIsEmpty,
    this.bluesky,
    this.blueskyImageUrl,
  });

  final BlueskyProfileField field;
  final String? bluesky;
  final String? blueskyImageUrl;
  final bool covesIsEmpty;
}

class BlueskyProfileImport {
  const BlueskyProfileImport({required this.status, required this.fields});

  /// Parses a getBlueskyProfileImport response. Throws [FormatException] on
  /// an unknown status or a malformed shape; skips unknown field names.
  factory BlueskyProfileImport.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'];
    final status = BlueskyProfileImportStatus.values
        .where((value) => value.name == statusName)
        .firstOrNull;
    if (status == null) {
      throw FormatException('Unknown Bluesky import status: $statusName');
    }
    final entries = json['fields'];
    if (entries is! List) {
      throw const FormatException('Bluesky import fields must be a list');
    }
    final fields = <BlueskyProfileImportFieldView>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Bluesky import field must be an object');
      }
      final covesIsEmpty = entry['covesIsEmpty'];
      final bluesky = entry['bluesky'];
      final blueskyImageUrl = entry['blueskyImageUrl'];
      if (covesIsEmpty is! bool ||
          (bluesky != null && bluesky is! String) ||
          (blueskyImageUrl != null && blueskyImageUrl is! String)) {
        throw const FormatException('Malformed Bluesky import field');
      }
      final fieldName = entry['field'];
      final field = fieldName is String
          ? BlueskyProfileField.fromWireName(fieldName)
          : null;
      if (field == null) {
        continue;
      }
      fields.add(
        BlueskyProfileImportFieldView(
          field: field,
          bluesky: bluesky as String?,
          blueskyImageUrl: blueskyImageUrl as String?,
          covesIsEmpty: covesIsEmpty,
        ),
      );
    }
    return BlueskyProfileImport(status: status, fields: fields);
  }

  final BlueskyProfileImportStatus status;
  final List<BlueskyProfileImportFieldView> fields;
}

class BlueskyImportChoice {
  const BlueskyImportChoice({
    required this.view,
    required this.initiallyChecked,
  });

  final BlueskyProfileImportFieldView view;
  final bool initiallyChecked;
}

/// The choices for the automatic offer after sign-in: only fields empty on
/// Coves, all checked. Null when there is nothing to offer.
List<BlueskyImportChoice>? automaticImportChoices(
  BlueskyProfileImport profileImport,
) {
  if (profileImport.status != BlueskyProfileImportStatus.offer) {
    return null;
  }
  final choices = [
    for (final view in profileImport.fields)
      if (view.covesIsEmpty)
        BlueskyImportChoice(view: view, initiallyChecked: true),
  ];
  return choices.isEmpty ? null : choices;
}

/// The choices for the Edit Profile import: every field, checked when empty
/// on Coves. Null when there is no Bluesky profile or nothing to import.
List<BlueskyImportChoice>? settingsImportChoices(
  BlueskyProfileImport profileImport,
) {
  switch (profileImport.status) {
    case BlueskyProfileImportStatus.noBlueskyProfile:
    case BlueskyProfileImportStatus.nothingToImport:
      return null;
    case BlueskyProfileImportStatus.dismissed:
    case BlueskyProfileImportStatus.complete:
    case BlueskyProfileImportStatus.offer:
      return [
        for (final view in profileImport.fields)
          BlueskyImportChoice(view: view, initiallyChecked: view.covesIsEmpty),
      ];
  }
}
