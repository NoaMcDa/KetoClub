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

/// Builds the venue tile at an index of a [VenueGrid] or a
/// [SliverVenueGrid], with the photo aspect ratio it should use: null in a
/// single column, keeping the phone's fixed-height banner
/// (`.design/Discovery.dc.html`), and [VenueCard.gridPhotoAspectRatio]
/// once there are two or more, so a tile is a photo with the name under it
/// rather than a letterbox strip.
typedef VenueGridItemBuilder = Widget Function(
  BuildContext context,
  int index,
  double? photoAspectRatio,
);

/// How many rows [itemCount] tiles fill at [columns] to a row.
int _rowCount(int itemCount, int columns) =>
    (itemCount + columns - 1) ~/ columns;

/// One row of a venue grid: the tiles from index [row] × [columns], laid
/// side by side and stretched to the row's tallest so their surfaces line
/// up, or the one tile itself in a single column.
///
/// Shared by [VenueGrid] and [SliverVenueGrid], so the eager and the lazy
/// grid cannot drift apart.
Widget _venueGridRow(
  BuildContext context, {
  required int row,
  required int columns,
  required int itemCount,
  required VenueGridItemBuilder itemBuilder,
}) {
  if (columns == 1) return itemBuilder(context, row, null);
  final start = row * columns;
  return IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var column = 0; column < columns; column++) ...[
          if (column > 0) const SizedBox(width: VenueGrid.columnGap),
          // A short last row keeps its cards the width of the rows above,
          // leaving the empty slots blank.
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
  );
}

/// Lays [itemCount] venue tiles out in one, two or three columns by the
/// width it is given ([venueGridColumns]; issue #222).
///
/// [itemBuilder] receives the photo aspect ratio its tile should use (see
/// [VenueGridItemBuilder]). The cards in one row are stretched to the
/// row's tallest, so their surfaces line up.
///
/// **Built eagerly: every tile at once.** That suits a handful of tiles
/// that all show together, which is what it is used for now — the three
/// loading skeletons. A list of venues goes in [SliverVenueGrid], which
/// builds only the rows on screen (issue #446): a nearby search answers
/// hundreds of venues, and building them all froze the page for seconds.
class VenueGrid extends StatelessWidget {
  /// Lays out [itemCount] tiles built by [itemBuilder].
  const new({required this.itemCount, required this.itemBuilder, super.key});

  /// How many tiles there are.
  final int itemCount;

  /// Builds the tile at an index, with the photo aspect ratio it should
  /// use, or null for the single-column banner.
  final VenueGridItemBuilder itemBuilder;

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
        final rows = _rowCount(itemCount, columns);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var row = 0; row < rows; row++) ...[
              if (row > 0) const SizedBox(height: rowGap),
              _venueGridRow(
                context,
                row: row,
                columns: columns,
                itemCount: itemCount,
                itemBuilder: itemBuilder,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// [VenueGrid] as a sliver that builds its rows lazily (issue #446): only
/// the rows on screen, and the scroll view's cache extent beyond it, exist
/// at any time, so a list of hundreds of venues costs what a screenful
/// does — to build, to lay out, and in photos requested.
///
/// The layout is [VenueGrid]'s, row for row: one, two or three columns by
/// the sliver's cross-axis extent ([venueGridColumns]), [VenueGrid.rowGap]
/// between rows, the cards of a row stretched to its tallest, and a short
/// last row keeping its cards' width.
///
/// It goes straight into a `CustomScrollView`, or a `SliverPadding` or
/// `SliverMainAxisGroup` inside one. A row's height is only known once it
/// is built, so the scroll extent of the rows not yet built is an
/// estimate, as with any lazy list.
class SliverVenueGrid extends StatelessWidget {
  /// Lays out [itemCount] tiles built by [itemBuilder], lazily.
  const new({required this.itemCount, required this.itemBuilder, super.key});

  /// How many tiles there are.
  final int itemCount;

  /// Builds the tile at an index, with the photo aspect ratio it should
  /// use, or null for the single-column banner. Called only for the tiles
  /// of rows on or near the screen.
  final VenueGridItemBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = venueGridColumns(constraints.crossAxisExtent);
        return SliverList.separated(
          itemCount: _rowCount(itemCount, columns),
          separatorBuilder: (context, row) =>
              const SizedBox(height: VenueGrid.rowGap),
          itemBuilder: (context, row) => _venueGridRow(
            context,
            row: row,
            columns: columns,
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          ),
        );
      },
    );
  }
}
