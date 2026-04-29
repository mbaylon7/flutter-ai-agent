import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/domain/models/session.dart';

void main() {
  test('Session.fromJson reads gateway shape (key/displayName/Unix-ms)', () {
    final s = Session.fromJson({
      'key': 'agent:main:main',
      'displayName': 'heartbeat',
      'kind': 'direct',
      'updatedAt': 1777443641130,
      'totalTokens': 16519,
      'estimatedCostUsd': 0.31,
    });
    expect(s.key, 'agent:main:main');
    expect(s.title, 'heartbeat');
    expect(s.kind, 'direct');
    expect(s.updatedAt.millisecondsSinceEpoch, 1777443641130);
    expect(s.pinned, false);
    expect(s.totalTokens, 16519);
  });

  test('copyWith preserves unspecified fields', () {
    final s = Session(
      key: 'k', title: 'old',
      updatedAt: DateTime(2026), kind: 'direct', pinned: false,
    );
    final next = s.copyWith(title: 'new');
    expect(next.title, 'new');
    expect(next.key, 'k');
    expect(next.kind, 'direct');
  });
}
