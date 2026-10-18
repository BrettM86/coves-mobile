import '../models/moderation.dart';
import '../providers/viewer_authority_provider.dart';

/// Whether an admin tool for [capability] may be offered on an item whose
/// [capabilities] were loaded under [loadedUnderSessionKey].
///
/// The capability comes only from the server's token on the item; the item
/// must have been loaded by the current signed-in session, and the session's
/// authority must not have been revoked since.
bool adminToolAllowed({
  required ModerationCapability capability,
  required Set<ModerationCapability> capabilities,
  required Object? loadedUnderSessionKey,
  required ViewerAuthorityProvider authority,
}) {
  final sessionKey = authority.sessionKey;
  return capabilities.contains(capability) &&
      !authority.isRevoked &&
      sessionKey != null &&
      sessionKey == loadedUnderSessionKey;
}
