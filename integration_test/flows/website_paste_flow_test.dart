// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4, D19; issue
// #181): a restaurant's own homepage, pasted on Explore, becomes a
// classified menu.
//
// Everything below the HTTP client is real and wired the way `di.dart`
// wires a web build with a backend: a real `CachedMenuRepository` over a
// real `WebsiteMenuAdapter` whose fetcher comes from `websiteFetcherFor`
// with the proxy base `menuProxyBase` gives a browser. Only KetoClub's
// backend is faked, by one `MockClient` answering `POST /v1/website/fetch`
// the way the route does: the homepage links to `/menu`, and `/menu` is a
// priced dish list. The classifier is the harness's all-green fake.
//
// The pages below are adjacent string literals that concatenate into one
// document; markup needs no whitespace between tags.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/di.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/website/website_adapter.dart';
import 'package:ketoclub/widgets/rules_reason_banner.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The restaurant homepage the user pastes.
const String _homepage = 'https://cafe-noir.example/';

/// The normalised URL the resolver stores, which the adapter asks for.
const String _home = 'https://cafe-noir.example';

/// The menu page the homepage links to.
const String _menuPage = 'https://cafe-noir.example/menu';

/// A homepage with navigation and no dishes of its own.
const String _homeHtml =
    '<html><body><nav><a href="/">Home</a> <a href="/menu">Menu</a></nav>'
    '<h1>Cafe Noir</h1><p>A neighbourhood bistro since 1998.</p>'
    '</body></html>';

/// A menu page whose prices end each dish line.
const String _menuHtml =
    '<html><body><h2>Mains</h2><table>'
    '<tr><td>Grilled salmon</td><td>96 ₪</td></tr>'
    '<tr><td>Entrecote steak</td><td>128 ₪</td></tr>'
    '<tr><td>Caesar salad</td><td>52 ₪</td></tr>'
    '</table><p>Tel 03-5551234</p></body></html>';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('website paste flow', () {
    testWidgets('pasting a restaurant homepage finds its /menu page and '
        'shows a classified, unpriced menu under the site host', (
      tester,
    ) async {
      // Setup: the faked backend answers the homepage and its menu page.
      final asked = <String>[];
      final backend = MockClient((request) async {
        if (request.url.path != '/v1/website/fetch') {
          return http.Response('', 404);
        }
        final url = (jsonDecode(request.body) as Map<String, Object?>)['url'];
        asked.add('$url');
        final html = switch (url) {
          _home => _homeHtml,
          _menuPage => _menuHtml,
          _ => null,
        };
        if (html == null) {
          return http.Response(
            jsonEncode({'reason': 'notFound', 'status_code': 404}),
            404,
          );
        }
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'kind': 'html',
              'content_type': 'text/html; charset=utf-8',
              'body': html,
              'final_url': url,
            }),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final fakes = FakeAppDependencies();
      fakes.repositoryOverride = CachedMenuRepository(
        adapters: [
          WebsiteMenuAdapter(
            fetcher: websiteFetcherFor(
              client: backend,
              proxyBase: menuProxyBase(
                runsInBrowser: true,
                configured: 'http://localhost:8000',
              ),
              installIdStore: FlowFakeInstallIdStore(),
            ),
            scannedClassifier: fakes.scannedClassifier,
            readOptions: () async => ClassificationOptions.fromSettings(
              await fakes.settingsStore.read(),
            ),
            clock: fakes.clock,
          ),
        ],
        cache: FlowForgetfulMenuCache(),
        clock: fakes.clock,
      );
      await pumpApp(tester, fakes);

      // Act: paste the homepage and open it.
      await enterText(tester, _homepage);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: the homepage, then the page it links to, were read.
      expect(asked, [_home, _menuPage]);
      // A classified menu, labelled with the site's host, with every dish
      // and no price anywhere (a site's price is unverified, D19).
      expect(find.byType(RulesReasonBanner), findsOneWidget);
      expect(find.byType(VerdictCounterTiles), findsOneWidget);
      expect(find.textContaining('cafe-noir.example'), findsWidgets);
      expect(find.text('Grilled salmon'), findsOneWidget);
      expect(find.text('Entrecote steak'), findsOneWidget);
      expect(find.textContaining('₪'), findsNothing);
      expect(find.textContaining('Tel 03'), findsNothing);
    });
  });
}
