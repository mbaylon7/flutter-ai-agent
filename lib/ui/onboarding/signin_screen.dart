import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stt_tts/core/design_tokens.dart';
import 'package:stt_tts/data/auth/auth_service.dart';
import 'package:stt_tts/state/auth_provider.dart';
import 'package:stt_tts/state/theme_provider.dart';

/// Ported 1:1 from `docs/signin.html`. Theming flows through [tokensProvider]
/// so light/dark follow the rest of the app. OAuth + Continue currently
/// forward to the existing pairing flow — Firebase wiring lands next on the
/// `firebase-auth` branch.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // `--border-strong` from the HTML — the input borders are noticeably
  // darker than the generic `border` token, so we lift the alpha here.
  Color _borderStrong(OcTokens t) => t.brightness == Brightness.dark
      ? const Color.fromRGBO(255, 255, 255, 0.16)
      : const Color.fromRGBO(0, 0, 0, 0.16);

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on AuthFailure catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _continueWithEmail() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      _showError('Email and password required.');
      return;
    }
    await _run(() async {
      await ref
          .read(authServiceProvider)
          .signInWithEmail(email: email, password: password);
      // _AppRouter swaps the screen automatically once authStateProvider
      // emits the new user.
    });
  }

  Future<void> _continueWithGoogle() async {
    await _run(() async {
      await ref.read(authServiceProvider).signInWithGoogle();
    });
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _showError('Enter your email first to receive a reset link.');
      return;
    }
    await _run(() async {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset email sent to $email'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  void _unimplementedProvider(String name) {
    _showError('$name sign-in is not configured yet.');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tokensProvider);
    final isDark = t.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          // Brand glow — soft static rainbow above the logo.
          Positioned(
            top: -120,
            left: 0,
            right: 0,
            height: 320,
            child: IgnorePointer(
              child: Center(
                child: SizedBox(
                  width: 460,
                  height: 320,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                    child: Opacity(
                      opacity: isDark ? 0.55 : 0.40,
                      child: CustomPaint(painter: _BrandGlowPainter()),
                    ),
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 60),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        const SizedBox(height: 36),

                  // Logo — inverts with theme (dark mode: white bg/black icon;
                  // light mode: black bg/white icon)
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
                    child: Icon(
                      Icons.bolt_rounded,
                      color: isDark ? Colors.black : Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Welcome to OpenClaw',
                    style: TextStyle(
                      color: t.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in or create an account',
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),

                  // Flexible gap — pushes the form toward the vertical centre
                  // on tall screens (design uses a fixed 130px here; a flex
                  // gap adapts to device height instead of leaving dead space).
                  const Spacer(flex: 3),

                  // Email
                  _OcAuthField(
                    controller: _email,
                    hint: 'Email address',
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    tokens: t,
                    borderStrong: _borderStrong(t),
                  ),
                  const SizedBox(height: 15),

                  // Password
                  _OcAuthField(
                    controller: _password,
                    hint: 'Password',
                    obscure: !_showPassword,
                    keyboardType: TextInputType.visiblePassword,
                    autofillHints: const [AutofillHints.password],
                    tokens: t,
                    borderStrong: _borderStrong(t),
                    onSubmitted: (_) => _continueWithEmail(),
                    suffix: IconButton(
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: t.textMuted,
                      ),
                      tooltip:
                          _showPassword ? 'Hide password' : 'Show password',
                      splashRadius: 18,
                    ),
                  ),

                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: _busy ? null : _forgotPassword,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Forgot password?',
                          style: TextStyle(
                            color: t.textSoft,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 9),

                  // Primary CTA — inverted (text-color background)
                  _PrimaryCta(
                    tokens: t,
                    busy: _busy,
                    onPressed: _continueWithEmail,
                  ),

                  const SizedBox(height: 20),

                  // Terms
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 11.5,
                        height: 1.55,
                      ),
                      children: [
                        const TextSpan(
                          text: "By continuing, you agree to OpenClaw's\n",
                        ),
                        TextSpan(
                          text: 'Terms of Service',
                          style: TextStyle(
                            color: t.textSoft,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: TextStyle(
                            color: t.textSoft,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // OAuth row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _OAuthIconButton(
                        tokens: t,
                        borderStrong: _borderStrong(t),
                        onPressed: () => _unimplementedProvider('Apple'),
                        child: Icon(Icons.apple, size: 22, color: t.text),
                      ),
                      const SizedBox(width: 14),
                      _OAuthIconButton(
                        tokens: t,
                        borderStrong: _borderStrong(t),
                        onPressed: _busy ? null : _continueWithGoogle,
                        child: const _GoogleGlyph(size: 20),
                      ),
                      const SizedBox(width: 14),
                      _OAuthIconButton(
                        tokens: t,
                        borderStrong: _borderStrong(t),
                        onPressed: () => _unimplementedProvider('Microsoft'),
                        child: const _MicrosoftGlyph(size: 20),
                      ),
                    ],
                  ),

                        // Smaller bottom slack so the OAuth row settles into
                        // the lower third rather than mid-screen — balances
                        // against the larger flex gap above the form.
                        const Spacer(flex: 2),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Email/password text field styled to match `.field input` in the HTML.
class _OcAuthField extends StatelessWidget {
  const _OcAuthField({
    required this.controller,
    required this.hint,
    required this.tokens,
    required this.borderStrong,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.suffix,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final OcTokens tokens;
  final Color borderStrong;
  final bool obscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        onSubmitted: onSubmitted,
        cursorColor: tokens.accent,
        style: TextStyle(
          color: tokens.text,
          fontSize: 14.5,
          fontWeight: FontWeight.w400,
        ),
        decoration: InputDecoration(
          isCollapsed: true,
          contentPadding: EdgeInsets.fromLTRB(16, 16, suffix == null ? 16 : 46, 16),
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
    );
  }
}

/// Inverted primary button — background = text color, label = bg color.
class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({
    required this.tokens,
    required this.onPressed,
    this.busy = false,
  });

  final OcTokens tokens;
  final VoidCallback onPressed;
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
                'Continue',
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

class _OAuthIconButton extends StatelessWidget {
  const _OAuthIconButton({
    required this.tokens,
    required this.borderStrong,
    required this.onPressed,
    required this.child,
  });

  final OcTokens tokens;
  final Color borderStrong;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.chipBg,
          shape: BoxShape.circle,
          border: Border.all(color: borderStrong),
        ),
        child: child,
      ),
    );
  }
}

// ─── Brand glow painter ────────────────────────────────────────────────
class _BrandGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    void blob(double cx, double cy, double rx, double ry, Color color) {
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: rx * 2,
        height: ry * 2,
      );
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0.0, 0.7],
        ).createShader(rect);
      canvas.drawOval(rect, paint);
    }

    blob(w * 0.25, h * 0.60, w * 0.25, h * 0.25,
        const Color(0xFF9646F0).withValues(alpha: 0.55));
    blob(w * 0.50, h * 0.50, w * 0.20, h * 0.20,
        const Color(0xFF50B4FF).withValues(alpha: 0.45));
    blob(w * 0.75, h * 0.60, w * 0.25, h * 0.25,
        const Color(0xFFFF9650).withValues(alpha: 0.45));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── OAuth glyphs ──────────────────────────────────────────────────────

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _GooglePainter());
  }
}

