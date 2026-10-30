import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a lone regional indicator inserted at the start re-pairs flags far '
      'from the edit and the far range snaps to the new clusters', () {
    // Each regional indicator is 2 UTF-16 units.
    // 🇺🇸=[0,4) 🇫🇷=[4,8) 🇩🇪=[8,12).
    // Inserting 🇺 at 0 then re-pairs every flag:
    // 🇺🇺=[0,4) 🇸🇫=[4,8) 🇷🇩=[8,12) 🇪=[12,14).
    // Bold shifts to [10,14), which splits 🇷🇩, so its start snaps down to 8.
    final controller = FacetEditingController(text: '🇺🇸🇫🇷🇩🇪')
      ..selection = const TextSelection(baseOffset: 8, extentOffset: 12)
      ..toggleInline(InlineFormat.bold)
      ..selection = const TextSelection.collapsed(offset: 0)
      ..value = const TextEditingValue(
        text: '🇺🇺🇸🇫🇷🇩🇪',
        selection: TextSelection.collapsed(offset: 2),
      );

    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 8, 14),
    ]);
  });
}
