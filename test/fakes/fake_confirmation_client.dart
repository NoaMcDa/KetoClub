import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/community/confirmation_client.dart';

/// One [FakeConfirmationClient.confirm] call, exactly as it was asked.
typedef FakeConfirmationCall = ({
  VenueRef ref,
  String dishFingerprint,
  String restrictionId,
  ConfirmationPolarity polarity,
});

/// A scripted [ConfirmationClient] for tests (issue #409).
///
/// A configured fake answers every [confirm] with
/// `ConfirmationRecorded(counted: true)`; set [isConfigured] to false for a
/// build with no backend, or [result] to script another answer. Every call
/// is recorded in [calls], in order.
final class FakeConfirmationClient implements ConfirmationClient {
  /// Creates a configured fake.
  new();

  @override
  bool isConfigured = true;

  /// What every [confirm] answers.
  ConfirmationResult result = const ConfirmationRecorded(counted: true);

  /// Every call, in order.
  final List<FakeConfirmationCall> calls = <FakeConfirmationCall>[];

  @override
  Future<ConfirmationResult> confirm({
    required VenueRef ref,
    required String dishFingerprint,
    required String restrictionId,
    required ConfirmationPolarity polarity,
  }) async {
    calls.add((
      ref: ref,
      dishFingerprint: dishFingerprint,
      restrictionId: restrictionId,
      polarity: polarity,
    ));
    return result;
  }
}
