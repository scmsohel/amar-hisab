import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

void main() => runApp(const AmarHisabApp());

const _blue = Color(0xFF2563EB);
const _navy = Color(0xFF172554);
const _ink = Color(0xFF172033);
const _muted = Color(0xFF7B879B);
const _pale = Color(0xFFF4F7FF);

class AmarHisabApp extends StatelessWidget {
  const AmarHisabApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'আমার হিসাব',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: _pale,
          colorScheme: ColorScheme.fromSeed(seedColor: _blue),
          fontFamily: 'Roboto',
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF7F9FD),
            hintStyle: const TextStyle(color: Color(0xFF9AA5B7), fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE5EAF3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE5EAF3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _blue, width: 1.5),
            ),
          ),
        ),
        home: const SplashScreen(),
      );
}


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    Future<void>.delayed(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => const AuthScreen(),
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFF617D80);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF071B15) : const Color(0xFFFCFFFD),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 720;
          final artSize = (constraints.maxHeight * (compact ? .27 : .31))
              .clamp(190.0, 330.0).toDouble();
          return Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/animations/Minimal Mint Leaf Wave Background.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: compact ? 10 : 20,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (constraints.maxHeight -
                                MediaQuery.of(context).padding.vertical -
                                (compact ? 20 : 40))
                            .clamp(0.0, double.infinity).toDouble(),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _floatController,
                            builder: (context, child) => Transform.translate(
                              offset: Offset(
                                0,
                                -5 * Curves.easeInOut.transform(_floatController.value),
                              ),
                              child: child,
                            ),
                            child: SizedBox(
                              width: artSize,
                              height: artSize,
                              child: Image.asset(
                                'assets/animations/logo.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 0 : 0),
                          Transform.translate(
                            offset: const Offset(0, -80),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 180,
                                  height: 180,
                                  child: Lottie.asset(
                                    'assets/animations/loading_spinner.json',
                                    repeat: true,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'তথ্য প্রস্তুত করা হচ্ছে...',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFFB6D8C9) : muted,
                                    fontSize: compact ? 20 : 24,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum AuthMode { login, signup }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  AuthMode _mode = AuthMode.login;
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _loading = false;
  String? _message;
  final _formKey = GlobalKey<FormState>();
  final _identity = TextEditingController();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _invite = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _identity.dispose();
    _name.dispose();
    _mobile.dispose();
    _invite.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _switchMode(AuthMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _message = null;
      _showPassword = false;
      _showConfirm = false;
    });
    _formKey.currentState?.reset();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    // The existing web API is cookie-session based. Its base URL and mobile
    // cookie/session handling must be configured before submitting credentials.
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _message = 'ডিজাইন প্রস্তুত। আসল Login/Signup চালু করতে আপনার Amar Hisab API-এর ঠিকানা সংযুক্ত করতে হবে।';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLogin = _mode == AuthMode.login;
    return Scaffold(
      body: Stack(
        children: [
          Positioned(top: -100, right: -90, child: _Glow(size: 250, color: const Color(0xFFBBD2FF).withValues(alpha: .48))),
          Positioned(bottom: -120, left: -100, child: _Glow(size: 280, color: const Color(0xFFC7F3E2).withValues(alpha: .52))),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BrandHeader(),
                      const SizedBox(height: 22),
                      const _FinanceIllustration(),
                      const SizedBox(height: 20),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(begin: const Offset(.04, .04), end: Offset.zero).animate(animation),
                            child: child,
                          ),
                        ),
                        child: Container(
                          key: ValueKey(_mode),
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .96),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF203B72).withValues(alpha: .08), blurRadius: 34, offset: const Offset(0, 16)),
                            ],
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  isLogin ? 'আবার স্বাগতম!' : 'অ্যাকাউন্ট তৈরি করুন',
                                  style: const TextStyle(fontSize: 24, height: 1.25, fontWeight: FontWeight.w800, color: _ink),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  isLogin ? 'আপনার হিসাবের জগতে ফিরে আসুন' : 'আপনার আয়-ব্যয় গুছিয়ে রাখতে শুরু করুন',
                                  style: const TextStyle(color: _muted, fontSize: 13.5, height: 1.5),
                                ),
                                const SizedBox(height: 21),
                                if (!isLogin) ...[
                                  _FieldLabel(label: 'পূর্ণ নাম'),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _name,
                                    textCapitalization: TextCapitalization.words,
                                    decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded), hintText: 'আপনার নাম লিখুন'),
                                    validator: (v) => (v == null || v.trim().length < 2) ? 'কমপক্ষে ২ অক্ষরের নাম দিন।' : null,
                                  ),
                                  const SizedBox(height: 14),
                                  _FieldLabel(label: 'মোবাইল নম্বর'),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _mobile,
                                    keyboardType: TextInputType.phone,
                                    decoration: const InputDecoration(prefixIcon: Icon(Icons.phone_iphone_rounded), hintText: '+880 1XXXXXXXXX'),
                                    validator: (v) => (v == null || v.trim().replaceAll(RegExp(r'\D'), '').length < 10) ? 'সঠিক মোবাইল নম্বর দিন।' : null,
                                  ),
                                  const SizedBox(height: 14),
                                  _FieldLabel(label: 'Invitation Code'),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _invite,
                                    decoration: const InputDecoration(prefixIcon: Icon(Icons.key_rounded), hintText: 'Admin-এর দেওয়া কোড'),
                                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Invitation code প্রয়োজন।' : null,
                                  ),
                                  const SizedBox(height: 14),
                                ] else ...[
                                  _FieldLabel(label: 'Email অথবা মোবাইল নম্বর'),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _identity,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [AutofillHints.username],
                                    decoration: const InputDecoration(prefixIcon: Icon(Icons.alternate_email_rounded), hintText: 'Email বা মোবাইল নম্বর'),
                                    validator: (v) {
                                      final value = (v ?? '').trim();
                                      if (value.isEmpty) return 'Email অথবা মোবাইল নম্বর দিন।';
                                      if (value.contains('@') && (!value.contains('.') || value.startsWith('@') || value.endsWith('@'))) return 'সঠিক Email address দিন।';
                                      if (!value.contains('@') && value.replaceAll(RegExp(r'\D'), '').length < 10) return 'সঠিক মোবাইল নম্বর দিন।';
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                _FieldLabel(label: 'Password'),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _password,
                                  obscureText: !_showPassword,
                                  autofillHints: isLogin ? const [AutofillHints.password] : const [AutofillHints.newPassword],
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                                    hintText: isLogin ? 'আপনার Password' : 'কমপক্ষে ৮ অক্ষর',
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(() => _showPassword = !_showPassword),
                                      icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: _muted),
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return 'Password দিন।';
                                    if (!isLogin && v.length < 8) return 'Password কমপক্ষে ৮ অক্ষরের হতে হবে।';
                                    return null;
                                  },
                                ),
                                if (!isLogin) ...[
                                  const SizedBox(height: 14),
                                  _FieldLabel(label: 'Confirm Password'),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _confirm,
                                    obscureText: !_showConfirm,
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(Icons.verified_user_outlined),
                                      hintText: 'Password আবার লিখুন',
                                      suffixIcon: IconButton(
                                        onPressed: () => setState(() => _showConfirm = !_showConfirm),
                                        icon: Icon(_showConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: _muted),
                                      ),
                                    ),
                                    validator: (v) => v != _password.text ? 'দুইটি Password মিলছে না।' : null,
                                  ),
                                ],
                                if (isLogin) ...[
                                  const SizedBox(height: 7),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => _showNotice('Password recovery-এর API এখনো সংযুক্ত করা হয়নি।'),
                                      child: const Text('Password ভুলে গেছেন?', style: TextStyle(color: _blue, fontWeight: FontWeight.w700, fontSize: 12)),
                                    ),
                                  ),
                                ] else
                                  const Padding(
                                    padding: EdgeInsets.only(top: 10),
                                    child: Text('নোট: Signup-এর জন্য Admin-এর বৈধ invitation code প্রয়োজন।', style: TextStyle(color: _muted, fontSize: 11.5, height: 1.45)),
                                  ),
                                if (_message != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: const Color(0xFFFFF5E8), borderRadius: BorderRadius.circular(12)),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      const Icon(Icons.info_outline_rounded, color: Color(0xFFB76A0B), size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(_message!, style: const TextStyle(color: Color(0xFF8D550C), fontSize: 12, height: 1.45))),
                                    ]),
                                  ),
                                ],
                                const SizedBox(height: 19),
                                SizedBox(
                                  height: 54,
                                  child: FilledButton(
                                    onPressed: _loading ? null : _submit,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _blue,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 180),
                                      child: _loading
                                          ? const SizedBox(key: ValueKey('loading'), width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                          : Row(key: const ValueKey('label'), mainAxisAlignment: MainAxisAlignment.center, children: [
                                              Text(isLogin ? 'Login করুন' : 'অ্যাকাউন্ট তৈরি করুন', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                              const SizedBox(width: 9),
                                              const Icon(Icons.arrow_forward_rounded, size: 19),
                                            ]),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 17),
                                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Flexible(child: Text(isLogin ? 'নতুন account প্রয়োজন? ' : 'আগে থেকেই account আছে? ', style: const TextStyle(color: _muted, fontSize: 12.5))),
                                  GestureDetector(
                                    onTap: () => _switchMode(isLogin ? AuthMode.signup : AuthMode.login),
                                    child: Text(isLogin ? 'Signup করুন' : 'Login করুন', style: const TextStyle(color: _blue, fontSize: 12.5, fontWeight: FontWeight.w800)),
                                  ),
                                ]),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.shield_outlined, color: Color(0xFF7B879B), size: 15),
                        SizedBox(width: 6),
                        Text('আপনার হিসাব, আপনার নিয়ন্ত্রণে', style: TextStyle(color: _muted, fontSize: 11.5)),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_blue, Color(0xFF6D8FFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(17),
              boxShadow: [BoxShadow(color: _blue.withValues(alpha: .22), blurRadius: 16, offset: const Offset(0, 7))],
            ),
            child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 27),
          ),
          const SizedBox(width: 12),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('আমার হিসাব', style: TextStyle(color: _ink, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -.4)),
            SizedBox(height: 2),
            Text('আপনার অর্থ, আরও গোছানো', style: TextStyle(color: _muted, fontSize: 11.5)),
          ]),
        ],
      );
}

