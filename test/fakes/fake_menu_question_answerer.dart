import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/menu_question.dart';
import 'package:ketoclub/services/classifier/menu_question_answerer.dart';

/// A scripted [MenuQuestionAnswerer] for tests.
///
/// Script responses with [enqueue]; if the queue is empty, [ask] returns
/// a [MenuQuestionFailed] with [MenuQuestionFailureReason.badResponse].
/// Every call is recorded in [calls].
final class FakeMenuQuestionAnswerer implements MenuQuestionAnswerer {
  /// Creates a fake with no scripted result.
  new();

  final List<MenuQuestionResult> _queue = <MenuQuestionResult>[];

  /// Every call received, in call order — `(menu, analysis, question)`.
  final List<({Menu menu, MenuAnalysed analysis, String question})> calls =
      <({Menu menu, MenuAnalysed analysis, String question})>[];

  /// Queues [result] as the next response.
  void enqueue(MenuQuestionResult result) => _queue.add(result);

  /// Queues a [MenuQuestionAnswered] with [answer] and optional [dishIds].
  void enqueueAnswer(
    String answer, {
    List<String> dishIds = const <String>[],
  }) =>
      enqueue(MenuQuestionAnswered(answer: answer, referencedDishIds: dishIds));

  @override
  Future<MenuQuestionResult> ask(
    Menu menu,
    MenuAnalysed analysis,
    String question,
  ) async {
    calls.add((menu: menu, analysis: analysis, question: question));
    if (_queue.isEmpty) {
      return const MenuQuestionFailed(
        reason: MenuQuestionFailureReason.badResponse,
      );
    }
    return _queue.removeAt(0);
  }
}
