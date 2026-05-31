import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/design_tokens.dart';
import 'package:stt_tts/state/connection_provider.dart';
import 'package:stt_tts/state/onboarding_provider.dart';
import 'package:stt_tts/state/theme_provider.dart';

/// Post-login screen offering optional agent setup.
///
/// Connect — pairs with the gateway, persists the device token, marks
/// onboarding done and lets the router show the home shell.
/// Skip — marks onboarding done without pairing; the home shell still works
/// for speech-to-text but assistant replies are replaced by "Please connect
/// to your agent" until the user pairs an agent from Settings.
///
/// Theming flows through [tokensProvider] so this screen follows the same
/// dark/light system as the sign-in screen and the rest of the app. The
/// background fills the whole `Scaffold` (solid `t.bg`) — no fixed-height
/// gradient that can leave dead space at the bottom on tall devices.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _url = TextEditingController();
  final _port = TextEditingController();
  final _token = TextEditingController();

  bool _showToken = false;
  String? _inlineError;

  @override
  void dispose() {
    _url.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  // `--border-strong` — input borders sit a touch darker than the generic
  // border token, mirroring the sign-in fields.
  Color _borderStrong(OcTokens t) => t.brightness == Brightness.dark
      ? const Color.fromRGBO(255, 255, 255, 0.16)
      : const Color.fromRGBO(0, 0, 0, 0.16);

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
    final controller = ref.read(agentConnectionControllerProvider.notifier);
    await controller.connect(url: url, port: port, token: token);
    if (!mounted) return;

    final result = ref.read(agentConnectionControllerProvider);
    if (result.status == AgentConnectionStatus.connected) {
      await ref.markOnboardingDone();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agent connected successfully')),
      );
      // _AppRouter swaps to HomeShell once onboardingDoneProvider re-emits.
    } else {
      setState(() => _inlineError = result.error ?? 'Unable to connect to agent');
    }
  }

  Future<void> _skip() async {
    await ref.markOnboardingDone();
    // Router will swap to HomeShell on next frame.
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tokensProvider);
    final isDark = t.brightness == Brightness.dark;
    final conn = ref.watch(agentConnectionControllerProvider);
    final busy = conn.isBusy;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand mark — inverts with theme (dark: white tile / dark glyph,
              // light: dark tile / light glyph), matching the sign-in logo.
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '⌘',
                    style: TextStyle(
                      fontSize: 28,
                      color: isDark ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Connect your agent',
                style: TextStyle(
                  color: t.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'OpenClaw can run on its own for speech-to-text. '
                'Connecting an agent unlocks AI replies. You can do this '
                'later from Settings.',
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              _OcField(
                label: 'Agent URL',
                controller: _url,
                hint: 'wss://my.agent.com',
                keyboardType: TextInputType.url,
                tokens: t,
                borderStrong: _borderStrong(t),
              ),
              const SizedBox(height: 14),
              _OcField(
                label: 'Port',
                controller: _port,
                hint: '18789',
                keyboardType: TextInputType.number,
                tokens: t,
                borderStrong: _borderStrong(t),
              ),
              const SizedBox(height: 14),
              _OcField(
                label: 'Token',
                controller: _token,
                hint: 'Paste your agent token',
                obscure: !_showToken,
                tokens: t,
                borderStrong: _borderStrong(t),
                suffix: IconButton(
                  onPressed: () => setState(() => _showToken = !_showToken),
                  icon: Icon(
                    _showToken
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: t.textMuted,
                  ),
                  tooltip: _showToken ? 'Hide token' : 'Show token',
                  splashRadius: 18,
                ),
              ),
              if (busy) ...[
                const SizedBox(height: 18),
                _StatusLine(
                  icon: Icons.wifi_tethering,
                  text: 'Connecting to agent…',
                  tone: _StatusTone.info,
                  tokens: t,
                ),
              ],
              if (_inlineError != null) ...[
                const SizedBox(height: 18),
                _StatusLine(
                  icon: Icons.error_outline,
                  text: _inlineError!,
                  tone: _StatusTone.error,
                  tokens: t,
                ),
              ],
              const SizedBox(height: 24),
              _PrimaryButton(
                label: 'Connect',
                busy: busy,
                tokens: t,
                onPressed: busy ? null : _connect,
              ),
              const SizedBox(height: 12),
              _SecondaryButton(
                label: 'Skip for now',
                tokens: t,
                borderStrong: _borderStrong(t),
                onPressed: busy ? null : _skip,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labelled, theme-aware text field — mirrors the sign-in field styling
/// (filled `chipBg`, strong border, 14-px radius) with an uppercase label.
class _OcField extends StatelessWidget {
  const _OcField({
    required this.label,
    required this.controller,
    required this.tokens,
    required this.borderStrong,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final OcTokens tokens;
  final Color borderStrong;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: tokens.textMuted,
            fontWeight: FontWeight.w600,
            fontSize: 11,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 50,
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            cursorColor: tokens.accent,
            style: TextStyle(
              color: tokens.text,
              fontSize: 14.5,
              fontWeight: FontWeight.w400,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding:
                  EdgeInsets.fromLTRB(16, 16, suffix == null ? 16 : 46, 16),
              hintText: hint,
              hintStyle: TextStyle(color: tokens.textMuted, fontSize: 14.5),
              filled: true,
              fillColor: tokens.chipBg,
              suffixIcon: suffix,
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: borderStrong),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: tokens.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Inverted primary button — background = text color, label = bg color.
/// Identical treatment to the sign-in "Continue" CTA.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.tokens,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final OcTokens tokens;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: Container(
        height: 50,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.text,
          borderRadius: BorderRadius.circular(14),
        ),
        child: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.bg,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  color: tokens.bg,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

/// Outline secondary button.
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.tokens,
    required this.borderStrong,
    required this.onPressed,
  });

  final String label;
  final OcTokens tokens;
  final Color borderStrong;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 50,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderStrong),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: tokens.textSoft,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

enum _StatusTone { info, error }

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.text,
    required this.tone,
    required this.tokens,
  });

  final IconData icon;
  final String text;
  final _StatusTone tone;
  final OcTokens tokens;

  @override
  Widget build(BuildContext context) {
    final color = tone == _StatusTone.error
        ? const Color(0xFFDC2626)
        : tokens.text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 13, height: 1.35),
          ),
        ),
      ],
    );
  }
}
