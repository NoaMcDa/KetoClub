# test/fakes/

Hand-written fakes for every service interface under `lib/services/`, used by
widget, controller and flow tests instead of a mocking library
(`architecture.md` §18.1). There is no `mockito` or `mocktail` dependency in
this repo — a fake is a small, real implementation of the interface, and it
is exercised by the same contract suite as the production implementations it
stands in for.

## The pattern, as practised here

Every fake in this directory follows the same shape. Read `fake_menu_cache.dart`
or `fake_platform_menu_adapter.dart` for a worked example; the rules below are
inferred from them and from the rest of the directory, not aspirational.

1. **A fake is a real, minimal implementation, not a proxy.** It implements
   the interface directly (`implements KeyStore`, `implements MenuCache`, …)
   and gives every method a small, deterministic body — usually an in-memory
   `Map` or a `List` acting as a queue. It never wraps or delegates to the real
   service.

2. **A fake records what it was called with.** Every call a test might need
   to assert on is appended to a `final List<...>` field, in call order, named
   for what it holds — `loadCalls`, `fetchCalls`, `canHandleCalls`, `requests`,
   `calls`. A call whose arguments matter is recorded as a record type
   (`({VenueRef ref, bool forceRefresh})` in `FakeMenuRepository.loadCalls`) or
   a small named class (`RecordedChatRequest` in `fake_llm_chat_client.dart`)
   rather than as loose positional fields, so a test can destructure it.
   A call that carries no useful argument, or whose count alone matters, is
   instead recorded as an `int ...CallCount` field (`writeCallCount`,
   `clearCacheCallCount`). Not every method needs a counter or a list — a pure
   read that always answers from the same in-memory state (`read()` on
   `FakeKeyStore`, `now()` on `FakeClock`) is not interesting to have called
   twice, so it is left unrecorded; record a call only when a test could
   plausibly assert on it.

3. **A fake exposes setters to script its answers**, never a constructor
   parameter per scenario. The common shapes are:
   - a **queue**, drained in order and then sticking on its last entry or a
     `fallback` (`FakePlatformMenuAdapter.queueResult`/`queueFetched`/
     `queueFailed`, `FakeLlmChatClient.enqueue`);
   - a **scripted single value**, set once and returned from then on
     (`FakeMenuClassifier.respondWith`, `stub`/`stubAll` on
     `FakeMenuRepository`);
   - a **degradation switch**, a plain `bool` field a test flips to make an
     otherwise-working fake start failing without ever throwing
     (`FakeMenuCache.failOnRead`/`failOnWrite`).

   With nothing scripted, a fake still behaves like a working implementation
   — it derives a plausible, valid default result from its arguments (an
   empty `Menu` keyed to the requested `VenueRef`, a `MenuAnalysed` with every
   dish marked `orderAsIs`) — so a test that does not care about the response
   shape does not have to script one just to keep the contract suite honest.

4. **Naming.** The file is `test/fakes/fake_<thing>.dart`; the class is
   `Fake<Thing>`, matching the interface it implements
   (`fake_key_store.dart` → `FakeKeyStore implements KeyStore`). A small
   value type built only to hold one fake's recorded call
   (`RecordedChatRequest`) lives in the same file as the fake that produces
   it, not in its own file.

5. **A composite fake wires the smaller fakes together and exposes every
   one of them.** `FakeAppDependencies` builds one instance of each service
   fake, keeps every one as a `final` field so a test can steer or inspect it
   directly, and exposes an `AppDependencies get dependencies` getter to hand
   to the widget under test. It adds no behaviour of its own.

## Contract suites: how a `..._contract.dart` pairs with its runner

A `..._contract.dart` file (there is one per service interface, living next
to that interface's other tests — e.g.
`test/services/storage/key_store_contract.dart`,
`test/services/menu/platform_menu_adapter_contract.dart`,
`test/services/classifier/menu_classifier_contract.dart`) is not itself a
test file `flutter test` collects. It exports one function:

```dart
void run<Interface>Contract(
  String name,
  <Interface> Function() build, {
  // any fixtures a given contract needs, e.g.:
  // required VenueRef refItHandles,
  // required VenueRef refItRejects,
}) {
  group(name, () {
    test('...', () async {
      final instance = build();
      // assertions against the interface only — never against a
      // particular implementation's internals, and never asserting which
      // verdict/result a given input gets when two correct implementations
      // could legitimately disagree.
    });
    ...
  });
}
```

The signature is the same everywhere it is used: a `String name` (folded into
each nested test's description) and a **factory**, `<Interface> Function()
build` — never an already-constructed instance — so the suite gets a fresh,
independent object per test and cannot leak state between them. Contracts
whose interface needs fixtures to exercise (`MenuRepository`,
`PlatformMenuAdapter`) add them as required named parameters after `build`;
the shape of `build` itself does not change.

Every implementation of that interface — every production implementation
*and* the fake — runs the same suite, called from its own test file:

```dart
// test/services/storage/secure_key_store_test.dart
runKeyStoreContract('SecureKeyStore', _buildStore);

// test/services/classifier/menu_classifier_contract_test.dart
runMenuClassifierContract('FakeMenuClassifier', FakeMenuClassifier.new);
```

`build` is passed as a tear-off (`FakeMenuRepository.new`) when the no-arg
constructor is enough, or as a closure (`() => CachedMenuRepository(...)`)
when the implementation needs fixtures wired in. This is what keeps a fake
from silently drifting away from the interface it stands in for (Liskov
substitution, `architecture.md` §18.1): the fake is held to exactly the same
executable contract as `SecureKeyStore` or `HiveMenuCache`, not just to
"implements the interface" as the analyzer checks it.

A fake with no natural contract suite of its own — `FakeAppLogger` (its
interface is two logging calls with nothing to substitute-check), `FakeClock`
— is instead tested directly in `fakes_test.dart`. `FakeAppDependencies` is
exercised indirectly, through the widget and flow tests that build one.

## CI

These are ordinary `flutter test` unit tests: nothing about them is special
to CI. `tool/check.sh` runs `flutter test --coverage` over the whole `test/`
tree, `fakes_test.dart` and every `..._contract_test.dart` included, so a
fake that stops satisfying its contract fails the `test` CI job the same way
a broken production implementation would. There is no separate fakes job and
no opt-out.
