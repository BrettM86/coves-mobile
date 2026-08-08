import 'package:flutter/foundation.dart';

import '../models/comment.dart';
import '../models/community.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../providers/community_subscription_provider.dart';
import '../providers/vote_provider.dart';

/// One home for the viewer-state seeding every fetch path used to hand-roll.
///
/// A Coves response carries the signed-in user's own state alongside the
/// content: `post.viewer.vote` and `community.viewer.subscribed`. Eight call
/// sites used to walk that state into [VoteProvider] and
/// [CommunitySubscriptionProvider] themselves, each with its own traversal
/// and its own copy of the signed-in gate. Only the four provider-layer
/// sites carried a second gate: their vote provider was nullable. The four
/// widget sites resolved theirs with `context.read`, which throws rather
/// than returning null, so a wired-provider check never existed there.
///
/// This service owns three things: **the gates**, the **per-shape
/// traversal**, and — the one that is easy to miss — the **null-handling
/// policy for `subscribed`**, which is deliberately NOT uniform. Compare
/// [hydrateCommunityListSubscriptions], which coerces a null to false, with
/// [hydrateCommunitySubscription] and the subscription half of
/// [hydrateFeed], which skip. It deliberately does NOT own
///
///  * *which* items a caller hands over — the feed provider passes the raw
///    response while the pagination controllers pass only deduplicated new
///    items, and that difference is observable on cursor drift,
///  * *when* the caller notifies its listeners, or
///  * what a hydration *throw* does to the page that triggered it. The
///    callers genuinely disagree — some discard the page that just landed,
///    some keep it and report, one lets the error propagate untouched — and
///    each says which at its own call site. Not summarised here: an
///    enumeration this far from the code is how a doc goes stale.
///
/// Those stay with the callers on purpose. The method names below encode
/// the remaining semantic differences so they cannot be quietly "unified"
/// away.
///
/// Vote contract: [VoteProvider.applyServerVoteState] is the only
/// server-side write path, and it accepts ONLY snapshots the response being
/// processed actually delivered — never a cached or merge-preserved copy. A
/// null vote direction is still applied: that is how a vote removed on
/// another device gets cleared here, so no vote method below guards against
/// one. Subscriptions are the opposite — a null `subscribed` IS guarded,
/// and, as above, not identically by every method.
class ViewerStateHydrator {
  ViewerStateHydrator({
    required AuthProvider authProvider,
    VoteProvider? voteProvider,
    CommunitySubscriptionProvider? subscriptionProvider,
  }) : _authProvider = authProvider,
       _voteProvider = voteProvider,
       _subscriptionProvider = subscriptionProvider;

  final AuthProvider _authProvider;

  /// Nullable because several construction sites are wired without votes
  /// (defensively, or because the surface has none). A null provider makes
  /// every vote method a no-op.
  final VoteProvider? _voteProvider;

  /// Nullable for the same reason, plus the surfaces that only ever hydrate
  /// votes.
  final CommunitySubscriptionProvider? _subscriptionProvider;

  bool _warnedMissingVotes = false;
  bool _warnedMissingSubscriptions = false;

  /// A copy of this hydrator bound to [authProvider], keeping the same
  /// collaborators.
  ///
  /// UserProfileProvider swaps its AuthProvider at runtime. Before the auth
  /// gate moved in here it was read at CALL time, so a swap took effect
  /// immediately; a hydrator captured at construction would instead keep
  /// gating on the old instance forever. Rebinding through this method
  /// restores the original behaviour without exposing the collaborators.
  ViewerStateHydrator withAuthProvider(AuthProvider authProvider) {
    return ViewerStateHydrator(
      authProvider: authProvider,
      voteProvider: _voteProvider,
      subscriptionProvider: _subscriptionProvider,
    );
  }

