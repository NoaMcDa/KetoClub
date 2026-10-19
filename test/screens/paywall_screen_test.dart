// The Banto Premium paywall (ALG-18, issue #360), in English and Hebrew:
// what Premium adds, the store's own price, Subscribe, Restore, and the
// line saying what is never locked. Its copy never says "safe" or "בטוח".

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/screens/paywall_screen.dart';
import 'package:ketoclub/services/platform/entitlement.dart';
import 'package:ketoclub/state/premium_controller.dart';
import 'package:ketoclub/utils/premium_gates.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_entitlement.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

/// "safe" as an English word, "בטוח" anywhere in Hebrew.
final RegExp _safe = RegExp('(?<![A-Za-z])safe|בטוח', caseSensitive: false);

/// Every result the paywall can be left with.
const List<EntitlementResult> _everyResult = <EntitlementResult>[
  PremiumActive(),
  PremiumInactive(),
  PurchaseCancelled(),
  PurchasePending(),
  EntitlementFailed(EntitlementFailureReason.notSold),
  EntitlementFailed(EntitlementFailureReason.storeUnavailable),
  EntitlementFailed(EntitlementFailureReason.productNotFound),
  EntitlementFailed(EntitlementFailureReason.storeError),
  EntitlementFailed(EntitlementFailureReason.timedOut),
];

/// Pumps a home page whose button pushes the paywall for [reason], over a
/// [PremiumController] on [store], in [locale]. Returns what the paywall
/// popped with, once it has.
Future<List<bool?>> _pump(
  WidgetTester tester,
  FakeEntitlement store, {
  PremiumFeature? reason,
  Locale locale = const Locale('en'),
}) async {
  final popped = <bool?>[];
  final premium = PremiumController(store, bantoMode: true);
  addTearDown(premium.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<PremiumController>.value(
      value: premium,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => popped.add(
                  await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => PaywallScreen(reason: reason),
                    ),
                  ),
                ),
                child: const Icon(Icons.open_in_new),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byIcon(Icons.open_in_new));
  await tester.pumpAndSettle();
  return popped;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Every string on screen.
List<String> _texts(WidgetTester tester) => <String>[
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
];

void main() {
  for (final (locale, l10n) in <(Locale, AppLocalizations)>[
    (const Locale('en'), _en),
    (const Locale('he'), _he),
  ]) {
    group('PaywallScreen in ${locale.languageCode}', () {
      testWidgets('shows what Premium adds, the store price, both buttons '
          'and what is never locked', (tester) async {
        await _pump(tester, FakeEntitlement(), locale: locale);

        expect(find.text(l10n.premiumTitle), findsOneWidget);
        expect(find.text(l10n.paywallIntro), findsOneWidget);
        expect(find.text(l10n.paywallFeaturesHeading), findsOneWidget);
        for (final feature in <String>[
          l10n.paywallFeatureRestrictions,
          l10n.paywallFeatureGroup,
          l10n.paywallFeatureTrip,
          l10n.paywallFeatureScans,
        ]) {
          expect(find.text(feature), findsOneWidget);
        }
        expect(find.text(l10n.paywallNeverLocked), findsOneWidget);
        expect(find.text(l10n.paywallPrice('₪19.90')), findsOneWidget);
        expect(find.text(l10n.paywallBuy), findsOneWidget);
        expect(find.text(l10n.paywallRestore), findsOneWidget);
        expect(find.text(l10n.paywallTerms), findsOneWidget);
        expect(find.byKey(paywallReasonKey), findsNothing);
        for (final text in _texts(tester)) {
          expect(_safe.hasMatch(text), isFalse, reason: text);
        }
      });

      for (final feature in PremiumFeature.values) {
        testWidgets('names the gate that opened it: $feature', (tester) async {
          await _pump(
            tester,
            FakeEntitlement(),
            reason: feature,
            locale: locale,
          );
          expect(find.text(paywallReasonText(l10n, feature)), findsOneWidget);
        });
      }

      testWidgets("without the store's price, says it will show; never a "
          'written figure', (tester) async {
        await _pump(tester, FakeEntitlement(price: null), locale: locale);
        expect(find.text(l10n.paywallPriceUnknown), findsOneWidget);
        expect(find.textContaining(RegExp(r'[$₪€£]\s?\d')), findsNothing);
      });
    });
  }

  group('PaywallScreen purchases', () {
    testWidgets('opened by a gate, a purchase closes it with true', (
      tester,
    ) async {
      final store = FakeEntitlement();
      final popped = await _pump(
        tester,
        store,
        reason: PremiumFeature.restrictions,
      );

      await _tap(tester, find.byKey(paywallBuyKey));

      expect(find.byType(PaywallScreen), findsNothing);
      expect(popped, <bool?>[true]);
      expect(store.isPremium, isTrue);
    });

    testWidgets('opened from Settings, a purchase stays and says Premium is '
        'active; Subscribe is then off', (tester) async {
      await _pump(tester, FakeEntitlement());

      await _tap(tester, find.byKey(paywallBuyKey));

      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text(_en.paywallActive), findsOneWidget);
      final buy = tester.widget<FilledButton>(find.byKey(paywallBuyKey));
      expect(buy.onPressed, isNull);
    });

    testWidgets('a cancelled purchase stays, says so and keeps the free '
        'plan', (tester) async {
      final store = FakeEntitlement()..queuePurchase(const PurchaseCancelled());
      await _pump(tester, store, reason: PremiumFeature.scans);

      await _tap(tester, find.byKey(paywallBuyKey));

      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text(_en.paywallCancelled), findsOneWidget);
      expect(store.isPremium, isFalse);
    });

    testWidgets("a restore that finds Premium closes a gate's paywall", (
      tester,
    ) async {
      final store = FakeEntitlement()..queueRestore(const PremiumActive());
      final popped = await _pump(
        tester,
        store,
        reason: PremiumFeature.tripMode,
      );

      await _tap(tester, find.byKey(paywallRestoreKey));

      expect(popped, <bool?>[true]);
    });

    testWidgets('a restore that finds nothing says so', (tester) async {
      await _pump(tester, FakeEntitlement(), reason: PremiumFeature.tripMode);

      await _tap(tester, find.byKey(paywallRestoreKey));

      expect(find.text(_en.paywallRestoredNone), findsOneWidget);
    });
  });

  group('paywallResultText', () {
    test('gives every result its own line, in both languages', () {
      for (final l10n in <AppLocalizations>[_en, _he]) {
        final lines = <String>{
          for (final result in _everyResult) paywallResultText(l10n, result),
        };
        expect(lines, hasLength(_everyResult.length));
      }
    });
  });

  group('the Premium copy', () {
    test('never says "safe" or "בטוח", in either ARB file', () {
      for (final path in <String>[
        'lib/l10n/app_en.arb',
        'lib/l10n/app_he.arb',
      ]) {
        final decoded =
            jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
        final premium = <String, String>{
          for (final entry in decoded.entries)
            if (!entry.key.startsWith('@') &&
                entry.value is String &&
                (entry.key.startsWith('paywall') ||
                    entry.key.startsWith('premium') ||
                    entry.key.startsWith('settingsPremium') ||
                    entry.key == 'scanFreeScansLeft'))
              entry.key: entry.value! as String,
        };
        expect(premium, isNotEmpty);
        for (final MapEntry(:key, :value) in premium.entries) {
          expect(_safe.hasMatch(value), isFalse, reason: '$path $key');
        }
      }
    });
  });
}
