import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The distinct unknown feature numbered [i] in a fixture.
UnknownFacetFeature unknown(int i) =>
    UnknownFacetFeature(data: {r'$type': 'com.example.u$i'});

/// The wire JSON of [unknown] numbered [i].
Map<String, dynamic> unknownJson(int i) => {r'$type': 'com.example.u$i'};

/// The unknown features numbered [first] through [last], inclusive.
List<UnknownFacetFeature> unknowns(int first, int last) => [
  for (var i = first; i <= last; i++) unknown(i),
];

/// The wire JSON of [unknowns] numbered [first] through [last], inclusive.
List<Map<String, dynamic>> unknownsJson(int first, int last) => [
  for (var i = first; i <= last; i++) unknownJson(i),
];

RichTextFacet facet(int byteStart, int byteEnd, List<FacetFeature> features) =>
    RichTextFacet(
      index: ByteSlice(byteStart: byteStart, byteEnd: byteEnd),
      features: features,
    );

Map<String, dynamic> facetJson(
  int byteStart,
  int byteEnd,
  List<Map<String, dynamic>> features,
) => {
  'index': {'byteStart': byteStart, 'byteEnd': byteEnd},
  'features': features,
};

/// Loads the literal wire [facets] over [content].
FacetEditingController load(String content, List<Map<String, dynamic>> facets) {
  final controller = FacetEditingController.fromRecord(content, [
    for (final facet in facets) RichTextFacet.fromJson(facet),
  ]);
  addTearDown(controller.dispose);
  return controller;
}

/// Replaces the whole value with [text] and a collapsed caret at [caret],
/// the way a keystroke reaches the controller.
void edit(FacetEditingController controller, String text, int caret) {
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret),
  );
}

/// Delivers [text] with an active composing [composing] region.
void compose(
  FacetEditingController controller,
  String text,
  int caret,
  TextRange composing,
) {
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret),
    composing: composing,
  );
}

void caretAt(FacetEditingController controller, int offset) {
  controller.selection = TextSelection.collapsed(offset: offset);
}

void select(FacetEditingController controller, int start, int end) {
  controller.selection = TextSelection(baseOffset: start, extentOffset: end);
}
