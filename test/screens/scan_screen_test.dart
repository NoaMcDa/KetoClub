import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/screens/scan_screen.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/platform/qr_scanner.dart';
import 'package:ketoclub/state/scan_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/widgets/scan_failure_copy.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_page_picker.dart';
import '../fakes/fake_qr_scanner.dart';
import '../fakes/fake_scanned_menu_classifier.dart';
import '../fakes/fake_settings_store.dart';

/// The English strings a test can read expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings for the RTL test.
final AppLocalizations _he = AppLocalizationsHe();

/// Pumps the screen over [controller]. Every route other than `/` is
/// recorded into [pushed] and answered with a marker widget.
Future<void> _pump(
  WidgetTester tester,
  ScanController controller, {
  Locale locale = const Locale('en'),
  List<String>? pushed,
  FakePagePicker? picker,
  bool directToGoogle = false,
}) async {
  // Tall enough that the whole screen is built: a ListView builds lazily,
  // so anything below the fold would be absent from the tree.
  tester.view
    ..physicalSize = const Size(800, 3200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) {
          if (settings.name == '/') {
            return ChangeNotifierProvider<ScanController>.value(
              value: controller,
              child: ScanScreen(
                pagePicker: picker ?? FakePagePicker(),
                directToGoogle: directToGoogle,
              ),
            );
          }
          pushed?.add(settings.name!);
          return Text('pushed:${settings.name}');
        },
      ),
    ),
  );
}

ScanController _controller(
  FakeMenuRepository repository, {
  FakeScannedMenuClassifier? classifier,
}) => ScanController(
  classifier: classifier ?? FakeScannedMenuClassifier(),
  repository: repository,
  clock: FakeClock(DateTime.utc(2026, 9, 29)),
  settingsStore: FakeSettingsStore(),
);

/// A distinct JPEG page, so several in one scan do not compare equal.
ScannedPage _jpeg(int seed, {int bytes = 3}) => ScannedPage(
  mimeType: ScannedPage.jpeg,
  bytes: Uint8List.fromList([seed, ...List<int>.filled(bytes - 1, 1)]),
);

/// A PDF page of [bytes] bytes.
ScannedPage _pdf({int bytes = 2048}) =>
    ScannedPage(mimeType: ScannedPage.pdf, bytes: Uint8List(bytes));

/// The button that analyses the collected pages.
Finder _analysePages(AppLocalizations l10n) =>
    find.widgetWithText(ElevatedButton, l10n.scanScreenAnalysePages);

/// An action button, found by its label.
///
/// `OutlinedButton.icon` builds a private subclass, which `byType` would
/// not match, hence `bySubtype`.
Finder _action(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<OutlinedButton>(),
);

/// Whether [finder]'s button is enabled.
bool _enabled(WidgetTester tester, Finder finder) =>
    tester.widget<ButtonStyleButton>(finder).onPressed != null;

/// The Analyse button, found by its label.
Finder _analyse(AppLocalizations l10n) =>
    find.widgetWithText(ElevatedButton, l10n.scanAnalyse);