class _FinanceIllustration extends StatelessWidget {
  const _FinanceIllustration();
  @override
  Widget build(BuildContext context) => Container(
        height: 174,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(colors: [Color(0xFFE7EFFF), Color(0xFFF2F6FF), Color(0xFFE5F8F0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Stack(
          children: [
            Positioned(right: -24, top: -42, child: _Glow(size: 150, color: Colors.white.withValues(alpha: .65))),
            Positioned(left: -22, bottom: -52, child: _Glow(size: 130, color: const Color(0xFFBDD3FF).withValues(alpha: .5))),
            Positioned(left: 20, top: 25, child: _FloatingIcon(icon: Icons.savings_rounded, color: const Color(0xFF2F67D8), size: 42)),
            Positioned(right: 24, top: 20, child: _FloatingIcon(icon: Icons.trending_up_rounded, color: const Color(0xFF179B75), size: 37)),
            Positioned(
              left: 72,
              right: 72,
              top: 24,
              bottom: 20,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: .94, end: 1),
                duration: const Duration(milliseconds: 850),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(21),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [BoxShadow(color: _navy.withValues(alpha: .10), blurRadius: 20, offset: const Offset(0, 9))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 28, height: 28, decoration: BoxDecoration(color: const Color(0xFFE8EFFF), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.account_balance_wallet_rounded, color: _blue, size: 16)),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('মোট ব্যালেন্স', style: TextStyle(color: _muted, fontSize: 10.5, fontWeight: FontWeight.w600))),
                      const Icon(Icons.more_horiz_rounded, color: _muted, size: 18),
                    ]),
                    const SizedBox(height: 8),
                    const Text('৳ ৪৮,৫০০', style: TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 19, letterSpacing: -.5)),
                    const SizedBox(height: 9),
                    Expanded(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        for (final h in [17.0, 26.0, 21.0, 34.0, 27.0, 43.0, 36.0])
                          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Container(height: h, decoration: BoxDecoration(color: h == 43 ? const Color(0xFF36B98A) : const Color(0xFFB9D0FF), borderRadius: BorderRadius.circular(5))))),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
            Positioned(left: 26, bottom: 22, child: _FloatingIcon(icon: Icons.savings_outlined, color: const Color(0xFF159A70), size: 28)),
            Positioned(right: 30, bottom: 24, child: _FloatingIcon(icon: Icons.currency_exchange_rounded, color: const Color(0xFFDA9B24), size: 29)),
          ],
        ),
      );
}

class _FloatingIcon extends StatelessWidget {
  const _FloatingIcon({required this.icon, required this.color, required this.size});
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutBack,
        builder: (context, value, child) => Opacity(opacity: value.clamp(0, 1), child: Transform.translate(offset: Offset(0, (1 - value) * 9), child: child)),
        child: Container(
          width: size + 17,
          height: size + 17,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .88), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: color.withValues(alpha: .10), blurRadius: 14, offset: const Offset(0, 5))]),
          child: Icon(icon, color: color, size: size),
        ),
      );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)])),
      );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(label, style: const TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w700));
}