class _GooglePainter extends CustomPainter {
  // Simplified 4-color Google "G" — colored arcs around a central white gap,
  // with a horizontal bar for the G's interior stroke.
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final r = size.width / 2;
    final stroke = size.width * 0.22;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    final ring = Rect.fromCircle(center: center, radius: r - stroke / 2);

    // Blue – top right quadrant
    canvas.drawArc(ring, -1.5708, 1.5708,
        false, paint..color = const Color(0xFF4285F4));
    // Green – bottom right
    canvas.drawArc(ring, 0, 1.5708, false, paint..color = const Color(0xFF34A853));
    // Yellow – bottom left
    canvas.drawArc(ring, 1.5708, 1.5708,
        false, paint..color = const Color(0xFFFBBC05));
    // Red – top left
    canvas.drawArc(ring, 3.1416, 1.5708,
        false, paint..color = const Color(0xFFEA4335));

    // Inner horizontal "G" bar
    final bar = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    final barRect = Rect.fromLTWH(
      center.dx,
      center.dy - stroke * 0.45,
      r - stroke * 0.4,
      stroke * 0.9,
    );
    canvas.drawRect(barRect, bar);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MicrosoftGlyph extends StatelessWidget {
  const _MicrosoftGlyph({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) {
    final gap = size * 0.08;
    final cell = (size - gap) / 2;
    Widget sq(Color c) => Container(width: cell, height: cell, color: c);
    return SizedBox(
      width: size,
      height: size,
      child: Column(
        children: [
          Row(children: [
            sq(const Color(0xFFF25022)),
            SizedBox(width: gap),
            sq(const Color(0xFF7FBA00)),
          ]),
          SizedBox(height: gap),
          Row(children: [
            sq(const Color(0xFF00A4EF)),
            SizedBox(width: gap),
            sq(const Color(0xFFFFB900)),
          ]),
        ],
      ),
    );
  }
}

