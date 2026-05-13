import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/theme.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/ui/onboarding/connecting_screen.dart';
import 'package:stt_tts/ui/widgets/oc_button.dart';
import 'package:stt_tts/ui/widgets/oc_text_field.dart';

class PairFormScreen extends ConsumerStatefulWidget {
  const PairFormScreen({super.key});
  @override
  ConsumerState<PairFormScreen> createState() => _PairFormScreenState();
}

class _PairFormScreenState extends ConsumerState<PairFormScreen> {
  final _url = TextEditingController(text: 'ws://192.168.1.3:18789/');
  final _token = TextEditingController(text: 'test-123');

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: OcColors.textPrimary,
        title: const Text('Connect'),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: ocBackgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Text(
                  'Pair this phone to your gateway',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: OcColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'URL and gateway token from your .env. The token is only kept until pairing succeeds.',
                  style: TextStyle(
                    color: OcColors.textSubtitle,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 22),
                OcTextField(
                  label: 'Gateway URL',
                  controller: _url,
                  hint: 'ws://192.168.1.10:18789',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 14),
                OcTextField(
                  label: 'Gateway token',
                  controller: _token,
                  hint: 'OPENCLAW_GATEWAY_TOKEN',
                  obscure: true,
                ),
                const Spacer(),
                OcButton(
                  label: 'Connect',
                  onPressed: () {
                    final url = _url.text.trim();
                    final token = _token.text.trim();
                    if (url.isEmpty || token.isEmpty) return;
                    ref
                        .read(pairControllerProvider.notifier)
                        .pair(wsUrl: url, token: token);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ConnectingScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
