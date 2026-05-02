import 'package:permission_handler/permission_handler.dart';

enum MicPermissionState { granted, denied, permanentlyDenied }

class MicPermission {
  Future<MicPermissionState> request() async {
    final status = await Permission.microphone.request();
    return _toState(status);
  }

  Future<MicPermissionState> check() async {
    final status = await Permission.microphone.status;
    return _toState(status);
  }

  Future<void> openSettings() => openAppSettings();

  static MicPermissionState _toState(PermissionStatus s) => switch (s) {
        PermissionStatus.granted => MicPermissionState.granted,
        PermissionStatus.permanentlyDenied => MicPermissionState.permanentlyDenied,
        _ => MicPermissionState.denied,
      };
}
