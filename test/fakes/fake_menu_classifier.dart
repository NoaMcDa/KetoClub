import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';

/// A scripted [MenuClassifier] for tests.
///
/// With no scripted result set, [classify] derives a trivially valid
/// [MenuAnalysed] from the menu it is given: every dish is verdict
/// [DishVerdict.orderAsIs] with a fixed non-empty [defaultWhy], nothing
/// is [MenuAnalysed.unclassified], and the result is stamped
/// [derivedEngine] (a [RulesEngine] by default), recording the options it
/// was given the way every real classifier does — so it satisfies the
/// classifier contract suite on any input without a test having to build
/// a result by hand. Call
/// [respondWith] to make every subsequent call return a specific
/// [MenuAnalysis] instead. Every call is recorded in [calls].
class FakeMenuClassifier implements MenuClassifier {
  /// Creates a fake with no scripted result.
  new();

  /// Why every default-derived dish is marked safe. Not a real
  /// analysis — only the shape a working classifier must return.
  static const String defaultWhy =
      'FakeMenuClassifier default verdict; no real analysis performed.';

  MenuAnalysis? _scripted;

  /// The engine a default-derived result is stamped with. A
  /// [RulesEngine] unless a test needs an LLM-shaped result — the only
  /// kind `MenuController` ever reuses from the cache (issue #57).
  AnalysisEngine derivedEngine = const RulesEngine(
    reason: MenuAnalysisFailureReason.notConfigured,
  );

  /// Every menu and options this fake was asked to classify, in call
  /// order.
  final List<(Menu, ClassificationOptions)> calls =
      <(Menu, ClassificationOptions)>[];

  /// Makes every future [classify] call return [result] instead of the
  /// default derived analysis.
  // ignore: use_setters_to_change_properties, reads as an action.
  void respondWith(MenuAnalysis result) {
    _scripted = result;
  }

  @override
  Future<MenuAnalysis> classify(
    Menu menu, {
    ClassificationOptions options = const ClassificationOptions(),
  }) async {
    calls.add((menu, options));
    final scripted = _scripted;
    if (scripted != null) return scripted;
    return MenuAnalysed(
      dishes: [
        for (final dish in menu.allDishes)
          AnalysedDish(
            dishId: dish.id,
            name: dish.name,
            verdict: DishVerdict.orderAsIs,
            why: defaultWhy,
          ),
      ],
      unclassified: const <String>[],
      engine: derivedEngine,
      analysedAt: DateTime.utc(2026),
      options: options.snapshot,
    );
  }
}
