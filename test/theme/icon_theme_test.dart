import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/widgets/icons/animated_heart_icon.dart';
import 'package:coves_flutter/widgets/icons/reply_icon.dart';
import 'package:coves_flutter/widgets/icons/share_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/theme_pump.dart';

void main() {
  // `testWidgets`, never a plain `test`: AppTheme.dark pulls fonts through
  // google_fonts, whose loader only stays inert inside the fake-async zone.
  testWidgets('AppTheme.dark paints unstyled action icons on-palette', (
    tester,
  ) async {
    // The reply, share and heart icons each fall back to
    // `Theme.of(context).iconTheme.color` when given no explicit color, so
    // the theme is the single lever controlling how bright a post card's
    // action row reads.
    late ThemeData theme;
    await pumpUnderAppTheme(
      tester,
      Builder(
        builder: (context) {
          theme = Theme.of(context);
          return const SizedBox.shrink();
        },
      ),
    );

    expect(
      theme.iconTheme.color,
      AppColors.textPrimary,
      reason: 'unstyled icons must read as bright as primary text',
    );

    // Assert it end to end as well: that the theme carries the color is
    // weaker than that the icons actually paint in it. Each painter ends in
    // `canvas.drawPath` with a Paint carrying the resolved color, which the
    // `paints` matcher can read straight off the recorded display list.
    await pumpUnderAppTheme(tester, const ReplyIcon());
    expect(
      find.byType(ReplyIcon),
      paints..path(color: AppColors.textPrimary),
    );

    await pumpUnderAppTheme(tester, const ShareIcon());
    expect(
      find.byType(ShareIcon),
      paints..path(color: AppColors.textPrimary),
    );

    await pumpUnderAppTheme(tester, const AnimatedHeartIcon(isLiked: false));
    expect(
      find.byType(AnimatedHeartIcon),
      paints..path(color: AppColors.textPrimary),
    );
  });

  // A separate contract from the icon *theme* color above: this is the
  // widget's own default for the liked state.
  testWidgets('a liked heart defaults to the vote color', (tester) async {
    // No `likedColor`. Every call site passes one today, so the default is
    // unreachable in practice - which is exactly why it drifted to a third
    // red that is neither the vote color nor the error color. A default is
    // a decision; this one should be the same decision the call sites make.
    await pumpUnderAppTheme(tester, const AnimatedHeartIcon(isLiked: true));

    expect(
      find.byType(AnimatedHeartIcon),
      paints..path(color: AppColors.voteLiked),
    );
  });
}
