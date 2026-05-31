import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/design_tokens.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/state/theme_provider.dart';

/// Agent connection card — entry point for users who skipped onboarding or
/// want to re-pair to a different gateway. Reuses the same three inputs as
/// the onboarding screen (URL · Port · Token) and exposes Connect /
/// Disconnect actions plus inline status.
class AgentSetupSection extends ConsumerStatefulWidget {
  const AgentSetupSection({super.key});

  @override
  ConsumerState<AgentSetupSection> createState() => _AgentSetupSectionState();
}

class _AgentSetupSectionState extends ConsumerState<AgentSetupSection> {
  late final TextEditingController _url;
  late final TextEditingController _port;
  late final TextEditingController _token;
  String? _inlineError;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController();
    _port = TextEditingController();
    _token = TextEditingController();
    // Prefill URL/Port from the persisted wsUrl on a microtask — the
    // SecureStore read is async and we don't want to block the first frame.
    _prefillFromStore();
  }

  Future<void> _prefillFromStore() async {
    final stored = await ref.read(secureStoreProvider).read('oc.wsUrl');
    if (stored == null || !mounted) return;
    final parsed = Uri.tryParse(stored);
    if (parsed == null || parsed.host.isEmpty) return;
    if (mounted) {
      setState(() {
        _url.text = '${parsed.scheme}://${parsed.host}';
        if (parsed.hasPort) _port.text = parsed.port.toString();
        _prefilled = true;
      });
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _url.text.trim();
    final portText = _port.text.trim();
    final token = _token.text.trim();
    if (url.isEmpty || portText.isEmpty || token.isEmpty) {
      setState(() => _inlineError = 'Invalid connection details');
      return;
    }
    final port = int.tryParse(portText);
    if (port == null) {
      setState(() => _inlineError = 'Invalid connection details');
      return;
    }
    setState(() => _inlineError = null);
    final ctrl = ref.read(agentConnectionControllerProvider.notifier);
    await ctrl.connect(url: url, port: port, token: token);
    if (!mounted) return;
    final result = ref.read(agentConnectionControllerProvider);
    if (result.status == AgentConnectionStatus.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agent connected successfully')),
      );
      _token.clear();
    } else {
      setState(() => _inlineError = result.error ?? 'Unable to connect to agent');
    }
  }

  Future<void> _disconnect() async {
    await ref.read(agentConnectionControllerProvider.notifier).disconnect();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Agent disconnected')),
    );
    setState(() {
      _token.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(tokensProvider);
    final conn = ref.watch(agentConnectionControllerProvider);
    final busy = conn.isBusy;
    final connected = conn.isConnected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBadge(connected: connected, busy: busy, tokens: tokens),
          const SizedBox(height: 14),
          _Field(
            label: 'Agent URL',
            controller: _url,
            hint: 'wss://my.agent.com',
            keyboardType: TextInputType.url,
            tokens: tokens,
          ),
          const SizedBox(height: 10),
          _Field(
            label: 'Port',
            controller: _port,
            hint: '18789',
            keyboardType: TextInputType.number,
            tokens: tokens,
          ),
          const SizedBox(height: 10),
          _Field(
            label: 'Token',
            controller: _token,
            hint: 'Paste your agent token',
            obscure: true,
            tokens: tokens,
          ),
          if (busy) ...[
            const SizedBox(height: 12),
            _StatusLine(
              icon: Icons.wifi_tethering,
              text: 'Connecting to agent…',
              color: tokens.text,
            ),
          ],
          if (_inlineError != null) ...[
            const SizedBox(height: 12),
            _StatusLine(
              icon: Icons.error_outline,
              text: _inlineError!,
              color: const Color(0xFFDC2626),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PillButton(
                  label: connected ? 'Reconnect' : 'Connect',
                  primary: true,
                  busy: busy,
                  onTap: busy ? null : _connect,
                  tokens: tokens,
                ),
              ),
              if (connected) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _PillButton(
                    label: 'Disconnect',
                    primary: false,
                    onTap: busy ? null : _disconnect,
                    tokens: tokens,
                  ),
                ),
              ],
            ],
          ),
          if (_prefilled && !connected) ...[
            const SizedBox(height: 8),
            Text(
              'URL and port were filled from your last session. Re-enter the token to reconnect.',
              style: TextStyle(color: tokens.textMuted, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.connected,
    required this.busy,
    required this.tokens,
  });
  final bool connected;
  final bool busy;
  final OcTokens tokens;

  @override
  Widget build(BuildContext context) {
    final Color dot;
    final String label;
    if (busy) {
      dot = const Color(0xFFFBBC05);
      label = 'Connecting…';
    } else if (connected) {
      dot = const Color(0xFF22C55E);
      label = 'Connected';
    } else {
      dot = tokens.textMuted;
      label = 'Not connected';
    }
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: tokens.text,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 12.5, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.tokens,
    this.hint,
    this.obscure = false,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final OcTokens tokens;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 42,
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            cursorColor: tokens.accent,
            style: TextStyle(color: tokens.text, fontSize: 13),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              hintText: hint,
              hintStyle: TextStyle(color: tokens.textMuted, fontSize: 13),
              filled: true,
              fillColor: tokens.chipBg,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: tokens.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: tokens.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.primary,
    required this.onTap,
    required this.tokens,
    this.busy = false,
  });

  final String label;
  final bool primary;
  final VoidCallback? onTap;
  final OcTokens tokens;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? tokens.text : Colors.transparent;
    final fg = primary ? tokens.bg : tokens.text;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: primary ? null : Border.all(color: tokens.border),
        ),
        child: busy
            ? SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: fg,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
