# Coves mobile

Flutter iOS/Android client for Coves. Global working rules are in `~/.claude/CLAUDE.md`; this file is project facts only.

Backend: `~/Code/coves`. Web client: `~/Code/coves-frontend`.

## Stack

Flutter + Dart. Navigation `go_router`, state `provider`, HTTP `dio` with interceptors, auth via atProto OAuth. Tokens go in `flutter_secure_storage`, settings in `shared_preferences`. Models use `freezed` + `json_serializable`.

```bash
flutter analyze   # must pass with no warnings before a commit
flutter test
dart fix --apply
```

## Layout

`lib/screens` route destinations, `lib/widgets` reusable components, `lib/providers` state, `lib/models`, `lib/services` API and auth clients, `lib/utils`, `lib/constants` config values (never hardcode URLs), `lib/config`.

## Rules that differ from defaults

- Tokens never go in `shared_preferences`.
- Session must survive an app restart and token refresh must be automatic.
- Deep links must work over both HTTPS and the custom scheme.
- Test on physical devices, not only emulators, for anything touching auth, deep links, or keyboard layout.
