import 'package:flutter/material.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/app_tokens.dart';

/// A fixed-size photo tile for a dish or venue, filled from the platform
/// feed when [imageUrl] is set, or the placeholder gradient otherwise —
/// while an image is loading, when it fails to load, and when there is no
/// URL at all (`phase2_discovery_research.md` §8.4, issue #50).
///
/// The tile's footprint is always [width] by [size] regardless of state,
/// so an image arriving never shifts the surrounding layout. On web,
/// [WebHtmlElementStrategy.fallback] draws the photo through a
/// platform-view `<img>` element when Flutter's own CORS-gated byte fetch
/// fails, which is also why this widget never caches bytes itself — see
/// §8.4 for why the app carries no image-caching dependency: on the web
/// there is nothing to cache without CORS, and on phones the menu is
/// already re-fetched at most daily.
///
/// Decorative: a dish or venue name is always printed beside the tile, so
/// it carries no semantics of its own ([ExcludeSemantics]).
class PhotoTile extends StatelessWidget {
  /// Creates a tile [size] logical pixels tall — and as wide, unless
  /// [width] says otherwise — showing [imageUrl] when it is set, else the
  /// theme's placeholder gradient.
  const new({
    required this.imageUrl,
    required this.size,
    this.width,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    super.key,
  });

  /// The photo's URL, read from the platform feed (`Dish.imageUrl` /
  /// `Venue.imageUrl`). Null shows the placeholder gradient outright —
  /// never an attempted, guaranteed-to-fail request.
  final String? imageUrl;

  /// The tile's fixed height, and its width when [width] is null.
  final double size;

  /// The tile's width, when it is not square: `double.infinity` fills the
  /// parent's width, as the venue card's full-bleed photo does
  /// (`.design/Discovery.dc.html`: `width: 100%; height: 118px`). Null
  /// keeps the tile [size] square, as the dish row's 72px tile is.
  final double? width;

  /// The tile's corner radius. Defaults to 12, the artboard's dish-row
  /// photo tile (`.design/Main.dc.html`).
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final width = this.width ?? size;
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: size,
        child: ClipRRect(
          borderRadius: borderRadius,
          child: url == null
              ? const _PhotoPlaceholder()
              : Image.network(
                  url,
                  width: width.isFinite ? width : null,
                  height: size,
                  fit: BoxFit.cover,
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  loadingBuilder: (context, child, loadingProgress) =>
                      loadingProgress == null
                      ? child
                      : const _PhotoPlaceholder(),
                  errorBuilder: (context, error, stackTrace) =>
                      const _PhotoPlaceholder(),
                ),
        ),
      ),
    );
  }
}

/// The placeholder gradient ([PhotoPlaceholder], `app_theme.dart`), shown
/// for a null URL, while an image loads, and when one fails to load.
class _PhotoPlaceholder extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final placeholder = _placeholderOf(context);
    return DecoratedBox(
      key: const ValueKey('photoTilePlaceholder'),
      decoration: BoxDecoration(gradient: placeholder.gradient),
      child: Center(
        child: Icon(Icons.image_outlined, color: placeholder.ink, size: 20),
      ),
    );
  }
}

/// Reads the [PhotoPlaceholder] registered on the ambient [Theme], falling
/// back to the light theme's own tokens the same way `app_theme.dart`'s
/// other theme-extension readers do, for a bare [MaterialApp] with no
/// `theme:` — many existing widget tests pump one.
PhotoPlaceholder _placeholderOf(BuildContext context) {
  final extension = Theme.of(context).extension<PhotoPlaceholder>();
  if (extension != null) return extension;
  return const PhotoPlaceholder(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppTokens.lightPhotoStart, AppTokens.lightPhotoEnd],
    ),
    ink: AppTokens.lightPhotoInk,
  );
}
