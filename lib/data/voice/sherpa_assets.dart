import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Asset-copying + PCM conversion helpers shared by [SttService] and
/// [TtsService]. Sherpa-ONNX models live in the Flutter asset bundle as a
/// read-only resource; the native library expects file paths on disk, so we
/// copy them into the app support directory on first launch and re-use the
/// cached files thereafter.

Future<String> _appSupportPath() async {
  final dir = await getApplicationSupportDirectory();
  return dir.path;
}

/// Copy a single Flutter asset to the app support dir. Returns the absolute
/// filesystem path. No-op if the file already exists with the same size.
Future<String> copyAssetFile(String assetPath) async {
  final base = await _appSupportPath();
  final dst = p.join(base, assetPath);
  final f = File(dst);

  // Cheap freshness check: if size on disk matches the asset size, skip.
  final data = await rootBundle.load(assetPath);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  if (await f.exists() && (await f.length()) == bytes.length) {
    return dst;
  }

  await f.parent.create(recursive: true);
  await f.writeAsBytes(bytes, flush: true);
  return dst;
}

/// Copy every asset under [assetPrefix] (recursive) and return the local
/// directory path that mirrors the prefix. Uses [AssetManifest] to enumerate,
/// so every file must be declared in `pubspec.yaml`.
Future<String> copyAssetDir(String assetPrefix) async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final normalized = assetPrefix.endsWith('/') ? assetPrefix : '$assetPrefix/';
  final keys = manifest.listAssets().where((k) => k.startsWith(normalized));
  for (final k in keys) {
    await copyAssetFile(k);
  }
  final base = await _appSupportPath();
  return p.join(base, normalized.substring(0, normalized.length - 1));
}

/// Convert PCM signed-16-bit little-endian bytes into a Float32 list scaled
/// to [-1.0, 1.0] — the format Sherpa-ONNX expects via
/// `OnlineStream.acceptWaveform`.
Float32List convertBytesToFloat32(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final out = Float32List(n);
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i < n; i++) {
    final s = bd.getInt16(i * 2, Endian.little);
    out[i] = s / 32768.0;
  }
  return out;
}
