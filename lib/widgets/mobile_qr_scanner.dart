import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/services/platform/qr_scanner.dart';
import 'package:mobile_scanner/mobile_scanner.dart'
    show
        BarcodeCapture,
        BarcodeFormat,
        MobileScanner,
        MobileScannerController,
        MobileScannerErrorCode,
        MobileScannerException;

/// Builds the camera view inside the scanner page: a widget that calls
/// `onCode` with the text of each QR code it decodes. The real one is the
/// `mobile_scanner` preview; a test passes a stand-in that needs no camera.
typedef QrCameraBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onCode,
);

/// The [QrScanner] for iOS and Android, over `mobile_scanner` (issue #182).
///
/// [scan] pushes a full-screen camera page on the app's root navigator
/// (its navigator key) and answers the first QR code the camera decodes,
/// popping the page as it does; backing out answers null. It never throws: a
/// denied camera permission shows a message on the page, which the user
/// closes, and that too answers null. A second [scan] while a page is already
/// up answers null rather than stacking another camera.
///
/// It lives in `widgets/`, not `services/platform/` beside the other plugin
/// wrappers, because it owns a page and `services/` may import no widget
/// code (`architecture.md` §5); the `mobile_scanner` import is still pinned
/// to this one file by the architecture test.
///
/// The constructor performs no plugin I/O: `MobileScannerController` is
/// built, and the camera opened, only when the page is shown, so `di.dart`
/// can construct this at start-up (`di_test` asserts it).
final class MobileQrScanner implements QrScanner {
  /// Creates a scanner that shows its page on the navigator behind
  /// `navigatorKey`. `cameraBuilder` defaults to the real camera view; tests
  /// pass a fake.
  new({required this._navigatorKey, QrCameraBuilder? cameraBuilder})
    : _camera = cameraBuilder ?? _pluginCamera;

  final GlobalKey<NavigatorState> _navigatorKey;
  final QrCameraBuilder _camera;
  bool _open = false;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> scan() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || _open) return null;
    _open = true;
    try {
      return await navigator.push<String>(
        MaterialPageRoute<String>(
          fullscreenDialog: true,
          builder: (_) => _QrScannerPage(camera: _camera),
        ),
      );
    } on Exception {
      return null;
    } finally {
      _open = false;
    }
  }

  static Widget _pluginCamera(
    BuildContext context,
    ValueChanged<String> onCode,
  ) => _PluginCamera(onCode: onCode);
}

/// The full-screen page: the camera under a one-line instruction. Pops with
/// the first code it is given, once.
class _QrScannerPage extends StatefulWidget {
  const new({required this.camera});

  final QrCameraBuilder camera;

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  bool _done = false;

  void _onCode(String code) {
    if (_done || code.isEmpty || !mounted) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanQrTitle)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          widget.camera(context, _onCode),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.inverseSurface.withAlpha(220),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      l10n.scanQrInstruction,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onInverseSurface),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The real camera view: a `mobile_scanner` preview that looks for QR codes
/// only, and a message in its place when the camera cannot start.
class _PluginCamera extends StatefulWidget {
  const new({required this.onCode});

  final ValueChanged<String> onCode;

  @override
  State<_PluginCamera> createState() => _PluginCameraState();
}

class _PluginCameraState extends State<_PluginCamera> {
  late final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        widget.onCode(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => MobileScanner(
    controller: _controller,
    onDetect: _onDetect,
    errorBuilder: (context, error) => _CameraError(error: error),
  );
}

/// What replaces the preview when the camera cannot start. The page's own
/// close button is the way out.
class _CameraError extends StatelessWidget {
  const new({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.inverseSurface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            liveRegion: true,
            child: Text(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? l10n.scanQrCameraDenied
                  : l10n.scanQrCameraUnavailable,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onInverseSurface),
            ),
          ),
        ),
      ),
    );
  }
}
