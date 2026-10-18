# PRD: Mobile admin moderation tools and modlog (Phase B)

Status: draft 2026-10-04. Builds on Phase A (branch `tdd/moderation-read`: read-side tombstones, placeholder copy, moderator NSFW, `lib/models/moderation.dart`).
Sources: backend `~/Code/coves/docs/PRD_ADMIN_MODERATION.md`; handoff doc "Coves Moderation: Client Handoff"; backend viewer-moderation contract (coves branch `tdd/viewer-moderation`, unmerged as of 2026-10-04).

## Goal

Server admins can moderate from the app: remove and restore posts and comments, mark posts NSFW and retract that label, and read the moderation log. Everyone can read the public moderation log.

## Decisions (user, 2026-10-04)

- Admin tools are native on mobile, not a link to web.
- Admin capability comes from the server, never a client role check: per item `viewer.moderation`; per viewer `social.coves.actor.getViewerAuthority`. Do not probe admin endpoints for `Forbidden`. The hardcoded `kAdminHandles` list is not used for moderation.
- Post tombstone copy is `[Removed by server admin]` (no title: the server sends none by design).
- Public modlog entry point: the bottom of the Explore (communities discovery) screen.
- Restore is offered from the modlog entry, the removed-post tombstone and the removed-comment placeholder.
- Remove flow: pick a reason, optionally add a private note, then press Remove.
- Modlog filters: action (remove/restore) and community.

## Backend contract

Per item, `viewer.moderation`: the actions the signed-in viewer may take. Absent for signed-out viewers and non-admins (no menu). Show only listed actions.
- Live post without this server's NSFW label: `["remove","label"]`; with it: `["remove","retract-label"]`.
- Live comment: `["remove"]`. Removed-comment placeholder and `moderatedPost` tombstone: `["restore"]`.
- The `moderatedPost` tombstone's `viewer` is the narrow `social.coves.community.post.defs#moderatedPostViewerState` (`{"moderation":["restore"]}` only, no `saved`), not the full post viewerState; parse it separately on `PostGetModerated`.
- Present on feeds (incl. Discover), threads/comments, post.get, author feeds.

Per viewer: `GET social.coves.actor.getViewerAuthority` → `{instanceAdmin: bool}`; 401 `AuthRequired` signed out; non-admins `false`; 503 on session-store failure; ignore unknown keys.

Admin actions (POST, admin-only, all return `{outcome: applied|unchanged, state, action?}`):
1. On tap, `GET social.coves.moderation.getSubjectState?subject=<at-uri>` → `state.version`, `moderation`, `recordState` (present|deleted|unavailable), `currentSubject` (strongRef), `localRemoval` (action ref), `localLabels[{value, action}]`.
2. Call the procedure with `expectedVersion = state.version` and a fresh `idempotencyKey` (reuse only to retry the same submission).
- `removeContent{subject: strongRef, expectedVersion, idempotencyKey, reason, privateNote?}`: posts and comments; all six reasons.
- `restoreContent{actionId (from localRemoval), expectedVersion, idempotencyKey, reason, reviewedSubject? (required when record present), privateNote?}`: reasons exclude doxing and illegal content.
- `labelContent{subject, labelValue: "nsfw", expectedVersion, idempotencyKey, reason?, privateNote?}`: posts only; doxing/illegal-content reasons rejected.
- `retractContentLabel{actionId (from localLabels), expectedVersion, idempotencyKey, reason?, reviewedSubject?, privateNote?}`.
- `privateNote` ≤ 1,000 grapheme clusters and ≤ 10,000 UTF-8 bytes (lexicon `maxGraphemes`/`maxLength`).
- Reasons: `social.coves.moderation.defs#reason{Spam,Harassment,Doxing,IllegalContent,RuleViolation,ModeratorDiscretion}`.
- Errors → user message: `StateConflict` (someone acted first: reload and confirm again), `ContentChanged` (author edited it: show the new version), `IdempotencyConflict` (new key), `DecisionNotFound`/`InvalidDecision` (gone: reload), `ModerationUnavailable` (temporary: retry), `Forbidden` (no longer an admin: hide tools), `UnsupportedReason`/`UnsupportedLabel`/`InvalidRequest` (client bug).

