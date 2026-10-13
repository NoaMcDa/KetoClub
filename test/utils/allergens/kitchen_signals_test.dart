import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/tenbis/tenbis_menu_mapper.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

import '../../../tool/golden/golden_corpus.dart';
import '../../../tool/golden/kitchen_signals_corpus.dart';

/// Signals of [menu] under the test vocabulary, not the group files.
List<KitchenSignal> _signals(Menu menu) =>
    KitchenSignals.ofWith(menu, kitchenFixtureVocabulary);

/// The kinds of [menu]'s signals, in order.
List<KitchenSignalKind> _kinds(Menu menu) => <KitchenSignalKind>[
  for (final signal in _signals(menu)) signal.kind,
];

/// A one-category menu of dish names.
Menu _menuOf(List<String> names, {String heading = 'Menu'}) => Menu(
  venueRef: const VenueRef(source: MenuSource.scan, platformId: 'kitchen'),
  currency: 'ILS',
  fetchedAt: goldenNow,
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c',
      name: heading,
      dishes: <Dish>[
        for (final (index, name) in names.indexed) menuDish('d$index', name),
      ],
    ),
  ],
);

Menu _fixtureMenu(String path, Menu Function(Map<String, Object?>) read) =>
    read(jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>);

Menu _wolt() => _fixtureMenu('test/fixtures/wolt_hamosad_menu.json', (raw) {
  final result = WoltMenuMapper.toMenu(
    raw,
    ref: goldenWoltRef,
    fetchedAt: goldenNow,
  );
  return (result as MenuFetched).menu;
});

Menu _tenBis() =>
    _fixtureMenu('test/fixtures/tenbis_synthetic_menu.json', (raw) {
      final result = TenBisMenuMapper.toMenu(
        raw,
        ref: goldenTenBisRef,
        fetchedAt: goldenNow,
      );
      return (result as MenuFetched).menu;
    });

/// English fragments no question may contain (`banned_words_test.dart`),
/// plus the words of reassurance a question must never use.
const List<String> _bannedEnglish = <String>[
  'diagnos',
  'treat',
  'cure',
  'medical device',
  'medically',
  'guarantee',
  '100%',
  'safe',
  'free of',
];

/// Hebrew fragments no question may contain.
const List<String> _bannedHebrew = <String>[
  'מאבחן',
  'אבחון',
  'מטפל',
  'טיפול רפואי',
  'מכשיר רפואי',
  'מבטיח',
  'בטוח',
  'בטוחה',
];

