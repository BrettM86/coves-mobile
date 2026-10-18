import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'B1 post viewer parses known capabilities without losing vote or save',
    () {
      final withVote = ViewerState.fromJson({
        'vote': 'up',
        'voteUri': 'at://did:plc:viewer/social.coves.community.vote/v1',
        'saved': true,
        'moderation': ['remove', 'label', 'frobnicate'],
      });
      expect(withVote.moderation, {
        ModerationCapability.remove,
        ModerationCapability.label,
      });
      expect(withVote.vote, 'up');
      expect(
        withVote.voteUri,
        'at://did:plc:viewer/social.coves.community.vote/v1',
      );
      expect(withVote.saved, isTrue);

      final restored = ViewerState.fromJson({
        'moderation': ['restore', 'retract-label'],
      });
      expect(restored.moderation, {
        ModerationCapability.restore,
        ModerationCapability.retractLabel,
      });
      expect(ViewerState.fromJson({}).moderation, isEmpty);
      expect(
        ViewerState.fromJson({'moderation': 'remove'}).moderation,
        isEmpty,
      );
    },
  );
}
