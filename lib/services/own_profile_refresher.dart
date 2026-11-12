import 'coves_api_service.dart';
import 'profile_cache.dart';

/// Fetches the signed-in user's profile and puts it in [cache], unless a
/// newer put landed or the viewer changed during the fetch. Errors propagate.
Future<void> refreshOwnProfile({
  required CovesApiService apiService,
  required ProfileCache cache,
  required String did,
}) async {
  final generation = cache.generation;
  final requestSequence = cache.nextRequestSequence();
  final profile = await apiService.getProfile(actor: did);
  if (cache.generation != generation) {
    return;
  }
  cache.put(profile, requestSequence: requestSequence);
}
