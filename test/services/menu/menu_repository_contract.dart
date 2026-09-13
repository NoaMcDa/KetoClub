// The executable MenuRepository contract (architecture.md §18.1, Liskov).
//
// Every implementation and every fake runs these assertions from its own test
// file, so "never throws" and "a cached menu carries its staleReason" are
// checked claims rather than doc comments.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';

/// Asserts the [MenuRepository] contract against what [build] returns.
///
/// [refItHandles] must be a ref the repository can serve; [refItRejects] one no
/// registered adapter handles. The suite drives the interface only, and never
/// asserts *which* menu comes back, because a cache-backed and a network-backed
/// repository legitimately differ there.
void runMenuRepositoryContract(
  String name,
  MenuRepository Function() build, {
  required VenueRef refItHandles,
  required VenueRef refItRejects,
}) {
  group('$name (MenuRepository contract)', () {
    late MenuRepository repository;

    setUp(() {
      repository = build();
    });

    test('load resolves to a sealed result for a ref it serves', () async {
      // Act
      final result = await repository.load(refItHandles);

      // Assert
      expect(result, isA<MenuFetchResult>());
    });

    test('load never throws for a ref no adapter handles', () async {
      // Assert: an unreadable venue is an ordinary outcome, not an exception.
      await expectLater(repository.load(refItRejects), completes);
    });

    test(
      'load returns a menu addressed to the ref that was asked for',
      () async {
        // Act
        final result = await repository.load(refItHandles);

        // Assert: a repository may not hand back another venue's menu.
        if (result is MenuFetched) {
          expect(result.menu.venueRef, refItHandles);
        }
      },
    );

    test('load with forceRefresh resolves to a sealed result', () async {
      // Act
      final result = await repository.load(refItHandles, forceRefresh: true);

      // Assert
      expect(result, isA<MenuFetchResult>());
    });

    test('a cached menu names why fresh data was unavailable', () async {
      // Act
      final result = await repository.load(refItHandles);

      // Assert: staleReason exists only alongside fromCache, so "here is your
      // menu, and it may be old" is expressible (architecture.md §10, row 1).
      if (result is MenuFetched && !result.fromCache) {
        expect(result.staleReason, isNull);
      }
    });

    test('cached returns null rather than throwing on a miss', () async {
      // Act
      final entry = await repository.cached(refItRejects);

      // Assert
      expect(entry, isNull);
    });

    test('saveAnalysis completes even when no menu is cached', () async {
      // Arrange
      const analysis = MenuAnalysisFailed(
        reason: MenuAnalysisFailureReason.noDishesFound,
      );

      // Assert: an analysis without its menu is dropped, never an error.
      await expectLater(
        repository.saveAnalysis(refItRejects, analysis),
        completes,
      );
    });

    test('clearCache completes and leaves nothing cached', () async {
      // Act
      await repository.clearCache();

      // Assert
      expect(await repository.cached(refItHandles), isNull);
    });

    test('load can be called twice for one ref', () async {
      // Assert: no single-shot state.
      await expectLater(repository.load(refItHandles), completes);
      await expectLater(repository.load(refItHandles), completes);
    });
  });
}