Modlog:
- Public `GET social.coves.moderation.listActions` (auth optional, changes nothing): `limit` ≤ 100, `cursor`, `action` (remove|restore), `community` (DID, handle, name or name@instance), plus `subject`, `collection`, `actor`, `since`, `until` (backend inventory). Mobile sends only `limit`, `cursor`, `action`, `community` and `subject`. Output `{actions: actionView[], cursor?}`; no cursor = end.
- Entry: `ref` (`serviceDid` + `actionId`; models keep the full action ref here and in `reverses`, `localRemoval` and `localLabels`), `action`, `createdAt`, `actor.did` (resolve and show the handle), `subject{uri, cid?, communityDid?}` (absent = "subject hidden": doxing/illegal content, or an erased account), `reason`, `reverses.actionId`, `authorityDid`, `scope`, `origin` (always `local` for now).
- Admin `GET listAdminActions`: same filters plus `actionId` (mobile does not send `actionId`); includes label/retract-label; wraps entries with `actorDid`, `privateNote`, `privateSubject` (the subject the public log hides). Admins see the admin log so they can restore hidden-subject removals.
- Unknown actions, reasons and scopes render as generic text.

## Behaviour

1. **Moderation API client and models.** Typed client for the endpoints above with typed errors (error codes, not booleans); `viewer.moderation` parsed on post and comment viewer state (unknown tokens ignored); `getViewerAuthority` exposed to the UI and refreshed on session change.
2. **Modlog screen.** Public log, newest first, cursor pagination using the shared pagination controller, action and community filters. Entry row: action, relative time, admin handle, reason label, subject link (post → post detail/tombstone; comment → thread focused on the comment) or "Subject hidden". Restore entries show what they reverse. Admins (`instanceAdmin`) get the admin log with private notes and private subjects. Entry point at the bottom of Explore. A tombstone links to the log filtered to that subject.
3. **Remove.** Post and comment menus show "Remove" only when `viewer.moderation` contains `remove`. Sheet: six reasons, optional private note (≤ 1,000), Remove button. Flow: getSubjectState → removeContent. On success the post leaves every loaded feed (reuse the deleted-post removal path) and a comment becomes the `[Removed by server admin]` placeholder in place.
4. **NSFW.** Post menu shows "Mark NSFW" for `label` and "Remove NSFW label" for `retract-label`. Remove NSFW label sends the post's shown strongRef as `reviewedSubject` when the record is present (Q-10 (a), 2026-10-08). Optional reason excludes doxing/illegal content. On success the post's blur updates in place everywhere it is shown.
5. **Restore.** From a modlog removal entry, a tombstone and a placeholder carrying `restore`. Reason picker excludes doxing/illegal content. getSubjectState → restoreContent with `localRemoval.actionId` and `reviewedSubject = currentSubject` when the record is present. If the outcome leaves the subject unavailable (author deleted it, or the record is unavailable), say so.

All admin flows: a confirm step, a disabled button while in flight, the error mapping above, and no optimistic UI before the server answers.

## Out of scope

Community moderators, label federation, inherited actions UI, reports queue, account bans, comment NSFW labels, admin inspection of removed content.

## Dependencies and verification

- Backend `tdd/viewer-moderation` merged and the local stack running it, with a local test account in `MODERATION_ADMINS` (env edit + AppView restart). Chunks needing `viewer.moderation` or `getViewerAuthority` against a live server wait on it; host tests use fixtures.
- Production Caddy `@appview` allowlist must include the `social.coves.moderation.*` and `getViewerAuthority` routes before release (ops).
- Release gate: admins stay disabled in production (`MODERATION_ADMINS` empty) until a mobile build with Phase A is in the stores.
- Device verification: emulator for all screens; a signed-in admin and a non-admin account.

## Implementation notes

Built 2026-10-04 to 2026-10-15 on branch `prd/prd_mobile_moderation_admin`, based on Phase A (`tdd/moderation-read` @ acbef76), not main.

### Chunks

