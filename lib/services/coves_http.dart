import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../config/environment_config.dart';

/// How long an idle keep-alive connection to the Coves backend stays open.
///
/// dio's default adapter closes idle sockets after 3 seconds, so nearly
/// every request after a pause (a vote, opening a post, the next feed page)
/// paid for a fresh DNS + TCP + TLS handshake - two extra round trips.
/// 15 seconds is dart:io's own default: long enough to keep the connection
/// warm while the user reads, short enough that a socket dropped by a
/// network switch or carrier NAT is rarely reused. That matters because a
/// dead reused socket surfaces as a connectionError, which the retry policy
/// deliberately does not retry for POSTs (votes, comments).
const Duration covesIdleConnectionTimeout = Duration(seconds: 15);

/// One connection pool for every client that talks to the Coves backend
/// (API, votes, comments, auth), so a connection opened by one is reused by
/// the others instead of each service holding its own cold pool.
final HttpClientAdapter _sharedCovesAdapter = _UnclosableAdapter(
  IOHttpClientAdapter(
    createHttpClient: () =>
        HttpClient()..idleTimeout = covesIdleConnectionTimeout,
  ),
);

/// Builds a [Dio] for the Coves backend on the shared connection pool.
///
/// Closing the returned [Dio] does not close the shared pool - other
/// services are still using it.
Dio createCovesDio({Map<String, dynamic>? headers}) {
  return Dio(
    BaseOptions(
      baseUrl: EnvironmentConfig.current.apiUrl,
      // Shorter timeout with retries for mobile network resilience
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: headers,
    ),
  )..httpClientAdapter = _sharedCovesAdapter;
}

/// Delegates to a shared adapter but ignores [close], so disposing one
/// service's [Dio] can't tear down the pool the others share.
class _UnclosableAdapter implements HttpClientAdapter {
  _UnclosableAdapter(this._inner);

  final HttpClientAdapter _inner;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}
