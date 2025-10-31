import 'package:dio/dio.dart';

/// PDS Discovery Service
///
/// Handles the resolution of atProto handles to their Personal Data
/// Servers (PDS). This is crucial for proper decentralized
/// authentication - each user may be on a different PDS, and we need to
/// redirect them to THEIR PDS's OAuth server.
///
/// Flow:
/// 1. Resolve handle to DID using a handle resolver (bsky.social)
/// 2. Fetch the DID document from the PLC directory
/// 3. Extract the PDS endpoint from the service array
/// 4. Return the PDS URL for OAuth discovery
class PDSDiscoveryService {
  final Dio _dio = Dio();

  /// Discover the PDS URL for a given atProto handle
  ///
  /// Example:
  /// ```dart
  /// final pds = await discoverPDS('bretton.dev');
  /// // Returns: 'https://pds.bretton.dev'
  /// ```
  Future<String> discoverPDS(String handle) async {
    try {
      // Step 1: Resolve handle to DID
      final did = await _resolveHandle(handle);

      // Step 2: Fetch DID document
      final didDoc = await _fetchDIDDocument(did);

      // Step 3: Extract PDS endpoint
      final pdsUrl = _extractPDSEndpoint(didDoc);

      return pdsUrl;
    } catch (e) {
      throw Exception('Failed to discover PDS for $handle: $e');
    }
  }

  /// Resolve an atProto handle to a DID
  ///
  /// Uses Bluesky's public resolver which can resolve ANY atProto handle,
  /// not just bsky.social handles.
  Future<String> _resolveHandle(String handle) async {
    try {
      final response = await _dio.get(
        'https://bsky.social/xrpc/com.atproto.identity.resolveHandle',
        queryParameters: {'handle': handle},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to resolve handle: ${response.statusCode}');
      }

      final did = response.data['did'] as String?;
      if (did == null) {
        throw Exception('No DID found in response');
      }

      return did;
    } catch (e) {
      throw Exception('Handle resolution failed: $e');
    }
  }

  /// Fetch a DID document from the PLC directory
  Future<Map<String, dynamic>> _fetchDIDDocument(String did) async {
    try {
      final response = await _dio.get('https://plc.directory/$did');

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch DID document: ${response.statusCode}');
      }

      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('DID document fetch failed: $e');
    }
  }

  /// Extract the PDS endpoint from a DID document
  ///
  /// Looks for a service entry with:
  /// - id ending in '#atproto_pds'
  /// - type: 'AtprotoPersonalDataServer'
  String _extractPDSEndpoint(Map<String, dynamic> didDoc) {
    final services = didDoc['service'] as List<dynamic>?;
    if (services == null || services.isEmpty) {
      throw Exception('No services found in DID document');
    }

    // Find the atproto_pds service
    for (final service in services) {
      final serviceMap = service as Map<String, dynamic>;
      final id = serviceMap['id'] as String?;
      final type = serviceMap['type'] as String?;

      if (id != null &&
          id.endsWith('#atproto_pds') &&
          type == 'AtprotoPersonalDataServer') {
        final endpoint = serviceMap['serviceEndpoint'] as String?;
        if (endpoint == null) {
          throw Exception('PDS service has no endpoint');
        }

        // Remove trailing slash if present
        return endpoint.endsWith('/')
            ? endpoint.substring(0, endpoint.length - 1)
            : endpoint;
      }
    }

    throw Exception('No atproto_pds service found in DID document');
  }
}
