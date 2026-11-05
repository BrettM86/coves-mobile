import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

/// Stands in for the tiles of [count] images still being prepared.
class PreparingImagesTile extends StatelessWidget {
  const PreparingImagesTile({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        key: const Key('image-attachment-preparing'),
        container: true,
        label: count == 1 ? 'Preparing image…' : 'Preparing $count images…',
        excludeSemantics: true,
        child: Container(
          width: 96,
          height: 96,
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: AppColors.backgroundTertiary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: SizedBox.square(
              dimension: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
