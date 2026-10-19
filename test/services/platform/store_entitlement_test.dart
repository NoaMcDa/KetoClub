import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:ketoclub/services/platform/entitlement.dart';
import 'package:ketoclub/services/platform/store_entitlement.dart';

import 'entitlement_contract.dart';

/// A purchase of [productId] in [status].
PurchaseDetails _purchase(
  PurchaseStatus status, {
  String productId = premiumProductId,
  bool pendingComplete = false,
}) => PurchaseDetails(
  purchaseID: 'p-$productId',
  productID: productId,
  verificationData: PurchaseVerificationData(
    localVerificationData: 'local',
    serverVerificationData: 'server',
    source: 'test',
  ),
  transactionDate: '1767225600000',
  status: status,
)..pendingCompletePurchase = pendingComplete;

/// The store's details of [premiumProductId] at [price].
ProductDetails _product({String price = '₪19.90'}) => ProductDetails(
  id: premiumProductId,
  title: 'Banto Premium',
  description: 'Monthly',
  price: price,
  rawPrice: 19.9,
  currencyCode: 'ILS',
);

/// A stand-in for the plugin: answers what the test scripts, emits on its
/// purchase stream the way StoreKit and Play Billing do, and records what
/// it was asked. Anything the entitlement must not call fails the test
/// through [noSuchMethod].
final class _FakeStore implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> stream =
      StreamController<List<PurchaseDetails>>.broadcast();

  bool available = true;
  bool throwOnAvailable = false;
  ProductDetailsResponse products = ProductDetailsResponse(
    productDetails: <ProductDetails>[_product()],
    notFoundIDs: const <String>[],
  );
  bool throwOnProducts = false;
  bool hangOnProducts = false;

  /// What a restore emits; null emits nothing (a store that never answers).
  List<PurchaseDetails>? restored = const <PurchaseDetails>[];
  bool throwOnRestore = false;

  /// What a purchase emits after the sheet; null emits nothing.
  List<PurchaseDetails>? bought = <PurchaseDetails>[
    _purchase(PurchaseStatus.purchased, pendingComplete: true),
  ];
  bool buyStarts = true;
  bool throwOnBuy = false;

  int restoreCalls = 0;
  final List<PurchaseParam> buys = <PurchaseParam>[];
  final List<PurchaseDetails> completed = <PurchaseDetails>[];
  int queries = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => stream.stream;

  @override
  Future<bool> isAvailable() async {
    if (throwOnAvailable) throw StateError('no billing');
    return available;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    queries++;
    if (throwOnProducts) throw StateError('query failed');
    if (hangOnProducts) {
      return await Completer<ProductDetailsResponse>().future;
    }
    return products;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls++;
    if (throwOnRestore) throw StateError('restore failed');
    final batch = restored;
    if (batch != null) stream.add(batch);
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buys.add(purchaseParam);
    if (throwOnBuy) throw StateError('buy failed');
    final batch = bought;
    if (buyStarts && batch != null) stream.add(batch);
    return buyStarts;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeStore store;
  late int connects;

  StoreEntitlement build({
    Duration answerTimeout = const Duration(seconds: 5),
    Duration purchaseTimeout = const Duration(seconds: 5),
  }) => StoreEntitlement(
    store: () {
      connects++;
      return store;
    },
    answerTimeout: answerTimeout,
    purchaseTimeout: purchaseTimeout,
  );

  setUp(() {
    store = _FakeStore();
    connects = 0;
  });

  runEntitlementContract('StoreEntitlement', () {
    store = _FakeStore();
    return StoreEntitlement(store: () => store);
  });

  group('StoreEntitlement', () {
    test('sells Premium, and its constructor reaches no plugin', () {
      final entitlement = build();
      expect(entitlement.sellsPremium, isTrue);
      expect(entitlement.isPremium, isFalse);
      expect(connects, 0);
    });

    test('the default connection is the plugin, reached on first use '
        'only', () {
      // No plugin binding here, so reaching the plugin in the constructor
      // would throw; nothing does until a call needs the store.
      expect(StoreEntitlement.new, returnsNormally);
    });

    test('a refresh reads the active subscription the store holds', () async {
      store.restored = <PurchaseDetails>[
        _purchase(PurchaseStatus.restored, pendingComplete: true),
      ];
      final entitlement = build();
      final changes = <bool>[];
      entitlement.changes.listen(changes.add);

      expect(await entitlement.refresh(), const PremiumActive());
      await pumpEventQueue();

      expect(entitlement.isPremium, isTrue);
      expect(changes, <bool>[true]);
      expect(store.completed, hasLength(1));
      expect(connects, 1);
    });

    test('a restore with no entry for the product reads as lapsed', () async {
      store.restored = <PurchaseDetails>[_purchase(PurchaseStatus.restored)];
      final entitlement = build();
      expect(await entitlement.restore(), const PremiumActive());

      store.restored = <PurchaseDetails>[
        _purchase(PurchaseStatus.restored, productId: 'something_else'),
      ];
      expect(await entitlement.restore(), const PremiumInactive());
      expect(entitlement.isPremium, isFalse);
    });

    test('two restores at once ask the store once', () async {
      final entitlement = build();
      final results = await Future.wait(<Future<EntitlementResult>>[
        entitlement.restore(),
        entitlement.restore(),
      ]);
      expect(results, everyElement(const PremiumInactive()));
      expect(store.restoreCalls, 1);
    });

    test('a store that is not available answers storeUnavailable', () async {
      store.available = false;
      final entitlement = build();
      const unavailable = EntitlementFailed(
        EntitlementFailureReason.storeUnavailable,
      );
      expect(await entitlement.refresh(), unavailable);
      expect(await entitlement.purchase(), unavailable);
      expect(await entitlement.localizedPrice(), isNull);
    });

    test('a plugin that throws is storeUnavailable, never a throw', () async {
      store.throwOnAvailable = true;
      expect(
        await build().restore(),
        const EntitlementFailed(EntitlementFailureReason.storeUnavailable),
      );
      final broken = StoreEntitlement(
        store: () => throw StateError('no plugin'),
      );
      expect(
        await broken.purchase(),
        const EntitlementFailed(EntitlementFailureReason.storeUnavailable),
      );
    });

    test('a restore the store refuses is storeError', () async {
      store.throwOnRestore = true;
      expect(
        await build().restore(),
        const EntitlementFailed(EntitlementFailureReason.storeError),
      );
    });

    test('a restore the store never answers times out and keeps the '
        'state', () async {
      store.restored = null;
      final entitlement = build(
        answerTimeout: const Duration(milliseconds: 20),
      );
      expect(
        await entitlement.restore(),
        const EntitlementFailed(EntitlementFailureReason.timedOut),
      );
      expect(entitlement.isPremium, isFalse);
    });

    test("the price is the store's own localized string, looked up "
        'once', () async {
      store.products = ProductDetailsResponse(
        productDetails: <ProductDetails>[_product(price: r'$4.99')],
        notFoundIDs: const <String>[],
      );
      final entitlement = build();
      expect(await entitlement.localizedPrice(), r'$4.99');
      expect(await entitlement.localizedPrice(), r'$4.99');
      expect(store.queries, 1);
    });

    test('a purchase buys the product, finishes it and activates '
        'Premium', () async {
      final entitlement = build();
      expect(await entitlement.purchase(), const PremiumActive());
      await pumpEventQueue();
      expect(entitlement.isPremium, isTrue);
      expect(store.buys.single.productDetails.id, premiumProductId);
      expect(store.completed, hasLength(1));
    });

    test('each way a purchase ends is its own result', () async {
      final cases = <PurchaseStatus, EntitlementResult>{
        PurchaseStatus.canceled: const PurchaseCancelled(),
        PurchaseStatus.pending: const PurchasePending(),
        PurchaseStatus.error: const EntitlementFailed(
          EntitlementFailureReason.storeError,
        ),
      };
      for (final MapEntry(key: status, value: expected) in cases.entries) {
        store = _FakeStore()..bought = <PurchaseDetails>[_purchase(status)];
        final entitlement = build();
        expect(await entitlement.purchase(), expected, reason: '$status');
        expect(entitlement.isPremium, isFalse, reason: '$status');
      }
    });

    test('an unknown product is productNotFound; a failed lookup is '
        'storeError; a slow one timedOut', () async {
      store.products = ProductDetailsResponse(
        productDetails: const <ProductDetails>[],
        notFoundIDs: const <String>[premiumProductId],
      );
      expect(
        await build().purchase(),
        const EntitlementFailed(EntitlementFailureReason.productNotFound),
      );

      store = _FakeStore()
        ..products = ProductDetailsResponse(
          productDetails: const <ProductDetails>[],
          notFoundIDs: const <String>[],
          error: IAPError(source: 'test', code: 'x', message: 'down'),
        );
      expect(
        await build().purchase(),
        const EntitlementFailed(EntitlementFailureReason.storeError),
      );

      store = _FakeStore()..throwOnProducts = true;
      expect(
        await build().purchase(),
        const EntitlementFailed(EntitlementFailureReason.storeError),
      );

      store = _FakeStore()..hangOnProducts = true;
      expect(
        await build(answerTimeout: const Duration(milliseconds: 20)).purchase(),
        const EntitlementFailed(EntitlementFailureReason.timedOut),
      );
    });

    test('a purchase the store will not start, or that throws, is '
        'storeError', () async {
      store.buyStarts = false;
      expect(
        await build().purchase(),
        const EntitlementFailed(EntitlementFailureReason.storeError),
      );
      store = _FakeStore()..throwOnBuy = true;
      expect(
        await build().purchase(),
        const EntitlementFailed(EntitlementFailureReason.storeError),
      );
    });

    test('a purchase with no answer in time reads as pending, and a later '
        'approval still activates Premium', () async {
      store.bought = null;
      final entitlement = build(
        purchaseTimeout: const Duration(milliseconds: 20),
      );
      final changes = <bool>[];
      entitlement.changes.listen(changes.add);

      expect(await entitlement.purchase(), const PurchasePending());
      store.stream.add(<PurchaseDetails>[_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();

      expect(entitlement.isPremium, isTrue);
      expect(changes, <bool>[true]);
    });

    test('an error on the purchase stream ends the waiting call', () async {
      store.bought = null;
      final entitlement = build();
      final pending = entitlement.purchase();
      await pumpEventQueue();
      store.stream.addError(StateError('stream broke'));
      expect(
        await pending,
        const EntitlementFailed(EntitlementFailureReason.storeError),
      );
    });

    test('dispose stops listening and closes the change stream', () async {
      final entitlement = build();
      await entitlement.refresh();
      await entitlement.dispose();
      expect(await entitlement.changes.isEmpty, isTrue);
    });
  });
}
