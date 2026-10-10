import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:test/test.dart';

/// Guards the entry condition of [SendNotifier.sendFile].
///
/// Regression: applying the "first send" states to retries as well silently
/// swallowed the ↻ (retry) button on the progress page. The progress page shows
/// that button whenever a *file* failed — including when the *session* is
/// `canceledByReceiver` — so clicking it did nothing at all: no new
/// prepare-upload was sent, the receiver never showed its confirmation again and
/// the sender logged nothing. That made "retry continues the transfer" look
/// broken.
void main() {
  group('SendNotifier.maySendOrRetry', () {
    test('without a session nothing happens', () {
      expect(SendNotifier.maySendOrRetry(status: null, isRetry: false), isFalse);
      expect(SendNotifier.maySendOrRetry(status: null, isRetry: true), isFalse);
    });

    test('a first send only runs while active or partially failed', () {
      const allowed = {SessionStatus.sending, SessionStatus.finishedWithErrors};
      for (final status in SessionStatus.values) {
        expect(
          SendNotifier.maySendOrRetry(status: status, isRetry: false),
          allowed.contains(status),
          reason: 'first send while $status',
        );
      }
    });

    test('a retry is allowed from every state', () {
      for (final status in SessionStatus.values) {
        expect(
          SendNotifier.maySendOrRetry(status: status, isRetry: true),
          isTrue,
          reason: 'retry while $status',
        );
      }
    });

    test('regression: retrying a receiver-canceled session is allowed', () {
      expect(
        SendNotifier.maySendOrRetry(status: SessionStatus.canceledByReceiver, isRetry: true),
        isTrue,
      );
      expect(
        SendNotifier.maySendOrRetry(status: SessionStatus.canceledBySender, isRetry: true),
        isTrue,
      );
      expect(
        SendNotifier.maySendOrRetry(status: SessionStatus.finishedWithErrors, isRetry: true),
        isTrue,
      );
    });
  });
}
