import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../constants/app_colors.dart';
import '../providers/community_subscription_provider.dart';
import '../services/api_exceptions.dart';

/// Style variant for the join button.
enum CommunityJoinButtonStyle {
  /// Compact style used in hero cards — no icon, smaller padding.
  compact,

  /// Normal style used in list tiles — includes icon, animated container.
  normal,
}

/// Shared join/leave button for community widgets.
///
/// Accepts a [communityDid] and a [style] variant to adapt its appearance
/// for different contexts (hero cards vs list tiles). Uses
/// [CommunitySubscriptionProvider] for state management.
class CommunityJoinButton extends StatelessWidget {
  const CommunityJoinButton({
    required this.communityDid,
    this.style = CommunityJoinButtonStyle.normal,
    super.key,
  });

  final String communityDid;
  final CommunityJoinButtonStyle style;

  @override
  Widget build(BuildContext context) {
    return Consumer<CommunitySubscriptionProvider>(
      builder: (context, provider, _) {
        final isSubscribed = provider.isSubscribed(communityDid);
        final isPending = provider.isPending(communityDid);

        if (isPending) {
          return const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.teal,
            ),
          );
        }

        return GestureDetector(
          onTap: () => _onTap(context, provider),
          child: style == CommunityJoinButtonStyle.compact
              ? _buildCompact(isSubscribed)
              : _buildNormal(isSubscribed),
        );
      },
    );
  }

  Future<void> _onTap(
    BuildContext context,
    CommunitySubscriptionProvider provider,
  ) async {
    try {
      await provider.toggleSubscription(communityDid: communityDid);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } on Exception catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to update membership. Please try again.',
            ),
          ),
        );
      }
    }
  }

  Widget _buildCompact(bool isSubscribed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isSubscribed
            ? AppColors.teal.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.1),
        border: Border.all(
          color: isSubscribed
              ? AppColors.teal.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Text(
        isSubscribed ? 'Joined' : 'Join',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isSubscribed ? AppColors.teal : AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildNormal(bool isSubscribed) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isSubscribed
            ? AppColors.teal.withValues(alpha: 0.12)
            : Colors.transparent,
        border: Border.all(
          color: isSubscribed
              ? AppColors.teal
              : AppColors.textSecondary.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSubscribed ? Icons.check : Icons.add,
            size: 13,
            color: isSubscribed ? AppColors.teal : AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            isSubscribed ? 'Joined' : 'Join',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSubscribed ? AppColors.teal : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
