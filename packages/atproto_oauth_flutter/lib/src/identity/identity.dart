/// Identity resolution for atProto.
///
/// This module provides the core identity resolution functionality for atProto,
/// enabling decentralized identity through handle and DID resolution.
///
/// ## Key Components
///
/// - **IdentityResolver**: Main interface for resolving handles/DIDs to identity info
/// - **HandleResolver**: Resolves atProto handles (e.g., "alice.bsky.social") to DIDs
/// - **DidResolver**: Resolves DIDs to DID documents
/// - **DidDocument**: Represents a DID document with services and handles
///
/// ## Why This Matters for Decentralization
///
/// This is the **most important module for atProto decentralization**. It enables:
/// 1. Users to host their data on any PDS, not just bsky.social
/// 2. Custom domain handles (e.g., "alice.example.com")
/// 3. Portable identity (change PDS without losing identity)
///
/// ## Usage
///
/// ```dart
/// // Create a resolver
/// final resolver = AtprotoIdentityResolver.withDefaults(
///   handleResolverUrl: 'https://bsky.social',
/// );
///
/// // Resolve a handle to find their PDS
/// final pdsUrl = await resolver.resolveToPds('alice.bsky.social');
/// print('Alice\'s PDS: $pdsUrl');
///
/// // Get full identity info
/// final info = await resolver.resolve('alice.bsky.social');
/// print('DID: ${info.did}');
/// print('Handle: ${info.handle}');
/// print('PDS: ${info.pdsUrl}');
/// ```
library;

export 'constants.dart';
export 'did_document.dart';
export 'did_helpers.dart';
export 'did_resolver.dart';
export 'handle_helpers.dart';
export 'handle_resolver.dart';
export 'identity_resolver.dart';
export 'identity_resolver_error.dart';
