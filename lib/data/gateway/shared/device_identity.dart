import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:stt_tts/data/secure/secure_store.dart';

const _kSecret = 'oc.deviceSecret'; // base64url-no-pad of 32 raw bytes
const _kPublic = 'oc.devicePublic'; // base64url-no-pad of 32 raw bytes
const _kDeviceId = 'oc.deviceId';   // 64-char lowercase hex of SHA-256(public)

/// Encodes bytes as base64url WITHOUT padding (matches gateway's En()).
String base64UrlNoPad(List<int> b) =>
    base64Url.encode(b).replaceAll('=', '');

/// Decodes a base64url-no-pad string. Adds back '=' padding before decoding.
Uint8List decodeBase64UrlNoPad(String s) {
  final padded = s + '=' * ((4 - s.length % 4) % 4);
  return base64Url.decode(padded);
}

/// Lowercase hex string (matches gateway's On()).
String hexLower(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

class DeviceIdentity {
  DeviceIdentity._({
    required this.deviceId,
    required this.publicKeyB64u,
    required SimpleKeyPair keyPair,
  }) : _keyPair = keyPair;

  /// 64 lowercase hex chars: `hex(SHA-256(publicKeyBytes))`.
  final String deviceId;

  /// Raw 32-byte Ed25519 public key, base64url-no-pad.
  final String publicKeyB64u;

  final SimpleKeyPair _keyPair;
  static final _algo = Ed25519();

  /// Signs the canonical UTF-8 bytes; returns base64url-no-pad of the
  /// 64-byte raw Ed25519 signature.
  Future<String> signCanonical(String canonical) async {
    final sig = await _algo.sign(
      utf8.encode(canonical),
      keyPair: _keyPair,
    );
    return base64UrlNoPad(sig.bytes);
  }
}

class DeviceIdentityManager {
  DeviceIdentityManager({required this.store});
  final SecureStore store;
  static final _algo = Ed25519();
  static final _sha = Sha256();

  Future<DeviceIdentity> loadOrCreate() async {
    final secB64 = await store.read(_kSecret);
    final pubB64 = await store.read(_kPublic);
    final id = await store.read(_kDeviceId);

    if (secB64 != null && pubB64 != null && id != null) {
      final secBytes = decodeBase64UrlNoPad(secB64);
      final pubBytes = decodeBase64UrlNoPad(pubB64);
      // Re-derive deviceId and confirm match. If corrupt, regenerate.
      final hash = await _sha.hash(pubBytes);
      final derivedId = hexLower(hash.bytes);
      if (derivedId != id) {
        await _wipe();
        return loadOrCreate();
      }
      final keyPair = await _algo.newKeyPairFromSeed(secBytes);
      return DeviceIdentity._(
        deviceId: id,
        publicKeyB64u: pubB64,
        keyPair: keyPair,
      );
    }
    return _generateNew();
  }

  Future<DeviceIdentity> _generateNew() async {
    final keyPair = await _algo.newKeyPair();
    final secret = await keyPair.extractPrivateKeyBytes();
    final pub = await keyPair.extractPublicKey();
    final pubBytes = await pub.bytes;
    final hash = await _sha.hash(pubBytes);
    final deviceId = hexLower(hash.bytes);
    final pubB64u = base64UrlNoPad(pubBytes);
    final secB64u = base64UrlNoPad(secret);

    await store.write(_kSecret, secB64u);
    await store.write(_kPublic, pubB64u);
    await store.write(_kDeviceId, deviceId);

    return DeviceIdentity._(
      deviceId: deviceId,
      publicKeyB64u: pubB64u,
      keyPair: keyPair,
    );
  }

  Future<void> _wipe() async {
    await store.delete(_kSecret);
    await store.delete(_kPublic);
    await store.delete(_kDeviceId);
  }
}
