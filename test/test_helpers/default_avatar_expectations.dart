import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Circles painted inside [scope] in [argb].
Finder tintedCircleIn(Finder scope, int argb) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate((widget) {
    if (widget is! DecoratedBox) {
      return false;
    }
    final decoration = widget.decoration;
    return decoration is BoxDecoration &&
        decoration.shape == BoxShape.circle &&
        decoration.color?.toARGB32() == argb;
  }),
);

/// Images inside [scope] requesting a default-avatar picture.
Finder defaultAvatarImagesIn(Finder scope) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is CachedNetworkImage &&
        widget.imageUrl.contains('/img/default-avatars/'),
  ),
);

/// Asserts the avatar at [userAvatar] draws a default avatar: its image
/// requests [url], and its circle is painted in [tint].
///
/// Surface tests cannot inject a cache manager, and every image request
/// fails under testWidgets, so the tinted circle is what shows.
void expectDefaultAvatar(
  Finder userAvatar, {
  required String url,
  required int tint,
}) {
  expect(userAvatar, findsOneWidget, reason: 'one avatar is under test');
  expect(
    find.descendant(
      of: userAvatar,
      matching: find.byWidgetPredicate(
        (widget) => widget is CachedNetworkImage && widget.imageUrl == url,
      ),
    ),
    findsOneWidget,
    reason: 'an avatar with no picture requests its DID default $url',
  );
  expect(
    tintedCircleIn(userAvatar, tint),
    findsWidgets,
    reason:
        'the default is drawn on a circle in the DID tint '
        '0x${tint.toRadixString(16).toUpperCase()}',
  );
}
