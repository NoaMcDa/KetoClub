import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/widgets/content_direction.dart';

void main() {
  group('contentDirection', () {
    test('reads Hebrew text right to left in an LTR UI', () {
      // Arrange
      const text = 'סלט ירקות';

      // Act
      final direction = contentDirection(text, TextDirection.ltr);

      // Assert
      expect(direction, TextDirection.rtl);
    });

    test('reads English text left to right in an RTL UI', () {
      // Arrange
      const text = 'Aged 300g cut over charcoal, herb butter, grilled onion.';

      // Act
      final direction = contentDirection(text, TextDirection.rtl);

      // Assert
      expect(direction, TextDirection.ltr);
    });

    test('reads mixed text containing Hebrew right to left', () {
      // Arrange
      const text = 'סלט Caesar';

      // Act
      final direction = contentDirection(text, TextDirection.ltr);

      // Assert
      expect(direction, TextDirection.rtl);
    });

    test('keeps the ambient direction for text with no letters', () {
      // Arrange
      const text = '300 · 42';

      // Act
      final rtl = contentDirection(text, TextDirection.rtl);
      final ltr = contentDirection(text, TextDirection.ltr);

      // Assert
      expect(rtl, TextDirection.rtl);
      expect(ltr, TextDirection.ltr);
    });
  });
}
