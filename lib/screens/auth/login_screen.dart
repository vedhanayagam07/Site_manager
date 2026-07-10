import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';

/// Key used to persist the "remember me" preference.
const _kRememberMeKey = 'auth_remember_me';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _rememberMe = true; // default ON for convenience

  late AnimationController _entranceCtrl;
  late AnimationController _orbCtrl;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _cardSlide;
  late Animation<double> _cardFade;

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _orbCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
          parent: _entranceCtrl,
          curve: const Interval(0, 0.5, curve: Curves.easeOutBack)),
    );
    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _entranceCtrl,
          curve: const Interval(0, 0.4, curve: Curves.easeOut)),
    );
    _cardSlide = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(
          parent: _entranceCtrl,
          curve: const Interval(0.3, 1, curve: Curves.easeOutCubic)),
    );
    _cardFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _entranceCtrl,
          curve: const Interval(0.3, 0.8, curve: Curves.easeOut)),
    );

    _entranceCtrl.forward();
    _loadRememberMe();
  }

  Future<void> _loadRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _rememberMe = prefs.getBool(_kRememberMeKey) ?? true;
      });
    }
  }

  Future<void> _saveRememberMe(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRememberMeKey, value);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _entranceCtrl.dispose();
    _orbCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Persist remember-me preference
      await _saveRememberMe(_rememberMe);

      if (mounted) context.go('/dashboard');
    } on AuthException catch (error) {
      setState(() => _errorMessage = error.message);
    } catch (error) {
      setState(() => _errorMessage = 'An unexpected error occurred');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF090B12),
      body: Stack(
        children: [
          // ── Animated ambient glow orbs ────────────────────────────────────
          AnimatedBuilder(
            animation: _orbCtrl,
            builder: (_, __) {
              final t = _orbCtrl.value;
              return Stack(
                children: [
                  Positioned(
                    left: size.width * 0.12 +
                        math.sin(t * 2 * math.pi) * 30,
                    top: size.height * 0.08 +
                        math.cos(t * 2 * math.pi) * 20,
                    child: _GlowOrb(
                      size: 280,
                      color: const Color(0xFFC68E65).withValues(alpha: 0.12),
                    ),
                  ),
                  Positioned(
                    right: size.width * 0.05 +
                        math.cos(t * 2 * math.pi) * 25,
                    top: size.height * 0.25 +
                        math.sin(t * 2 * math.pi) * 20,
                    child: _GlowOrb(
                      size: 200,
                      color: const Color(0xFF5B6AF5).withValues(alpha: 0.08),
                    ),
                  ),
                  Positioned(
                    left: size.width * 0.3,
                    bottom: size.height * 0.1 +
                        math.sin(t * 2 * math.pi + 1) * 15,
                    child: _GlowOrb(
                      size: 160,
                      color:
                          const Color(0xFFC68E65).withValues(alpha: 0.07),
                    ),
                  ),
                ],
              );
            },
          ),

          // ── Content ───────────────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 24),

                    // Animated logo + title
                    AnimatedBuilder(
                      animation: _entranceCtrl,
                      builder: (_, child) => FadeTransition(
                        opacity: _logoFade,
                        child: ScaleTransition(scale: _logoScale, child: child),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.95),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFC68E65)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 40,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset('assets/tsrlogo.png',
                                  fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'TSR BUILDERS',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Construction Intelligence Platform',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Animated login card
                    AnimatedBuilder(
                      animation: _entranceCtrl,
                      builder: (_, child) => Transform.translate(
                        offset: Offset(0, _cardSlide.value),
                        child: FadeTransition(
                            opacity: _cardFade, child: child),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          color: const Color(0xFF13151E),
                          border: Border.all(
                            color: const Color(0xFFC68E65)
                                .withValues(alpha: 0.18),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.6),
                              blurRadius: 40,
                              spreadRadius: -4,
                              offset: const Offset(0, 20),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Welcome back',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Sign in to continue',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13),
                            ),
                            const SizedBox(height: 28),

                            // Email field
                            _PremiumTextField(
                              controller: _emailController,
                              label: 'Email Address',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              enabled: !_isLoading,
                            ),
                            const SizedBox(height: 16),

                            // Password field
                            _PremiumTextField(
                              controller: _passwordController,
                              label: 'Password',
                              icon: Icons.lock_outline,
                              obscureText: _obscurePassword,
                              enabled: !_isLoading,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: AppColors.textSecondary,
                                  size: 20,
                                ),
                                onPressed: () => setState(() =>
                                    _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Remember Me toggle ─────────────────────────
                            GestureDetector(
                              onTap: () => setState(() {
                                _rememberMe = !_rememberMe;
                              }),
                              child: Row(
                                children: [
                                  AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 220),
                                    width: 42,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      color: _rememberMe
                                          ? AppColors.roseGold
                                          : Colors.white12,
                                      border: Border.all(
                                        color: _rememberMe
                                            ? AppColors.roseGold
                                            : Colors.white24,
                                      ),
                                      boxShadow: _rememberMe
                                          ? [
                                              BoxShadow(
                                                color: AppColors.roseGold
                                                    .withValues(alpha: 0.3),
                                                blurRadius: 8,
                                              )
                                            ]
                                          : [],
                                    ),
                                    child: AnimatedAlign(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      alignment: _rememberMe
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: Container(
                                        margin: const EdgeInsets.all(3),
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.25),
                                              blurRadius: 4,
                                            )
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Remember Me',
                                          style: TextStyle(
                                            color: _rememberMe
                                                ? Colors.white
                                                : AppColors.textSecondary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          _rememberMe
                                              ? 'You won\'t need to sign in again'
                                              : 'You\'ll be signed out next time',
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 8),

                            // Error message
                            if (_errorMessage != null)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.only(
                                    top: 8, bottom: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.danger
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.danger
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: AppColors.danger, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: const TextStyle(
                                            color: AppColors.danger,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 24),

                            // Sign In button (gradient)
                            _GradientButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              isLoading: _isLoading,
                              label: 'Sign In',
                              icon: Icons.login,
                            ),

                            const SizedBox(height: 20),

                            // Credentials hint
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.roseGold
                                    .withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppColors.roseGold
                                      .withValues(alpha: 0.12),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      color: AppColors.roseGold, size: 16),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'HELLO',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium text field with focus glow animation
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final bool enabled;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;

  const _PremiumTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.enabled = true,
    this.keyboardType,
    this.suffixIcon,
  });

  @override
  State<_PremiumTextField> createState() => _PremiumTextFieldState();
}

class _PremiumTextFieldState extends State<_PremiumTextField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: AppColors.roseGold.withValues(alpha: 0.2),
                    blurRadius: 16,
                    spreadRadius: -2,
                  ),
                ]
              : [],
        ),
        child: TextField(
          controller: widget.controller,
          obscureText: widget.obscureText,
          enabled: widget.enabled,
          keyboardType: widget.keyboardType,
          autocorrect: false,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: Icon(
              widget.icon,
              color:
                  _focused ? AppColors.roseGold : AppColors.textSecondary,
              size: 20,
            ),
            suffixIcon: widget.suffixIcon,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gradient sign-in button with press animation
// ─────────────────────────────────────────────────────────────────────────────
class _GradientButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;
  final IconData icon;

  const _GradientButton({
    required this.onPressed,
    required this.isLoading,
    required this.label,
    required this.icon,
  });

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: widget.onPressed == null
                  ? [Colors.grey.shade800, Colors.grey.shade700]
                  : const [Color(0xFFB77B57), Color(0xFFD4A574)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: widget.onPressed != null && !_pressed
                ? [
                    BoxShadow(
                      color: const Color(0xFFC68E65).withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        widget.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ambient glow orb
// ─────────────────────────────────────────────────────────────────────────────
class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, Colors.transparent],
          stops: const [0, 1],
        ),
      ),
    );
  }
}
