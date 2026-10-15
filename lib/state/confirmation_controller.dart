import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/storage/notes_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/utils/allergens/confirmations.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';

/// One answer to "Did you ask about X in this dish?" (ALG-14).
enum ConfirmationAnswer {
  /// The staff said it is in the dish.
  present,

  /// The staff said it is not in the dish.
  absent,

  /// The person did not ask; nothing is recorded.
  notAsked,
}

/// One dish of the post-meal prompt: the dish, the concerns the profile
/// has about it, and whether it carried a change to ask for.
@immutable
final class ConfirmationDish {
  /// Creates the prompt's entry for [dish].
  const new({
    required this.dish,
    required this.concerns,
    required this.hasChange,
  });

  /// The dish as the menu printed it.
  final Dish dish;

  /// The concerns the profile has about [dish], one question each.
  final List<Concern> concerns;

  /// Whether the evaluation asked the kitchen for a change, so the prompt
  /// asks whether it was made.
  final bool hasChange;
}

/// The post-meal "Did you ask the staff?" prompt for one menu in the
/// Recent tab (Banto, ALG-14, issue #356; architecture.md D27).
///
/// [load] reads the menu's cached copy and analysis, the profile the
/// device holds now (the union of the active people's, as the menu screen
/// reads it) and the visit history entry, and lists every analysed dish
/// the profile has a concern about, with that concern exactly as the menu
/// screen finds it before any earlier answer. Today's answers already
/// recorded are shown again so they can be corrected; an earlier day's are
/// history and are never rewritten.
///
/// [save] writes the answers with the visit history
/// ([VisitHistoryStore.setConfirmations]) stamped with today's date from
/// the clock, and each changed note to the [NotesStore]. "Didn't ask" is
/// recorded as nothing, and nothing is written when nothing changed. None
/// of it leaves the device (D26 C1).
final class ConfirmationController extends ChangeNotifier {
  /// Creates the prompt for the menu [ref].
  new({
    required this.ref,
    required this._repository,
    required this._settings,
    required this._history,
    required this._notes,
    required this._clock,
  });

  /// The menu the prompt is about.
  final VenueRef ref;

  final MenuRepository _repository;
  final SettingsStore _settings;
  final VisitHistoryStore _history;
  final NotesStore _notes;
  final Clock _clock;

  bool _isLoading = true;
  bool _isAvailable = false;
  List<ConfirmationDish> _dishes = const <ConfirmationDish>[];
  DateTime _today = DateTime(1970);
  List<DishConfirmation> _stored = const <DishConfirmation>[];
  List<ChangeConfirmation> _storedChanges = const <ChangeConfirmation>[];
  final Map<String, ConfirmationAnswer> _answers =
      <String, ConfirmationAnswer>{};
  final Map<String, bool> _changes = <String, bool>{};
  Map<String, String> _loadedNotes = const <String, String>{};
  final Map<String, String> _notesDraft = <String, String>{};

  /// Whether [load] has not finished yet.
  bool get isLoading => _isLoading;

  /// Whether the prompt has something to ask: the menu is still on this
  /// device with an analysis, and its history entry exists. False while
  /// loading.
  bool get isAvailable => _isAvailable;

  /// The dishes to ask about, in menu order; empty when the profile has no
  /// concern about any of them.
  List<ConfirmationDish> get dishes => _dishes;

  /// The key one answer is held under: the dish and the concern's
  /// [Confirmations.keyOf].
  static String _key(String dishId, Concern concern) =>
      _keyOf(dishId, concern.restrictionId, concern.matchedText);

  /// The key of an answer about [id] (with [matchedText] for the user's
  /// own restriction) in the dish [dishId].
  static String _keyOf(String dishId, RestrictionId id, String? matchedText) =>
      '$dishId|${Confirmations.keyOf(id, matchedText)}';

  /// The key [confirmation] answers.
  static String _storedKey(DishConfirmation confirmation) => _keyOf(
    confirmation.dishId,
    confirmation.restrictionId,
    confirmation.matchedText,
  );

  /// The answer chosen for [concern] in the dish [dishId];
  /// [ConfirmationAnswer.notAsked] until one is.
  ConfirmationAnswer answerFor(String dishId, Concern concern) =>
      _answers[_key(dishId, concern)] ?? ConfirmationAnswer.notAsked;

  /// Chooses [answer] for [concern] in the dish [dishId].
  void setAnswer(String dishId, Concern concern, ConfirmationAnswer answer) {
    _answers[_key(dishId, concern)] = answer;
    notifyListeners();
  }

  /// Whether the kitchen made the change asked for on the dish [dishId];
  /// null when not answered.
  bool? changeFor(String dishId) => _changes[dishId];

  /// Records whether the kitchen made the change on the dish [dishId];
  /// null clears the answer.
  void setChange(String dishId, {required bool? honoured}) {
    if (honoured == null) {
      _changes.remove(dishId);
    } else {
      _changes[dishId] = honoured;
    }
    notifyListeners();
  }

