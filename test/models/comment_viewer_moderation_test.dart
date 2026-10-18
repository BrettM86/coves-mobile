import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('B2 comment viewer parses known capabilities and retains vote', () {
    final voted = CommentViewerState.fromJson({
      'vote': 'down',
      'voteUri': 'at://did:plc:viewer/social.coves.community.vote/v2',
      'moderation': ['remove', 'x'],
    });
    expect(voted.moderation, {ModerationCapability.remove});
    expect(voted.vote, 'down');
    expect(voted.voteUri, 'at://did:plc:viewer/social.coves.community.vote/v2');

    final restored = CommentViewerState.fromJson({
      'moderation': ['restore', 'label', 'retract-label'],
    });
    expect(restored.moderation, {
      ModerationCapability.restore,
      ModerationCapability.label,
      ModerationCapability.retractLabel,
    });
    expect(CommentViewerState.fromJson({}).moderation, isEmpty);
    expect(
      CommentViewerState.fromJson({'moderation': 'remove'}).moderation,
      isEmpty,
    );
  });
}
