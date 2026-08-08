import 'dart:collection';

import 'comment.dart';

/// The comment-thread algebra: lookup, replacement, subtree merging, and the
/// decision of what a load-more-replies response actually produces.
///
/// A thin value wrapper over the `List<ThreadViewComment>` a thread is made
/// of. Pure by construction — no providers, no notifiers, no I/O, no
/// logging, no clock. Everything here is a function of its arguments, so it
/// needs no mocks to test directly, though today's coverage happens to
/// reach it through CommentsProvider's public surface instead.
///
/// What deliberately stays outside: the fetch, staleness/generation guards,
/// the anchored-response contract check, the empty-response pagination
/// clear, `notifyListeners`, and any read or write of the provider's own
/// comment list. Those are orchestration; this is algebra.
///
/// ## Reporting a missed replacement
///
/// [replaceNode] returns a `replaced` flag alongside the new tree rather
/// than leaving callers to infer "nothing matched" from list identity. The
/// flag says one thing and says it precisely; identity said two things at
/// once — "the URI is not in this tree" AND "the replacement was already
/// the node sitting there" — and a caller could not tell them apart. That
/// ambiguity is why [nodes] can now be an unmodifiable view: nothing
/// depends on it being the same instance any more.
///
/// ## Deliberate asymmetries
///
/// [mergeSubtree] has branches that answer the same question in opposite
/// ways, and [subtreeFromResponse] picks between appending and merging on a
/// cursor whose value the caller captured at a different moment than the
/// node it is paired with. Each of those looks like a bug and is not; each
/// is documented at the branch that makes the choice, and each is pinned by
/// a characterization test. Do not harmonise them here — if the product
/// decision changes, change it together with its test.
class CommentThreadTree {
  const CommentThreadTree(this._nodes);

  final List<ThreadViewComment> _nodes;

  /// The top-level comments of the thread, read-only.
  ///
  /// An unmodifiable view: this type calls itself pure, and handing out the
  /// caller's growable list let any holder `add` straight into a provider's
  /// live comment tree. Cheap — the view wraps, it does not copy.
  List<ThreadViewComment> get nodes => UnmodifiableListView(_nodes);