- 01 Public moderation log: list, pagination and the Explore entry — a635f5c
- 02 Moderation log rows: admin handle, subject, reverses and scope — 6028675
- 03 Modlog filters and the tombstone link — 85591d9
- 04 Viewer authority from the server, with a revoked state — ba093a3
- 05 A removed post leaves every loaded surface (remove and replace events) — 772f96b
- 06 Moderation service contract: viewer capabilities, subject state, mutation results, log redaction — 1e50b29
- 07 Remove a post from its card menu — fbc5094
- 08 Admin action retries and error recovery — 2b5739f
- 09 Admin tools and submissions belong to the session that fetched them — d7c4930
- 10 The admin moderation log — c510cbf
- 11 Remove a comment in place — 96da739
- 12 Mark a post NSFW and remove the NSFW label — 9045de2
- 13 Restore a removed post from its tombstone — 664bc0b
- 14 Restore a removed comment from its placeholder — e17688c
- 15 Restore from a modlog removal entry — e27bd75
- 16 Modlog comment subjects open the thread focused on the comment — 5a8ce09
- 17 Fix stale-session reload loop and focused-thread false reload success — 8a4cb12
- 18 Remove NSFW label reviews the version the admin saw — 03ed346
- 19 Remove the unreachable restoredButStillRemoved restore outcome — f3a0011
- 20 Admin tools in the post detail menu — 40bfbf8
- 21 Restore is offered right after an in-place comment removal — 4066b8e

### Contracts and invariants

Capability and authority:
- Admin capability comes only from the server. Per item: `viewer.moderation`, parsed by `parseModerationCapabilities` (`lib/models/moderation.dart`, unknown tokens dropped). Per viewer: `ViewerAuthorityProvider` (`lib/providers/viewer_authority_provider.dart`). `kAdminHandles` still gates the communities admin panel and nothing in moderation.
- `ViewerAuthorityProvider` lives for the app's lifetime (registered in `main.dart`, never disposed). Statuses: signedOut, loading, instanceAdmin, notAdmin, unavailable, revoked. An explicit `refresh()` supersedes an in-flight fetch, `refresh()` from revoked skips loading, and listeners are notified only on a status change. `getViewerAuthority()` throws `ApiException` on a malformed body; it never returns false for one.
- Nothing retries authority from unavailable on its own. An admin surface that opens with status unavailable must call `refresh()` (the modlog does on pull-to-refresh). Revoked hides admin items app-wide until a new session or a refresh that returns admin.
- Session ownership: `ViewerAuthorityProvider.sessionKey` is a `({String did, int generation})` record exposed as `Object?` (null when signed out), new for every sign-in and never reused. `adminToolAllowed` (`lib/services/admin_tools_gate.dart`) requires the capability, a non-revoked status and a stamp equal to the current key; a null stamp is denied. Surfaces stamp the key at first-page request time.
- `sessionStamp` is required on `PostCard`, `PostCardActions`, `FeedPage`, `PostDetailScreen`, `CommentCard`, `CommentThread` and `_CommentItem`. `sessionKeyOf` is required on `MultiFeedProvider`, `UserProfileProvider` and `CommentsProvider` (forwarded by `CommentsProviderCache`), and optional on `CursorPaginationController`.
- `CursorPaginationController.refresh()` re-requests page 1 when the key changed mid-load (at most 3 attempts, then `SessionChangedDuringLoadException`). `loadMore()` under a stale stamp runs `refresh()`, except while `error` is set: then it sends nothing until `retry()`, `refresh()` or `reset()`.

