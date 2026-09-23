import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/state/saved_controller.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:provider/provider.dart';

/// The brand name shown for [source] (architecture.md §10) — the same
/// literal names `menu_screen.dart`'s own `_platformName` uses. Kept as
/// this file's own copy rather than a shared import: not an l10n key
/// either, for the same reason as there — a platform's brand name does
/// not translate (architecture.md §18.2's "each file stays
/// self-contained").
String _platformName(MenuSource source) => switch (source) {
  MenuSource.wolt => 'Wolt',
  MenuSource.tenbis => '10bis',
  MenuSource.tabit => 'Tabit',
  MenuSource.ontopo => 'Ontopo',
};

/// The bucketed "time ago" phrase for [fetchedAt] relative to [now] — this
/// file's own copy of `menu_screen.dart`'s `_ageLabel`, kept local for the
/// same self-containment reason as [_platformName].
String _ageLabel(DateTime fetchedAt, DateTime now, AppLocalizations l10n) {
  final elapsed = now.difference(fetchedAt);
  if (elapsed.inMinutes < 1) return l10n.ageJustNow;
  if (elapsed.inHours < 1) return l10n.ageMinutes(elapsed.inMinutes);
  if (elapsed.inDays < 1) return l10n.ageHours(elapsed.inHours);
  return l10n.ageDays(elapsed.inDays);
}

/// The Saved tab (architecture.md §6.6; issue #48): every cached menu,
/// newest first, opening offline exactly as it did online — the
/// repository behind [SavedController] serves cache first — with swipe
/// or a trailing action to remove one.
///
/// Every menu the user has ever opened is cached automatically for a day
/// (`MenuCache`, architecture.md §6.4); this screen is not a separate
/// "save this venue" feature, it is a view onto that cache — matching the
/// "works offline" promise on the Settings artboard.
///
/// Reads its [SavedController] from `provider` and loads it once, after
/// the first frame, the same way `MenuScreen` and `SettingsScreen` defer
/// their own loads: a `StatefulWidget` with an `initState` that posts a
/// callback, so building this screen never itself starts I/O.
class SavedScreen extends StatefulWidget {
  /// Creates the Saved tab.
  const new({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame, so building this screen never
    // itself starts the load — a widget's build method must stay free of
    // side effects. See the class doc for why this must be a
    // StatefulWidget rather than provider's create.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<SavedController>().load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<SavedController>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.savedPlaceholderTitle)),
      body: controller.entries.isEmpty
          ? _emptyState(l10n)
          : _list(context, l10n, controller),
    );
  }

  /// Shown when nothing is cached yet — before the first menu has ever
  /// been opened, or once every entry has been removed. The same icon and
  /// layout issue #11's original placeholder used; only the body copy
  /// changed, since this screen is no longer "coming in a later update".
  Widget _emptyState(AppLocalizations l10n) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bookmark_border, size: 48),
          const SizedBox(height: 16),
          Text(l10n.savedPlaceholderBody, textAlign: TextAlign.center),
        ],
      ),
    ),
  );

  /// The cached-menu list, `controller.entries` already newest-fetched
  /// first.
  Widget _list(
    BuildContext context,
    AppLocalizations l10n,
    SavedController controller,
  ) {
    final entries = controller.entries;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _SavedEntryTile(
          entry: entry,
          onTap: () => Navigator.pushNamed(
            context,
            '/venue/${entry.ref.source.name}/${entry.ref.platformId}',
          ),
          onRemove: () => _removeWithUndo(context, controller, entry),
        );
      },
    );
  }

  /// Takes [entry] out of the visible list through [SavedController.hide]
  /// and offers an undo `SnackBar`. Undone within the `SnackBar`'s
  /// lifetime, [SavedController.restore] puts it back and nothing is ever
  /// deleted from storage; left to run out, [SavedController.commitRemoval]
  /// deletes it once the `SnackBar` closes.
  void _removeWithUndo(
    BuildContext context,
    SavedController controller,
    CachedMenuEntry entry,
  ) {
    final removed = controller.hide(entry.ref);
    if (removed == null) return;
    final l10n = AppLocalizations.of(context)!;
    final title = removed.venueName ?? removed.ref.platformId;
    var undone = false;

    unawaited(
      ScaffoldMessenger.of(context)
          .showSnackBar(
            SnackBar(
              content: Text(l10n.savedRemovedMessage(title)),
              action: SnackBarAction(
                label: l10n.savedUndo,
                onPressed: () {
                  undone = true;
                  controller.restore(removed);
                },
              ),
            ),
          )
          .closed
          .then((_) {
            if (!undone) unawaited(controller.commitRemoval(removed.ref));
          }),
    );
  }
}

/// One row in the Saved list: venue name, platform and age, dish count,
/// an [EngineChip] when the cached menu was analysed, and a way to remove
/// it by swipe or by [onRemove]'s trailing button.
class _SavedEntryTile extends StatelessWidget {
  const new({required this.entry, required this.onTap, required this.onRemove});

  /// The cached menu this row summarises.
  final CachedMenuEntry entry;

  /// Called when the row itself is tapped, to open [entry]'s menu.
  final VoidCallback onTap;

  /// Called on a swipe-to-dismiss or a tap on the trailing remove button.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final title = entry.venueName ?? entry.ref.platformId;
    final age = _ageLabel(entry.fetchedAt, DateTime.now(), l10n);
    final engine = entry.engine;

    return Dismissible(
      key: ValueKey(entry.ref.cacheKey),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          onTap: onTap,
          title: Text(title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              Text(l10n.menuSourceLine(_platformName(entry.ref.source), age)),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(l10n.savedEntryDishCount(entry.dishCount)),
                  if (engine != null) EngineChip(engine: engine),
                ],
              ),
            ],
          ),
          trailing: Semantics(
            label: l10n.savedRemoveSemanticLabel(title),
            button: true,
            excludeSemantics: true,
            child: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.savedRemove,
              onPressed: onRemove,
            ),
          ),
        ),
      ),
    );
  }
}
