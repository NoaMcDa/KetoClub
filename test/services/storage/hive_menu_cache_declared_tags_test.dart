// The Hive menu cache keeps a dish's declared tags (Banto, ALG-09, issue
// #351): a field on Dish needs no schemaVersion bump.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    // Arrange: a real, isolated Hive home per test.
    tempDir = Directory.systemTemp.createTempSync('hive_declared_tags_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  test('write then read round-trips a dish with declared tags', () async {
    // Arrange
    const ref = VenueRef(source: MenuSource.tenbis, platformId: '9001');
    final cache = HiveMenuCache(
      openBox: () => Hive.openBox<String>('menu_cache'),
      openPinBox: () => Hive.openBox<String>('menu_cache_pins'),
    );
    final entry = CachedMenu(
      menu: Menu(
        venueRef: ref,
        currency: 'ILS',
        fetchedAt: DateTime.utc(2026),
        categories: const <MenuCategory>[
          MenuCategory(
            id: 'c',
            name: 'Bakery',
            dishes: <Dish>[
              Dish(
                id: '1003',
                name: 'Bread basket',
                description: '',
                price: 0,
                options: <DishOption>[],
                declaredTags: <String>['kosher'],
              ),
            ],
          ),
        ],
      ),
    );

    // Act
    await cache.write(entry);
    final result = await cache.read(ref);

    // Assert
    expect(result, equals(entry));
    expect(result?.menu.allDishes.single.declaredTags, <String>['kosher']);
  });
}
