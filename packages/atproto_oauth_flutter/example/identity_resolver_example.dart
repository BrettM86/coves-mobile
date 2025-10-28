/// Example usage of the atProto identity resolution layer.
///
/// This demonstrates the critical functionality for decentralization:
/// resolving handles and DIDs to find where user data is actually stored.

import 'package:atproto_oauth_flutter/src/identity/identity.dart';

Future<void> main() async {
  print('=== atProto Identity Resolution Examples ===\n');

  // Create an identity resolver
  // The handleResolverUrl should point to an XRPC service that implements
  // com.atproto.identity.resolveHandle (typically bsky.social for public resolution)
  final resolver = AtprotoIdentityResolver.withDefaults(
    handleResolverUrl: 'https://bsky.social',
  );

  print('Example 1: Resolve a Bluesky handle to find their PDS');
  print('--------------------------------------------------');
  try {
    // This is the most common use case: find where a user's data lives
    final pdsUrl = await resolver.resolveToPds('pfrazee.com');
    print('Handle: pfrazee.com');
    print('PDS URL: $pdsUrl');
    print('✓ This user hosts their data on: $pdsUrl\n');
  } catch (e) {
    print('Error: $e\n');
  }

  print('Example 2: Get full identity information');
  print('--------------------------------------------------');
  try {
    final info = await resolver.resolve('pfrazee.com');
    print('Handle: ${info.handle}');
    print('DID: ${info.did}');
    print('PDS URL: ${info.pdsUrl}');
    print('Has valid handle: ${info.hasValidHandle}');
    print('Also known as: ${info.didDoc.alsoKnownAs}');
    print('✓ Complete identity information retrieved\n');
  } catch (e) {
    print('Error: $e\n');
  }

  print('Example 3: Resolve from a DID');
  print('--------------------------------------------------');
  try {
    // You can also start from a DID
    final info = await resolver.resolveFromDid('did:plc:ragtjsm2j2vknwkz3zp4oxrd');
    print('DID: ${info.did}');
    print('Handle: ${info.handle}');
    print('PDS URL: ${info.pdsUrl}');
    print('✓ Resolved DID to handle and PDS\n');
  } catch (e) {
    print('Error: $e\n');
  }

  print('Example 4: Custom domain handle (CRITICAL for decentralization)');
  print('--------------------------------------------------');
  try {
    // This demonstrates why this code is essential:
    // Users can use their own domains and host on their own PDS
    final info = await resolver.resolve('jay.bsky.team');
    print('Handle: ${info.handle}');
    print('DID: ${info.did}');
    print('PDS URL: ${info.pdsUrl}');
    print('✓ Custom domain resolves to custom PDS (not hardcoded!)\n');
  } catch (e) {
    print('Error: $e\n');
  }

  print('Example 5: Validation - Invalid handle');
  print('--------------------------------------------------');
  try {
    await resolver.resolve('not-a-valid-handle');
  } catch (e) {
    print('✓ Correctly rejected invalid handle: $e\n');
  }

  print('=== Why This Matters ===');
  print('''
This identity resolution layer is THE CRITICAL PIECE for atProto decentralization:

1. **No Hardcoded Servers**: Unlike broken implementations that hardcode bsky.social,
   this correctly resolves each user's actual PDS location.

2. **Custom Domains**: Users can use their own domains (e.g., alice.example.com)
   and host on any PDS they choose.

3. **Portability**: Users can change their PDS without losing their DID or identity.
   The DID document always points to the current PDS location.

4. **Bi-directional Validation**: We verify that:
   - Handle → DID resolution works
   - DID document contains the handle
   - Both directions match (security!)

5. **Caching**: Built-in caching prevents redundant lookups while respecting TTLs.

Without this layer, apps are locked to centralized servers. With it, atProto
achieves true decentralization where users control their data location.
''');
}
