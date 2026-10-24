import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every semantics node in the pumped tree that a screen reader could
/// activate, in traversal order.
///
/// A control is only reachable if the node carrying its label is also the
/// node carrying the tap, so the labels of the activatable nodes are the
/// whole story.
List<String> activatableLabels(WidgetTester tester, Finder anyNode) => [
  for (final node in activatableNodes(tester, anyNode)) node.label,
];

/// The semantics nodes behind [activatableLabels], so a test can fire the
/// tap a screen reader would on one of them.
List<SemanticsNode> activatableNodes(WidgetTester tester, Finder anyNode) => [
  for (final node in allSemanticsNodes(tester, anyNode))
    if (node.getSemanticsData().hasAction(SemanticsAction.tap)) node,
];

/// Every semantics node in the pumped tree, in traversal order, starting
/// from the root above the node [anyNode] locates.
List<SemanticsNode> allSemanticsNodes(WidgetTester tester, Finder anyNode) {
  var root = tester.getSemantics(anyNode);
  while (root.parent != null) {
    root = root.parent!;
  }

  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return nodes;
}

/// Fires the screen-reader activation gesture on the node [finder] locates.
void activateBySemantics(WidgetTester tester, Finder finder) {
  activateSemanticsNode(tester.getSemantics(finder));
}

/// Fires the screen-reader activation gesture on [node].
void activateSemanticsNode(SemanticsNode node) {
  node.owner!.performAction(node.id, SemanticsAction.tap);
}
