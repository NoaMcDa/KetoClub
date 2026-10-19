import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/platform/entitlement.dart';

import '../../fakes/fake_entitlement.dart';
import 'entitlement_contract.dart';

void main() {
  runEntitlementContract('NullEntitlement', NullEntitlement.new);
  runEntitlementContract('FakeEntitlement', FakeEntitlement.new);
  runEntitlementContract(
    'FakeEntitlement selling nothing',
    () => FakeEntitlement(sellsPremium: false),
  );
  runEntitlementContract(
    'FakeEntitlement already premium',
    () => FakeEntitlement(premium: true),
  );

  group('NullEntitlement', () {
    test('sells nothing, so the web build gates nothing', () async {
      const entitlement = NullEntitlement();
      expect(entitlement.sellsPremium, isFalse);
      expect(entitlement.isPremium, isFalse);
      expect(await entitlement.refresh(), const PremiumInactive());
      expect(await entitlement.changes.isEmpty, isTrue);
    });
  });

  group('premiumProductId', () {
    test('is the one monthly product the stores are set up with', () {
      expect(premiumProductId, 'banto_premium_monthly');
    });
  });

  group('EntitlementFailed', () {
    test('is equal by reason and names it', () {
      const a = EntitlementFailed(EntitlementFailureReason.timedOut);
      expect(a, const EntitlementFailed(EntitlementFailureReason.timedOut));
      expect(
        a,
        isNot(const EntitlementFailed(EntitlementFailureReason.storeError)),
      );
      expect(a.hashCode, EntitlementFailureReason.timedOut.hashCode);
      expect('$a', contains('timedOut'));
    });
  });

  group('FakeEntitlement', () {
    test('a purchase activates Premium and reports the change', () async {
      final fake = FakeEntitlement();
      final changes = <bool>[];
      fake.changes.listen(changes.add);

      expect(await fake.purchase(), const PremiumActive());
      await pumpEventQueue();

      expect(fake.isPremium, isTrue);
      expect(changes, <bool>[true]);
      expect(fake.calls, <EntitlementCall>[EntitlementCall.purchase]);
    });

    test(
      'scripted answers are used in order, then the store default',
      () async {
        final fake = FakeEntitlement(premium: true)
          ..queueRestore(const PremiumInactive())
          ..queuePurchase(const PurchaseCancelled())
          ..queueRefresh(
            const EntitlementFailed(EntitlementFailureReason.storeUnavailable),
          );

        expect(await fake.restore(), const PremiumInactive());
        expect(fake.isPremium, isFalse);
        expect(await fake.purchase(), const PurchaseCancelled());
        expect(fake.isPremium, isFalse);
        expect(
          await fake.refresh(),
          const EntitlementFailed(EntitlementFailureReason.storeUnavailable),
        );
        expect(await fake.restore(), const PremiumInactive());
        expect(await fake.localizedPrice(), '₪19.90');
      },
    );
  });
}
