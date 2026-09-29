import 'package:ketoclub/services/platform/qr_scanner.dart';

/// A scripted [QrScanner] for tests.
///
/// [queuePayload] adds one answer, returned by the next [scan] in order; a
/// queued null is a cancelled scan. With the queue empty [scan] answers
/// null, exactly as a cancelled camera does. [available] is what
/// [isAvailable] reports, so a test can show or hide the Scan tab's QR
/// action. Every [scan] is counted in [scanCallCount].
final class FakeQrScanner implements QrScanner {
  /// Creates a scanner that is [available] (default true) with nothing
  /// queued.
  new({this.available = true});

  /// What [isAvailable] answers.
  bool available;

  /// How many times [scan] was called.
  int scanCallCount = 0;

  final List<String?> _payloads = <String?>[];

  /// Queues [payload] as the answer to the next unanswered [scan]; null
  /// queues a cancelled scan.
  void queuePayload(String? payload) => _payloads.add(payload);

  @override
  bool get isAvailable => available;

  @override
  Future<String?> scan() async {
    scanCallCount++;
    return _payloads.isEmpty ? null : _payloads.removeAt(0);
  }
}
