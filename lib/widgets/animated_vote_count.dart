import 'package:flutter/material.dart';

import '../utils/display_utils.dart';

/// Compact vote score with the frontend's 400ms number transition.
class AnimatedVoteCount extends StatelessWidget {
  const AnimatedVoteCount({
    required this.count,
    required this.style,
    super.key,
  });

  final int count;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      DisplayUtils.formatCount(count),
      key: ValueKey(count),
      style: style,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return text;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final outgoing = animation.status == AnimationStatus.reverse;
          final progress = Curves.easeOutBack.transform(
            outgoing ? 1 - animation.value : animation.value,
          );
          return Opacity(
            opacity: (outgoing ? 1 - progress : progress).clamp(0, 1),
            child: Transform.translate(
              offset: Offset(
                0,
                outgoing ? 10 * progress : -10 * (1 - progress),
              ),
              child: child,
            ),
          );
        },
      ),
      child: text,
    );
  }
}
