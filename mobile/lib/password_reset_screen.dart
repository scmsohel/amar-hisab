import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PasswordResetRequest = Future<Map<String, dynamic>> Function(String email);
typedef PasswordResetSubmit = Future<Map<String, dynamic>> Function({
  required String email,
  required String otp,
  required String newPassword,
});

const _green = Color(0xFF078B62);
const _greenDark = Color(0xFF056B4C);
const _ink = Color(0xFF173B35);
const _muted = Color(0xFF71847C);
const _hint = Color(0xFF71847C);

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({
    super.key,
    this.initialEmail = '',
    required this.onRequestCode,
    required this.onResetPassword,
  });

  final String initialEmail;
  final PasswordResetRequest onRequestCode;
  final PasswordResetSubmit onResetPassword;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _codeSent = false;
  bool _submitting = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _email.dispose();
    _otp.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _startCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
      } else if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    if (_submitting) return;
    final email = _email.text.trim();
    if (!RegExp(r'^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$').hasMatch(email)) {
      _notice('সঠিক Email Address দিন।');
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await widget.onRequestCode(email);
      if (!mounted) return;
      setState(() => _codeSent = true);
      _startCooldown();
      _notice(result['message']?.toString() ??
          'অ্যাকাউন্ট থাকলে Email-এ OTP পাঠানো হয়েছে।');
    } catch (error) {
      if (mounted) _notice(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reset() async {
    FocusScope.of(context).unfocus();
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      await widget.onResetPassword(
        email: _email.text.trim(),
        otp: _otp.text.trim(),
        newPassword: _password.text,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          icon: const Icon(Icons.check_circle_rounded, color: _green, size: 48),
          title: const Text('Password পরিবর্তন হয়েছে'),
          content: const Text('এখন নতুন Password দিয়ে Login করুন।'),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('লগইন করুন'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _notice(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        prefixIcon: Icon(icon, color: _green),
        hintText: label,
        hintStyle: const TextStyle(color: _hint, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF5FBF8),
        suffixIcon: suffix,
      );

  Widget _primaryButton(String label, VoidCallback? onPressed) => SizedBox(
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_green, _greenDark]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: _green.withValues(alpha: .20), blurRadius: 14,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                const SizedBox(width: 9),
                const Icon(Icons.arrow_forward_rounded, size: 19),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          Positioned.fill(
            child: Image.asset(
              'assets/animations/Minimal Mint Leaf Wave Background.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
                child: Row(children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: _ink),
                  ),
                  const SizedBox(width: 4),
                  const Text('পাসওয়ার্ড পুনরুদ্ধার',
                      style: TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w900)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(22, 25, 22, 22),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .96),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: [
                            BoxShadow(color: _green.withValues(alpha: .09),
                                blurRadius: 28, offset: const Offset(0, 10)),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  width: 66,
                                  height: 66,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEAF8F0),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.lock_reset_rounded,
                                      color: _green, size: 34),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _codeSent ? 'OTP যাচাই করুন' : 'পাসওয়ার্ড ভুলে গেছেন?',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: _ink, fontSize: 21, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                _codeSent
                                    ? 'আপনার Email-এ পাঠানো ৬ সংখ্যার কোড ও নতুন Password দিন।'
                                    : 'আপনার অ্যাকাউন্টের Email Address দিন। আমরা একটি ৬ সংখ্যার OTP পাঠাব।',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: _muted, fontSize: 13, height: 1.5),
                              ),
                              const SizedBox(height: 22),
                              TextFormField(
                                controller: _email,
                                readOnly: _codeSent,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w600),
                                decoration: _decoration('ইমেইল ঠিকানা', Icons.mail_outline_rounded),
                                validator: (value) {
                                  final email = (value ?? '').trim();
                                  return RegExp(r'^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$').hasMatch(email)
                                      ? null : 'সঠিক Email Address দিন।';
                                },
                              ),
                              if (_codeSent) ...[
                                const SizedBox(height: 13),
                                TextFormField(
                                  controller: _otp,
                                  keyboardType: TextInputType.number,
                                  maxLength: 6,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  style: const TextStyle(color: _ink, fontSize: 17,
                                      fontWeight: FontWeight.w800, letterSpacing: 5),
                                  decoration: _decoration('৬ সংখ্যার OTP', Icons.password_rounded)
                                      .copyWith(counterText: ''),
                                  validator: (value) => (value == null || value.trim().length != 6)
                                      ? '৬ সংখ্যার OTP দিন।' : null,
                                ),
                                const SizedBox(height: 13),
                                TextFormField(
                                  controller: _password,
                                  obscureText: !_showPassword,
                                  style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w600),
                                  decoration: _decoration(
                                    'নতুন Password (কমপক্ষে ১২ অক্ষর)',
                                    Icons.lock_outline_rounded,
                                    suffix: IconButton(
                                      onPressed: () => setState(() => _showPassword = !_showPassword),
                                      icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                          color: _hint),
                                    ),
                                  ),
                                  validator: (value) => (value == null || value.length < 12)
                                      ? 'Password কমপক্ষে ১২ অক্ষরের হতে হবে।' : null,
                                ),
                                const SizedBox(height: 13),
                                TextFormField(
                                  controller: _confirmPassword,
                                  obscureText: !_showConfirmPassword,
                                  style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w600),
                                  decoration: _decoration(
                                    'নতুন Password আবার লিখুন',
                                    Icons.lock_reset_rounded,
                                    suffix: IconButton(
                                      onPressed: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
                                      icon: Icon(_showConfirmPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                          color: _hint),
                                    ),
                                  ),
                                  validator: (value) => value != _password.text
                                      ? 'দুটি Password মিলছে না।' : null,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text('কোড পাননি? ', style: TextStyle(color: _muted, fontSize: 12)),
                                    TextButton(
                                      onPressed: _submitting || _resendSeconds > 0 ? null : _sendCode,
                                      child: Text(
                                        _resendSeconds > 0
                                            ? 'আবার পাঠান (${_resendSeconds}s)'
                                            : 'আবার OTP পাঠান',
                                        style: const TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 12),
                              _primaryButton(
                                _submitting
                                    ? (_codeSent ? 'যাচাই হচ্ছে...' : 'OTP পাঠানো হচ্ছে...')
                                    : (_codeSent ? 'Password পরিবর্তন করুন' : 'OTP পাঠান'),
                                _submitting ? null : (_codeSent ? _reset : _sendCode),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _submitting ? null : () {
                                  if (_codeSent) {
                                    setState(() {
                                      _codeSent = false;
                                      _otp.clear();
                                      _password.clear();
                                      _confirmPassword.clear();
                                    });
                                  } else {
                                    Navigator.of(context).pop();
                                  }
                                },
                                child: Text(
                                  _codeSent ? 'Email পরিবর্তন করুন' : 'Login-এ ফিরে যান',
                                  style: const TextStyle(color: _green, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      );
}
