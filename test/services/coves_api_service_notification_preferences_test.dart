import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late DioAdapter adapter;
  late CovesApiService service;
  late List<RequestOptions> requests;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
    requests = [];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.next(options);
        },
      ),
    );
    adapter = DioAdapter(dio: dio);
    service = CovesApiService(
      sessionKeyOf: () => null,
      dio: dio,
      tokenGetter: () async => null,
    );
  });

  tearDown(() => service.dispose());

  test(
    'B1 GET parses four required booleans and rejects malformed bodies',
    () async {
      var responseBody = <String, dynamic>{
        'postReply': true,
        'commentReply': false,
        'mention': false,
        'upvote': true,
      };
      adapter.onGet(
        '/xrpc/social.coves.notification.getPreferences',
        (server) => server.replyCallback(200, (_) => responseBody),
      );

      final preferences = await service.getNotificationPreferences();
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(
        requests.single.path,
        '/xrpc/social.coves.notification.getPreferences',
      );
      expect(preferences.postReply, isTrue);
      expect(preferences.commentReply, isFalse);
      expect(preferences.mention, isFalse);
      expect(preferences.upvote, isTrue);

      for (final (name, body) in [
        (
          'missing postReply',
          <String, dynamic>{
            'commentReply': false,
            'mention': false,
            'upvote': true,
          },
        ),
        (
          'missing commentReply',
          <String, dynamic>{
            'postReply': true,
            'mention': false,
            'upvote': true,
          },
        ),
        (
          'missing mention',
          <String, dynamic>{
            'postReply': true,
            'commentReply': false,
            'upvote': true,
          },
        ),
        (
          'missing upvote',
          <String, dynamic>{
            'postReply': true,
            'commentReply': false,
            'mention': false,
          },
        ),
        (
          'string mention',
          <String, dynamic>{
            'postReply': true,
            'commentReply': false,
            'mention': 'false',
            'upvote': true,
          },
        ),
        (
          'null upvote',
          <String, dynamic>{
            'postReply': true,
            'commentReply': false,
            'mention': false,
            'upvote': null,
          },
        ),
      ]) {
        responseBody = body;
        await expectLater(
          service.getNotificationPreferences(),
          throwsA(isA<ApiException>()),
          reason: name,
        );
      }
    },
  );

  test(
    'B2 PUT sends one exact sparse body and parses the full response',
    () async {
      var responseBody = <String, dynamic>{
        'postReply': true,
        'commentReply': false,
        'mention': false,
        'upvote': true,
      };
      adapter.onPost(
        '/xrpc/social.coves.notification.putPreferences',
        (server) => server.replyCallback(200, (_) => responseBody),
        data: Matchers.any,
      );
      for (final (name, send, expectedBody) in [
        (
          'postReply false',
          () => service.putNotificationPreferences(postReply: false),
          <String, bool>{'postReply': false},
        ),
        (
          'commentReply true',
          () => service.putNotificationPreferences(commentReply: true),
          <String, bool>{'commentReply': true},
        ),
        (
          'mention false',
          () => service.putNotificationPreferences(mention: false),
          <String, bool>{'mention': false},
        ),
        (
          'upvote true',
          () => service.putNotificationPreferences(upvote: true),
          <String, bool>{'upvote': true},
        ),
      ]) {
        requests.clear();
        final preferences = await send();
        expect(requests, hasLength(1), reason: name);
        expect(requests.single.method, 'POST', reason: name);
        expect(
          requests.single.path,
          '/xrpc/social.coves.notification.putPreferences',
          reason: name,
        );
        expect(requests.single.data, expectedBody, reason: name);
        expect(preferences.postReply, isTrue, reason: name);
        expect(preferences.commentReply, isFalse, reason: name);
        expect(preferences.mention, isFalse, reason: name);
        expect(preferences.upvote, isTrue, reason: name);
      }

      responseBody = {
        'postReply': true,
        'commentReply': false,
        'mention': false,
      };
      await expectLater(
        service.putNotificationPreferences(mention: false),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
