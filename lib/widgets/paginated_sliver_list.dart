import 'package:flutter/material.dart';

import 'loading_error_states.dart';

/// A paginated [SliverList] with the feed's anti-jitter behaviour built in.
///
/// Every paginated surface in the app used to hand-roll this and each got a
/// different subset right. The invariants this widget carries:
///
/// 1. **the footer slot is always reserved** while [items] is non-empty, so
///    the child count never fluctuates as pagination toggles between idle,
///    loading and error — a fluctuating child count moves the scroll offset.
/// 2. **the idle footer is exactly as tall as the spinner**: both are sized
///    from [kInlineLoadingHeight].
/// 3. **the footer has a stable key**, so it is not rebuilt from scratch as
///    its contents change.
/// 4. **[SliverChildBuilderDelegate.findChildIndexCallback] maps item keys
///    and the footer**, which is what lets Flutter keep elements (and the
///    scroll offset) when a page is appended or prepended.
/// 5. **a failed refresh is visible**: screens gate their full-screen error
///    on an empty list, so [refreshError] carries that failure into the
///    footer when there are items on screen.
///
/// Items are wrapped in a [RepaintBoundary] keyed by [idOf] so scrolling
/// does not repaint neighbours and element identity survives list updates.
class PaginatedSliverList<T> extends StatelessWidget {
  const PaginatedSliverList({
    required this.items,
    required this.isLoadingMore,
    required this.hasMore,
    required this.onRetryLoadMore,
    required this.idOf,
    required this.itemBuilder,
    this.loadMoreError,
    this.refreshError,
    this.onRetryRefresh,
    this.endOfFeedWidget,
    this.emptyWidget,
    this.footerKey,
    super.key,
  }) : assert(
         refreshError == null || onRetryRefresh != null,
         'a refreshError needs an onRetryRefresh to recover with',
       );

  /// The loaded items.
  final List<T> items;

  /// Whether the next page is in flight (footer shows a spinner).
  final bool isLoadingMore;

  /// Whether another page exists (drives the end-of-feed footer).
  final bool hasMore;

  /// Pagination error, shown verbatim in the footer with a retry.
  final String? loadMoreError;

  /// First-page/refresh error to surface in the footer.
  ///
  /// Pass this only when the caller is *not* showing a full-screen error —
  /// i.e. when there are items on screen. Requires [onRetryRefresh].
  final String? refreshError;

  /// Invoked by the footer's retry button while [refreshError] is showing.
  final VoidCallback? onRetryRefresh;

  /// Invoked by the footer's retry button while [loadMoreError] is showing.
  final VoidCallback onRetryLoadMore;

  /// Stable identity for an item — its URI, DID, or other server id.
  final String Function(T item) idOf;

  /// Builds the row for an item. The [RepaintBoundary] and key are added
  /// by this widget.
  final Widget Function(BuildContext context, T item, int index) itemBuilder;

  /// Shown in the footer once [hasMore] is false. Without one the footer
  /// stays the invisible 80px spacer.
  final Widget? endOfFeedWidget;

  /// Shown instead of the list when [items] is empty.
  final Widget? emptyWidget;

  /// Overrides the footer's key. Must be a `ValueKey<String>` ending in
  /// `_footer` to stay consistent with the rest of the app.
  final Key? footerKey;

  Key get _footerKey =>
      footerKey ?? const ValueKey<String>('paginated_list_footer');

  @override
  Widget build(BuildContext context) {
    // Not a constructor assert: `endsWith` is not a constant expression, and
    // this constructor stays const.
    assert(
      footerKey == null ||
          (footerKey is ValueKey<String> &&
              (footerKey! as ValueKey<String>).value.endsWith('_footer')),
      'footerKey must be a ValueKey<String> ending in "_footer" '
      '(got $footerKey)',
    );

    if (items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: emptyWidget ?? const SizedBox.shrink(),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == items.length) {
            return KeyedSubtree(key: _footerKey, child: _buildFooter());
          }

          final item = items[index];
          return RepaintBoundary(
            key: ValueKey<String>(idOf(item)),
            child: itemBuilder(context, item, index),
          );
        },
        // The footer slot is reserved unconditionally: making it depend on
        // isLoadingMore/loadMoreError is exactly what causes the jitter.
        childCount: items.length + 1,
        findChildIndexCallback: (Key key) {
          if (key == _footerKey) {
            return items.length;
          }
          if (key is! ValueKey<String>) {
            return null;
          }
          final index = items.indexWhere((item) => idOf(item) == key.value);
          return index != -1 ? index : null;
        },
      ),
    );
  }

  Widget _buildFooter() {
    if (isLoadingMore) {
      return const InlineLoading();
    }

    final pageError = loadMoreError;
    if (pageError != null) {
      return InlineError(message: pageError, onRetry: onRetryLoadMore);
    }

    // A failed refresh with items on screen: the caller's full-screen error
    // is suppressed (it would blank content the user can still read), so
    // this is the only place the failure is visible.
    final refreshFailure = refreshError;
    if (refreshFailure != null) {
      return InlineError(message: refreshFailure, onRetry: onRetryRefresh!);
    }

    final endOfFeed = endOfFeedWidget;
    if (!hasMore && endOfFeed != null) {
      return endOfFeed;
    }

    // Idle: an invisible spacer the same height as the spinner, so the
    // list geometry does not change when loading starts.
    return const SizedBox(height: kInlineLoadingHeight);
  }
}
