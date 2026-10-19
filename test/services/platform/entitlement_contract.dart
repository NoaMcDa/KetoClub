// The shared Entitlement contract (Banto, ALG-18, issue #360).
//
// Every implementation of Entitlement, including the fake in test/fakes/,
// is run through this suite from its own test file. It asserts only what
// the interface promises: no call throws, each answers a result of the
// sealed family, and an answer that says what the store holds agrees with
// isPremium.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/platform/entitlement.dart';

/// Asserts the [Entitlement] contract against what [build] returns.
void runEntitlementContract(String name, Entitlement Function() build) {
  group('$name (Entitlement contract)', () {
    test('the getters are plain answers that do not throw', () {
      final entitlement = build();
      expect(() => entitlement.sellsPremium, returnsNormally);
      expect(() => entitlement.isPremium, returnsNormally);
      expect(
        () => entitlement.changes.listen((_) {}).cancel(),
        returnsNormally,
      );
    });

    test('refresh never throws and agrees with isPremium', () async {
      final entitlement = build();
      late final Future<EntitlementResult> future;
      expect(() => future = entitlement.refresh(), returnsNormally);
      final result = await future;
      switch (result) {
        case PremiumActive():
          expect(entitlement.isPremium, isTrue);
        case PremiumInactive():
          expect(entitlement.isPremium, isFalse);
        case EntitlementFailed():
          break;
        case PurchaseCancelled() || PurchasePending():
          fail('a refresh opens no purchase sheet, so it cannot be $result');
      }
    });

    test('localizedPrice never throws and is null or a non-empty '
        'string', () async {
      final entitlement = build();
      final price = await entitlement.localizedPrice();
      if (price != null) expect(price.trim(), isNotEmpty);
    });

    test('purchase never throws, and an active answer means premium', () async {
      final entitlement = build();
      late final Future<EntitlementResult> future;
      expect(() => future = entitlement.purchase(), returnsNormally);
      final result = await future;
      if (result is PremiumActive) expect(entitlement.isPremium, isTrue);
    });

    test('restore never throws and agrees with isPremium', () async {
      final entitlement = build();
      late final Future<EntitlementResult> future;
      expect(() => future = entitlement.restore(), returnsNormally);
      final result = await future;
      if (result is PremiumActive) expect(entitlement.isPremium, isTrue);
      if (result is PremiumInactive) expect(entitlement.isPremium, isFalse);
    });

    test('a build that sells nothing is never premium and buys '
        'nothing', () async {
      final entitlement = build();
      if (entitlement.sellsPremium) return;
      expect(entitlement.isPremium, isFalse);
      expect(
        await entitlement.purchase(),
        const EntitlementFailed(EntitlementFailureReason.notSold),
      );
      expect(
        await entitlement.restore(),
        const EntitlementFailed(EntitlementFailureReason.notSold),
      );
      expect(await entitlement.localizedPrice(), isNull);
    });
  });
}
