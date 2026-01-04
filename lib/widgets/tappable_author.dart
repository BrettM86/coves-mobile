import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Wraps a child widget to make it navigate to an author's profile on tap.
///
/// This widget encapsulates the common pattern of tapping an author's avatar
/// or name to navigate to their profile page. It handles the InkWell styling
/// and navigation logic.
///
/// Example:
/// ```dart
/// TappableAuthor(
///   authorDid: post.author.did,
///   child: Row(
///     children: [
///       AuthorAvatar(author: post.author),
///       Text('@${post.author.handle}'),
///     ],
///   ),
/// )
/// ```
class TappableAuthor extends StatelessWidget {
  const TappableAuthor({
    required this.authorDid,
    required this.child,
    this.borderRadius = 4.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    super.key,
  });

  /// The DID of the author to navigate to
  final String authorDid;

  /// The child widget to wrap (typically avatar + handle row)
  final Widget child;

  /// Border radius for the InkWell splash effect
  final double borderRadius;

  /// Padding around the child
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/profile/$authorDid'),
      borderRadius: BorderRadius.circular(borderRadius),
      child: Padding(padding: padding, child: child),
    );
  }
}
