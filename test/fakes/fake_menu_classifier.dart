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
/// [RulesEngine] — so it satisfies the classifier contract suite on any
/// input without a test having to build a result by hand. Call
/// [respondWith] to make every subsequent call return a specific
/// [MenuAnalysis] instead. Every call is recorded in [calls].
///
/// Like the real engines, it can announce itself through
/// [ClassificationOptions.onEngineStarted]: set [announces] to the
/// engines to announce, in order, at the start of each call (issue #65).
/// Set [gate] to hold every call open until that future completes, so a
/// test can look at the screen while classification is still running.
class FakeMenuClassifier implements MenuClassifier {
  /// Creates a fake with no scripted result.
  new();

  /// Why every default-derived dish is marked safe. Not a real
  /// analysis — only the shape a working classifier must return.
  static const String defaultWhy =
      'FakeMenuClassifier default verdict; no real analysis performed.';

  MenuAnalysis? _scripted;

  /// The engines each [classify] call announces, in order, before it
  /// answers; empty (the default) announces nothing, the way a
  /// classifier that predates issue #65 behaved.
  List<ClassifyingEngine> announces = const <ClassifyingEngine>[];

  /// When non-null, every [classify] call waits for this future — after
  /// announcing [announces] — before it answers.
  Future<void>? gate;

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
    final listener = options.onEngineStarted;
    if (listener != null) announces.forEach(listener);
    final pending = gate;
    if (pending != null) await pending;
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
      engine: const RulesEngine(
        reason: MenuAnalysisFailureReason.notConfigured,
      ),
      analysedAt: DateTime.utc(2026),
    );
  }
}
