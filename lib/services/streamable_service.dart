import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Service for interacting with Streamable API
///
/// Fetches video data from Streamable to get direct MP4 URLs
/// for in-app video playback.
///
/// Implements caching to reduce API calls for recently accessed videos.
class StreamableService {
  StreamableService({Dio? dio}) : _dio = dio ?? _sharedDio;

  // Singleton Dio instance for efficient connection reuse
  static final Dio _sharedDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ),
  );

  final Dio _dio;

  // Cache for video URLs (shortcode -> {url, timestamp})
  // Short-lived cache (5 min) to reduce API calls
  final Map<String, ({String url, DateTime cachedAt})> _urlCache = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Extracts the Streamable shortcode from a URL
  ///
  /// Examples:
  /// - https://streamable.com/7kpdft -> 7kpdft
  /// - https://streamable.com/e/abc123 -> abc123
  /// - streamable.com/abc123 -> abc123
  static String? extractShortcode(String url) {
    try {
      // Handle URLs without scheme
      var urlToParse = url;
      if (!url.contains('://')) {
        urlToParse = 'https://$url';
      }

      final uri = Uri.parse(urlToParse);
      final path = uri.path;

      // Get the last non-empty path segment (handles /e/ prefix and other cases)
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) {
        return null;
      }

      final shortcode = segments.last;

      if (shortcode.isEmpty) {
        return null;
      }

      return shortcode;
    } on FormatException catch (e) {
      if (kDebugMode) {
        debugPrint('Error extracting Streamable shortcode: $e');
      }
      return null;
    }
  }

  /// Fetches the MP4 video URL for a Streamable video
  ///
  /// Returns the direct MP4 URL or null if the video cannot be fetched.
  /// Uses a 5-minute cache to reduce API calls for repeated access.
  Future<String?> getVideoUrl(String streamableUrl) async {
    try {
      final shortcode = extractShortcode(streamableUrl);
      if (shortcode == null) {
        if (kDebugMode) {
          debugPrint('Failed to extract shortcode from: $streamableUrl');
        }
        return null;
      }

      // Check cache first
      final cached = _urlCache[shortcode];
      if (cached != null) {
        final age = DateTime.now().difference(cached.cachedAt);
        if (age < _cacheDuration) {
          if (kDebugMode) {
            debugPrint('Using cached URL for shortcode: $shortcode');
          }
          return cached.url;
        }
        // Cache expired, remove it
        _urlCache.remove(shortcode);
      }

      // Fetch video data from Streamable API
      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.streamable.com/videos/$shortcode',
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data!;

        // Extract MP4 URL from response
        // Response structure: { "files": { "mp4": { "url": "//..." } } }
        final files = data['files'] as Map<String, dynamic>?;
        if (files == null) {
          if (kDebugMode) {
            debugPrint('No files found in Streamable response');
          }
          return null;
        }

        final mp4 = files['mp4'] as Map<String, dynamic>?;
        if (mp4 == null) {
          if (kDebugMode) {
            debugPrint('No MP4 file found in Streamable response');
          }
          return null;
        }

        var videoUrl = mp4['url'] as String?;
        if (videoUrl == null) {
          if (kDebugMode) {
            debugPrint('No URL found in MP4 data');
          }
          return null;
        }

        // Prepend https: if URL is protocol-relative
        if (videoUrl.startsWith('//')) {
          videoUrl = 'https:$videoUrl';
        }

        // Cache the URL for future requests
        _urlCache[shortcode] = (url: videoUrl, cachedAt: DateTime.now());

        return videoUrl;
      }

      if (kDebugMode) {
        debugPrint('Failed to fetch Streamable video: ${response.statusCode}');
      }
      return null;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching Streamable video URL: $e');
      }
      return null;
    }
  }
}
