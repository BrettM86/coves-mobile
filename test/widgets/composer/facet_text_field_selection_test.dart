import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rebuilds on every change to [controller], as the create-post screen does
/// to keep its Post button current.
class _RebuildingHost extends StatefulWidget {
  const _RebuildingHost({required this.controller});

  final FacetEditingController controller;

  @override
  State<_RebuildingHost> createState() => _RebuildingHostState();
}

class _RebuildingHostState extends State<_RebuildingHost> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return FacetTextField(controller: widget.controller, minLines: 4);
  }
}

void main() {
  testWidgets('dragging a selection handle survives the parent rebuilding '
      'on every selection change', (tester) async {
    final controller = FacetEditingController(text: 'first line here');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.android),
        home: Scaffold(body: _RebuildingHost(controller: controller)),
      ),
    );

    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    Offset globalAt(int offset) => editable.localToGlobal(
      editable
          .getEndpointsForSelection(TextSelection.collapsed(offset: offset))
          .single
          .point,
    );

    // Long-press "first" to select it and show the handles
    final press = await tester.startGesture(globalAt(2));
    await tester.pump(const Duration(milliseconds: 700));
    await press.up();
    await tester.pumpAndSettle();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );

    // Drag the end handle to the end of "line". The Material end handle
    // hangs below and to the right of the selection's end, so (4, 8) from
    // that point lands inside it.
    final handle = globalAt(5) + const Offset(4, 8);
    final drag = await tester.startGesture(handle);
    await tester.pump(const Duration(milliseconds: 50));
    final distance = globalAt(10).dx - globalAt(5).dx;
    for (var step = 1; step <= 10; step++) {
      await drag.moveTo(handle + Offset(distance * step / 10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();

    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 10),
    );
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    expect(state.selectionOverlay?.handlesAreVisible, isTrue);
    expect(state.selectionOverlay?.toolbarIsVisible, isTrue);
  });
}
