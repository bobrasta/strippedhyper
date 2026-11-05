import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/labeled_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus  = FocusNode();

  bool    _obscure = true;
  bool    _loading = false;
  String? _error;

  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final data = await AuthService.instance.login(email, pass);
      authTokenNotifier.value = data['token'] as String;
      final user = data['user'] as Map?;
      final userName = user?['name'] as String?;
      final userRole = user?['role'] as String?;
      final userId   = user?['id'];
      if (userName != null) userNameNotifier.value = userName;
      if (user != null) applyUserIdentity(user);
      if (userId is num) userIdNotifier.value = userId.toInt();
      // Fetch permissions BEFORE setting the role — the sidebar/app-shell
      // rebuild the moment userRoleNotifier changes, and only listen to that
      // notifier, not userPermissionsNotifier. If the role were set first,
      // allowedScreenKeys() would run once with stale (empty) permissions,
      // fall back to the legacy hardcoded table, and never get a second
      // chance to react once the real permissions arrived a moment later.
      await refreshPermissions();
      if (userRole != null) userRoleNotifier.value = userRole;
    } on AuthException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      setState(() { _error = 'Unexpected error. Please try again.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w >= 860;

    return Scaffold(
      backgroundColor: context.pal.bg,
      body: isWide ? _buildWide() : _buildNarrow(),
    );
  }

  Widget _buildWide() => Row(children: [
    const Expanded(child: _BrandPanel()),
    SizedBox(width: 500, child: _buildFormPanel(wide: true)),
  ]);

  Widget _buildNarrow() => SingleChildScrollView(
    child: Column(children: [
      const SizedBox(height: 220, child: _BrandPanel(compact: true)),
      _buildFormPanel(wide: false),
    ]),
  );

  Widget _buildFormPanel({required bool wide}) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          constraints: BoxConstraints(minHeight: wide ? double.infinity : 0),
          height: wide ? double.infinity : null,
          color: context.pal.surface1,
          padding: EdgeInsets.symmetric(horizontal: wide ? 56 : 28),
          child: Column(
            mainAxisAlignment: wide ? MainAxisAlignment.center : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide) const SizedBox(height: 0) else const SizedBox(height: 40),

              // Mini brand mark
              Row(children: [
                Image.asset('assets/images/hypermed_icon.png', height: 28, fit: BoxFit.contain),
                const SizedBox(width: 10),
                Text('Hypermed',
                  style: AppTheme.bodyStrong.copyWith(
                    fontSize: 14, color: AppColors.teal, letterSpacing: 0.2,
                  )),
              ]),

              const SizedBox(height: 32),

              // Heading
              Text('Welcome back',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: context.pal.text,
                  letterSpacing: -0.5,
                )),
              const SizedBox(height: 6),
              Text('Sign in to your account to continue',
                style: TextStyle(fontSize: 14, color: context.pal.textMute, height: 1.4)),

              const SizedBox(height: 36),

              // Error banner
              if (_error != null) ...[
                _ErrorBanner(message: _error!),
                const SizedBox(height: 20),
              ],

              // Email
              _FieldLabel('Email address'),
              const SizedBox(height: 7),
              _AuthField(
                controller: _emailCtrl,
                focusNode: _emailFocus,
                hint: 'you@hypermed.tz',
                icon: Symbols.mail,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _passFocus.requestFocus(),
              ),
              const SizedBox(height: 20),

              // Password
              _FieldLabel('Password'),
              const SizedBox(height: 7),
              _AuthField(
                controller: _passCtrl,
                focusNode: _passFocus,
                hint: '••••••••',
                icon: Symbols.lock,
                obscure: _obscure,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                suffix: GestureDetector(
                  onTap: () => setState(() => _obscure = !_obscure),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Icon(
                      _obscure ? Symbols.visibility : Symbols.visibility_off,
                      size: 17,
                      color: context.pal.textDim,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Submit
              _LoginButton(loading: _loading, onTap: _submit),

              const SizedBox(height: 40),

              // Divider + credit
              Container(width: double.infinity, height: 1, color: context.pal.divider),
              const SizedBox(height: 16),
              Center(
                child: Column(children: [
                  Text(
                    'Designed & built by Bob Temu · Neville Temu',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.pal.textDim,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Powered by BobLabs · © 2026 Hypermed',
                    style: TextStyle(
                      fontSize: 10,
                      color: context.pal.textDim.withValues(alpha: 0.6),
                    ),
                  ),
                ]),
              ),

              SizedBox(height: wide ? 0 : 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Field label ───────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: context.pal.textMute,
      letterSpacing: 0.3,
    ),
  );
}

// ── Auth text field ───────────────────────────────────────────────────────────

class _AuthField extends StatefulWidget {
  const _AuthField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.icon,
    this.obscure          = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.suffix,
  });

  final TextEditingController  controller;
  final FocusNode              focusNode;
  final String                 hint;
  final IconData               icon;
  final bool                   obscure;
  final TextInputType?         keyboardType;
  final TextInputAction?       textInputAction;
  final ValueChanged<String>?  onSubmitted;
  final Widget?                suffix;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  // The Settings text input (LabeledTextField), with the login screen's
  // own FocusNode passed through so the keyboard next/submit chain works.
  @override
  Widget build(BuildContext context) => LabeledTextField(
    label: '',
    controller: widget.controller,
    focusNode: widget.focusNode,
    hint: widget.hint,
    prefixIcon: widget.icon,
    obscure: widget.obscure,
    keyboardType: widget.keyboardType,
    textInputAction: widget.textInputAction,
    onSubmitted: widget.onSubmitted,
    suffix: widget.suffix,
  );
}

