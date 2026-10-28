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
* **Hidden carbs** (§9.4 rule 5a on the rules path, issue #213): a red has
  none; a yellow keeps its script and carries the rule match's flags; a dish
  that would be green with at least one flag is yellow with
  ``hiddenCarbWhy`` and the first flag's question as its script.
* **Dietary rules** are switched on by the options' prompt fragments (a
  ``ClassificationOptions.seedOilFree`` is "the seed-oil fragment is in
  ``dietaryConstraints``") and run in the fixed order seed-oil, dairy,
  carnivore. ``netCarbLimitGrams`` changes nothing here: the vocabulary
  never estimates grams.
* **Allergen concerns** (Banto; ALG-04b): when the snapshot's
  ``restrictionsRequested`` is true, every dish carries
  :func:`app.keto.rules.allergen_concerns`, whatever its verdict; otherwise
  none, so a keto analysis is byte-identical.
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
    allergen_concerns,
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
    # Banto (ALG-04b): attached only when asked for, so a keto-only analysis
    # serialises exactly as before (``concerns`` is omitted when empty).
    concerns = allergen_concerns(dish) if options.restrictions_requested else []

    if found.is_non_keto:
        template = templates.red_why_he if is_hebrew else templates.red_why_en
        return AnalysedDish(
            dish_id=dish.id,
            name=dish.name,
            verdict="nonKeto",
            why=template.replace("{base}", found.base_label or ""),
            concerns=concerns,
        )

    dietary = _dietary_sentences(text, options, is_hebrew=is_hebrew)
    hidden_carbs = list(found.hidden_carbs)
    if found.instructions or dietary:
        if found.instructions:
            why = templates.yellow_why_he if is_hebrew else templates.yellow_why_en
        else:
            why = (
                templates.dietary_rule_why_he
                if is_hebrew
                else templates.dietary_rule_why_en
            )
        # A yellow keeps its own script and carries the flags beside it.
        return AnalysedDish(
            dish_id=dish.id,
            name=dish.name,
            verdict="modifiable",
            why=why,
            modification="\n".join([*found.instructions, *dietary]),
            hidden_carbs=hidden_carbs,
            concerns=concerns,
        )

    if hidden_carbs:
        # §9.4 rule 5a on the rules path: the flag is the whole reason, so
        # its question is the instruction.
        return AnalysedDish(
            dish_id=dish.id,
            name=dish.name,
            verdict="modifiable",
            why=(
                templates.hidden_carb_why_he
                if is_hebrew
                else templates.hidden_carb_why_en
            ),
            modification=hidden_carbs[0].waiter_question,
            hidden_carbs=hidden_carbs,
            concerns=concerns,
        )

    return AnalysedDish(
        dish_id=dish.id,
        name=dish.name,
        verdict="orderAsIs",
        why=templates.green_why_he if is_hebrew else templates.green_why_en,
        concerns=concerns,
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
