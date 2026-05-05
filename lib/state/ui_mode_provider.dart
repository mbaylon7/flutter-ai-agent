import 'package:flutter_riverpod/flutter_riverpod.dart';

enum UiMode { voice, chat }

final uiModeProvider = StateProvider<UiMode>((_) => UiMode.voice);
