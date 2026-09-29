import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/platform/page_picker.dart';

import 'page_picker_contract.dart';

void main() {
  runPagePickerContract('NoPagePicker', NoPagePicker.new);

  group('NoPagePicker', () {
    test('answers every method as cancelled', () async {
      const picker = NoPagePicker();

      expect(await picker.takePhoto(), isEmpty);
      expect(await picker.pickImages(), isEmpty);
      expect(await picker.pickPdf(), isEmpty);
    });
  });
}
