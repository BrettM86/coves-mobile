import 'constants.dart';
import 'handle_helpers.dart';

/// Represents a DID document as defined by W3C DID Core spec.
///
/// This is a simplified version focused on atProto needs.
/// See: https://www.w3.org/TR/did-core/
class DidDocument {
  /// The DID subject (the DID itself)
  final String id;

  /// Alternative identifiers (used for atProto handles: at://handle)
  final List<String>? alsoKnownAs;

  /// Service endpoints (used to find PDS URL)
  final List<DidService>? service;

  /// Verification methods for authentication
  final List<dynamic>? verificationMethod;

  /// Authentication methods
  final List<dynamic>? authentication;

  /// Optional controller DIDs
  final dynamic controller; // Can be String or List<String>

  /// The @context field
  final dynamic context;

  const DidDocument({
    required this.id,
    this.alsoKnownAs,
    this.service,
    this.verificationMethod,
    this.authentication,
    this.controller,
    this.context,
  });

  /// Parses a DID document from JSON.
  factory DidDocument.fromJson(Map<String, dynamic> json) {
    return DidDocument(
      id: json['id'] as String,
      alsoKnownAs:
          (json['alsoKnownAs'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList(),
      service:
          (json['service'] as List<dynamic>?)
              ?.map((e) => DidService.fromJson(e as Map<String, dynamic>))
              .toList(),
      verificationMethod: json['verificationMethod'] as List<dynamic>?,
      authentication: json['authentication'] as List<dynamic>?,
      controller: json['controller'],
      context: json['@context'],
    );
  }

  /// Converts the DID document to JSON.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'id': id};

    if (context != null) map['@context'] = context;
    if (alsoKnownAs != null) map['alsoKnownAs'] = alsoKnownAs;
    if (service != null) {
      map['service'] = service!.map((s) => s.toJson()).toList();
    }
    if (verificationMethod != null) {
      map['verificationMethod'] = verificationMethod;
    }
    if (authentication != null) map['authentication'] = authentication;
    if (controller != null) map['controller'] = controller;

    return map;
  }

  /// Extracts the atProto PDS URL from the DID document.
  ///
  /// Returns null if no PDS service is found.
  String? extractPdsUrl() {
    if (service == null) return null;

    for (final s in service!) {
      // Check for standard atproto_pds service
      if (s.id == atprotoServiceId && s.type == atprotoServiceType) {
        if (s.serviceEndpoint is String) {
          return s.serviceEndpoint as String;
        }
      }

      // Also check if type matches (some implementations may vary on id)
      if (s.type == atprotoServiceType && s.serviceEndpoint is String) {
        return s.serviceEndpoint as String;
      }
    }

    return null;
  }

  /// Extracts the raw atProto handle from the DID document.
  ///
  /// Returns null if no handle is found in alsoKnownAs.
  String? extractAtprotoHandle() {
    if (alsoKnownAs == null) return null;

    for (final aka in alsoKnownAs!) {
      if (aka.startsWith('at://')) {
        // Strip off "at://" prefix
        return aka.substring(5);
      }
    }

    return null;
  }

  /// Extracts a validated, normalized atProto handle from the DID document.
  ///
  /// Returns null if no valid handle is found.
  String? extractNormalizedHandle() {
    final handle = extractAtprotoHandle();
    if (handle == null) return null;
    return asNormalizedHandle(handle);
  }
}

/// Represents a service endpoint in a DID document.
class DidService {
  /// Service ID (e.g., "#atproto_pds")
  final String id;

  /// Service type (e.g., "AtprotoPersonalDataServer")
  final String type;

  /// Service endpoint URL
  final dynamic serviceEndpoint; // Can be String, Map, or List

  const DidService({
    required this.id,
    required this.type,
    required this.serviceEndpoint,
  });

  /// Parses a service from JSON.
  factory DidService.fromJson(Map<String, dynamic> json) {
    return DidService(
      id: json['id'] as String,
      type: json['type'] as String,
      serviceEndpoint: json['serviceEndpoint'],
    );
  }

  /// Converts the service to JSON.
  Map<String, dynamic> toJson() {
    return {'id': id, 'type': type, 'serviceEndpoint': serviceEndpoint};
  }
}