  /// The note on the dish [dishId] as it stands in the prompt: the one on
  /// file until it is edited.
  String noteFor(String dishId) =>
      _notesDraft[dishId] ?? _loadedNotes[dishId] ?? '';

  /// Replaces the prompt's note on the dish [dishId] with [note]; written
  /// by [save]. Does not notify: the text field already shows it.
  void setNote(String dishId, String note) => _notesDraft[dishId] = note;

  /// Reads everything the prompt needs; see the class doc. Never throws.
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    final entry = await _history.read(ref);
    final cached = await _repository.cached(ref);
    final analysis = cached?.analysis;
    if (entry == null || cached == null || analysis is! MenuAnalysed) {
      _isAvailable = false;
      _isLoading = false;
      notifyListeners();
      return;
    }
    final settings = await _settings.read();
    final profile = GroupEvaluator.union(<DietaryProfile>[
      for (final named in settings.activeProfiles) named.profile,
    ]);
    final analysedById = <String, AnalysedDish>{
      for (final dish in analysis.dishes) dish.dishId: dish,
    };
    final dishes = <ConfirmationDish>[];
    for (final category in cached.menu.categories) {
      for (final dish in category.dishes) {
        final analysed = analysedById[dish.id];
        if (analysed == null) continue;
        final evaluated = ProfileEvaluator.evaluate(
          analysed,
          dish,
          profile,
          heading: category.name,
        );
        if (evaluated.concerns.isEmpty) continue;
        dishes.add(
          ConfirmationDish(
            dish: dish,
            concerns: evaluated.concerns,
            hasChange: evaluated.modification != null,
          ),
        );
      }
    }
    _dishes = List<ConfirmationDish>.unmodifiable(dishes);
    _today = confirmationDay(_clock.now());
    _stored = entry.confirmations;
    _storedChanges = entry.changeConfirmations;
    _answers.clear();
    _changes.clear();
    for (final confirmation in _stored) {
      if (confirmation.day != _today) continue;
      _answers[_storedKey(
        confirmation,
      )] = confirmation.polarity == ConfirmationPolarity.present
          ? ConfirmationAnswer.present
          : ConfirmationAnswer.absent;
    }
    for (final change in _storedChanges) {
      if (change.day == _today) _changes[change.dishId] = change.honoured;
    }
    _loadedNotes = await _notes.readAll(ref);
    _notesDraft.clear();
    _isAvailable = true;
    _isLoading = false;
    notifyListeners();
  }

  /// Writes the prompt's answers and notes; see the class doc. Returns
  /// whether anything was written. Never throws.
  Future<bool> save() async {
    if (!_isAvailable) return false;
    final asked = <String>{
      for (final item in _dishes)
        for (final concern in item.concerns) _key(item.dish.id, concern),
    };
    final confirmations = <DishConfirmation>[
      for (final confirmation in _stored)
        if (confirmation.day != _today ||
            !asked.contains(_storedKey(confirmation)))
          confirmation,
      for (final item in _dishes)
        for (final concern in item.concerns)
          if (_answerToday(item.dish.id, concern) case final polarity?)
            DishConfirmation(
              dishId: item.dish.id,
              restrictionId: concern.restrictionId,
              polarity: polarity,
              day: _today,
              source: concern.source,
              matchedText: concern.matchedText,
            ),
    ];
    final changeDishes = <String>{
      for (final item in _dishes)
        if (item.hasChange) item.dish.id,
    };
    final changes = <ChangeConfirmation>[
      for (final change in _storedChanges)
        if (change.day != _today || !changeDishes.contains(change.dishId))
          change,
      for (final dishId in changeDishes)
        if (_changes[dishId] case final honoured?)
          ChangeConfirmation(dishId: dishId, honoured: honoured, day: _today),
    ];
    var wrote = false;
    if (!listEquals(confirmations, _stored) ||
        !listEquals(changes, _storedChanges)) {
      await _history.setConfirmations(
        ref,
        confirmations: confirmations,
        changes: changes,
      );
      _stored = List<DishConfirmation>.unmodifiable(confirmations);
      _storedChanges = List<ChangeConfirmation>.unmodifiable(changes);
      wrote = true;
    }
    for (final MapEntry(key: dishId, value: draft) in _notesDraft.entries) {
      final note = draft.trim();
      if (note == (_loadedNotes[dishId] ?? '')) continue;
      if (note.isEmpty) {
        await _notes.delete(ref, dishId);
      } else {
        await _notes.write(ref, dishId, note);
      }
      wrote = true;
    }
    _loadedNotes = await _notes.readAll(ref);
    _notesDraft.clear();
    return wrote;
  }

  /// The polarity to record today for [concern] in the dish [dishId], or
  /// null for "didn't ask".
  ConfirmationPolarity? _answerToday(String dishId, Concern concern) =>
      switch (answerFor(dishId, concern)) {
        ConfirmationAnswer.present => ConfirmationPolarity.present,
        ConfirmationAnswer.absent => ConfirmationPolarity.absent,
        ConfirmationAnswer.notAsked => null,
      };
}
