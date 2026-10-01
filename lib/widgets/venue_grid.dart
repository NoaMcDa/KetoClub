import 'package:flutter/widgets.dart';
import 'package:ketoclub/widgets/venue_card.dart';

/// The widest the Discovery screen's content grows, in logical pixels
/// (issue #222): room for three venue cards per row, where every other
/// screen stops at `contentMaxWidth`'s 680 (issue #221).
const double discoveryMaxWidth = 1080;

/// How many venue cards fit side by side in [width] logical pixels of
/// list (issue #222, `docs/UX_REVIEW.md` §1 item 2).
///
/// One on a phone, two from 680px of list — a 720px window less the
/// Discovery screen's 20px gutters — and three from 1000px, so a window
/// that reaches [discoveryMaxWidth] always shows three.
int venueGridColumns(double width) {
  if (width >= 1000) return 3;
  if (width >= 680) return 2;
  return 1;
}

/// Lays [itemCount] venue tiles out in one, two or three columns by the
/// width it is given ([venueGridColumns]; issue #222).
///
/// [itemBuilder] receives the photo aspect ratio its tile should use:
/// null in a single column, keeping the phone's fixed-height banner
/// (`.design/Discovery.dc.html`), and [VenueCard.gridPhotoAspectRatio]
/// once there are two or more, so a tile is a photo with the name under
/// it rather than a letterbox strip. The cards in one row are stretched
/// to the row's tallest, so their surfaces line up.
///
/// Built eagerly, like the list it replaced: a search answers a few dozen
/// venues at most, and every tile stays in the element tree for tests and
/// screen readers alike.
class VenueGrid extends StatelessWidget {
  /// Lays out [itemCount] tiles built by [itemBuilder].
  const new({required this.itemCount, required this.itemBuilder, super.key});

  /// How many tiles there are.
  final int itemCount;

  /// Builds the tile at an index, with the photo aspect ratio it should
  /// use, or null for the single-column banner.
  final Widget Function(
    BuildContext context,
    int index,
    double? photoAspectRatio,
  )
  itemBuilder;

  /// The space between two cards in one row.
  static const double columnGap = 16;

  /// The space between two rows, the gap the single-column list always
  /// had.
  static const double rowGap = 19;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = venueGridColumns(constraints.maxWidth);
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < itemCount; i++) ...[
                if (i > 0) const SizedBox(height: rowGap),
                itemBuilder(context, i, null),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var start = 0; start < itemCount; start += columns) ...[
              if (start > 0) const SizedBox(height: rowGap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) const SizedBox(width: columnGap),
                      // A short last row keeps its cards the width of the
                      // rows above, leaving the empty slots blank.
                      Expanded(
                        child: start + column < itemCount
                            ? itemBuilder(
                                context,
                                start + column,
                                VenueCard.gridPhotoAspectRatio,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
