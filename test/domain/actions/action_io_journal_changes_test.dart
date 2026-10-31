import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/action_io_journal_changes.dart';

final class _Journal with ActionIoJournalChanges {}

void main() {
  test('commits between the check and wait are coalesced per execution', () async {
    final journal = _Journal();
    final reader = journal.observeChanges('active');
    final other = journal.observeChanges('other');
    addTearDown(reader.close);
    addTearDown(other.close);
    const fallback = Duration(minutes: 1);
    var otherWoke = false;
    final otherWait = other.wait(fallback).then((_) => otherWoke = true);
    journal.signalJournalCommit('active');
    journal.signalJournalCommit('active');
    await reader.wait(fallback).timeout(const Duration(seconds: 2));
    expect(otherWoke, false);
    final waiting = reader.wait(fallback);
    journal.signalJournalCommit('active');
    await waiting.timeout(const Duration(seconds: 2));
    other.close();
    await otherWait.timeout(const Duration(seconds: 2));
  });
}
