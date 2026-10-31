# Default avatars — mobile implementation notes

PRD: coves `docs/PRD_DEFAULT_AVATARS.md` (coves main 8d74e068). Built by /prd-loop on branch `prd/prd_default_avatars`.

## Implementation notes

- 01 Default avatars on mobile — aed799b

Notes still true of the landed code:
- `UserAvatar.did` is required; `fallbackIcon` is deleted; `cacheManager` is an optional pass-through used by widget tests. `CompactPostCard` has `String? authorDid`. Without `fallbackColor`, UserAvatar draws no initial; only the Bluesky cards keep `fallbackColor`/`fallbackTextColor` and never draw the default (D12).
- An empty DID draws a plain Mist `#DCE0EA` circle; `ProfileHeader` with no profile loaded has no DID (D13).
- Every avatar-less user now builds a CachedNetworkImage for the default picture. Widget tests that use `tester.runAsync` with avatar-less users need the never-completing `plugins.flutter.io/path_provider` mock (see `post_detail_screen_load_more_test`). Under `testWidgets`, uncontrolled images get a synthetic 400; `user_avatar_test.dart` has a test-local controlled image fixture.
- Mobile assignment tests use the §4.2 literal vectors only; the web/mobile comparison for one account is run separately.
- Device flow `.maestro/f6_default_avatar_profile.yaml` is standalone and needs the deep link `social.coves:///profile/livecheck.local.coves.dev` fired first.

Deferred findings: none open. Two review suggestions were skipped as not needed (deduplicating `_buildFallback`/`_buildPlaceholderCircle`; a `CompactPostCard.authorDid` doc change, already accurate).

Device check: passed `f6_default_avatar_profile` on the emulator (real avatar shown; `livecheck.local.coves.dev` → sea-turtle on Sand `#F4E7C1`; community avatars unchanged). Not observable on the local device and covered by host tests only: a failing real-avatar URL falling back to the default, a failing default picture leaving the tinted circle alone, the empty-DID Mist circle, and the Bluesky-embed fallback. "No request to a public host" was checked from config, not captured traffic.