  /// The vote provider to write through, or null when this hydrator must
  /// not touch votes.
  ///
  /// The two reasons for null are not equally innocent. Signed out is a
  /// STATE — nothing to hydrate, stay quiet. A missing provider while
  /// signed in is a WIRING BUG, and a silent one: every vote site becomes a
  /// permanent no-op, so hearts never light and nothing anywhere complains.
  /// It is reported once per hydrator, in debug builds only, so release
  /// behaviour stays byte-identical.
  ///
  /// Deliberately not an `assert`: the characterization net pins a
  /// fully-unwired hydrator as a silent no-op, so a throwing assert would
  /// fail those tests rather than surface a real defect.
  VoteProvider? get _votes {
    if (!_authProvider.isAuthenticated) {
      return null;
    }
    final provider = _voteProvider;
    if (provider == null) {
      assert(() {
        if (!_warnedMissingVotes) {
          _warnedMissingVotes = true;
          debugPrint(
            '⚠️ ViewerStateHydrator: no VoteProvider wired - vote state '
            'from server responses is being silently discarded for this '
            'surface',
          );
        }
        return true;
      }(), 'debug-only diagnostic');
    }
    return provider;
  }

  /// The subscription provider to write through, or null when this hydrator
  /// must not touch subscriptions.
  ///
  /// Same reasoning as [_votes]: silent when signed out, one debug-only
  /// warning when signed in without a provider.
  CommunitySubscriptionProvider? get _subscriptions {
    if (!_authProvider.isAuthenticated) {
      return null;
    }
    final provider = _subscriptionProvider;
    if (provider == null) {
      assert(() {
        if (!_warnedMissingSubscriptions) {
          _warnedMissingSubscriptions = true;
          debugPrint(
            '⚠️ ViewerStateHydrator: no CommunitySubscriptionProvider wired '
            '- subscription state from server responses is being silently '
            'discarded for this surface',
          );
        }
        return true;
      }(), 'debug-only diagnostic');
    }
    return provider;
  }

  /// Votes *and* community subscriptions for a page of feed items.
  ///
  /// Serves site 1 ([MultiFeedProvider]'s discover/for-you fetch) and site 2
  /// (the community feed screen's page hook).
  ///
  /// Which items reach this method is the caller's call and is NOT the same
  /// everywhere: site 1 passes the raw response feed, site 2 passes the
  /// pagination controller's deduplicated new items. That divergence (D3) is
  /// load bearing on cursor drift and must stay with the callers.
  void hydrateFeed(Iterable<FeedViewPost> feed) {
    _hydrateFeedVotes(feed);
    _hydrateFeedSubscriptions(feed);
  }

  /// Votes only for a page of feed items, leaving community subscriptions
  /// untouched even though `post.community.viewer.subscribed` is right there
  /// in the same payload.
  ///
  /// Serves site 3 (profile posts). This method exists to preserve
  /// divergence D1: profile posts have never seeded subscriptions. Keeping
  /// it separate from [hydrateFeed] makes that a visible decision instead of
  /// an accident of which provider happened to be wired in.
  void hydrateFeedVotesOnly(Iterable<FeedViewPost> feed) =>
      _hydrateFeedVotes(feed);

  /// The vote snapshot on a single cold-loaded post.
  ///
  /// Serves site 6 ([PostDetailLoader]). That caller resolves its providers
  /// *inside* its own auth gate so provider-less widget trees never look
  /// them up; the gate here is a second, independent check and does not
  /// replace it.
  void hydratePost(PostView post) {
    final voteProvider = _votes;
    if (voteProvider == null) {
      return;
    }
    _applyPostVote(voteProvider, post);
  }

  /// Vote snapshots for a flat list of comments — no nested replies.
  ///
  /// Serves site 4 (profile comments, which the API returns flat). Use
  /// [hydrateCommentTree] for threaded responses.
  void hydrateComments(Iterable<CommentView> comments) {
    final voteProvider = _votes;
    if (voteProvider == null) {
      return;
    }
    for (final comment in comments) {
      _applyCommentVote(voteProvider, comment);
    }
  }