Admin flow and errors:
- `AdminModerationFlow` (`lib/services/admin_moderation_flow.dart`): `submitRemoval`, `submitLabel`, `submitLabelRetraction`, `submitRestore`, `retry()`. Every submit reads `getSubjectState` first and uses a fresh `Random.secure()` 16-byte hex idempotency key. Only an ambiguous mutation failure keeps the submission; `retry()` replays the exact body and key with no state read. A new flow is created per menu open, which is what discards a kept retry on reopen. An unknown 2xx outcome throws `StateError`.
- Results are the sealed `ModerationFlowResult`: Succeeded, PreflightFailed, MutationFailed (`currentState` set only for StateConflict), StaleSession (any answer after the session key changed; kept submissions are dropped), NotRemoved (no `localRemoval`), RemovalNoLongerActive (modlog restore whose `expectedRemoval` differs from the fresh `localRemoval`; nothing is sent).
- `reviewedSubject`: remove and label send the shown item's StrongRef. Retract-label sends the caller's StrongRef when the record is present and never reads `currentSubject`; an empty cid returns PreflightFailed(invalidSubject) and sends nothing. Restore sends `state.currentSubject`, since admins cannot see removed content.
- `restoreOutcomeOf` classifies a restore success by `recordState` alone: deleted → restoredButDeleted, unavailable → restoredButUnavailable, anything else → restored; plus notRemoved. There is no restoredButStillRemoved outcome: coves `restore.go` returns no `activeRemoval`.
- `ModerationError.fromException` (`lib/services/moderation_errors.dart`) maps error codes to a recovery (ambiguousRetry, preflightRetry, reloadSubject, revoke, clientBug, ...) and a message. Unrecognised codes fall back to transport: network and federation errors → network; server errors and status ≥ 500 → moderationUnavailable (ambiguousRetry). 401 AuthRequired maps to unknown.
- `moderationFailureDecision` (`lib/widgets/moderation/moderation_failure_decision.dart`) is the one failure handler for post card, post detail, comment card and modlog. Handle Succeeded, NotRemoved and RemovalNoLongerActive before calling it; it throws `ArgumentError` on them.
- `ModerationActionSheet.show<R>` (`lib/widgets/moderation/moderation_action_sheet.dart`) takes `authority:` and `onResult` returning `ModerationSheetDecision {close, failureMessage, retryLocked}`. It cannot be dismissed while submitting, closes silently on a session change without calling `onResult`, and pops on a session change only when its route is current. `showOptionalReason` is the "No reason" mode used by label, retract and restore.
- Reason lists and note limits are in `lib/constants/moderation_constants.dart`: `removalReasons`, `labelReasons`, `restoreReasons`, `privateNoteMaxGraphemes` (1,000), `privateNoteMaxBytes` (10,000).
- A mutation response carries `state` and `contentLabels` but no removal `sources` and no `viewer.moderation`. A local removal placeholder takes its attribution from the confirmed local decision. Restore on a just-removed comment comes from a read-back of the comment (Q-11 (a)), never a client-derived capability.

Posts:
- `PostChangeBroadcast` (`lib/services/post_change_broadcast.dart`): `removePost(uri)` and `replacePost(PostView)`, app-wide in `main.dart`, injected into `MultiFeedProvider` and `UserProfileProvider`. Publish only after the server confirms. Replace subscribers swap the PostView without hydrating, so a replace publisher routes fresh viewer state through `VoteProvider.applyServerVoteState` itself. Admin removal hides the post from every backend read synchronously, so the feeds' removed-URI memory is enough.
- Post admin actions are in `lib/widgets/moderation/post_admin_tools.dart`: `PostAdminTool` enum, `allowedPostAdminTools(capabilities:, sessionStamp:, authority:)`, `runPostAdminTool(context, shownPost:, tool:)`. Card and detail both use them. Detail re-checks the allowed tools at tap time; the runner itself does not compare sessions.
- NSFW success publishes an interim post (result moderation, empty capabilities), closes, then an unawaited `getPost` → `applyServerVoteState` → `replacePost`. A success whose state is removed calls `removePost` instead.
- `/post/:postUri` always builds `PostDetailLoader`. The in-app extra is `PostDetailRouteExtra({FeedViewPost post, Object? sessionStamp})`, pushed with `pushPostDetail(context, post:, sessionStamp:)`; a plain `FeedViewPost` extra is no longer read. The loader renders a handed-over post without a fetch and takes its stamp; otherwise it stamps the session at request time. It refetches on a PostRemoved for its URI, so detail shows the tombstone after a removal from any surface.
- `PostGetModerated.viewerModeration` parses the narrow `moderatedPostViewerState`. The tombstone offers Restore and links to the modlog filtered to the post.

Comments:
- `CommentsProvider`: `markCommentRemoved`, `applyRemovalOverlay(thread, {since})`, `removalSequence`, `clearCommentRemoval(uri)` (no notify; callers reload), `fetchCommentSnapshot(uri)` (by `parentRkey`, no merge), `readBackRemovedComment(uri)`.
- `_removals` entries are `({int sequence, ModerationView moderation, CommentView? served})`. A node shows that removal's local placeholder only when `identical(node.comment.moderation, entry.moderation)`. A served node that is deleted and carries moderation is never downgraded to the local placeholder.
- After a removal, `readBackRemovedComment` does one `getComments(parentRkey)` and adopts the served view only if it is removed, deleted and carries `restore`, the entry's sequence is still current, and the provider is not disposed. Only `ApiException` is caught.
- Restore clears the local overlay only for restored and notRemoved; deleted and unavailable outcomes keep it, because it masks pre-removal snapshots.
- `FocusedThreadScreen` stamps each ancestor row and the fallback anchor with `removalSequence` at request start and does not overlay at build time. `refreshSnapshots()` returns false when any ancestor or the anchor subtree is missing. `reloadAfterModeration` is `Future<bool>` (true when the reload landed) and is required whenever `sessionStamp` is non-null.
- A modlog restore of a comment does not touch any `CommentsProvider`; an open thread shows the change on its next reload.

