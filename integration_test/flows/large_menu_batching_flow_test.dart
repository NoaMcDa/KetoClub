// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4; issue #188):
// a menu too large for one model request is analysed in batches, end to
// end, and the user sees one AI result.
//
// Everything from the chat client up is real: a real `RoutingMenuClassifier`
// over a real `LlmMenuClassifier`, the menu screen and its verdict tiles.
// Only the menu fetch (a scripted repository answering a 200-dish Wolt
// menu) and the chat client are faked; the chat client answers each
// request from the dish lines of its own user prompt, as a model would,
// so a batch is placed by exactly what it was sent.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/llm_menu_classifier.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/large-market';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'large-market',
);

/// How many dishes the menu holds: well past one request's ceiling.
const int _dishCount = 200;

/// A [_dishCount]-dish menu, 25 dishes a category.
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  venueName: 'Large Market',
  categories: <MenuCategory>[
    for (var start = 0; start < _dishCount; start += 25)
      MenuCategory(
        id: 'grill-$start',
        name: 'Grill ${start ~/ 25}',
        dishes: <Dish>[
          for (var i = start; i < start + 25; i++)
            Dish(
              id: 'dish-$i',
              name: 'Grilled steak $i',
              description: 'With butter',
              price: 80,
              options: const <DishOption>[],
            ),
        ],
      ),
  ],
);

/// A chat client that places every dish its user prompt names as
/// order-as-is, records every prompt, and answers the calls [failures]
/// names (from 1) with those results instead.
final class _MenuReadingChatClient implements LlmChatClient {
  /// Creates a client answering the calls [failures] names with them.
  new([this.failures = const <int, ChatResult>{}]);

  /// The answer to the n-th call, by n, instead of the placed reply.
  final Map<int, ChatResult> failures;

  /// Every user prompt received, in call order.
  final List<String> userPrompts = <String>[];

  @override
  Future<ChatResult> complete({
    required String systemPrompt,
    required String userPrompt,
    Map<String, Object?>? responseSchema,
    String? schemaName,
    List<ChatImagePart> images = const <ChatImagePart>[],
  }) async {
    userPrompts.add(userPrompt);
    final scripted = failures[userPrompts.length];
    if (scripted != null) return scripted;
    return ChatCompleted(
      content: jsonEncode(<String, Object?>{
        'dishes': <Object?>[
          for (final line in userPrompt.split('\n'))
            <String, Object?>{
              'id': line.split(' | ')[0],
              'name': line.split(' | ')[2],
              'verdict': 'orderAsIs',
              'why': 'Steak in butter, no carb sides.',
              'modification': null,
              'net_carbs_estimate': 1,
              'hidden_carbs': <Object?>[],
            },
        ],
      }),
      model: 'flow-test-model',
    );
  }
}

/// Wires [fakes] with the real router and LLM classifier over [chat].
void _wire(FakeAppDependencies fakes, LlmChatClient chat) {
  fakes
    ..classifierOverride = RoutingMenuClassifier(
      LlmMenuClassifier(chat, fakes.clock),
      HeuristicMenuClassifier(clock: fakes.clock),
      fakes.connectivity,
    )
    ..repository.stub(_ref, MenuFetched(menu: _menu));
}

/// The loaded menu's list, the one `scrollUntilVisible` drives.
final Finder _menuList = find
    .descendant(
      of: find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(ListView),
      ),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('A menu larger than one request (issue #188)', () {
    testWidgets('is analysed in three requests and shown as one AI result', (
      tester,
    ) async {
      // Setup: consent on (the D16 default), the disclosure already seen.
      final fakes = FakeAppDependencies();
      await fakes.settingsStore.write(const AppSettings(disclosureSeen: true));
      final chat = _MenuReadingChatClient();
      _wire(fakes, chat);
      await pumpApp(tester, fakes);

      // Act: paste the link and open the venue.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: three requests of 67, 67 and 66 dishes, in menu order, each
      // numbering its own dishes from 1 rather than sending their ids.
      expect(
        [for (final p in chat.userPrompts) p.split('\n').length],
        [67, 67, 66],
      );
      expect(
        chat.userPrompts.first,
        startsWith('1 | Grill 0 | Grilled steak 0 |'),
      );
      expect(
        chat.userPrompts.last.split('\n').last,
        startsWith('66 | Grill 7 | Grilled steak 199 |'),
      );
      expect(chat.userPrompts.join('\n'), isNot(contains('dish-')));

      // Assert: one AI result covering every dish, no rules fallback.
      expect(find.text(_en.engineChipAi), findsOneWidget);
      expect(find.text(_en.engineChipRules), findsNothing);
      expect(
        find.descendant(
          of: find.byType(VerdictCounterTiles),
          matching: find.text('$_dishCount'),
        ),
        findsOneWidget,
      );
      expect(find.text('Grilled steak 0'), findsOneWidget);
    });

    testWidgets('one failed batch leaves an AI result with its dishes listed '
        'as not read', (tester) async {
      // Setup: the second of three requests comes back unusable.
      final fakes = FakeAppDependencies();
      await fakes.settingsStore.write(const AppSettings(disclosureSeen: true));
      final chat = _MenuReadingChatClient({
        2: const ChatFailed(reason: ChatFailureReason.badResponse),
      });
      _wire(fakes, chat);
      await pumpApp(tester, fakes);

      // Act
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: the third batch was still sent, and the result is the
      // model's, with the failed batch's 67 dishes named as not read.
      expect(chat.userPrompts, hasLength(3));
      expect(find.text(_en.engineChipAi), findsOneWidget);
      expect(find.text(_en.engineChipRules), findsNothing);
      expect(
        find.descendant(
          of: find.byType(VerdictCounterTiles),
          matching: find.text('${_dishCount - 67}'),
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text(_en.unclassifiedTitle(67)),
        1000,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      expect(find.text(_en.unclassifiedTitle(67)), findsOneWidget);
    });

    testWidgets('a rate limit mid-menu is named on a rules result', (
      tester,
    ) async {
      // Setup: the second request finds the bucket empty.
      final fakes = FakeAppDependencies();
      await fakes.settingsStore.write(const AppSettings(disclosureSeen: true));
      final chat = _MenuReadingChatClient({
        2: const ChatFailed(reason: ChatFailureReason.rateLimited),
      });
      _wire(fakes, chat);
      await pumpApp(tester, fakes);

      // Act
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: no third request, and the rules answer, saying why.
      expect(chat.userPrompts, hasLength(2));
      expect(find.text(_en.engineChipAi), findsNothing);
      expect(find.text(_en.analysisRateLimited), findsOneWidget);
    });
  });
}
