import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/utils/display_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A plain `test`: no widgets, no fonts, just the palette.
  //
  // Characterization. `DisplayUtils.getFallbackColor` indexes this list by
  // `name.hashCode.abs() % length`, so both the ORDER and the LENGTH are
  // load-bearing: reordering, inserting or removing an entry silently
  // repaints existing accounts. Nothing caught that until now - the nine
  // avatar tests all compute their expected color by calling
  // `getFallbackColor` itself, so they agree with any permutation.
  //
  // Deliberately NOT asserting `getFallbackColor('somename') == <color>`.
  // `String.hashCode` carries no cross-SDK stability contract, so pinning a
  // specific name to a specific color would be a test that breaks on an SDK
  // upgrade for no defect. Pinning the list pins everything the app
  // actually controls.
  test('the avatar fallback palette keeps its order and length', () {
    expect(
      AppColors.avatarFallbacks,
      hasLength(6),
      reason: 'length is the modulus - changing it repaints every avatar',
    );
    expect(AppColors.avatarFallbacks, const [
      AppColors.coral,
      AppColors.teal,
      Color(0xFF9B59B6),
      Color(0xFF3498DB),
      Color(0xFF27AE60),
      Color(0xFFE74C3C),
    ]);

    // The alias call sites use must stay the same list, not a copy that can
    // drift.
    expect(DisplayUtils.fallbackColors, same(AppColors.avatarFallbacks));
  });
}
