import 'dart:convert';

import 'package:coves_flutter/models/facet.dart';

/// One string per facet: its byte range and the wire JSON of every feature
/// it carries, so a wrong range, wrong feature field, extra feature or extra
/// facet all fail
String describeFacet(RichTextFacet facet) {
  final range = '[${facet.index.byteStart},${facet.index.byteEnd})';
  final features = jsonEncode([
    for (final feature in facet.features) feature.toJson(),
  ]);
  return '$range $features';
}
