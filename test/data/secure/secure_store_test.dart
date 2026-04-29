import 'package:flutter_test/flutter_test.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

void main() {
  test('FakeSecureStore stores and retrieves values', () async {
    final store = FakeSecureStore();
    expect(await store.read('k'), null);
    await store.write('k', 'v');
    expect(await store.read('k'), 'v');
    await store.delete('k');
    expect(await store.read('k'), null);
  });
}
