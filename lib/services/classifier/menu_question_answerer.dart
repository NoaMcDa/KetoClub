import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/menu_question.dart';

/// Answers one free-text question about a menu that has already been analysed
/// (architecture.md §9.5; issue #214).
///
/// One call per user question, no history — see `LlmMenuQuestionAnswerer` for
/// the concrete implementation. There is no rules fallback for questions: a
/// rules engine has no way to reason about a free-text question.
abstract interface class MenuQuestionAnswerer {
  /// Sends [question] about [menu] — grounded in [analysis] — to the model
  /// and returns the answer.
  ///
  /// Never throws: transport failures, parse failures, and consent checks are
  /// all represented as [MenuQuestionFailed] variants.
  Future<MenuQuestionResult> ask(
    Menu menu,
    MenuAnalysed analysis,
    String question,
  );
}
