import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newRequestId() => _uuid.v4();
String newDeviceId() => _uuid.v4();
String newInstanceId() => _uuid.v4();
