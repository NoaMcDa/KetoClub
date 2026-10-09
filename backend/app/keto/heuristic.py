"""The rules (heuristic) classifier (architecture.md §6.2, D25, #324).

The Python twin of ``lib/services/classifier/heuristic_menu_classifier.dart``:
:func:`classify_heuristic` runs :func:`app.keto.rules.match_dish` over every
dish of a menu and turns each result into a verdict, a ``why`` and, for a
modifiable dish, a waiter script. The golden ``heuristic.json`` pins the
whole :class:`~app.keto.models.MenuAnalysed` it returns.

* **Language** follows the dish's own text, not any UI locale: a dish whose
  rules text (:func:`app.keto.normaliser.dish_rules_text`) holds a Hebrew
  character gets the Hebrew ``why`` and dietary sentences.
* **Red** gets ``redWhy`` with ``{base}`` filled and no script. **Yellow**
  (carb sentences, dietary sentences, or both) gets ``yellowWhy`` when a
  carb sentence fired and ``dietaryRuleWhy`` otherwise, and a script of the
  carb sentences then the dietary ones, one per line. Everything else is
  **green** with ``greenWhy``.
* **Dietary rules** are switched on by the options' prompt fragments (a
  ``ClassificationOptions.seedOilFree`` is "the seed-oil fragment is in
  ``dietaryConstraints``") and run in the fixed order seed-oil, dairy,
  carnivore. ``netCarbLimitGrams`` changes nothing here: the vocabulary
  never estimates grams.
* The engine is ``rules`` with reason ``notConfigured`` (the router
  re-stamps the real reason), ``unclassified`` is always empty, the options
  snapshot is recorded as given, and ``schemaVersion`` keeps its default.

Pure: the caller supplies ``analysed_at`` (Dart's ``Clock.now()``, written
by ``DateTime.toIso8601String``), so nothing here reads the clock.
"""

from app.keto.models import (
    AnalysedDish,
    AnalysisOptionsSnapshot,
    Dish,
    Menu,
    MenuAnalysed,
    RulesEngine,
)
from app.keto.normaliser import contains_hebrew, dish_rules_text
from app.keto.rules import (
    match_dish,
    mentions_dairy,
    mentions_plant,
    mentions_seed_oil,
)
from app.keto.vocabulary import vocabulary


def classify_heuristic(
    menu: Menu, options_snapshot: AnalysisOptionsSnapshot, *, analysed_at: str
) -> MenuAnalysed:
    """``HeuristicMenuClassifier.classify(menu, options: ...)``.

    ``options_snapshot`` is the ``ClassificationOptions.snapshot`` the call
    ran under; ``analysed_at`` is the ISO-8601 timestamp to stamp.
    """
    return MenuAnalysed(
        dishes=[_analyse(dish, options_snapshot) for dish in menu.all_dishes()],
        unclassified=[],
        engine=RulesEngine(reason="notConfigured"),
        analysed_at=analysed_at,
        options=options_snapshot,
    )


def _analyse(dish: Dish, options: AnalysisOptionsSnapshot) -> AnalysedDish:
    templates = vocabulary().templates
    text = dish_rules_text(dish)
    is_hebrew = contains_hebrew(text)
    found = match_dish(dish)

    if found.is_non_keto:
        template = templates.red_why_he if is_hebrew else templates.red_why_en
        return AnalysedDish(
            dish_id=dish.id,
            name=dish.name,
            verdict="nonKeto",
            why=template.replace("{base}", found.base_label or ""),
        )

    dietary = _dietary_sentences(text, options, is_hebrew=is_hebrew)
    if found.instructions or dietary:
        if found.instructions:
            why = templates.yellow_why_he if is_hebrew else templates.yellow_why_en
        else:
            why = (
                templates.dietary_rule_why_he
                if is_hebrew
                else templates.dietary_rule_why_en
            )
        return AnalysedDish(
            dish_id=dish.id,
            name=dish.name,
            verdict="modifiable",
            why=why,
            modification="\n".join([*found.instructions, *dietary]),
        )

    return AnalysedDish(
        dish_id=dish.id,
        name=dish.name,
        verdict="orderAsIs",
        why=templates.green_why_he if is_hebrew else templates.green_why_en,
    )


def _dietary_sentences(
    text: str, options: AnalysisOptionsSnapshot, *, is_hebrew: bool
) -> list[str]:
    """The sentence of each dietary rule ``options`` switches on whose
    triggers ``text`` names: seed-oil, dairy, carnivore, in that order."""
    vocab = vocabulary()
    prompt = vocab.prompt
    templates = vocab.templates
    constraints = options.dietary_constraints
    sentences: list[str] = []
    if prompt.seed_oil_free_prompt_fragment in constraints and mentions_seed_oil(text):
        sentences.append(
            templates.seed_oil_free_modification_he
            if is_hebrew
            else templates.seed_oil_free_modification_en
        )
    if prompt.dairy_free_prompt_fragment in constraints and mentions_dairy(text):
        sentences.append(
            templates.dairy_free_modification_he
            if is_hebrew
            else templates.dairy_free_modification_en
        )
    if prompt.carnivore_only_prompt_fragment in constraints and mentions_plant(text):
        sentences.append(
            templates.carnivore_only_modification_he
            if is_hebrew
            else templates.carnivore_only_modification_en
        )
    return sentences
