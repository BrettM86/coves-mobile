import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Comments section header with sort dropdown
///
/// Displays:
/// - Comment count with pluralization
/// - Sort dropdown (Hot/Top/New)
/// - Empty state when no comments
class CommentsHeader extends StatelessWidget {
  const CommentsHeader({
    required this.commentCount,
    required this.currentSort,
    required this.onSortChanged,
    super.key,
  });

  final int commentCount;
  final String currentSort;
  final void Function(String) onSortChanged;

  static const _sortOptions = ['hot', 'top', 'new'];
  static const _sortLabels = ['Hot', 'Top', 'New'];

  /// Get icon for a sort type
  IconData _getSortIcon(String sortType) {
    switch (sortType) {
      case 'hot':
        return Icons.local_fire_department;
      case 'top':
        return Icons.auto_awesome_rounded;
      case 'new':
        return Icons.fiber_new;
      default:
        return Icons.sort;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show empty state if no comments
    if (commentCount == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No comments yet',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textPrimary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Be the first to comment',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    // Show comment count and sort dropdown
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Comment count with dropdown
          Expanded(
            child: PopupMenuButton<String>(
              initialValue: currentSort,
              onSelected: onSortChanged,
              offset: const Offset(0, 40),
              color: AppColors.backgroundSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _getSortIcon(currentSort),
                    color: AppColors.textSecondary,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$commentCount '
                    '${commentCount == 1 ? 'Comment' : 'Comments'}',
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_drop_down,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
              itemBuilder:
                  (context) => [
                    for (var i = 0; i < _sortOptions.length; i++)
                      PopupMenuItem<String>(
                        value: _sortOptions[i],
                        child: Row(
                          children: [
                            Icon(
                              _getSortIcon(_sortOptions[i]),
                              color: AppColors.textPrimary,
                              size: 18,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _sortLabels[i],
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                            if (currentSort == _sortOptions[i])
                              const Icon(
                                Icons.check,
                                color: AppColors.primary,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                  ],
            ),
          ),
        ],
      ),
    );
  }
}
