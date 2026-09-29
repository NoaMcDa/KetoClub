import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';

/// A scripted [ScannedMenuClassifier] for tests.
///
/// With no scripted result set, [classify] stands in for a working vision
/// classifier: a scan with at least one page is read as one dish per page
/// ("Scanned dish 1", …) in a single `scanned` category, under a
/// `MenuSource.scan` reference, every dish [DishVerdict.orderAsIs] with a
/// fixed [defaultWhy], stamped [derivedEngine] and recording the options
/// it was given; a scan with no pages answers
/// [MenuAnalysisFailureReason.noDishesFound]. Call [respondWith] to make
/// every later call return a specific [ScannedMenuResult] instead. Every
/// call is recorded in [calls].
///
/// Like `FakeMenuClassifier`, set [announces] to the engines to announce
/// through [ClassificationOptions.onEngineStarted] at the start of each
/// call, and [gate] to hold every call open until that future completes.
final class FakeScannedMenuClassifier implements ScannedMenuClassifier {
  /// Creates a fake with no scripted result.
  new();

  /// Why every default-derived dish is marked safe. Not a real
  /// analysis — only the shape a working classifier must return.
  static const String defaultWhy =
      'FakeScannedMenuClassifier default verdict; no real analysis '
      'performed.';

  /// The fixed time a default-derived menu and analysis are stamped with.
  static final DateTime defaultReadAt = DateTime.utc(2026);

  ScannedMenuResult? _scripted;

  /// The engines each [classify] call announces, in order, before it
  /// answers; empty (the default) announces nothing.
  List<ClassifyingEngine> announces = const <ClassifyingEngine>[];

  /// When non-null, every [classify] call waits for this future — after
  /// announcing [announces] — before it answers.
  Future<void>? gate;

  /// The engine a default-derived analysis is stamped with.
  AnalysisEngine derivedEngine = const LlmEngine(model: 'fake/vision');

  /// Every scan and options this fake was asked to classify, in call
  /// order.
  final List<(ScannedMenu, ClassificationOptions)> calls =
      <(ScannedMenu, ClassificationOptions)>[];

  /// Makes every future [classify] call return [result] instead of the
  /// default derived one.
  // ignore: use_setters_to_change_properties, reads as an action.
  void respondWith(ScannedMenuResult result) {
    _scripted = result;
  }

  @override
  Future<ScannedMenuResult> classify(
    ScannedMenu scan, {
    required ClassificationOptions options,
  }) async {
    calls.add((scan, options));
    final listener = options.onEngineStarted;
    if (listener != null) announces.forEach(listener);
    final pending = gate;
    if (pending != null) await pending;
    final scripted = _scripted;
    if (scripted != null) return scripted;
    if (scan.pages.isEmpty) {
      return const ScannedMenuFailed(
        reason: MenuAnalysisFailureReason.noDishesFound,
      );
    }
    final dishes = <Dish>[
      for (var i = 1; i <= scan.pages.length; i++)
        Dish(
          id: 'v$i',
          name: 'Scanned dish $i',
          description: '',
          price: 0,
          options: const <DishOption>[],
        ),
    ];
    final menu = Menu(
      venueRef: VenueRef(
        source: MenuSource.scan,
        platformId: 'fake-scan-${calls.length}',
      ),
      currency: 'ILS',
      fetchedAt: defaultReadAt,
      categories: <MenuCategory>[
        MenuCategory(id: 'scanned', name: 'scanned', dishes: dishes),
      ],
    );
    return ScannedMenuRead(
      menu: menu,
      analysis: MenuAnalysed(
        dishes: <AnalysedDish>[
          for (final dish in dishes)
            AnalysedDish(
              dishId: dish.id,
              name: dish.name,
              verdict: DishVerdict.orderAsIs,
              why: defaultWhy,
            ),
        ],
        unclassified: const <String>[],
        engine: derivedEngine,
        analysedAt: defaultReadAt,
        options: options.snapshot,
      ),
    );
  }
}
