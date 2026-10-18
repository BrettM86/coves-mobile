// The Explore moderation log entry is sized like the "Join your first
// community" card above it: same outer margin, inner padding, corner
// radius, icon box, gap and type sizes. Card height is left out: it
// follows how each card's copy wraps, not the sizing rules.
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/screens/home/communities_discovery_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/fake_providers.dart';
import '../../test_helpers/pump_helpers.dart';
import '../../test_helpers/test_mocks.dart';

/// The pinned phone viewport, in logical pixels.
const _viewportWidth = 390.0;

const _modlogTitle = 'Moderation log';
const _modlogSubtitle = 'See what moderators removed or restored, and why';
const _joinTitle = 'Join your first community';

Rect _rectOf(Element element) {
  final box = element.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The paragraph whose whole text is [text].
Finder _paragraph(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText() == text,
);

/// The card holding [title]: its outermost ancestor narrower than the
/// viewport, which excludes the full-width spacing around the card.
Element _cardOf(WidgetTester tester, String title) {
  Element? card;
  tester.element(_paragraph(title)).visitAncestorElements((ancestor) {
    final renderObject = ancestor.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return true;
    }
    if (renderObject.size.width >= _viewportWidth) {
      return false;
    }
    card = ancestor;
    return true;
  });
  return card!;
}

/// The corner radius a widget draws with, or null when it draws none.
double? _drawnCornerRadius(Widget widget) {
  BorderRadiusGeometry? radius;
  if (widget is Material) {
    final shape = widget.shape;
    radius = shape is RoundedRectangleBorder
        ? shape.borderRadius
        : widget.borderRadius;
  } else if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
    radius = (widget.decoration as BoxDecoration).borderRadius;
  } else if (widget is Ink && widget.decoration is BoxDecoration) {
    radius = (widget.decoration! as BoxDecoration).borderRadius;
  } else if (widget is ClipRRect) {
    radius = widget.borderRadius;
  }
  return radius?.resolve(TextDirection.ltr).topLeft.x;
}

/// The corner radius of [card]: the first radius drawn by it or by a
/// descendant covering the same box.
double? _cardCornerRadius(Element card) {
  final cardRect = _rectOf(card);
  double? found;
  void visit(Element element) {
    if (found != null) {
      return;
    }
    final renderObject = element.renderObject;
    if (renderObject is RenderBox &&
        renderObject.hasSize &&
        _rectOf(element) != cardRect) {
      return;
    }
    found = _drawnCornerRadius(element.widget);
    element.visitChildren(visit);
  }

  visit(card);
  return found;
}

/// The leading icon box in [card]: the leftmost decorated box inside it
/// that is smaller than the card.
({Rect rect, double? radius}) _iconBoxOf(Element card) {
  final cardRect = _rectOf(card);
  ({Rect rect, double? radius})? leftmost;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
      final rect = _rectOf(element);
      if (rect != cardRect &&
          (leftmost == null || rect.left < leftmost!.rect.left)) {
        leftmost = (rect: rect, radius: _drawnCornerRadius(widget));
      }
    }
    element.visitChildren(visit);
  }

  card.visitChildren(visit);
  return leftmost!;
}

/// The row of content inside [card]: the nearest Row above its icon box.
Rect _contentRowOf(Element card, Rect iconBox) {
  Element? row;
  void visit(Element element) {
    if (row != null) {
      return;
    }
    if (element.widget is Row && _rectOf(element).contains(iconBox.center)) {
      row = element;
      return;
    }
    element.visitChildren(visit);
  }

  card.visitChildren(visit);
  return _rectOf(row!);
}

TextStyle _paragraphStyle(WidgetTester tester, String text) =>
    tester.widget<RichText>(_paragraph(text)).text.style!;

void main() {
  late MockCovesApiService api;

  setUp(() => api = MockCovesApiService());

  testWidgets('modlog entry card matches the Join your first community card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // Signed in with no subscriptions, so the Join card shows.
    when(
      api.listCommunities(
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        sort: anyNamed('sort'),
        subscribed: anyNamed('subscribed'),
      ),
    ).thenAnswer((_) async => CommunitiesResponse(communities: []));
    final auth = FakeAuthProvider(
      signedInDid: 'did:plc:viewer',
      signedInHandle: 'viewer.coves.social',
    );
    addTearDown(auth.dispose);
    final subscriptions = FakeSubscriptionProvider(
      authProvider: auth,
      apiService: api,
    );
    addTearDown(subscriptions.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: CommunitiesDiscoveryScreen()),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CovesApiService>.value(value: api),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<CommunitySubscriptionProvider>.value(
            value: subscriptions,
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await pumpFrames(tester);

    expect(_paragraph(_joinTitle), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await pumpFrames(tester);
    await tester.scrollUntilVisible(
      _paragraph(_modlogTitle),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFrames(tester);

    final card = _cardOf(tester, _modlogTitle);
    final cardRect = _rectOf(card);
    final iconBox = _iconBoxOf(card);
    final contentRow = _contentRowOf(card, iconBox.rect);
    final titleRect = _rectOf(tester.element(_paragraph(_modlogTitle)));

    final measured = {
      'card left': cardRect.left,
      'card right': cardRect.right,
      'card corner radius': _cardCornerRadius(card),
      'inner padding left': contentRow.left - cardRect.left,
      'inner padding top': contentRow.top - cardRect.top,
      'inner padding right': cardRect.right - contentRow.right,
      'inner padding bottom': cardRect.bottom - contentRow.bottom,
      'icon box width': iconBox.rect.width,
      'icon box height': iconBox.rect.height,
      'icon box radius': iconBox.radius,
      'icon to text gap': titleRect.left - iconBox.rect.right,
      'title font size': _paragraphStyle(tester, _modlogTitle).fontSize,
      'title font weight': _paragraphStyle(tester, _modlogTitle).fontWeight,
      'subtitle font size': _paragraphStyle(tester, _modlogSubtitle).fontSize,
    };

    expect(measured, {
      'card left': 16.0,
      'card right': _viewportWidth - 16,
      'card corner radius': 12.0,
      'inner padding left': 16.0,
      'inner padding top': 16.0,
      'inner padding right': 16.0,
      'inner padding bottom': 16.0,
      'icon box width': 40.0,
      'icon box height': 40.0,
      'icon box radius': 12.0,
      'icon to text gap': 12.0,
      'title font size': 14.0,
      'title font weight': FontWeight.w600,
      'subtitle font size': 12.0,
    });
  });
}