  /// The node with [uri] anywhere in the tree, at any depth, or null.
  ThreadViewComment? findByUri(String uri) {
    for (final node in _nodes) {
      final found = node.findByUri(uri);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  /// Whether a comment with [uri] exists anywhere in the tree.
  bool containsUri(String uri) => findByUri(uri) != null;

  /// This tree with the node matching [replacement]'s URI replaced, plus
  /// whether anything actually was.
  ///
  /// `replaced` is false when no node in the tree carries that URI — and
  /// also, in principle, when [replacement] is the very instance already
  /// sitting there, because [ThreadViewComment.replaceDescendant] returns
  /// `this` on a match it does not have to change. Callers must not read
  /// false as "the URI is absent"; it means "this tree is unchanged", which
  /// is the only thing the walk below can honestly report. Test-pinned in
  /// both directions.
  ///
  /// `tree` is `this` when nothing changed, so an unchanged result costs no
  /// allocation.
  ({CommentThreadTree tree, bool replaced}) replaceNode(
    ThreadViewComment replacement,
  ) {
    var changed = false;
    final mapped = <ThreadViewComment>[];
    for (final node in _nodes) {
      final result = node.replaceDescendant(replacement);
      if (!identical(result, node)) {
        changed = true;
      }
      mapped.add(result);
    }
    if (!changed) {
      return (tree: this, replaced: false);
    }
    return (tree: CommentThreadTree(mapped), replaced: true);
  }

  /// Merges a freshly fetched [fresh] subtree with the [existing] version of
  /// the same node already in the tree.
  ///
  /// Semantics: fresh data wins for node content/stats, but deeper branches
  /// hydrated earlier (via nested load-more) are preserved when they are
  /// absent from the fresh response only because of its depth/sibling
  /// truncation - absence from a truncated response does not mean deletion.
  /// When the fresh listing of a node's replies is complete (no hasMore),
  /// absence DOES mean deletion and the stale children are dropped.
  ///
  /// The branches below disagree with each other on purpose. Every such
  /// disagreement is tagged ASYMMETRY where it happens and is pinned by a
  /// test; read the tags rather than trusting a count here.
  static ThreadViewComment mergeSubtree(
    ThreadViewComment fresh,
    ThreadViewComment existing,
  ) {
    assert(
      fresh.comment.uri == existing.comment.uri,
      'mergeSubtree requires nodes with the same URI',
    );

    final freshReplies = fresh.replies;
    final existingReplies = existing.replies;

    // Fresh node hit the response's depth cutoff (no replies loaded) but we
    // already hydrated this branch - keep the existing branch and its
    // pagination state; take the fresh node's content/stats.
    if (freshReplies == null || freshReplies.isEmpty) {
      if (existingReplies == null || existingReplies.isEmpty) {
        // ASYMMETRY (deliberate, test-pinned): with nothing to preserve on
        // either side the fresh node is returned VERBATIM, which drops BOTH
        // existing.repliesCursor and existing.hasMore - the two fields the
        // branch just below goes out of its way to keep. The only
        // difference between the two cases is whether the existing branch
        // had children.
        return fresh;
      }
      // ASYMMETRY (deliberate, test-pinned): hasMore is taken from
      // EXISTING here, and from FRESH on the recursive branch below.
      return fresh.copyWith(
        replies: existingReplies,
        hasMore: existing.hasMore,
        repliesCursor: existing.repliesCursor,
      );
    }

    // Merge per-child by URI: children present in both are merged
    // recursively (so grandchildren expansions survive too).
    final existingByUri = <String, ThreadViewComment>{
      for (final reply in existingReplies ?? const <ThreadViewComment>[])
        reply.comment.uri: reply,
    };
    final mergedReplies = <ThreadViewComment>[
      for (final freshChild in freshReplies)
        existingByUri.containsKey(freshChild.comment.uri)
            ? mergeSubtree(
              freshChild,
              existingByUri.remove(freshChild.comment.uri)!,
            )
            : freshChild,
    ];

    // Children we had before that are missing from a sibling-truncated
    // fresh page are preserved (appended after the fresh ordering).
    //
    // ASYMMETRY (deliberate, test-pinned): when fresh.hasMore is false the
    // listing is complete, so the leftovers are DROPPED rather than
    // appended. The append order - fresh first, leftovers after - is
    // asserted too.
    if (fresh.hasMore && existingByUri.isNotEmpty) {
      mergedReplies.addAll(existingByUri.values);
    }

    // ASYMMETRY (deliberate, test-pinned): repliesCursor is carried over
    // from existing but hasMore is NOT - it comes from fresh, via
    // copyWith's untouched field. That is the opposite pairing to the
    // truncation branch above. It only shows at nested depth: for the node
    // the request was anchored at, subtreeFromResponse below overwrites
    // both from the response cursor, hiding whichever pairing was chosen.
    return fresh.copyWith(
      replies: mergedReplies,
      // Per-node reply cursors only come from earlier subtree fetches of
      // that node - the fresh response doesn't carry them, so keep ours.
      repliesCursor: existing.repliesCursor,
    );
  }

  /// The subtree a load-more-replies response resolves to.
  ///
  /// [fresh] is the response's anchored node, [existingNode] the version
  /// already in the tree (null when it is not there), [requestCursor] the
  /// cursor that was SENT and [responseCursor] the one that came back.
  ///
  /// [requestCursor] and [existingNode] are two independent observations
  /// that the caller deliberately makes at different times - the cursor
  /// before the fetch, the node after it - so they can disagree when a
  /// concurrent refetch drops the node mid-flight. This function must treat
  /// them as independent and does: that case is pinned by a test, and it
  /// falls to the first-page branch even though a cursor was sent. The
  /// temptation to collapse the two into one lookup lives at the call site
  /// in `CommentsProvider._doLoadMoreReplies`, which carries the matching
  /// warning.
  static ThreadViewComment subtreeFromResponse({
    required ThreadViewComment fresh,
    required ThreadViewComment? existingNode,
    required String? requestCursor,
    required String? responseCursor,
  }) {
    if (requestCursor != null && existingNode != null) {
      // Cursor page: append the new page's direct replies (deduplicated
      // by URI) to the ones already loaded instead of replacing them.
      final existingReplies =
          existingNode.replies ?? const <ThreadViewComment>[];
      final seenUris = existingReplies.map((r) => r.comment.uri).toSet();
      final newPage = (fresh.replies ?? const <ThreadViewComment>[]).where(
        (reply) => !seenUris.contains(reply.comment.uri),
      );
      return fresh.copyWith(
        replies: [...existingReplies, ...newPage],
        hasMore: responseCursor != null,
        repliesCursor: responseCursor,
      );
    }

    // First page: merge with the existing node (if any) so deeper
    // branches hydrated earlier survive the refetch.
    final merged =
        existingNode == null ? fresh : mergeSubtree(fresh, existingNode);
    return merged.copyWith(
      hasMore: responseCursor != null,
      repliesCursor: responseCursor,
    );
  }
}