void main() {
  group('the signal table', () {
    test('the Wolt fixture shows a fryer and nothing else', () {
      // Act
      final signals = _signals(_wolt());

      // Assert
      expect(signals.map((signal) => signal.kind), <KitchenSignalKind>[
        KitchenSignalKind.fryer,
      ]);
      expect(signals.single.threatens, <RestrictionId>[
        RestrictionId.wheat,
        RestrictionId.gluten,
      ]);
      expect(signals.single.evidence, hasLength(3));
    });

    test('the 10bis fixture shows bread and tahini', () {
      // Act
      final signals = _signals(_tenBis());

      // Assert
      expect(signals.map((signal) => signal.kind), <KitchenSignalKind>[
        KitchenSignalKind.bakery,
        KitchenSignalKind.sesame,
      ]);
      expect(signals.first.evidence, <String>['Bread Basket (complimentary)']);
      expect(signals.last.evidence, <String>['Baby Gem with Tahini']);
    });

    test('the hand-built Hebrew menu shows a fryer, flour, nuts, sesame', () {
      // Act
      final signals = _signals(goldenHebrewMenu);

      // Assert
      expect(signals.map((signal) => signal.kind), <KitchenSignalKind>[
        KitchenSignalKind.fryer,
        KitchenSignalKind.bakery,
        KitchenSignalKind.nuts,
        KitchenSignalKind.sesame,
      ]);
      expect(signals.first.evidence, contains('שניצל'));
      expect(signals.first.threatens, contains(RestrictionId.fish));
    });

    test('a Hebrew grill menu with meat and fish shares a grill', () {
      // Act
      final signals = _signals(kitchenSignalMenus['grill_hebrew']!);

      // Assert
      expect(signals.single.kind, KitchenSignalKind.sharedGrill);
      expect(signals.single.threatens, <RestrictionId>[
        RestrictionId.fish,
        RestrictionId.crustaceans,
        RestrictionId.molluscs,
      ]);
    });

    test('a menu with none of these shows no signal', () {
      expect(_signals(kitchenSignalMenus['no_signals']!), isEmpty);
    });

    test('a menu with no category shows no signal', () {
      expect(_signals(kitchenSignalMenus['empty']!), isEmpty);
    });

    test('a fryer threatens the seafood a fried dish names', () {
      // Act
      final signals = _signals(kitchenSignalMenus['fried_cap_and_seafood']!);

      // Assert
      expect(signals.single.threatens, <RestrictionId>[
        RestrictionId.wheat,
        RestrictionId.gluten,
        RestrictionId.fish,
        RestrictionId.crustaceans,
        RestrictionId.molluscs,
      ]);
    });

    test('every kind maps to the restrictions the epic names', () {
      // Arrange
      final byKind = <KitchenSignalKind, List<RestrictionId>>{};
      for (final menu in <Menu>[
        kitchenSignalMenus['fried_cap_and_seafood']!,
        kitchenSignalMenus['wok_and_heading']!,
        kitchenSignalMenus['grill_by_heading']!,
        kitchenSignalMenus['bakery_and_prefixes']!,
        kitchenSignalMenus['nuts_and_sesame']!,
      ]) {
        for (final signal in _signals(menu)) {
          byKind.putIfAbsent(signal.kind, () => signal.threatens);
        }
      }

      // Assert
      expect(byKind, <KitchenSignalKind, List<RestrictionId>>{
        KitchenSignalKind.fryer: <RestrictionId>[
          RestrictionId.wheat,
          RestrictionId.gluten,
          RestrictionId.fish,
          RestrictionId.crustaceans,
          RestrictionId.molluscs,
        ],
        KitchenSignalKind.wok: <RestrictionId>[
          RestrictionId.peanuts,
          RestrictionId.soy,
          RestrictionId.wheat,
          RestrictionId.gluten,
          RestrictionId.crustaceans,
          RestrictionId.molluscs,
          RestrictionId.sesame,
        ],
        KitchenSignalKind.sharedGrill: <RestrictionId>[
          RestrictionId.fish,
          RestrictionId.crustaceans,
          RestrictionId.molluscs,
        ],
        KitchenSignalKind.bakery: <RestrictionId>[
          RestrictionId.milk,
          RestrictionId.eggs,
          RestrictionId.wheat,
          RestrictionId.gluten,
          RestrictionId.sesame,
        ],
        KitchenSignalKind.nuts: <RestrictionId>[
          RestrictionId.peanuts,
          RestrictionId.treeNuts,
        ],
        KitchenSignalKind.sesame: <RestrictionId>[RestrictionId.sesame],
      });
    });
  });

  group('what counts as a signal', () {
    test('stir fried, pan fried, air fried and fried rice are no fryer', () {
      // Act
      final kinds = _kinds(
        _menuOf(<String>[
          'Stir fried vegetables',
          'Pan fried sea bass',
          'Air fried wings',
          'Egg fried rice',
          'אורז מטוגן',
        ]),
      );

      // Assert
      expect(kinds, <KitchenSignalKind>[KitchenSignalKind.wok]);
    });

    test('chocolate chips are no fryer; fish and chips are', () {
      expect(_kinds(_menuOf(<String>['Chocolate chips'])), isEmpty);
      expect(_kinds(_menuOf(<String>['Fish and chips'])), <KitchenSignalKind>[
        KitchenSignalKind.fryer,
      ]);
    });

    test('chips tossed in oil are a fryer dish, not a wok dish', () {
      expect(
        _kinds(_menuOf(<String>["צ'יפס מוקפץ בשמן כמהין"])),
        <KitchenSignalKind>[KitchenSignalKind.fryer],
      );
    });

    test('a grill with meat only, or with a plant burger, is not shared', () {
      expect(_kinds(kitchenSignalMenus['grill_meat_only']!), isEmpty);
      expect(_kinds(kitchenSignalMenus['grill_vegan_burger']!), isEmpty);
    });

    test('a Grill heading puts its dishes on the grill', () {
      // Act
      final signals = _signals(kitchenSignalMenus['grill_by_heading']!);

      // Assert
      expect(signals.single.kind, KitchenSignalKind.sharedGrill);
      expect(signals.single.evidence, contains('Salmon fillet'));
      expect(signals.single.evidence, contains('Lamb chops'));
    });

    test('a Wok heading makes a wok of its dishes', () {
      // Act
      final signals = _signals(kitchenSignalMenus['wok_and_heading']!);

      // Assert
      expect(signals.first.kind, KitchenSignalKind.wok);
      expect(signals.first.evidence, contains('Chicken teriyaki'));
    });

    test('Hebrew prefixes count, except before challah', () {
      expect(_kinds(_menuOf(<String>['בלחם קלוי'])), <KitchenSignalKind>[
        KitchenSignalKind.bakery,
      ]);
      expect(_kinds(_menuOf(<String>['חלה טרייה'])), <KitchenSignalKind>[
        KitchenSignalKind.bakery,
      ]);
      expect(_kinds(_menuOf(<String>['החלה הגדולה'])), isEmpty);
    });

    test('breadcrumbs and a bun are not bread', () {
      expect(_kinds(_menuOf(<String>['Breadcrumbs'])), isEmpty);
      expect(_kinds(_menuOf(<String>['Hamburger in a bun'])), isEmpty);
    });

    test('an option names a fryer; a removal does not', () {
      // Act
      final signals = _signals(kitchenSignalMenus['options_and_removals']!);

      // Assert
      expect(signals.map((signal) => signal.kind), <KitchenSignalKind>[
        KitchenSignalKind.fryer,
      ]);
      expect(signals.single.evidence, <String>['Burger']);
    });

    test('nuts and sesame come from the matcher, guards included', () {
      // Act
      final signals = _signals(kitchenSignalMenus['nuts_and_sesame']!);

      // Assert
      expect(signals.map((signal) => signal.kind), <KitchenSignalKind>[
        KitchenSignalKind.nuts,
        KitchenSignalKind.sesame,
      ]);
      expect(signals.first.evidence, <String>['Peanut noodles', 'Baklava']);
      expect(
        signals.first.evidence,
        isNot(contains('Green salad')),
        reason: 'almond-free is guarded',
      );
    });

    test('a heading naming nuts makes every dish under it evidence', () {
      // Act
      final signals = _signals(kitchenSignalMenus['nuts_heading']!);

      // Assert
      expect(signals.single.evidence, <String>['Trail mix', 'Granola']);
    });

    test('the live vocabulary is the default for of()', () {
      // Arrange
      final menu = kitchenSignalMenus['fried_cap_and_seafood']!;

      // Assert
      expect(
        KitchenSignals.of(menu),
        KitchenSignals.ofWith(menu, allergenVocabulary),
      );
    });
  });

  group('the shape of a result', () {
    final menus = <String, Menu>{
      'wolt': _wolt(),
      'tenbis': _tenBis(),
      ...goldenHandBuiltMenus,
      ...kitchenSignalMenus,
    };

    test('signals come in kind order, at most one per kind', () {
      for (final menu in menus.values) {
        final indexes = [
          for (final signal in _signals(menu)) signal.kind.index,
        ];
        expect(indexes, orderedEquals([...indexes]..sort()));
        expect(indexes.toSet(), hasLength(indexes.length));
      }
    });

    test('evidence is 1 to 3 distinct dish names the menu prints', () {
      for (final menu in menus.values) {
        final printed = <String>{
          for (final category in menu.categories)
            for (final dish in category.dishes) dish.name,
        };
        for (final signal in _signals(menu)) {
          expect(signal.evidence, isNotEmpty);
          expect(signal.evidence.length, lessThanOrEqualTo(3));
          expect(signal.evidence.toSet(), hasLength(signal.evidence.length));
          expect(printed.containsAll(signal.evidence), isTrue);
        }
      }
    });

    test('a repeated dish name is one piece of evidence', () {
      // Act
      final signal = _signals(
        _menuOf(<String>['French fries', 'French fries', 'Onion rings']),
      ).single;

      // Assert
      expect(signal.evidence, <String>['French fries', 'Onion rings']);
    });

    test('threatened restrictions are taxonomy ids in enum order', () {
      // Arrange
      final known = <RestrictionId>{
        for (final restriction in restrictionTaxonomy) restriction.id,
      };

      // Assert
      for (final menu in menus.values) {
        for (final signal in _signals(menu)) {
          final indexes = [for (final id in signal.threatens) id.index];
          expect(known.containsAll(signal.threatens), isTrue);
          expect(indexes, orderedEquals([...indexes]..sort()));
          expect(signal.threatens.toSet(), hasLength(indexes.length));
        }
      }
    });

    test('every kind is reached by some menu', () {
      // Arrange
      final reached = <KitchenSignalKind>{
        for (final menu in menus.values) ..._kinds(menu),
      };

      // Assert
      expect(reached, KitchenSignalKind.values.toSet());
    });

    test('signals compare by value', () {
      // Arrange
      final menu = _menuOf(<String>['French fries']);

      // Assert
      expect(_signals(menu), _signals(menu));
      expect(_signals(menu).single.hashCode, _signals(menu).single.hashCode);
    });
  });

  group('the questions', () {
    final questions = <KitchenSignalKind, KitchenSignal>{};
    setUpAll(() {
      for (final menu in <Menu>[
        kitchenSignalMenus['fried_cap_and_seafood']!,
        kitchenSignalMenus['wok_and_heading']!,
        kitchenSignalMenus['grill_by_heading']!,
        kitchenSignalMenus['bakery_and_prefixes']!,
        kitchenSignalMenus['nuts_and_sesame']!,
      ]) {
        for (final signal in _signals(menu)) {
          questions.putIfAbsent(signal.kind, () => signal);
        }
      }
    });

    test('every kind has a question in both languages', () {
      expect(questions.keys.toSet(), KitchenSignalKind.values.toSet());
      for (final signal in questions.values) {
        expect(signal.questionEn, endsWith('?'));
        expect(signal.questionHe, endsWith('?'));
        expect(signal.questionHe, matches(RegExp('[א-ת]')));
      }
      expect(
        questions.values.map((signal) => signal.questionEn).toSet(),
        hasLength(KitchenSignalKind.values.length),
      );
      expect(
        questions.values.map((signal) => signal.questionHe).toSet(),
        hasLength(KitchenSignalKind.values.length),
      );
    });

    test('no question uses a banned or reassuring word', () {
      for (final signal in questions.values) {
        for (final word in _bannedEnglish) {
          expect(
            signal.questionEn.toLowerCase(),
            isNot(contains(word)),
            reason: '${signal.kind.name}: $word',
          );
        }
        for (final word in _bannedHebrew) {
          expect(
            signal.questionHe,
            isNot(contains(word)),
            reason: '${signal.kind.name}: $word',
          );
        }
      }
    });
  });
}