Modlog:
- Mobile sends only `limit`, `cursor`, `action`, `community` and `subject`. Collection checks accept both `social.coves.community.post` and `social.coves.community.postv2` (current posts are postv2). The subject-URI check follows atproto grammar. `ModerationActionRef` and `StrongRef` have value equality. `ModerationActionKind` is remove, restore, label, retractLabel, unknown; apply-removal and retract-removal parse as unknown.
- Entry points: the bottom of Explore, and a "Moderation log" row on `CommunitiesAdminPanel` (admins with `kAdminHandles` see the panel instead of Explore). The admin log (`listAdminModerationActions`) is chosen only from `ViewerAuthorityProvider`. `ModlogScreen` captures its run generation and session key at fetch time and calls `markRevoked()` on a 403 only when both are still current.
- `ModlogScreen` reads `ProfileCache` for handles and never writes it; tests pumping it need `Provider<ProfileCache>`. Copy helpers are in `lib/utils/moderation_copy.dart`; `moderationReversesLabel(kind, reversedAction)` takes the row's own kind.
- Restore is offered on a row when the admin log is shown, the viewer is instance admin, the stamp equals the current key, the action is remove, origin is `local`, and a public or private subject is present. `ModlogEntryTile` has exactly one `ButtonStyleButton` (Restore).
- Comment subjects (Q-09 (a), coves 7aad882): `ModerationSubjectRef.rootUri` is parsed only when a non-empty string. The link is `/post/<encodeComponent(root)>?comment=<encodeQueryComponent(comment)>` with root = `subject.rootUri ?? privateSubject?.rootUri`, linked only when the root is a post or postv2 URI; otherwise the row shows plain "Comment". Only comment actions recorded after 7aad882 carry `rootUri`.

Logging and privacy:
- `isPrivateModerationPath` (`lib/services/log_redaction.dart`): any path containing `social.coves.moderation.` is private except exactly `/xrpc/social.coves.moderation.listActions`. `CovesApiService` debug logging goes through `_ModerationSafeLogInterceptor`, which logs method, path without query and status for private routes; new admin endpoints are covered when their paths match.
- Sentry screenshots rely on the privacy defaults in `main.dart` (`maskAllText`). A private note must never appear in a widget Key, a Sentry message or Sentry extras.

Testing:
- New `CovesApiService` methods stubbed on `MockCovesApiService` need `test/test_helpers/test_mocks.mocks.dart` regenerated (`dart run build_runner build --delete-conflicting-outputs`).
- `test/test_helpers/fake_providers.dart` has `unchangingSessionKey` and `viewerAuthorityRegistration`; signed-in screen tests must stub `getViewerAuthority`. Tests pumping `PostDetailLoader` must register authority; tests pumping post detail, profile or community feed must register `PostChangeBroadcast`.
- `CommunityFeedScreen` has a `@visibleForTesting paginationClock`, because the pagination throttle reads `DateTime.now`, which widget pumps do not advance. Feed widget tests that need the footer use a 1080x2400 view at device pixel ratio 1.
- Maestro flows: `.maestro/d6_modlog_guest.yaml`, `e9_delete_post_profile_open.yaml`, `g5_post_detail_admin_menu.yaml`, `g6_comment_remove_restore.yaml`.

### Deferred findings

