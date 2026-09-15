import 'package:flutter/material.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/theme/app_tokens.dart';

/// The five colours one verdict needs, read off the artboard's own
/// `verdictStyles` table (`.design/Main.dc.html` around line 178).
///
/// The artboard names seven roles per verdict (`rail`, `pillBg`, `pillFg`,
/// `cardBg`, `cardEdge`, `carbBg`, `carbFg`) but only ever draws from four
/// underlying tokens per colour family — the base colour, its `-tint`, its
/// `-ink` and its `-on` — plus the base colour again for the rail. This
/// class exposes exactly those four tokens under five names so a caller
/// never has to know the family prefix:
///
/// - [rail]: the saturated base colour (`--green` / `--amber` / `--red`).
///   Used for the artboard's `rail` role, identically for every verdict.
/// - [pill]: the artboard's `pillBg` — the base colour for green and amber,
///   but the *tint* for red, because the artboard renders "Not keto" as a
///   quieter badge than the other two. Carried through verbatim rather than
///   normalised, so the rendered pill matches the design.
/// - [tint]: the soft `-tint` background, used for card backgrounds and the
///   carb badge (the artboard's `carbBg` for amber and red; green's card
///   uses it too even though its `carbBg` role happens to be `--surface`).
/// - [ink]: the `-ink` token — the artboard's `carbFg` for every verdict,
///   and also its `pillFg` for red (since red's pill uses [tint], its
///   foreground needs the ink-strength colour, not [on]).
/// - [on]: the `-on` token — the artboard's `pillFg` for green and amber,
///   where the pill background is the loud, saturated [pill] colour.
@immutable
final class VerdictTone {
  /// Creates a tone from its five resolved colours.
  const new({
    required this.rail,
    required this.pill,
    required this.tint,
    required this.ink,
    required this.on,
  });

  /// Linearly interpolates between [a] and [b], field by field.
  ///
  // The lint below wants this factory's own name written without repeating
  // the class ("VerdictTone.lerp" -> just ".lerp"), but Dart's constructor
  // grammar accepts the type-name-elision shorthand only for the unnamed
  // constructor (as `new`, used above); a named constructor still requires
  // its enclosing class name. Suppressed rather than worked around with an
  // invalid syntax.
  // ignore: unnecessary_type_name_in_constructor
  factory VerdictTone.lerp(VerdictTone a, VerdictTone b, double t) {
    return VerdictTone(
      rail: Color.lerp(a.rail, b.rail, t) ?? b.rail,
      pill: Color.lerp(a.pill, b.pill, t) ?? b.pill,
      tint: Color.lerp(a.tint, b.tint, t) ?? b.tint,
      ink: Color.lerp(a.ink, b.ink, t) ?? b.ink,
      on: Color.lerp(a.on, b.on, t) ?? b.on,
    );
  }

  /// The saturated base colour: left rail, icons, strong accents.
  final Color rail;

  /// Background for the loud pill variant (see the class doc comment for
  /// why this is not always equal to [rail]).
  final Color pill;

  /// The soft tint background for cards and secondary badges.
  final Color tint;

  /// High-contrast text/foreground for content drawn on [tint] (or, for the
  /// verdict whose [pill] is itself a tint, on [pill] too).
  final Color ink;

  /// Foreground for content drawn on the loud [pill] background.
  final Color on;