// ── Login button ──────────────────────────────────────────────────────────────

class _LoginButton extends StatefulWidget {
  const _LoginButton({required this.loading, required this.onTap});
  final bool         loading;
  final VoidCallback onTap;

  @override
  State<_LoginButton> createState() => _LoginButtonState();
}

class _LoginButtonState extends State<_LoginButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit:  (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.loading ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 50,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end:   Alignment.centerRight,
              colors: _hover && !widget.loading
                  ? [AppColors.blueStrong, AppColors.teal]
                  : [AppColors.teal, AppColors.teal],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppColors.teal.withValues(alpha: _hover ? 0.42 : 0.22),
                blurRadius: _hover ? 26 : 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: widget.loading
              ? const Center(
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text(
                    'Sign in',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Symbols.arrow_forward, size: 16, color: Colors.white),
                ]),
        ),
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.coralSoft,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.coral.withValues(alpha: 0.35)),
    ),
    child: Row(children: [
      Icon(Symbols.error_outline, size: 16, color: AppColors.coral),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          message,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.coral,
          ),
        ),
      ),
    ]),
  );
}

// ── Brand panel (always dark, ignores theme) ──────────────────────────────────

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      // Background
      const ColoredBox(color: AppColors.bg),
      // Decorative background
      CustomPaint(painter: _BrandPainter()),
      // Content
      Padding(
        padding: EdgeInsets.all(compact ? 28 : 52),
        child: compact ? _buildCompact() : _buildFull(),
      ),
    ]);
  }

  Widget _buildFull() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Spacer(),

      // Logo icon
      Image.asset('assets/images/hypermed_icon.png', height: 56, fit: BoxFit.contain),
      const SizedBox(height: 22),

      // Name
      const Text(
        'Hypermed',
        style: TextStyle(
          color: AppColors.text,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
      ),
      const SizedBox(height: 10),

      // Tagline
      const Text(
        'Biomedical Enterprise\nPlatform',
        style: TextStyle(
          color: AppColors.textMute,
          fontSize: 15.5,
          height: 1.55,
        ),
      ),

      const SizedBox(height: 52),

      // Credit
      const Text(
        'Designed & built by Bob Temu · Neville Temu',
        style: TextStyle(
          color: AppColors.textDim,
          fontSize: 10,
          letterSpacing: 0.3,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Powered by BobLabs',
        style: TextStyle(
          color: AppColors.teal.withValues(alpha: 0.35),
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    ],
  );

  Widget _buildCompact() => Row(children: [
    Image.asset('assets/images/hypermed_icon.png', height: 38, fit: BoxFit.contain),
    const SizedBox(width: 14),
    const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hypermed',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          )),
        SizedBox(height: 2),
        Text('Biomedical Enterprise Platform',
          style: TextStyle(
            color: AppColors.textMute,
            fontSize: 12,
          )),
      ],
    ),
  ]);
}

// ── Brand background painter ──────────────────────────────────────────────────

class _BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Subtle grid
    final grid = Paint()
      ..color = const Color(0x07FFFFFF)
      ..strokeWidth = 0.5;
    for (double x = 0; x <= size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y <= size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Teal radial glow — top right
    final glow1 = Paint()
      ..shader = RadialGradient(
        colors: [AppColors.teal.withValues(alpha: 0.094), AppColors.teal.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.85, size.height * 0.12), radius: 220));
    canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 0.12), 220, glow1);

    // Violet radial glow — bottom left (secondary accent, keeps the panel from reading as flat single-hue)
    final glow2 = Paint()
      ..shader = RadialGradient(
        colors: [AppColors.violet.withValues(alpha: 0.055), AppColors.violet.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.05, size.height * 0.85), radius: 190));
    canvas.drawCircle(
        Offset(size.width * 0.05, size.height * 0.85), 190, glow2);

    // Concentric corner arcs — top right
    final arc = Paint()
      ..color = AppColors.teal.withValues(alpha: 0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double r = 80; r <= 320; r += 60) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(size.width, 0), radius: r),
        math.pi / 2, math.pi / 2, false, arc,
      );
    }

    // Small cross marks scattered (decorative)
    final dot = Paint()
      ..color = const Color(0x0DFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const positions = [
      Offset(0.15, 0.25), Offset(0.72, 0.55),
      Offset(0.88, 0.80), Offset(0.35, 0.70),
    ];
    for (final p in positions) {
      final cx = p.dx * size.width;
      final cy = p.dy * size.height;
      canvas.drawLine(Offset(cx - 5, cy), Offset(cx + 5, cy), dot);
      canvas.drawLine(Offset(cx, cy - 5), Offset(cx, cy + 5), dot);
    }
  }

  @override
  bool shouldRepaint(_BrandPainter old) => false;
}
