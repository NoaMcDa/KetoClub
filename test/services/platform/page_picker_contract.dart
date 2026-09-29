// The shared PagePicker contract (architecture.md §18.1, D15; issue #82).
//
// Every implementation of PagePicker, including the fake in test/fakes/,
// is run through this suite from its own test file. It asserts only what
// the interface promises for a picker with nothing to answer: no method
// throws, and each resolves to a list (empty meaning cancelled).

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/platform/page_picker.dart';

/// Asserts the [PagePicker] contract against what [build] returns.
void runPagePickerContract(String name, PagePicker Function() build) {
  group(name, () {
    final methods = <String, Future<List<ScannedPage>> Function(PagePicker)>{
      'takePhoto': (picker) => picker.takePhoto(),
      'pickImages': (picker) => picker.pickImages(),
      'pickPdf': (picker) => picker.pickPdf(),
    };
    for (final MapEntry(key: method, value: call) in methods.entries) {
      test('$method never throws and resolves to a list', () async {
        final picker = build();
        late final Future<List<ScannedPage>> future;
        expect(() => future = call(picker), returnsNormally);
        await expectLater(future, completion(isA<List<ScannedPage>>()));
      });
    }
  });
}
