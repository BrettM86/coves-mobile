import '../models/community.dart';

/// Utility for filtering communities by search query.
///
/// Centralizes the name/displayName/description matching logic
/// shared by the discovery screen and see-all screen.
class CommunitySearchUtils {
  CommunitySearchUtils._();

  /// Filter a list of communities by a search query.
  ///
  /// Matches against [CommunityView.name], [CommunityView.displayName],
  /// and [CommunityView.description]. The [query] is normalized
  /// (trimmed and lowercased) before matching.
  static List<CommunityView> filterByQuery(
    List<CommunityView> communities,
    String query,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return communities;
    }

    return communities.where((community) {
      final name = community.name.toLowerCase();
      final displayName = community.displayName?.toLowerCase() ?? '';
      final description = community.description?.toLowerCase() ?? '';
      return name.contains(normalizedQuery) ||
          displayName.contains(normalizedQuery) ||
          description.contains(normalizedQuery);
    }).toList();
  }
}
