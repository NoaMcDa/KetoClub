import 'package:flutter/material.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/utils/allergens/chef_card_locales.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/group_chef_card.dart';

/// The chef card as it is drawn for the shared image (Banto, issue #420):
/// the card's own lines in its [language] — numbered for one person, or
/// the group card's greeting, sections and closing ([group]) — and a
/// footer, also in [language], that says the app is a helper and not a
/// guarantee ([ChefCardText.imageFooter]).
///
/// Always drawn in the light theme, whatever the app's, so the image
/// reads the same on any screen it is sent to; and in the card's own
/// direction (right to left for Hebrew). Holds no Copy or Share button:
/// what is drawn here is exactly what is shared, and nothing else.
class ChefCardImage extends StatelessWidget {
  /// Creates the image of a one-person card made of [lines], or of [group]
  /// when it is given.
  const new({
    required this.lines,
    required this.language,
    this.group,
    super.key,
  });

  /// The one-person card's lines; unused when [group] is given.
  final List<String> lines;

  /// The group card, or null for a one-person card.
  final GroupChefCard? group;

  /// The language the card is in, for the footer and the direction.
  final ChefCardLanguage language;

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.light(),
    child: Directionality(
      textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Builder(builder: _card),
    ),
  );

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    final card = group;
    final bold = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (card == null)
              ..._numbered(lines)
            else ...[
              Text(card.intro, style: theme.textTheme.titleMedium),
              if (card.dishLine.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(card.dishLine, style: bold),
              ],
              for (final section in card.sections) ...[
                const SizedBox(height: 16),
                Text(section.heading, style: bold),
                const SizedBox(height: 8),
                ..._numbered(section.lines),
              ],
              if (card.closing.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(card.closing, style: theme.textTheme.titleMedium),
              ],
            ],
            const SizedBox(height: 18),
            Divider(height: 1, color: theme.dividerColor),
            const SizedBox(height: 10),
            Text(
              ChefCardText.imageFooter(language),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _numbered(List<String> lines) => <Widget>[
    for (var i = 0; i < lines.length; i++)
      Padding(
        padding: EdgeInsetsDirectional.only(
          bottom: i == lines.length - 1 ? 0 : 12,
        ),
        child: _Line(number: i + 1, text: lines[i]),
      ),
  ];
}

/// One numbered line of the image, the Waiter Card's amber number beside
/// the text.
class _Line extends StatelessWidget {
  const new({required this.number, required this.text});

  /// The 1-based line number.
  final int number;

  /// The line's text.
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amber = VerdictColors.of(context).forVerdict(DishVerdict.modifiable);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: amber.pill, shape: BoxShape.circle),
          child: Text(
            number.toString(),
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: 13,
              color: amber.on,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              height: 1.38,
            ),
          ),
        ),
      ],
    );
  }
}
