import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Wraps a child widget to make it navigate to a community's feed on tap.
///
/// This widget encapsulates the common pattern of tapping a community's avatar
/// or name to navigate to its feed page. It handles the InkWell styling
/// and navigation logic.
///
/// Example:
/// ```dart
/// TappableCommunity(
///   communityDid: post.community.did,
///   child: Row(
///     children: [
///       CommunityAvatar(community: post.community),
///       Text(post.community.name),
///     ],
///   ),
/// )
/// ```
class TappableCommunity extends StatelessWidget {
  const TappableCommunity({
    required this.communityDid,
    required this.child,
    this.borderRadius = 4.0,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// The DID of the community to navigate to
  final String communityDid;

  /// The child widget to wrap (typically avatar + name row)
  final Widget child;

  /// Border radius for the InkWell splash effect
  final double borderRadius;

  /// Padding around the child
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/community/$communityDid'),
      borderRadius: BorderRadius.circular(borderRadius),
      child: Padding(padding: padding, child: child),
    );
  }
}
