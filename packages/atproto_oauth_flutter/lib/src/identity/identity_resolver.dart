import 'package:dio/dio.dart';

import 'constants.dart';
import 'did_document.dart';
import 'did_helpers.dart';
import 'did_resolver.dart';
import 'handle_helpers.dart';
import 'handle_resolver.dart';
import 'identity_resolver_error.dart';

/// Represents resolved identity information for an atProto user.
///
/// This combines DID, DID document, and validated handle information.
class IdentityInfo {
  /// The DID (Decentralized Identifier) for this identity
  final String did;

  /// The complete DID document
  final DidDocument didDoc;

  /// The validated handle, or 'handle.invalid' if handle validation failed
  final String handle;

  const IdentityInfo({
    required this.did,
    required this.didDoc,
    required this.handle,
  });

  /// Whether the handle is valid (not 'handle.invalid')
  bool get hasValidHandle => handle != handleInvalid;

  /// Extracts the PDS URL from the DID document.
  ///
  /// Returns null if no PDS service is found.
  String? get pdsUrl => didDoc.extractPdsUrl();
}

/// Options for identity resolution.
class ResolveIdentityOptions {
  /// Whether to bypass cache
  final bool noCache;

  /// Cancellation token for the request
  final CancelToken? cancelToken;

  const ResolveIdentityOptions({this.noCache = false, this.cancelToken});
}

/// Interface for resolving atProto identities (handles or DIDs) to complete identity info.
abstract class IdentityResolver {
  /// Resolves an identifier (handle or DID) to complete identity information.
  ///
  /// The identifier can be either:
  /// - An atProto handle (e.g., "alice.bsky.social")
  /// - A DID (e.g., "did:plc:...")
  ///
  /// Returns [IdentityInfo] with DID, DID document, and validated handle.
  Future<IdentityInfo> resolve(
    String identifier, [
    ResolveIdentityOptions? options,
  ]);
}

/// Implementation of the official atProto identity resolution strategy.
///
/// This resolver:
/// 1. Determines if input is a handle or DID
/// 2. Resolves handle → DID (if needed)
/// 3. Fetches DID document
/// 4. Validates bi-directional resolution (handle in DID doc matches original)
/// 5. Extracts PDS URL from DID document
///
/// This is the **critical piece for decentralization** - it ensures users can
/// host their data on any PDS, not just bsky.social.
class AtprotoIdentityResolver implements IdentityResolver {
  final DidResolver didResolver;
  final HandleResolver handleResolver;

  AtprotoIdentityResolver({
    required this.didResolver,
    required this.handleResolver,
  });

  /// Factory constructor with defaults for typical usage.
  ///
  /// [handleResolverUrl] should point to an atProto XRPC service that
  /// implements com.atproto.identity.resolveHandle. Typically this is
  /// https://bsky.social for public resolution, or your own PDS.
  factory AtprotoIdentityResolver.withDefaults({
    required String handleResolverUrl,
    String? plcDirectoryUrl,
    Dio? dio,
    DidCache? didCache,
    HandleCache? handleCache,
  }) {
    final dioInstance = dio ?? Dio();

    final baseDidResolver = AtprotoDidResolver(
      plcDirectoryUrl: plcDirectoryUrl,
      dio: dioInstance,
    );

    final baseHandleResolver = XrpcHandleResolver(
      handleResolverUrl,
      dio: dioInstance,
    );

    return AtprotoIdentityResolver(
      didResolver: CachedDidResolver(baseDidResolver, didCache),
      handleResolver: CachedHandleResolver(baseHandleResolver, handleCache),
    );
  }

  @override
  Future<IdentityInfo> resolve(
    String identifier, [
    ResolveIdentityOptions? options,
  ]) async {
    return isDid(identifier)
        ? resolveFromDid(identifier, options)
        : resolveFromHandle(identifier, options);
  }

  /// Resolves identity starting from a DID.
  ///
  /// This:
  /// 1. Fetches the DID document
  /// 2. Extracts the handle from alsoKnownAs
  /// 3. Validates that the handle resolves back to the same DID
  Future<IdentityInfo> resolveFromDid(
    String did, [
    ResolveIdentityOptions? options,
  ]) async {
    final document = await getDocumentFromDid(did, options);

    // We will only return the document's handle alias if it resolves to the
    // same DID as the input (bi-directional validation)
    final handle = document.extractNormalizedHandle();
    String? resolvedDid;

    if (handle != null) {
      try {
        resolvedDid = await handleResolver.resolve(
          handle,
          ResolveHandleOptions(
            noCache: options?.noCache ?? false,
            cancelToken: options?.cancelToken,
          ),
        );
      } catch (e) {
        // Ignore errors (handle might be temporarily unavailable)
        resolvedDid = null;
      }
    }

    return IdentityInfo(
      did: document.id,
      didDoc: document,
      handle: handle != null && resolvedDid == did ? handle : handleInvalid,
    );
  }

  /// Resolves identity starting from a handle.
  ///
  /// This:
  /// 1. Resolves handle → DID
  /// 2. Fetches DID document
  /// 3. Validates that the DID document contains the original handle
  Future<IdentityInfo> resolveFromHandle(
    String handle, [
    ResolveIdentityOptions? options,
  ]) async {
    final document = await getDocumentFromHandle(handle, options);

    // Bi-directional resolution is enforced in getDocumentFromHandle()
    return IdentityInfo(
      did: document.id,
      didDoc: document,
      handle: document.extractNormalizedHandle() ?? handleInvalid,
    );
  }

