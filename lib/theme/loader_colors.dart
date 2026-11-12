import 'package:flutter/material.dart';
import 'package:ketoclub/theme/app_tokens.dart';

/// The colours of the loaders (issues #450, #451): the three foods that
/// circle while KetoClub waits — a steak, a fried egg and a lettuce leaf —
/// the dashed ring they circle, and the highlight that sweeps across a
/// loading placeholder.
///
/// A [ThemeExtension] like `NeutralSurfaces`, so a widget reads
/// [LoaderColors.of] and both themes stay correct with no colour of its
/// own (`test/architecture/theme_tokens_test.dart`).
@immutable
final class LoaderColors extends ThemeExtension<LoaderColors> {
  /// Creates loader colours from explicit values.
  const new({
    required this.meat,
    required this.meatFat,
    required this.bone,
    required this.eggWhite,
    required this.eggEdge,
    required this.yolk,
    required this.leaf,
    required this.vein,
    required this.ring,
    required this.sweep,
  });

  /// The light theme's loader colours.
  const new light()
    : meat = AppTokens.lightMeat,
      meatFat = AppTokens.lightMeatFat,
      bone = AppTokens.lightBone,
      eggWhite = AppTokens.lightEggWhite,
      eggEdge = AppTokens.lightEggEdge,
      yolk = AppTokens.lightYolk,
      leaf = AppTokens.lightLeaf,
      vein = AppTokens.lightVein,
      ring = AppTokens.lightRing,
      sweep = AppTokens.lightSweep;

  /// The dark theme's loader colours.
  const new dark()
    : meat = AppTokens.darkMeat,
      meatFat = AppTokens.darkMeatFat,
      bone = AppTokens.darkBone,
      eggWhite = AppTokens.darkEggWhite,
      eggEdge = AppTokens.darkEggEdge,
      yolk = AppTokens.darkYolk,
      leaf = AppTokens.darkLeaf,
      vein = AppTokens.darkVein,
      ring = AppTokens.darkRing,
      sweep = AppTokens.darkSweep;

  /// The steak.
  final Color meat;

  /// The steak's marbling.
  final Color meatFat;

  /// The steak's bone.
  final Color bone;

  /// The egg white.
  final Color eggWhite;

  /// The hairline round the egg white.
  final Color eggEdge;

  /// The yolk.
  final Color yolk;

  /// The lettuce leaf.
  final Color leaf;

  /// The leaf's veins.
  final Color vein;

  /// The dashed ring the foods circle.
  final Color ring;

  /// The highlight that sweeps across a loading placeholder.
  final Color sweep;

  /// The [LoaderColors] registered on the ambient [Theme], or the light
  /// theme's for a bare `MaterialApp` with no `theme:`, as the other
  /// extensions' readers fall back.
  // ignore: prefer_constructors_over_static_methods
  static LoaderColors of(BuildContext context) =>
      Theme.of(context).extension<LoaderColors>() ?? const LoaderColors.light();

  @override
  LoaderColors copyWith({
    Color? meat,
    Color? meatFat,
    Color? bone,
    Color? eggWhite,
    Color? eggEdge,
    Color? yolk,
    Color? leaf,
    Color? vein,
    Color? ring,
    Color? sweep,
  }) {
    return LoaderColors(
      meat: meat ?? this.meat,
      meatFat: meatFat ?? this.meatFat,
      bone: bone ?? this.bone,
      eggWhite: eggWhite ?? this.eggWhite,
      eggEdge: eggEdge ?? this.eggEdge,
      yolk: yolk ?? this.yolk,
      leaf: leaf ?? this.leaf,
      vein: vein ?? this.vein,
      ring: ring ?? this.ring,
      sweep: sweep ?? this.sweep,
    );
  }

  @override
  LoaderColors lerp(ThemeExtension<LoaderColors>? other, double t) {
    if (other is! LoaderColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return LoaderColors(
      meat: mix(meat, other.meat),
      meatFat: mix(meatFat, other.meatFat),
      bone: mix(bone, other.bone),
      eggWhite: mix(eggWhite, other.eggWhite),
      eggEdge: mix(eggEdge, other.eggEdge),
      yolk: mix(yolk, other.yolk),
      leaf: mix(leaf, other.leaf),
      vein: mix(vein, other.vein),
      ring: mix(ring, other.ring),
      sweep: mix(sweep, other.sweep),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LoaderColors &&
      other.meat == meat &&
      other.meatFat == meatFat &&
      other.bone == bone &&
      other.eggWhite == eggWhite &&
      other.eggEdge == eggEdge &&
      other.yolk == yolk &&
      other.leaf == leaf &&
      other.vein == vein &&
      other.ring == ring &&
      other.sweep == sweep;

  @override
  int get hashCode => Object.hash(
    meat,
    meatFat,
    bone,
    eggWhite,
    eggEdge,
    yolk,
    leaf,
    vein,
    ring,
    sweep,
  );
}
