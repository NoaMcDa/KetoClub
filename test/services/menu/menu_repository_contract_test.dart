import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';

import '../../fakes/fake_menu_repository.dart';
import 'menu_repository_contract.dart';

void main() {
  runMenuRepositoryContract(
    'FakeMenuRepository',
    FakeMenuRepository.new,
    refItHandles: const VenueRef(
      source: MenuSource.wolt,
      platformId: 'vitrina-lilinblum',
    ),
    refItRejects: const VenueRef(
      source: MenuSource.ontopo,
      platformId: 'unsupported',
    ),
  );

  group('FakeMenuRepository', () {
    test('load records the ref and the forceRefresh flag', () async {
      // Arrange
      final repository = FakeMenuRepository();
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'x');

      // Act
      await repository.load(ref, forceRefresh: true);

      // Assert
      expect(repository.loadCalls, [(ref: ref, forceRefresh: true)]);
    });

    test('stub makes load answer the scripted result for that ref', () async {
      // Arrange
      final repository = FakeMenuRepository();
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'x');
      const failure = MenuFetchFailed(reason: MenuFetchFailureReason.notFound);
      repository.stub(ref, failure);

      // Act
      final result = await repository.load(ref);

      // Assert
      expect(result, failure);
    });

    test(
      'saveAnalysis attaches the analysis to a seeded cache entry',
      () async {
        // Arrange
        final repository = FakeMenuRepository();
        const ref = VenueRef(source: MenuSource.wolt, platformId: 'x');
        final fetched = await repository.load(ref) as MenuFetched;
        repository.seedCache(CachedMenu(menu: fetched.menu));
        const analysis = MenuAnalysisFailed(
          reason: MenuAnalysisFailureReason.timeout,
        );

        // Act
        await repository.saveAnalysis(ref, analysis);

        // Assert
        expect((await repository.cached(ref))?.analysis, analysis);
      },
    );
  });
}
