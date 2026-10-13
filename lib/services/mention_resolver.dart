import '../utils/rich_text_composer.dart';
import 'api_exceptions.dart';
import 'coves_api_service.dart';

/// [MentionResolver] backed by the Coves AppView.
class ApiMentionResolver implements MentionResolver {
  ApiMentionResolver(this._api);

  final CovesApiService _api;

  @override
  Future<String?> resolveHandle(String handle) =>
      _nullWhenNotFound(() => _api.resolveHandle(handle: handle));

  @override
  Future<String?> resolveCommunity(String community) => _nullWhenNotFound(
    () async => (await _api.getCommunity(community: community)).did,
  );

  /// The DID [lookup] returns, or null when the AppView answers 400 or 404,
  /// which is how it reports an unknown handle or community
  Future<String?> _nullWhenNotFound(Future<String> Function() lookup) async {
    try {
      return await lookup();
    } on ApiException catch (error) {
      if (error.statusCode == 400 || error.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }
}