void main() {
  group('ScanScreen', () {
    late FakeMenuRepository repository;
    late ScanController controller;

    setUp(() {
      repository = FakeMenuRepository();
      controller = _controller(repository);
    });

    tearDown(() => controller.dispose());

    testWidgets('shows the localized title, intro and paste field', (
      tester,
    ) async {
      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanTitle), findsOneWidget);
      expect(find.text(_en.scanPasteIntro), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(_analyse(_en), findsOneWidget);
    });

    testWidgets(
      'build under Locale(he) renders the Hebrew copy, right to left',
      (tester) async {
        // Act
        await _pump(tester, controller, locale: const Locale('he'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_he.scanTitle), findsOneWidget);
        expect(find.text(_he.scanPasteIntro), findsOneWidget);
        expect(_analyse(_he), findsOneWidget);
        expect(
          Directionality.of(tester.element(find.byType(TextField))),
          TextDirection.rtl,
        );
      },
    );

    testWidgets('Analyse is disabled while the field is empty', (tester) async {
      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(tester.widget<ElevatedButton>(_analyse(_en)).onPressed, isNull);
    });

    testWidgets('Analyse stays disabled for whitespace only', (tester) async {
      // Arrange
      await _pump(tester, controller);

      // Act
      await tester.enterText(find.byType(TextField), '   \n ');
      await tester.pump();

      // Assert
      expect(tester.widget<ElevatedButton>(_analyse(_en)).onPressed, isNull);
    });

    testWidgets('typing enables Analyse', (tester) async {
      // Arrange
      await _pump(tester, controller);

      // Act
      await tester.enterText(find.byType(TextField), 'Grilled salmon');
      await tester.pump();

      // Assert
      expect(tester.widget<ElevatedButton>(_analyse(_en)).onPressed, isNotNull);
    });

    testWidgets('Analyse stores the menu and opens /venue/scan/{id}', (
      tester,
    ) async {
      // Arrange
      final pushed = <String>[];
      await _pump(tester, controller, pushed: pushed);
      await tester.enterText(
        find.byType(TextField),
        'Grilled salmon 68 ₪\nCaesar salad',
      );
      await tester.pump();

      // Act
      await tester.tap(_analyse(_en));
      await tester.pumpAndSettle();

      // Assert
      final stored = repository.storedMenus.single;
      expect(pushed, ['/venue/scan/${stored.venueRef.platformId}']);
      expect(stored.allDishes.map((d) => d.name), [
        'Grilled salmon',
        'Caesar salad',
      ]);
      expect(stored.categories.single.name, _en.sourceScanned);
    });

    testWidgets('a paste with no dish shows the empty-paste copy and stays', (
      tester,
    ) async {
      // Arrange
      final pushed = <String>[];
      await _pump(tester, controller, pushed: pushed);
      await tester.enterText(find.byType(TextField), '45 ₪');
      await tester.pump();

      // Act
      await tester.tap(_analyse(_en));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanEmptyPaste), findsOneWidget);
      expect(pushed, isEmpty);
      expect(repository.storedMenus, isEmpty);
    });

    testWidgets('editing after the empty-paste copy clears it', (tester) async {
      // Arrange
      await _pump(tester, controller);
      await tester.enterText(find.byType(TextField), '45 ₪');
      await tester.pump();
      await tester.tap(_analyse(_en));
      await tester.pumpAndSettle();
      expect(find.text(_en.scanEmptyPaste), findsOneWidget);

      // Act
      await tester.enterText(find.byType(TextField), 'Steak');
      await tester.pump();

      // Assert
      expect(find.text(_en.scanEmptyPaste), findsNothing);
    });

    testWidgets('the empty-paste copy is in Hebrew under Locale(he)', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, controller, locale: const Locale('he'));
      await tester.enterText(find.byType(TextField), '45 ₪');
      await tester.pump();

      // Act
      await tester.tap(_analyse(_he));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_he.scanEmptyPaste), findsOneWidget);
    });
  });

  group('ScanScreen pages', () {
    late FakeMenuRepository repository;
    late FakeScannedMenuClassifier classifier;
    late FakePagePicker picker;
    late ScanController controller;

    setUp(() {
      repository = FakeMenuRepository();
      classifier = FakeScannedMenuClassifier();
      picker = FakePagePicker();
      controller = _controller(repository, classifier: classifier);
    });

    tearDown(() => controller.dispose());

    testWidgets('shows the three actions and no page list at first', (
      tester,
    ) async {
      // Act
      await _pump(tester, controller, picker: picker);

      // Assert
      expect(find.text(_en.scanScreenIntro), findsOneWidget);
      expect(_action(_en.scanScreenActionTakePhoto), findsOneWidget);
      expect(_action(_en.scanScreenActionChoosePhotos), findsOneWidget);
      expect(_action(_en.scanScreenActionChoosePdf), findsOneWidget);
      expect(find.text(_en.scanScreenPagesHeading), findsNothing);
    });

    testWidgets('each action calls its picker method and lists the pages', (
      tester,
    ) async {
      // Arrange
      picker
        ..queueTakePhoto([_jpeg(1)])
        ..queuePickImages([_jpeg(2), _jpeg(3)])
        ..queuePickPdf([_pdf()]);
      await _pump(tester, controller, picker: picker);

      // Act
      await tester.tap(_action(_en.scanScreenActionTakePhoto));
      await tester.pumpAndSettle();
      await tester.tap(_action(_en.scanScreenActionChoosePhotos));
      await tester.pumpAndSettle();
      await tester.tap(_action(_en.scanScreenActionChoosePdf));
      await tester.pumpAndSettle();

      // Assert
      expect(picker.calls, [
        PagePickerCall.takePhoto,
        PagePickerCall.pickImages,
        PagePickerCall.pickPdf,
      ]);
      expect(controller.pages, hasLength(4));
      expect(
        find.text(_en.scanScreenPageCount(4, maxScanPages)),
        findsOneWidget,
      );
      expect(find.text(_en.scanScreenPageLabel(1)), findsOneWidget);
      expect(find.text(_en.scanScreenPageLabel(3)), findsOneWidget);
      expect(find.text(_en.scanScreenPdfLabel), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsWidgets);
      expect(find.byType(Image), findsNWidgets(3));
    });

    testWidgets('a PDF row shows its size in KB', (tester) async {
      // Arrange
      picker.queuePickPdf([_pdf()]);
      await _pump(tester, controller, picker: picker);

      // Act
      await tester.tap(_action(_en.scanScreenActionChoosePdf));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanScreenPageSizeKb(2)), findsOneWidget);
    });

    testWidgets('a cancelled picker adds nothing', (tester) async {
      // Arrange
      await _pump(tester, controller, picker: picker);

      // Act
      await tester.tap(_action(_en.scanScreenActionTakePhoto));
      await tester.pumpAndSettle();

      // Assert
      expect(picker.calls, [PagePickerCall.takePhoto]);
      expect(controller.pages, isEmpty);
      expect(find.text(_en.scanScreenPagesHeading), findsNothing);
    });

    testWidgets('the remove button drops that page', (tester) async {
      // Arrange
      picker.queuePickImages([_jpeg(1), _jpeg(2)]);
      await _pump(tester, controller, picker: picker);
      await tester.tap(_action(_en.scanScreenActionChoosePhotos));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.byTooltip(_en.scanScreenRemovePage(1)));
      await tester.pumpAndSettle();

      // Assert
      expect(controller.pages, [_jpeg(2)]);
      expect(
        find.text(_en.scanScreenPageCount(1, maxScanPages)),
        findsOneWidget,
      );
    });

    testWidgets('at the cap the add actions are disabled and the cap copy '
        'shows; removing a page frees them', (tester) async {
      // Arrange
      picker.queuePickImages([for (var i = 0; i < maxScanPages; i++) _jpeg(i)]);
      await _pump(tester, controller, picker: picker);

      // Act
      await tester.tap(_action(_en.scanScreenActionChoosePhotos));
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.text(_en.scanScreenPageCount(maxScanPages, maxScanPages)),
        findsOneWidget,
      );
      expect(find.text(_en.scanScreenCapReached), findsOneWidget);
      for (final label in [
        _en.scanScreenActionTakePhoto,
        _en.scanScreenActionChoosePhotos,
        _en.scanScreenActionChoosePdf,
      ]) {
        expect(_enabled(tester, _action(label)), isFalse, reason: label);
      }

      // Act: remove one.
      await tester.tap(find.byTooltip(_en.scanScreenRemovePage(1)));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanScreenCapReached), findsNothing);
      expect(_enabled(tester, _action(_en.scanScreenActionTakePhoto)), isTrue);
    });

    testWidgets('more pages than fit report the too-many copy', (tester) async {
      // Arrange
      picker.queuePickImages([
        for (var i = 0; i < maxScanPages + 2; i++) _jpeg(i),
      ]);
      await _pump(tester, controller, picker: picker);

      // Act
      await tester.tap(_action(_en.scanScreenActionChoosePhotos));
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.text(_en.scanScreenTooManyPages(maxScanPages)),
        findsOneWidget,
      );
      expect(controller.pages, hasLength(maxScanPages));
    });

    testWidgets('an oversize page reports its own copy and is not added', (
      tester,
    ) async {
      // Arrange
      picker.queuePickPdf([_pdf(bytes: maxScanPageBytes + 1)]);
      await _pump(tester, controller, picker: picker);

      // Act
      await tester.tap(_action(_en.scanScreenActionChoosePdf));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanScreenPageTooLarge(3)), findsOneWidget);
      expect(find.text(_en.scanScreenTooManyPages(maxScanPages)), findsNothing);
      expect(controller.pages, isEmpty);
    });

    testWidgets('the next pick clears the rejection copy', (tester) async {
      // Arrange
      picker
        ..queuePickPdf([_pdf(bytes: maxScanPageBytes + 1)])
        ..queueTakePhoto([_jpeg(1)]);
      await _pump(tester, controller, picker: picker);
      await tester.tap(_action(_en.scanScreenActionChoosePdf));
      await tester.pumpAndSettle();
      expect(find.text(_en.scanScreenPageTooLarge(3)), findsOneWidget);

      // Act
      await tester.tap(_action(_en.scanScreenActionTakePhoto));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanScreenPageTooLarge(3)), findsNothing);
    });

    testWidgets('removing a page clears the rejection copy', (tester) async {
      // Arrange
      picker.queuePickImages([_jpeg(1), _jpeg(2)]);
      await _pump(tester, controller, picker: picker);
      await tester.tap(_action(_en.scanScreenActionChoosePhotos));
      await tester.pumpAndSettle();
      picker.queuePickPdf([_pdf(bytes: maxScanPageBytes + 1)]);
      await tester.tap(_action(_en.scanScreenActionChoosePdf));
      await tester.pumpAndSettle();
      expect(find.text(_en.scanScreenPageTooLarge(3)), findsOneWidget);

      // Act
      await tester.tap(find.byTooltip(_en.scanScreenRemovePage(1)));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanScreenPageTooLarge(3)), findsNothing);
    });

    testWidgets('Analyse pages is disabled with no pages, enabled with one', (
      tester,
    ) async {
      // Arrange
      picker.queueTakePhoto([_jpeg(1)]);
      await _pump(tester, controller, picker: picker);
      expect(_enabled(tester, _analysePages(_en)), isFalse);

      // Act
      await tester.tap(_action(_en.scanScreenActionTakePhoto));
      await tester.pumpAndSettle();

      // Assert
      expect(_enabled(tester, _analysePages(_en)), isTrue);
    });

    testWidgets('Analyse pages hands every page to the classifier in one '
        'call and opens the stored scan', (tester) async {
      // Arrange
      final pushed = <String>[];
      picker
        ..queuePickImages([_jpeg(1), _jpeg(2)])
        ..queuePickPdf([_pdf()]);
      await _pump(tester, controller, picker: picker, pushed: pushed);
      await tester.tap(_action(_en.scanScreenActionChoosePhotos));
      await tester.pumpAndSettle();
      await tester.tap(_action(_en.scanScreenActionChoosePdf));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(_analysePages(_en));
      await tester.pumpAndSettle();

      // Assert
      expect(classifier.calls, hasLength(1));
      expect(classifier.calls.single.$1.pages, hasLength(3));
      final stored = repository.storedMenus.single;
      expect(pushed, ['/venue/scan/${stored.venueRef.platformId}']);
      expect(repository.savedAnalyses, hasLength(1));
    });

    testWidgets('shows the progress row while the classifier is reading', (
      tester,
    ) async {
      // Arrange
      final gate = Completer<void>();
      classifier.gate = gate.future;
      picker.queueTakePhoto([_jpeg(1)]);
      await _pump(tester, controller, picker: picker);
      await tester.tap(_action(_en.scanScreenActionTakePhoto));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(_analysePages(_en));
      await tester.pump();

      // Assert: the row is up and nothing can change under the request.
      expect(find.text(_en.menuProgressAnalysing), findsOneWidget);
      expect(_enabled(tester, _analysePages(_en)), isFalse);
      expect(_enabled(tester, _action(_en.scanScreenActionTakePhoto)), isFalse);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close))
            .onPressed,
        isNull,
      );

      // Act: it finishes.
      gate.complete();
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.menuProgressAnalysing), findsNothing);
    });

    testWidgets('a failure shows its copy, keeps the pages and Retry '
        'calls the classifier again', (tester) async {
      // Arrange
      classifier.respondWith(
        const ScannedMenuFailed(reason: MenuAnalysisFailureReason.timeout),
      );
      final pushed = <String>[];
      picker.queueTakePhoto([_jpeg(1)]);
      await _pump(tester, controller, picker: picker, pushed: pushed);
      await tester.tap(_action(_en.scanScreenActionTakePhoto));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(_analysePages(_en));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanScreenFailureTimeout), findsOneWidget);
      expect(find.text(_en.scanScreenPageLabel(1)), findsOneWidget);
      expect(pushed, isEmpty);
      expect(repository.storedMenus, isEmpty);

      // Act: retry; the classifier now fails for another reason.
      classifier.respondWith(
        const ScannedMenuFailed(reason: MenuAnalysisFailureReason.offline),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, _en.actionRetry));
      await tester.pumpAndSettle();

      // Assert: called again with the same pages, copy replaced.
      expect(classifier.calls, hasLength(2));
      expect(classifier.calls.last.$1, classifier.calls.first.$1);
      expect(find.text(_en.scanScreenFailureTimeout), findsNothing);
      expect(find.text(_en.scanScreenFailureOffline), findsOneWidget);
    });

    testWidgets('Retry that succeeds opens the scan', (tester) async {
      // Arrange
      classifier.respondWith(
        const ScannedMenuFailed(reason: MenuAnalysisFailureReason.offline),
      );
      final pushed = <String>[];
      picker.queueTakePhoto([_jpeg(1)]);
      await _pump(tester, controller, picker: picker, pushed: pushed);
      await tester.tap(_action(_en.scanScreenActionTakePhoto));
      await tester.pumpAndSettle();
      await tester.tap(_analysePages(_en));
      await tester.pumpAndSettle();
      final working = FakeScannedMenuClassifier();
      final read = await working.classify(
        ScannedMenu(pages: [_jpeg(1)]),
        options: const ClassificationOptions(),
      );
      classifier.respondWith(read);

      // Act
      await tester.tap(find.widgetWithText(OutlinedButton, _en.actionRetry));
      await tester.pumpAndSettle();

      // Assert
      expect(pushed, hasLength(1));
      expect(find.text(_en.scanScreenFailureOffline), findsNothing);
    });

    testWidgets('every failure reason has its own copy on screen', (
      tester,
    ) async {
      // Arrange
      picker.queueTakePhoto([_jpeg(1)]);
      await _pump(tester, controller, picker: picker);
      await tester.tap(_action(_en.scanScreenActionTakePhoto));
      await tester.pumpAndSettle();

      // Act & Assert
      for (final reason in MenuAnalysisFailureReason.values) {
        classifier.respondWith(ScannedMenuFailed(reason: reason));
        await tester.tap(_analysePages(_en));
        await tester.pumpAndSettle();
        expect(
          find.text(scanFailureMessage(reason, _en, directToGoogle: false)),
          findsOneWidget,
          reason: '$reason',
        );
      }
    });

    testWidgets('on web notConfigured says scanning needs the server', (
      tester,
    ) async {
      // Arrange
      classifier.respondWith(
        const ScannedMenuFailed(
          reason: MenuAnalysisFailureReason.notConfigured,
        ),
      );
      picker.queueTakePhoto([_jpeg(1)]);
      await _pump(tester, controller, picker: picker);
      await tester.tap(_action(_en.scanScreenActionTakePhoto));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(_analysePages(_en));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanScreenFailureNeedsServer), findsOneWidget);
    });

    testWidgets('on phones notConfigured says scanning is unavailable', (
      tester,
    ) async {
      // Arrange
      classifier.respondWith(
        const ScannedMenuFailed(
          reason: MenuAnalysisFailureReason.notConfigured,
        ),
      );
      picker.queueTakePhoto([_jpeg(1)]);
      await _pump(tester, controller, picker: picker, directToGoogle: true);
      await tester.tap(_action(_en.scanScreenActionTakePhoto));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(_analysePages(_en));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanScreenFailureNotConfigured), findsOneWidget);
      expect(find.text(_en.scanScreenFailureNeedsServer), findsNothing);
    });

    testWidgets('consent withheld says to allow AI analysis in Settings', (
      tester,
    ) async {
      // Arrange
      classifier.respondWith(
        const ScannedMenuFailed(
          reason: MenuAnalysisFailureReason.consentWithheld,
        ),
      );
      picker.queueTakePhoto([_jpeg(1)]);
      await _pump(tester, controller, picker: picker);
      await tester.tap(_action(_en.scanScreenActionTakePhoto));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(_analysePages(_en));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanScreenFailureConsentWithheld), findsOneWidget);
    });

    testWidgets("the disclosure line names KetoClub's server on web", (
      tester,
    ) async {
      // Act
      await _pump(tester, controller, picker: picker);

      // Assert
      expect(find.text(_en.scanScreenDisclosureWeb), findsOneWidget);
      expect(find.text(_en.scanScreenDisclosureDirect), findsNothing);
      expect(_en.scanScreenDisclosureWeb, contains("KetoClub's server"));
      expect(_en.scanScreenDisclosureWeb, contains('Gemini API'));
    });

    testWidgets('the disclosure line says straight to Google on phones', (
      tester,
    ) async {
      // Act
      await _pump(tester, controller, picker: picker, directToGoogle: true);

      // Assert
      expect(find.text(_en.scanScreenDisclosureDirect), findsOneWidget);
      expect(find.text(_en.scanScreenDisclosureWeb), findsNothing);
      expect(_en.scanScreenDisclosureDirect, contains('straight'));
      expect(_en.scanScreenDisclosureDirect, contains('Gemini API'));
    });

    testWidgets('the Settings link opens /settings', (tester) async {
      // Arrange
      final pushed = <String>[];
      await _pump(tester, controller, picker: picker, pushed: pushed);

      // Act
      await tester.tap(
        find.widgetWithText(TextButton, _en.scanScreenSettingsLink),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(pushed, ['/settings']);
    });

    testWidgets('Hebrew renders the page copy right to left', (tester) async {
      // Arrange
      picker.queueTakePhoto([_jpeg(1)]);
      classifier.respondWith(
        const ScannedMenuFailed(reason: MenuAnalysisFailureReason.offline),
      );
      await _pump(
        tester,
        controller,
        picker: picker,
        locale: const Locale('he'),
      );

      // Act
      await tester.tap(_action(_he.scanScreenActionTakePhoto));
      await tester.pumpAndSettle();
      await tester.tap(_analysePages(_he));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_he.scanScreenIntro), findsOneWidget);
      expect(
        find.text(_he.scanScreenPageCount(1, maxScanPages)),
        findsOneWidget,
      );
      expect(find.text(_he.scanScreenDisclosureWeb), findsOneWidget);
      expect(find.text(_he.scanScreenFailureOffline), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(_he.scanScreenIntro))),
        TextDirection.rtl,
      );
    });

    testWidgets('the Hebrew oversize copy is shown under Locale(he)', (
      tester,
    ) async {
      // Arrange
      picker.queuePickPdf([_pdf(bytes: maxScanPageBytes + 1)]);
      await _pump(
        tester,
        controller,
        picker: picker,
        locale: const Locale('he'),
      );

      // Act
      await tester.tap(_action(_he.scanScreenActionChoosePdf));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_he.scanScreenPageTooLarge(3)), findsOneWidget);
    });
  });

  group('ScanScreen QR action (issue #182)', () {
    late FakeQrScanner scanner;
    late ScanController controller;

    ScanController build(QrScanner qrScanner) => ScanController(
      classifier: FakeScannedMenuClassifier(),
      repository: FakeMenuRepository(),
      clock: FakeClock(DateTime.utc(2026, 9, 29)),
      settingsStore: FakeSettingsStore(),
      qrScanner: qrScanner,
    );

    setUp(() {
      scanner = FakeQrScanner();
      controller = build(scanner);
    });

    tearDown(() => controller.dispose());

    testWidgets('shows the action when the build can scan', (tester) async {
      // Arrange & Act
      await _pump(tester, controller);

      // Assert
      expect(_action(_en.scanQrAction), findsOneWidget);
      expect(_enabled(tester, _action(_en.scanQrAction)), isTrue);
    });

    testWidgets('hides the action when the build cannot scan (web)', (
      tester,
    ) async {
      // Arrange
      final web = build(FakeQrScanner(available: false));
      addTearDown(web.dispose);

      // Act
      await _pump(tester, web);

      // Assert
      expect(find.text(_en.scanQrAction), findsNothing);
      expect(find.text(_en.scanScreenActionTakePhoto), findsOneWidget);
    });

    testWidgets('a Wolt code opens that venue exactly as a paste does', (
      tester,
    ) async {
      // Arrange
      scanner.queuePayload(
        'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum',
      );
      final pushed = <String>[];
      await _pump(tester, controller, pushed: pushed);

      // Act
      await tester.tap(_action(_en.scanQrAction));
      await tester.pumpAndSettle();

      // Assert
      expect(pushed, ['/venue/wolt/vitrina-lilinblum']);
    });

    testWidgets('a website code opens the website venue', (tester) async {
      // Arrange
      scanner.queuePayload('https://cafe.co.il/menu');
      final pushed = <String>[];
      await _pump(tester, controller, pushed: pushed);

      // Act
      await tester.tap(_action(_en.scanQrAction));
      await tester.pumpAndSettle();

      // Assert
      expect(pushed, [
        '/venue/website/${Uri.encodeComponent('https://cafe.co.il/menu')}',
      ]);
    });

    testWidgets('a cancelled scan opens nothing and says nothing', (
      tester,
    ) async {
      // Arrange
      final pushed = <String>[];
      await _pump(tester, controller, pushed: pushed);

      // Act
      await tester.tap(_action(_en.scanQrAction));
      await tester.pumpAndSettle();

      // Assert
      expect(pushed, isEmpty);
      expect(find.text(_en.scanQrPhotographInstead), findsNothing);
      expect(find.text(_en.scanQrUnsupportedSource('Tabit')), findsNothing);
      expect(_enabled(tester, _action(_en.scanQrAction)), isTrue);
    });

    testWidgets('a Tabit code says Tabit is not supported yet', (tester) async {
      // Arrange
      scanner.queuePayload('https://tabitisrael.co.il/tabit-order?siteName=x');
      final pushed = <String>[];
      await _pump(tester, controller, pushed: pushed);

      // Act
      await tester.tap(_action(_en.scanQrAction));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanQrUnsupportedSource('Tabit')), findsOneWidget);
      expect(pushed, isEmpty);
    });

    testWidgets('an Instagram code suggests photographing the menu', (
      tester,
    ) async {
      // Arrange
      scanner.queuePayload('https://www.instagram.com/cafe.noa');
      final pushed = <String>[];
      await _pump(tester, controller, pushed: pushed);

      // Act
      await tester.tap(_action(_en.scanQrAction));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanQrPhotographInstead), findsOneWidget);
      expect(pushed, isEmpty);
    });

    testWidgets('a code that is not a URL suggests photographing too', (
      tester,
    ) async {
      // Arrange
      scanner.queuePayload('Table 12');
      await _pump(tester, controller);

      // Act
      await tester.tap(_action(_en.scanQrAction));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanQrPhotographInstead), findsOneWidget);
    });

    testWidgets('the action is disabled while the camera is open', (
      tester,
    ) async {
      // Arrange
      final gate = Completer<String?>();
      final slow = build(_GatedScanner(gate.future));
      addTearDown(slow.dispose);
      await _pump(tester, slow);

      // Act
      await tester.tap(_action(_en.scanQrAction));
      await tester.pump();

      // Assert
      expect(_enabled(tester, _action(_en.scanQrAction)), isFalse);

      gate.complete(null);
      await tester.pumpAndSettle();
      expect(_enabled(tester, _action(_en.scanQrAction)), isTrue);
    });

    testWidgets('Hebrew renders the action and each notice, right to left', (
      tester,
    ) async {
      // Arrange
      scanner
        ..queuePayload('https://tabitisrael.co.il/tabit-order?siteName=x')
        ..queuePayload('https://www.instagram.com/cafe.noa');
      await _pump(tester, controller, locale: const Locale('he'));

      // Act & Assert
      expect(find.text(_he.scanQrAction), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(_he.scanQrAction))),
        TextDirection.rtl,
      );

      await tester.tap(_action(_he.scanQrAction));
      await tester.pumpAndSettle();
      expect(find.text(_he.scanQrUnsupportedSource('Tabit')), findsOneWidget);

      await tester.tap(_action(_he.scanQrAction));
      await tester.pumpAndSettle();
      expect(find.text(_he.scanQrPhotographInstead), findsOneWidget);
      expect(find.text(_he.scanQrUnsupportedSource('Tabit')), findsNothing);
    });
  });
}

/// A [QrScanner] that answers when its [gate] completes.
final class _GatedScanner implements QrScanner {
  new(this.gate);

  final Future<String?> gate;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> scan() => gate;
}