  /// Vote snapshots for a comment tree, recursing through every reply at
  /// every depth.
  ///
  /// Serves site 5 ([CommentsProvider]) for both the thread load and the
  /// load-more-replies subtree.
  ///
  /// Callers must pass ONLY the nodes the response delivered. The subtree
  /// merge preserves earlier-hydrated branches whose snapshots are old;
  /// re-applying those could roll back a vote the server has since confirmed
  /// through another surface.
  void hydrateCommentTree(Iterable<ThreadViewComment> nodes) {
    final voteProvider = _votes;
    if (voteProvider == null) {
      return;
    }
    for (final node in nodes) {
      _applyThreadCommentVote(voteProvider, node);
    }
  }

  /// Subscription snapshots for a list of communities.
  ///
  /// Serves site 7 (the communities discovery screen). Preserves the list
  /// half of divergence D2: a community whose `viewer` is null is skipped
  /// entirely, but a *present* viewer with a null `subscribed` is coerced to
  /// false. [hydrateCommunitySubscription] treats that same input the
  /// opposite way, on purpose.
  void hydrateCommunityListSubscriptions(
    Iterable<CommunityView> communities,
  ) {
    final subscriptionProvider = _subscriptions;
    if (subscriptionProvider == null) {
      return;
    }
    for (final community in communities) {
      final viewer = community.viewer;
      if (viewer == null) {
        continue;
      }
      subscriptionProvider.setInitialSubscriptionState(
        communityDid: community.did,
        isSubscribed: viewer.subscribed ?? false,
      );
    }
  }

  /// The subscription snapshot on a single community.
  ///
  /// Serves site 8 (the community feed screen's header load). Preserves the
  /// other half of divergence D2: this site skips whenever `subscribed` is
  /// null rather than coercing it to false, so a snapshot that says nothing
  /// leaves known state alone.
  void hydrateCommunitySubscription(CommunityView community) {
    final subscriptionProvider = _subscriptions;
    if (subscriptionProvider == null) {
      return;
    }
    final subscribed = community.viewer?.subscribed;
    if (subscribed == null) {
      return;
    }
    subscriptionProvider.setInitialSubscriptionState(
      communityDid: community.did,
      isSubscribed: subscribed,
    );
  }

  void _hydrateFeedVotes(Iterable<FeedViewPost> feed) {
    final voteProvider = _votes;
    if (voteProvider == null) {
      return;
    }
    for (final feedItem in feed) {
      _applyPostVote(voteProvider, feedItem.post);
    }
  }

  void _hydrateFeedSubscriptions(Iterable<FeedViewPost> feed) {
    final subscriptionProvider = _subscriptions;
    if (subscriptionProvider == null) {
      return;
    }
    for (final feedItem in feed) {
      final community = feedItem.post.community;
      final subscribed = community.viewer?.subscribed;
      if (subscribed == null) {
        continue;
      }
      subscriptionProvider.setInitialSubscriptionState(
        communityDid: community.did,
        isSubscribed: subscribed,
      );
    }
  }

  void _applyPostVote(VoteProvider voteProvider, PostView post) {
    final viewer = post.viewer;
    voteProvider.applyServerVoteState(
      postUri: post.uri,
      voteDirection: viewer?.vote,
      voteUri: viewer?.voteUri,
    );
  }

  void _applyCommentVote(VoteProvider voteProvider, CommentView comment) {
    final viewer = comment.viewer;
    voteProvider.applyServerVoteState(
      postUri: comment.uri,
      voteDirection: viewer?.vote,
      voteUri: viewer?.voteUri,
    );
  }

  void _applyThreadCommentVote(
    VoteProvider voteProvider,
    ThreadViewComment node,
  ) {
    _applyCommentVote(voteProvider, node.comment);

    final replies = node.replies;
    if (replies == null) {
      return;
    }
    for (final reply in replies) {
      _applyThreadCommentVote(voteProvider, reply);
    }
  }
}