Modlog:
- An all-malformed page ends pagination, and the shared pagination listener's throttle can drop a request (pre-existing; `lib/utils/pagination_scroll_listener.dart`, `cursor_pagination_controller.dart`).
- `ModlogScreen`'s controller has no `onUnexpectedError` (`lib/screens/moderation/modlog_screen.dart`).
- Handle display: the parser accepts an empty `actor.did`, an empty or `handle.invalid` handle renders `@…`, `profile.did` is not checked against the requested DID, and Retry does not re-resolve failed handles (`modlog_entry_tile.dart`, `modlog_screen.dart`).
- The AT-URI regex is duplicated with `WebLinkBuilder._parseAtUri`; test F10 does not pin the subject ellipsis (`lib/utils/moderation_copy.dart`).
- Private actor handles (`_actorHandles`) are not cleared on an authority change, and private actor DIDs reach debug `getProfile` logs (`modlog_screen.dart`).
- Private fields have no render-time admin-log gate (suggested `AdminModerationActionView.publicOnly`); an empty `privateNote` or `actorDid` is not treated as null; a non-list `actions` reads as an empty log.
- Full-screen Retry does not ask authority again when it is unavailable; only pull-to-refresh does.
- Label copy assumes NSFW. A revoke on any 403 is untested.
- Product questions not asked: an admin whose authority is unavailable silently sees the public log; a revocation is silent apart from the title.
- A hidden row's `privateSubject` link opens the ordinary `/post` route, which logs the URI in debug and stays open after revocation.
- Restore-outcome copy is in three places (tombstone, placeholder, modlog); extract it to `moderation_copy.dart`.
- `_offersRestore` is checked only at build; an item-kind subject offers "Restore post"; origin `local` is a string literal (`modlog_screen.dart`).
- `mounted` in `answerStillWanted` drops the Forbidden message on programmatic navigation (`modlog_screen.dart`).
- `rootUri`: a private root is taken without a URI match against the subject, the non-empty check is unpinned, doc wording, and a duplicated test helper (`modlog_entry_tile.dart`, `lib/models/moderation_action.dart`).

Flow, sheet and errors:
- `retry()` with a non-`ApiException` leaves the kept submission set while the sheet unlocks, so the next press replays the old reason and note (`admin_moderation_flow.dart`).
- A preflight clientBug (400 or malformed) gets the editable retry state instead of closing with "Couldn't complete this action."; an unknown 2xx keeps the sheet open through the generic catch.
- A StateConflict refetch swallows Forbidden; client-bug codes only show a snackbar and are never reported; a lost retract race (InvalidDecision) shows generic copy; "Post had no NSFW label" is unreachable.
- `ModerationSheetDecision` allows meaningless combinations; the retry lock is held in both sheet and flow; the session key is captured in three places (sheet, card, flow); the kept submission and its key are separate fields; `ModerationSubmission` uses a kind enum with `!` unwraps instead of a sealed hierarchy.
- The sheet's 48 px title row clips at 2x text; the success path waits a frame before pop; the counter shows graphemes only and is untested; failure text has no error colour or live region; the snackbar runs inside `onSubmit`; the idempotency key length is not asserted; Remove uses a Material icon, not Lucide (`moderation_action_sheet.dart`).
- A 401 AuthRequired maps to unknown; an `authRequired` code is suggested (`moderation_errors.dart`).
- `auth_interceptor.dart:158,166` debug-prints `error.message` and the exception on private moderation routes; fix with `isPrivateModerationPath`.
- Restore with a present record and a null `currentSubject` returns PreflightFailed(unknown), which loops on "Try again" without a report (`admin_moderation_flow.dart`). A malformed `localRemoval` reads as "This is no longer removed."
- No single convention for "decision gone" (NotRemoved versus PreflightFailed(decisionNotFound)); a parse failure or unknown outcome after a landed restore does not reload the tombstone.
- Admin-side stale restore replay (pre-existing).
- Pre-existing session leak: `RetryInterceptor` (POST on connect or send timeout) and the auth interceptor's 401 refresh-retry attach the current session's token, so a mutation started under one account can go out under another. Also the session-check to token-attach microtask window (`admin_moderation_flow.dart`) and `post.get` viewer vote state applied across an account switch (`post_detail_loader.dart`).
- `ModerationActionKind` does not model apply-removal or retract-removal, or `labelValue` and `issuedAt`.

Posts:
- Replace logic is duplicated in `multi_feed_provider.dart`, `user_profile_provider.dart` and `community_feed_screen.dart`.
- Removal tombstones are cleared before a refresh succeeds (`cursor_pagination_controller.dart` refresh, `multi_feed_provider.dart` InvalidCursor recovery); harmless while the backend hides removed posts synchronously.
- `refreshPost` removes the card for any non-success, including a parse failure.
- NSFW interim publish trusts a parse-fallback moderation; the post-success refresh has an empty catch and the follow-up `getPost` failure is swallowed; `labelContent` does not reject doxing and illegal-content reasons at the API layer.
- Post detail: the card push-site stamp is unbitten, `onPostRemoved` is optional, the popup value is untyped, loader docs are stale, the router ignores the path parameter when an extra is present, and `didUpdateWidget` with a different URI is untested.
- The loader keeps result and stamp as separate fields; the tombstone restore has the "restored but couldn't load the latest version" copy gap.