  /// Fetches a DID document from a DID.
  Future<DidDocument> getDocumentFromDid(
    String did, [
    ResolveIdentityOptions? options,
  ]) async {
    return didResolver.resolve(
      did,
      ResolveDidOptions(
        noCache: options?.noCache ?? false,
        cancelToken: options?.cancelToken,
      ),
    );
  }

  /// Fetches a DID document from a handle with bi-directional validation.
  ///
  /// This method:
  /// 1. Normalizes and validates the handle
  /// 2. Resolves handle → DID
  /// 3. Fetches DID document
  /// 4. Verifies the DID document contains the original handle
  Future<DidDocument> getDocumentFromHandle(
    String input, [
    ResolveIdentityOptions? options,
  ]) async {
    final handle = asNormalizedHandle(input);
    if (handle == null) {
      throw InvalidHandleError(input, 'Invalid handle format');
    }

    final did = await handleResolver.resolve(
      handle,
      ResolveHandleOptions(
        noCache: options?.noCache ?? false,
        cancelToken: options?.cancelToken,
      ),
    );

    if (did == null) {
      throw IdentityResolverError('Handle "$handle" does not resolve to a DID');
    }

    // Fetch the DID document
    final document = await didResolver.resolve(
      did,
      ResolveDidOptions(
        noCache: options?.noCache ?? false,
        cancelToken: options?.cancelToken,
      ),
    );

    // Enforce bi-directional resolution
    final docHandle = document.extractNormalizedHandle();
    if (handle != docHandle) {
      throw IdentityResolverError(
        'DID document for "$did" does not include the handle "$handle" '
        '(found: ${docHandle ?? "none"})',
      );
    }

    return document;
  }

  /// Convenience method to resolve directly to PDS URL.
  ///
  /// This is the most common use case: given a handle or DID, find the PDS URL.
  Future<String> resolveToPds(
    String identifier, [
    ResolveIdentityOptions? options,
  ]) async {
    final info = await resolve(identifier, options);
    final pdsUrl = info.pdsUrl;

    if (pdsUrl == null) {
      throw IdentityResolverError(
        'No PDS endpoint found in DID document for $identifier',
      );
    }

    return pdsUrl;
  }
}

/// Options for creating an identity resolver.
class IdentityResolverOptions {
  /// Custom identity resolver (if not provided, AtprotoIdentityResolver is used)
  final IdentityResolver? identityResolver;

  /// Custom DID resolver
  final DidResolver? didResolver;

  /// Custom handle resolver (or URL string for XRPC resolver)
  final dynamic handleResolver; // HandleResolver, String, or Uri

  /// Custom DID cache
  final DidCache? didCache;

  /// Custom handle cache
  final HandleCache? handleCache;

  /// Custom Dio instance for HTTP requests
  final Dio? dio;

  /// PLC directory URL (defaults to https://plc.directory/)
  final String? plcDirectoryUrl;

  const IdentityResolverOptions({
    this.identityResolver,
    this.didResolver,
    this.handleResolver,
    this.didCache,
    this.handleCache,
    this.dio,
    this.plcDirectoryUrl,
  });
}

/// Creates an identity resolver with the given options.
///
/// This is the main entry point for creating an identity resolver.
/// It handles setting up default implementations with proper caching.
IdentityResolver createIdentityResolver(IdentityResolverOptions options) {
  // If a custom identity resolver is provided, use it
  if (options.identityResolver != null) {
    return options.identityResolver!;
  }

  final dioInstance = options.dio ?? Dio();

  // Create DID resolver
  final didResolver = _createDidResolver(options, dioInstance);

  // Create handle resolver
  final handleResolver = _createHandleResolver(options, dioInstance);

  return AtprotoIdentityResolver(
    didResolver: didResolver,
    handleResolver: handleResolver,
  );
}

DidResolver _createDidResolver(IdentityResolverOptions options, Dio dio) {
  final didResolver =
      options.didResolver ??
      AtprotoDidResolver(plcDirectoryUrl: options.plcDirectoryUrl, dio: dio);

  // Wrap with cache if not already cached
  if (didResolver is CachedDidResolver && options.didCache == null) {
    return didResolver;
  }

  return CachedDidResolver(didResolver, options.didCache);
}

HandleResolver _createHandleResolver(IdentityResolverOptions options, Dio dio) {
  final handleResolverInput = options.handleResolver;

  if (handleResolverInput == null) {
    throw ArgumentError(
      'handleResolver is required. Provide either a HandleResolver instance, '
      'a URL string, or a Uri pointing to an XRPC service.',
    );
  }

  HandleResolver baseResolver;

  if (handleResolverInput is HandleResolver) {
    baseResolver = handleResolverInput;
  } else if (handleResolverInput is String || handleResolverInput is Uri) {
    baseResolver = XrpcHandleResolver(handleResolverInput.toString(), dio: dio);
  } else {
    throw ArgumentError(
      'handleResolver must be a HandleResolver, String, or Uri',
    );
  }

  // Wrap with cache if not already cached
  if (baseResolver is CachedHandleResolver && options.handleCache == null) {
    return baseResolver;
  }

  return CachedHandleResolver(baseResolver, options.handleCache);
}