  /// Returns a copy with the given fields replaced.
  VerdictTone copyWith({
    Color? rail,
    Color? pill,
    Color? tint,
    Color? ink,
    Color? on,
  }) {
    return VerdictTone(
      rail: rail ?? this.rail,
      pill: pill ?? this.pill,
      tint: tint ?? this.tint,
      ink: ink ?? this.ink,
      on: on ?? this.on,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VerdictTone &&
      other.rail == rail &&
      other.pill == pill &&
      other.tint == tint &&
      other.ink == ink &&
      other.on == on;

  @override
  int get hashCode => Object.hash(rail, pill, tint, ink, on);
}

/// A [ThemeExtension] carrying the three verdict palettes (architecture.md
/// §6.6): green ("order as-is"), amber ("modify") and red ("not keto").
///
/// Registered on both [ThemeData.extensions] in `app_theme.dart`. Widgets
/// read it through [VerdictColors.of], never by constructing their own
/// [VerdictTone].
@immutable
final class VerdictColors extends ThemeExtension<VerdictColors> {
  /// Creates a set of verdict palettes.
  const new({required this.green, required this.amber, required this.red});

  /// The light-mode palette, built straight from [AppTokens] — see the
  /// class doc comment for how the artboard's roles map onto [VerdictTone].
  ///
  /// `app_theme.dart` uses this to build `AppTheme.light`; [of] uses it as
  /// the fallback when no [VerdictColors] is registered on the ambient
  /// theme. Defined here rather than in `app_theme.dart` so this file never
  /// has to import that one — `app_theme.dart` already imports this file to
  /// register the palette, and the reverse import would be a cycle
  /// (architecture.md §18.2).
  // ignore: unnecessary_type_name_in_constructor
  factory VerdictColors.light() {
    return const VerdictColors(
      green: VerdictTone(
        rail: AppTokens.lightGreen,
        pill: AppTokens.lightGreen,
        tint: AppTokens.lightGreenTint,
        ink: AppTokens.lightGreenInk,
        on: AppTokens.lightGreenOn,
      ),
      amber: VerdictTone(
        rail: AppTokens.lightAmber,
        pill: AppTokens.lightAmber,
        tint: AppTokens.lightAmberTint,
        ink: AppTokens.lightAmberInk,
        on: AppTokens.lightAmberOn,
      ),
      red: VerdictTone(
        rail: AppTokens.lightRed,
        // The artboard renders "Not keto" as a quieter tint pill, not the
        // loud red — see the class doc comment above.
        pill: AppTokens.lightRedTint,
        tint: AppTokens.lightRedTint,
        ink: AppTokens.lightRedInk,
        on: AppTokens.lightRedOn,
      ),
    );
  }

  /// The dark-mode palette, the [VerdictColors.light] of `app_theme.dart`'s
  /// dark theme.
  // ignore: unnecessary_type_name_in_constructor
  factory VerdictColors.dark() {
    return const VerdictColors(
      green: VerdictTone(
        rail: AppTokens.darkGreen,
        pill: AppTokens.darkGreen,
        tint: AppTokens.darkGreenTint,
        ink: AppTokens.darkGreenInk,
        on: AppTokens.darkGreenOn,
      ),
      amber: VerdictTone(
        rail: AppTokens.darkAmber,
        pill: AppTokens.darkAmber,
        tint: AppTokens.darkAmberTint,
        ink: AppTokens.darkAmberInk,
        on: AppTokens.darkAmberOn,
      ),
      red: VerdictTone(
        rail: AppTokens.darkRed,
        pill: AppTokens.darkRedTint,
        tint: AppTokens.darkRedTint,
        ink: AppTokens.darkRedInk,
        on: AppTokens.darkRedOn,
      ),
    );
  }

  /// The "order as-is" tone.
  final VerdictTone green;

  /// The "modify" tone.
  final VerdictTone amber;

  /// The "not keto" tone.
  final VerdictTone red;

  /// The tone for [verdict]. An exhaustive switch with no `default`: adding
  /// a [DishVerdict] value without updating this function is a compile
  /// error (architecture.md §10).
  VerdictTone forVerdict(DishVerdict verdict) => switch (verdict) {
    DishVerdict.orderAsIs => green,
    DishVerdict.modifiable => amber,
    DishVerdict.nonKeto => red,
  };

  /// Reads the [VerdictColors] registered on the ambient [Theme].
  ///
  /// Falls back to [VerdictColors.light] when none is registered, rather
  /// than a bare `!`: many existing widget tests pump a bare [MaterialApp]
  /// with no `theme:` argument (the same palette `AppTheme.light`
  /// registers), and this keeps those tests passing without editing every
  /// one of them.
  ///
  /// Static rather than a constructor, and lint-suppressed accordingly:
  /// `of(context)` is Flutter's own convention for reading something off
  /// the ambient tree (`Theme.of`, `MediaQuery.of`), and a constructor
  /// named `VerdictColors.of` would read as though it built a new palette
  /// rather than looking one up.
  // ignore: prefer_constructors_over_static_methods
  static VerdictColors of(BuildContext context) {
    final extension = Theme.of(context).extension<VerdictColors>();
    return extension ?? VerdictColors.light();
  }

  @override
  VerdictColors copyWith({
    VerdictTone? green,
    VerdictTone? amber,
    VerdictTone? red,
  }) {
    return VerdictColors(
      green: green ?? this.green,
      amber: amber ?? this.amber,
      red: red ?? this.red,
    );
  }

  @override
  VerdictColors lerp(ThemeExtension<VerdictColors>? other, double t) {
    if (other is! VerdictColors) return this;
    return VerdictColors(
      green: VerdictTone.lerp(green, other.green, t),
      amber: VerdictTone.lerp(amber, other.amber, t),
      red: VerdictTone.lerp(red, other.red, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VerdictColors &&
      other.green == green &&
      other.amber == amber &&
      other.red == red;

  @override
  int get hashCode => Object.hash(green, amber, red);
}