Comments:
- Focused-thread snapshots are drawn under the provider's stamp, not their own request-time key; `fetchCommentSnapshot` should drop results whose request-time key differs (unreachable today).
- No host test covers the `main.dart` `sessionKeyOf` wiring; `_reloadAfterModeration` has no mounted check; the placeholder is rebuilt every build; a `fetchCommentSnapshot` URI mismatch and focused-thread fetch failures only reach `debugPrint` or nothing.
- A session change can leave a covered sheet open, because the sheet pops only when its route is current.
- Post detail's `provider.error == null` can read as success when a newer refresh supersedes the moderation reload.
- `_onLoadMoreReplies` merges a newer subtree into the fallback anchor but keeps its older removal stamp; entry ancestor rows are stamped 0 (`focused_thread_screen.dart`).
- A stacked focused screen keeps its server placeholder after a restore on a deeper screen, so Restore there answers "no longer removed".
- The restore sheet stays locked through the whole success reload, a throwing reload reads "Couldn't restore", and the unawaited `resolveStateConflict` reload has no try/catch (`comment_card.dart`). Overlay clearing for notRemoved and for restored with a failed reload is untested.
- `retryLoadMore` after a session change clears `loadMoreError`, then `loadMore()` returns at the guard, so the first tap does nothing (`cursor_pagination_controller.dart`).
- No test lands an ancestor without replies (reachable only through a block-index race).
- Read-back: `MalformedCommentUriException` escapes the unawaited read (unreachable); `_removedPlaceholder` order and the `isLocalPlaceholder` early return are unpinned; a non-adoptable read is silent; an adopted served view outlives restoredButDeleted and restoredButUnavailable; served capabilities carry no session tag (`comments_provider.dart`).

Documentation:
- Retract doc-comment rationale and ranking wording, the PRD's Q-10 citation and its circular "unavailable" wording, empty-cid copy, the unavailable-with-empty-cid row and B2/B3 test names (from chunks 18 and 19).

### Outstanding device checks

- 07: device pending — backend `tdd/viewer-moderation` not on the local stack.
- 07: physical — remove sheet with the keyboard up (portrait, iOS landscape, large text); note field and Remove reachable, then remove.
- 08: device pending — backend `tdd/viewer-moderation` not on the local stack.
- 08: physical — locked "Try again" and preflight-failure states with the keyboard open (portrait, iOS landscape, large text).
- 09: device pending — local stack down and backend unmerged; feeds regression pass needed.
- 09: physical — account switch and sign-out during a remove; gate sign-in then load-more on a community feed.
- 10: device pending — local stack down (public d6 flow, admin panel row, admin log).
- 11: device pending — local stack down.
- 11: physical — remove a comment with a private note, keyboard up, in post detail and a focused thread; system back during sign-out.
- 12: device pending — local stack down.
- 12: physical — NSFW sheets with a private note and the keyboard up; blur in place, including a deep-linked detail after navigating away and back.
- 13: device pending — backend `tdd/viewer-moderation` not on the local stack.
- 13: physical — private-note keyboard in the restore sheet from a post tombstone.
- 14: device pending — backend `tdd/viewer-moderation` not on the local stack.
- 14: physical — restore-sheet private-note keyboard from a comment placeholder (post detail, focused ancestor row, fallback anchor).
- 15: device pending — backend `tdd/viewer-moderation` not on the local stack.
- 15: physical — restore-sheet private-note keyboard from the modlog, on public-subject and private-subject rows.
- 16: device pending — the comment-link tap is untested live because home-pc's AppView still runs coves 5e419b8, which lacks `rootUri`; it needs a restart onto 7aad882 or later. The no-`rootUri` admin-log checks passed.
- 17: device pending — emulator overloaded; the focused-thread half needs `tdd/viewer-moderation`.
- 18: device pending — backend `tdd/viewer-moderation` not on the local stack.
- 20: physical — remove and NSFW sheets from the detail app bar with the keyboard up; "Remove NSFW label" at a large font scale.
