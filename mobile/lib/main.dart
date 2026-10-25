import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _AuthApi.loadBaseUrl();
  runApp(const AmarHisabApp());
}

const _blue = Color(0xFF00834A);
const _deepBlue = Color(0xFF006B3D);
const _ink = Color(0xFF075B3A);
const _muted = Color(0xFF687C78);
const _line = Color(0xFFDDEBE5);
const _pale = Color(0xFFF2F7FF);

class _AuthApi {
  static const String _baseUrlPreferenceKey = 'amar_hisab_server_url';
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  static String? _baseUrl;
  static String? _sessionCookie;

  static String? get baseUrl => _baseUrl;

  static Future<void> loadBaseUrl() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_baseUrlPreferenceKey);
    _baseUrl = saved == null || saved.trim().isEmpty ? null : _normalizeUrl(saved);
  }

  static String _normalizeUrl(String value) => value.trim().replaceFirst(RegExp(r'/+$'), '');

  static String? validateUrl(String value) {
    final normalized = _normalizeUrl(value);
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      return 'সঠিক Server URL দিন।';
    }
    if (uri.scheme != 'https') {
      return 'নিরাপত্তার জন্য HTTPS Server URL ব্যবহার করুন।';
    }
    if (uri.userInfo.isNotEmpty || uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
      return 'URL-এ username, password, query বা fragment দেওয়া যাবে না।';
    }
    if (uri.path != '/api' && !uri.path.endsWith('/api')) {
      return 'Server URL-এর শেষে /api থাকতে হবে।';
    }
    return null;
  }

  static Future<bool> testServerUrl(String value) async {
    final validationError = validateUrl(value);
    if (validationError != null) throw Exception(validationError);
    final base = _normalizeUrl(value);
    final uri = Uri.parse('$base/health');
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 12));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 15));
    final responseText = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception('Server health check ব্যর্থ হয়েছে (HTTP ${response.statusCode})।');
    }
    try {
      final data = jsonDecode(responseText);
      if (data is Map<String, dynamic> && data['status'] == 'ok') return true;
    } on FormatException {
      // Report a consistent connection error below.
    }
    throw Exception('Server-এর health response সঠিক নয়।');
  }

  static Future<void> saveBaseUrl(String value) async {
    final normalized = _normalizeUrl(value);
    final validationError = validateUrl(normalized);
    if (validationError != null) throw Exception(validationError);
    await testServerUrl(normalized);
    final preferences = await SharedPreferences.getInstance();
    if (_baseUrl != normalized) _sessionCookie = null;
    await preferences.setString(_baseUrlPreferenceKey, normalized);
    _baseUrl = normalized;
  }

  static Future<void> _ensureConfigured() async {
    if (_baseUrl == null || _baseUrl!.isEmpty) {
      throw Exception('আগে Settings থেকে Server Address সেট করুন।');
    }
    final validationError = validateUrl(_baseUrl!);
    if (validationError != null) throw Exception(validationError);
  }

  static Future<void> checkConfiguredServer() async {
    await _ensureConfigured();
    await testServerUrl(_baseUrl!);
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    await _ensureConfigured();
    final uri = Uri.parse('$_baseUrl$path');
    final request = await _client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (_sessionCookie != null) {
      request.headers.set(HttpHeaders.cookieHeader, _sessionCookie!);
    }
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final setCookie = response.headers[HttpHeaders.setCookieHeader];
    if (setCookie != null && setCookie.isNotEmpty) {
      _sessionCookie = setCookie
          .map((value) => value.split(';').first)
          .join('; ');
    }
    final responseText = await response.transform(utf8.decoder).join();
    Map<String, dynamic> data = {};
    if (responseText.isNotEmpty) {
      try {
        final decoded = jsonDecode(responseText);
        if (decoded is Map<String, dynamic>) data = decoded;
      } on FormatException {
        data = {'error': 'সার্ভার থেকে সঠিক উত্তর পাওয়া যায়নি।'};
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error']?.toString() ??
          'অনুরোধ ব্যর্থ হয়েছে (' + response.statusCode.toString() + ')।');
    }
    return data;
  }

  static Future<Map<String, dynamic>> login({
    required String identity,
    required String password,
  }) =>
      _post('/auth/login', {'identity': identity.trim(), 'password': password});

  static Future<Map<String, dynamic>> verifyInvite(String invite) =>
      _post('/auth/invite/verify', {'invite': invite.trim()});

  static Future<Map<String, dynamic>> register({
    required String invite,
    required String name,
    required String email,
    required String mobile,
    required String password,
  }) =>
      _post('/auth/register', {
        'invite': invite.trim(),
        'name': name.trim(),
        'email': email.trim(),
        'mobile': mobile.trim(),
        'password': password,
      });
}

class AmarHisabApp extends StatelessWidget {
  const AmarHisabApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'আমার হিসাব',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto',
          scaffoldBackgroundColor: _pale,
          colorScheme: ColorScheme.fromSeed(seedColor: _blue),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF9FBFF),
            hintStyle: const TextStyle(color: Color(0xFF8B95A7), fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: _line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: _line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: _blue, width: 1.4),
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
          pageBuilder: (_, _, _) => const LoginScreen(),
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
                          const SizedBox(height: 0),
                          Transform.translate(
                            offset: const Offset(0, -60),
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
                                const SizedBox(height: 2),
                                Transform.translate(
                                  offset: const Offset(0, -36),
                                  child: Text(
                                    'তথ্য প্রস্তুত করা হচ্ছে...',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isDark ? const Color(0xFFB6D8C9) : muted,
                                      fontSize: compact ? 20 : 24,
                                      fontWeight: FontWeight.w500,
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton();
  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ভাষা পরিবর্তনের সুবিধা পরবর্তী ধাপে যুক্ত হবে।')),
        ),
        iconAlignment: IconAlignment.end,
        label: const Text('বাংলা', style: TextStyle(color: Color(0xFF172554), fontWeight: FontWeight.w700)),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19, color: Color(0xFF172554)),
      );
}

class _CloudBackground extends StatelessWidget {
  const _CloudBackground({this.bottomWave = true});
  final bool bottomWave;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: CustomPaint(painter: _CloudPainter(bottomWave: bottomWave)),
      );
}

class _CloudPainter extends CustomPainter {
  _CloudPainter({required this.bottomWave});
  final bool bottomWave;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFF1F7FF), Color(0xFFFFFFFF), Color(0xFFEAF3FF)],
    ).createShader(rect);
    canvas.drawRect(rect, base);

    final top = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * .12)
      ..cubicTo(size.width * .74, size.height * .06, size.width * .53, size.height * .21, size.width * .28, size.height * .12)
      ..cubicTo(size.width * .15, size.height * .08, size.width * .08, size.height * .17, 0, size.height * .13)
      ..close();
    canvas.drawPath(top, Paint()..shader = const LinearGradient(
      colors: [Color(0xFF2D6DE7), Color(0xFFB9D9FF), Color(0xFFD9E9FF)],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * .22)));

    final glow = Paint()..shader = const RadialGradient(
      colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
    ).createShader(Rect.fromCircle(center: Offset(size.width * .5, size.height * .45), radius: size.width * .8));
    canvas.drawRect(rect, glow);

    if (bottomWave) {
      final wave = Path()
        ..moveTo(0, size.height * .91)
        ..cubicTo(size.width * .2, size.height * .84, size.width * .35, size.height * .99, size.width * .58, size.height * .92)
        ..cubicTo(size.width * .76, size.height * .86, size.width * .84, size.height * .87, size.width, size.height * .83)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(wave, Paint()..shader = const LinearGradient(
        colors: [Color(0xFF1C5FE0), Color(0xFF79B9FF)],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ).createShader(Rect.fromLTWH(0, size.height * .82, size.width, size.height * .18)));
      final wave2 = Path()
        ..moveTo(0, size.height * .96)
        ..cubicTo(size.width * .3, size.height * .9, size.width * .65, size.height, size.width, size.height * .91)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(wave2, Paint()..color = const Color(0xFF2446B8).withValues(alpha: .62));
    }
  }

  @override
  bool shouldRepaint(covariant _CloudPainter oldDelegate) => oldDelegate.bottomWave != bottomWave;
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;
  final _slides = const [
    _IntroSlide(title: 'স্মার্টভাবে\nআপনার অর্থ ব্যবস্থাপনা', icon: Icons.account_balance_wallet_rounded),
    _IntroSlide(title: 'আয়-ব্যয় রাখুন\nএক জায়গায় গুছিয়ে', icon: Icons.query_stats_rounded),
    _IntroSlide(title: 'সঞ্চয়ের লক্ষ্য পূরণ\nহোক আরও সহজ', icon: Icons.savings_rounded),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _continue() {
    if (_page < _slides.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeInOutCubic);
    } else {
      Navigator.of(context).pushReplacement(_route(const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          children: [
            const _CloudBackground(),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _slides.length,
                      onPageChanged: (value) => setState(() => _page = value),
                      itemBuilder: (context, index) => _OnboardingPage(slide: _slides[index]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
                    child: Row(
                      children: [
                        Row(
                          children: List.generate(_slides.length, (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.only(right: 8),
                            width: _page == i ? 12 : 9,
                            height: _page == i ? 12 : 9,
                            decoration: BoxDecoration(
                              color: _page == i ? Colors.white : Colors.white.withValues(alpha: .45),
                              shape: BoxShape.circle,
                            ),
                          )),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: _continue,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _blue,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                            shape: const StadiumBorder(),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(_page == _slides.length - 1 ? 'শুরু করুন' : 'পরবর্তী', style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 18),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _IntroSlide {
  const _IntroSlide({required this.title, required this.icon});
  final String title;
  final IconData icon;
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.slide});
  final _IntroSlide slide;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxHeight < 680;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Row(children: [
                const SizedBox(width: 42),
                const Spacer(),
                const _BrandMark(size: 46),
                const Spacer(),
                const SizedBox(width: 42),
              ]),
            ),
            const SizedBox(height: 10),
            const Text('আমার হিসাব', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: _ink)),
            const Text('আপনার আয়-ব্যয়ের হিসাব, এক জায়গায়', style: TextStyle(color: _muted, fontSize: 14)),
            SizedBox(height: compact ? 12 : 22),
            Expanded(child: _WalletArtwork(icon: slide.icon)),
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 12, 30, 12),
              child: Text(slide.title, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 23, height: 1.45, fontWeight: FontWeight.w800)),
            ),
          ],
        );
      });
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 54});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_blue, _deepBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(size * .28),
          boxShadow: [BoxShadow(color: _blue.withValues(alpha: .2), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Icon(Icons.account_balance_wallet_rounded, size: size * .55, color: Colors.white),
      );
}

class _WalletArtwork extends StatelessWidget {
  const _WalletArtwork({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final artWidth = width.clamp(260.0, 390.0).toDouble();
        return Center(
          child: SizedBox(
            width: artWidth,
            height: constraints.maxHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(top: 10, left: 4, child: _CloudPuff(size: 95)),
                Positioned(top: 50, right: 0, child: _CloudPuff(size: 110)),
                Positioned(bottom: 12, left: 2, child: Icon(Icons.eco_rounded, size: 104, color: const Color(0xFF28B77E).withValues(alpha: .8))),
                Positioned(bottom: 10, right: 0, child: Icon(Icons.eco_rounded, size: 78, color: const Color(0xFF57D9A5).withValues(alpha: .9))),
                Positioned(
                  bottom: constraints.maxHeight * .09,
                  left: width * .1,
                  right: width * .1,
                  child: Container(
                    height: constraints.maxHeight * .55,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF9BC8FF), Color(0xFF365BE0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(38),
                      boxShadow: [BoxShadow(color: _deepBlue.withValues(alpha: .2), blurRadius: 26, offset: const Offset(0, 18))],
                    ),
                    child: Stack(children: [
                      Positioned(left: 22, right: 22, top: 28, child: Container(
                        height: constraints.maxHeight * .28,
                        decoration: BoxDecoration(color: const Color(0xFFF9FCFF), borderRadius: BorderRadius.circular(20)),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(height: 10, width: 90, decoration: BoxDecoration(color: const Color(0xFFDCE7FF), borderRadius: BorderRadius.circular(8))),
                          const SizedBox(height: 12),
                          Container(height: 8, width: 130, decoration: BoxDecoration(color: const Color(0xFFE8EEFA), borderRadius: BorderRadius.circular(8))),
                          const SizedBox(height: 8),
                          Container(height: 8, width: 100, decoration: BoxDecoration(color: const Color(0xFFE8EEFA), borderRadius: BorderRadius.circular(8))),
                        ]),
                      )),
                      Positioned(left: 0, right: 0, bottom: 0, child: Container(
                        height: constraints.maxHeight * .25,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF3678F0), Color(0xFF2947B9)]),
                          borderRadius: BorderRadius.circular(30),
                        ),
                      )),
                      Positioned(right: 12, bottom: constraints.maxHeight * .1, child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(color: const Color(0xFFFFC857), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFFE39B), width: 3)),
                      )),
                    ]),
                  ),
                ),
                Positioned(top: constraints.maxHeight * .17, child: Container(
                  width: 78, height: 78,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFFE78D), Color(0xFFFFA900)]),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 5),
                    boxShadow: [BoxShadow(color: const Color(0xFFB87500).withValues(alpha: .22), blurRadius: 18, offset: const Offset(0, 8))],
                  ),
                  child: const Center(child: Text('৳', style: TextStyle(color: Colors.white, fontSize: 43, fontWeight: FontWeight.w900))),
                )),
                Positioned(top: constraints.maxHeight * .38, child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: const Color(0xFF1C8B60), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF70E2B4), width: 2)),
                  child: Icon(slideIcon(), color: const Color(0xFFC4F7A7), size: 42),
                )),
                Positioned(top: constraints.maxHeight * .1, right: 24, child: _Coin()),
                Positioned(top: constraints.maxHeight * .4, left: 18, child: _Coin(size: 43)),
              ],
            ),
          ),
        );
      });

  IconData slideIcon() => icon;
}

class _CloudPuff extends StatelessWidget {
  const _CloudPuff({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size * .58,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .82), borderRadius: BorderRadius.circular(size)),
      );
}

class _Coin extends StatelessWidget {
  const _Coin({this.size = 55});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFFE58A), Color(0xFFFFA900)]),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFFF1BA), width: 3),
          boxShadow: [BoxShadow(color: const Color(0xFF8A6100).withValues(alpha: .2), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: Center(child: Text('৳', style: TextStyle(fontSize: size * .52, fontWeight: FontWeight.w900, color: Colors.white))),
      );
}

Route<void> _route(Widget screen) => PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => screen,
      transitionDuration: const Duration(milliseconds: 380),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(.025, .02), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
    );

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identity = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _remember = false;
  bool _submitting = false;

  @override
  void dispose() {
    _identity.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      await _AuthApi.checkConfiguredServer();
      await _AuthApi.login(identity: _identity.text, password: _password.text);
      if (!mounted) return;
      _notice(context, 'লগইন সফল হয়েছে।');
    } catch (error) {
      if (!mounted) return;
      _notice(context, error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          Positioned.fill(child: Image.asset('assets/animations/Minimal Mint Leaf Wave Background.png', fit: BoxFit.cover)),
          SafeArea(child: Column(children: [
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
              child: Row(children: [
                const SizedBox(width: 42),
                const Spacer(),
                Transform.translate(offset: const Offset(-24, 10), child: SizedBox(width: 320, height: 165, child: ClipRect(child: Align(alignment: Alignment.topCenter, heightFactor: .30, child: Image.asset('assets/animations/logo.png', width: 320, fit: BoxFit.contain))))),
                const Spacer(),
                IconButton(
                  tooltip: 'Server Settings',
                  onPressed: () => Navigator.of(context).push(_route(const ServerSettingsScreen())),
                  icon: const Icon(Icons.dns_outlined, color: _ink),
                ),
              ]),
            ),
            Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .94), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white, width: 1.5), boxShadow: [BoxShadow(color: const Color(0xFF244A88).withValues(alpha: .07), blurRadius: 30, offset: const Offset(0, 12))]),
                    child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('লগইন করুন', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _ink)),
                      const SizedBox(height: 6),
                      const Text('আপনার অ্যাকাউন্টে প্রবেশ করুন', style: TextStyle(fontSize: 13.5, height: 1.5, color: _muted)),
                      const SizedBox(height: 22),
                      TextFormField(
                        controller: _identity,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.mail_outline_rounded), hintText: 'ইমেইল ঠিকানা'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'ইমেইল অথবা মোবাইল নম্বর দিন।' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(prefixIcon: const Icon(Icons.lock_outline_rounded), hintText: 'পাসওয়ার্ড', suffixIcon: IconButton(onPressed: () => setState(() => _showPassword = !_showPassword), icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded))),
                        validator: (v) => (v == null || v.isEmpty) ? 'পাসওয়ার্ড দিন।' : null,
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? false), visualDensity: VisualDensity.compact, side: const BorderSide(color: Color(0xFF9AA8BC))),
                        const Expanded(child: Text('আমাকে মনে রাখুন', style: TextStyle(color: _muted, fontSize: 12))),
                        TextButton(onPressed: () => _notice(context, 'পাসওয়ার্ড পুনরুদ্ধারের API এখনো সংযুক্ত করা হয়নি।'), child: const Text('পাসওয়ার্ড ভুলে গেছেন?', style: TextStyle(color: _blue, fontSize: 11.5, fontWeight: FontWeight.w700))),
                      ]),
                      const SizedBox(height: 8),
                      _PrimaryButton(label: _submitting ? 'লগইন হচ্ছে...' : 'লগইন করুন', onPressed: _submitting ? null : _submit),
                      const SizedBox(height: 18),
                      const _OrDivider(),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(_route(const InviteVerificationScreen())),
                        icon: const Icon(Icons.groups_2_outlined, color: Color(0xFF00834A), size: 24),
                        label: const Text('ইনভাইট কোড দিয়ে যোগ দিন', style: TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 13)),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), side: const BorderSide(color: _line), shape: const StadiumBorder()),
                      ),

                    ])),
                  ),
                ]),
              )),
            )),
          ])),
        ]),
      );
}


class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _serverUrl;
  bool _saving = false;
  bool _testing = false;
  bool _showHelp = false;

  @override
  void initState() {
    super.initState();
    _serverUrl = TextEditingController(text: _AuthApi.baseUrl ?? '');
  }

  @override
  void dispose() {
    _serverUrl.dispose();
    super.dispose();
  }

  Future<void> _testAndSave() async {
    FocusScope.of(context).unfocus();
    if (_saving || _testing || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _saving = true; _testing = true; });
    try {
      await _AuthApi.saveBaseUrl(_serverUrl.text);
      if (!mounted) return;
      _notice(context, 'Server সংযোগ সফল। Address সংরক্ষণ হয়েছে।');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _notice(context, error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() { _saving = false; _testing = false; });
    }
  }

  Future<void> _testOnly() async {
    FocusScope.of(context).unfocus();
    if (_saving || _testing || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _testing = true);
    try {
      await _AuthApi.testServerUrl(_serverUrl.text);
      if (!mounted) return;
      _notice(context, 'Server API ও database connection ঠিক আছে।');
    } catch (error) {
      if (!mounted) return;
      _notice(context, error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          const _CloudBackground(),
          SafeArea(child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 20, 0),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_rounded, color: _ink)),
                const Expanded(child: Text('Server Settings', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: _ink))),
                const Icon(Icons.dns_outlined, color: _blue, size: 26),
              ]),
            ),
            Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .95),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [BoxShadow(color: const Color(0xFF244A88).withValues(alpha: .07), blurRadius: 30, offset: const Offset(0, 12))],
                  ),
                  child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Icon(Icons.cloud_done_outlined, size: 44, color: _blue),
                    const SizedBox(height: 12),
                    const Text('আপনার Server Address', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _ink)),
                    const SizedBox(height: 8),
                    const Text('Cloudflare Tunnel দিয়ে প্রকাশ করা HTTPS API URL দিন। প্রথমবার কোনো server আগে থেকে নির্বাচন করা নেই।', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.6, color: _muted)),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _serverUrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.link_rounded), hintText: 'https://your-domain.example/api', labelText: 'API Server URL'),
                      validator: (value) => _AuthApi.validateUrl(value ?? ''),
                    ),
                    const SizedBox(height: 8),
                    const Text('URL-এর শেষে /api থাকতে হবে। উদাহরণ: https://amr.scsohel.site/api', style: TextStyle(fontSize: 12, height: 1.5, color: _muted)),
                    const SizedBox(height: 18),
                    _PrimaryButton(label: _testing ? 'সংযোগ পরীক্ষা হচ্ছে...' : 'শুধু সংযোগ পরীক্ষা', onPressed: _testing || _saving ? null : _testOnly),
                    const SizedBox(height: 10),
                    _PrimaryButton(label: _saving ? 'পরীক্ষা ও সংরক্ষণ হচ্ছে...' : 'Verify করে সংরক্ষণ', onPressed: _saving || _testing ? null : _testAndSave),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _showHelp = !_showHelp),
                      icon: const Icon(Icons.info_outline_rounded),
                      label: Text(_showHelp ? 'নির্দেশনা লুকান' : 'কোন URL ব্যবহার করব?'),
                    ),
                    if (_showHelp) ...[
                      const SizedBox(height: 8),
                      const Text('Server URL হলো আপনার public HTTPS address, যার /api/health endpoint {"status":"ok"} দেয়। শুধু domain-এর root URL নয়; /api অংশসহ লিখুন। Server বদলালে নতুন server-এর account ও data আলাদা হতে পারে.', style: TextStyle(fontSize: 12.5, height: 1.6, color: _muted)),
                    ],
                  ])),
                ),
              )),
            )),
          ])),
        ]),
      );
}

class InviteVerificationScreen extends StatefulWidget {
  const InviteVerificationScreen({super.key});

  @override
  State<InviteVerificationScreen> createState() => _InviteVerificationScreenState();
}

class _InviteVerificationScreenState extends State<InviteVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _invite = TextEditingController();
  bool _verifying = false;

  @override
  void dispose() {
    _invite.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    if (_verifying || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _verifying = true);
    try {
      await _AuthApi.checkConfiguredServer();
      await _AuthApi.verifyInvite(_invite.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        _route(SignupScreen(verifiedInvite: _invite.text.trim())),
      );
    } catch (error) {
      if (!mounted) return;
      _notice(context, error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          Positioned.fill(child: Image.asset('assets/animations/Minimal Mint Leaf Wave Background.png', fit: BoxFit.cover)),
          SafeArea(child: Column(children: [
            const SizedBox(height: 32),
            Transform.translate(offset: const Offset(-24, 10), child: SizedBox(width: 320, height: 165, child: ClipRect(child: Align(alignment: Alignment.topCenter, heightFactor: .30, child: Image.asset('assets/animations/logo.png', width: 320, fit: BoxFit.contain))))),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 16, 0),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_rounded, color: _ink)),
                const Spacer(),
              ]),
            ),
            Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .95), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white, width: 1.5), boxShadow: [BoxShadow(color: const Color(0xFF244A88).withValues(alpha: .07), blurRadius: 30, offset: const Offset(0, 12))]),
                  child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Icon(Icons.verified_user_outlined, size: 42, color: _blue),
                    const SizedBox(height: 12),
                    const Text('ইনভাইট কোড যাচাই', textAlign: TextAlign.center, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: _ink)),
                    const SizedBox(height: 8),
                    const Text('আপনার পাওয়া ইনভাইট কোডটি লিখে যাচাই করুন। কোড সঠিক হলে পরের ধাপে অ্যাকাউন্ট তৈরি করতে পারবেন।', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.6, color: _muted)),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _invite,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.groups_2_outlined), hintText: 'ইনভাইট কোড লিখুন'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'ইনভাইট কোড দিন।' : null,
                    ),
                    const SizedBox(height: 18),
                    _PrimaryButton(label: _verifying ? 'যাচাই হচ্ছে...' : 'Verify করুন', onPressed: _verifying ? null : _verify),
                  ])),
                ),
              )),
            )),
          ])),
        ]),
      );
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, this.verifiedInvite = ''});
  final String verifiedInvite;
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _invite = TextEditingController();
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _acceptedTerms = false;
  bool _submitting = false;
  bool _marketing = false;

  @override
  void initState() {
    super.initState();
    _invite.text = widget.verifiedInvite;
  }

  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _mobile.dispose(); _password.dispose(); _confirm.dispose(); _invite.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    if (!_acceptedTerms) {
      _notice(context, 'চালিয়ে যেতে শর্তাবলি ও গোপনীয়তা নীতি গ্রহণ করুন।');
      return;
    }
    setState(() => _submitting = true);
    try {
      await _AuthApi.register(
        invite: _invite.text,
        name: _name.text,
        email: _email.text,
        mobile: _mobile.text,
        password: _password.text,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('সাইন আপ সফল'),
          content: const Text('অ্যাকাউন্ট তৈরি হয়েছে। এখন লগইন করতে পারবেন।'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ঠিক আছে'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _notice(context, error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          Positioned.fill(child: Image.asset('assets/animations/Minimal Mint Leaf Wave Background.png', fit: BoxFit.cover)),
          SafeArea(child: Column(children: [
            const SizedBox(height: 32),
            Transform.translate(offset: const Offset(-24, 10), child: SizedBox(width: 320, height: 165, child: ClipRect(child: Align(alignment: Alignment.topCenter, heightFactor: .30, child: Image.asset('assets/animations/logo.png', width: 320, fit: BoxFit.contain))))),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 16, 0),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_rounded, color: _ink)),
                const Spacer(),
              ]),
            ),
            Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 2, 22, 22),
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('অ্যাকাউন্ট তৈরি করুন', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF075B3A))),
                  const SizedBox(height: 7),
                  const Text('ইনভাইট কোড দিয়ে যোগ দিন', style: TextStyle(fontSize: 13, height: 1.55, color: _muted)),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 17, 16, 18),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .95), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white, width: 1.5), boxShadow: [BoxShadow(color: const Color(0xFF244A88).withValues(alpha: .06), blurRadius: 26, offset: const Offset(0, 10))]),
                    child: Form(key: _formKey, child: Column(children: [
                      TextFormField(controller: _invite, readOnly: widget.verifiedInvite.isNotEmpty, decoration: InputDecoration(prefixIcon: const Icon(Icons.groups_2_outlined), hintText: 'ইনভাইট কোড', suffixIcon: widget.verifiedInvite.isNotEmpty ? const Icon(Icons.verified_rounded, color: _blue) : null), validator: (v) => (v == null || v.trim().isEmpty) ? 'ইনভাইট কোড দিন।' : null),
                      const SizedBox(height: 9),
                      TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded), hintText: 'আপনার নাম লিখুন'), validator: (v) => (v == null || v.trim().length < 2) ? 'সঠিক নাম লিখুন।' : null),
                      const SizedBox(height: 9),
                      TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(prefixIcon: Icon(Icons.mail_outline_rounded), hintText: 'ইমেইল লিখুন'), validator: (v) { final s = (v ?? '').trim(); return s.contains('@') && s.contains('.') ? null : 'সঠিক ইমেইল লিখুন।'; }),
                      const SizedBox(height: 9),
                      TextFormField(controller: _mobile, keyboardType: TextInputType.phone, decoration: const InputDecoration(prefixIcon: Icon(Icons.phone_iphone_rounded), hintText: 'মোবাইল নম্বর লিখুন'), validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length >= 10 ? null : 'সঠিক মোবাইল নম্বর লিখুন।'),
                      const SizedBox(height: 9),
                      TextFormField(controller: _password, obscureText: !_showPassword, decoration: InputDecoration(prefixIcon: const Icon(Icons.lock_outline_rounded), hintText: 'পাসওয়ার্ড লিখুন', suffixIcon: IconButton(onPressed: () => setState(() => _showPassword = !_showPassword), icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded))), validator: (v) => (v ?? '').length >= 8 ? null : 'পাসওয়ার্ড কমপক্ষে ৮ অক্ষরের হতে হবে।'),
                      const SizedBox(height: 9),
                      TextFormField(controller: _confirm, obscureText: !_showConfirm, decoration: InputDecoration(prefixIcon: const Icon(Icons.lock_outline_rounded), hintText: 'পাসওয়ার্ড আবার লিখুন', suffixIcon: IconButton(onPressed: () => setState(() => _showConfirm = !_showConfirm), icon: Icon(_showConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded))), validator: (v) => v == _password.text ? null : 'পাসওয়ার্ড দুটি মিলছে না।'),
                      const SizedBox(height: 9),

                      CheckboxListTile(
                        value: _acceptedTerms,
                        onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        title: const Text('আমি শর্তাবলি এবং গোপনীয়তা নীতি পড়েছি এবং সম্মত আছি', style: TextStyle(fontSize: 11.5, color: _ink, height: 1.4)),
                      ),
                      CheckboxListTile(
                        value: _marketing,
                        onChanged: (v) => setState(() => _marketing = v ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        title: const Text('আমাকে আপডেট ও গুরুত্বপূর্ণ তথ্য জানাবেন', style: TextStyle(fontSize: 11.5, color: _muted)),
                      ),
                      const SizedBox(height: 8),
                      _PrimaryButton(label: _submitting ? 'অ্যাকাউন্ট তৈরি হচ্ছে...' : 'অ্যাকাউন্ট তৈরি করুন', onPressed: _submitting ? null : _submit),
                      const SizedBox(height: 14),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Flexible(child: Text('ইতিমধ্যে অ্যাকাউন্ট আছে? ', style: TextStyle(color: _muted, fontSize: 12))),
                        GestureDetector(onTap: () => Navigator.of(context).pop(), child: const Text('লগইন করুন', style: TextStyle(color: _blue, fontWeight: FontWeight.w800, fontSize: 12))),
                      ]),
                    ])),
                  ),
                ]),
              )),
            )),
          ])),
        ]),
      );
}

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key, this.isSignup = false});
  final bool isSignup;
  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  int _step = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 850), (timer) {
      if (!mounted) return;
      if (_step < 3) {
        setState(() => _step++);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          const _CloudBackground(),
          SafeArea(child: Column(children: [
            const Spacer(flex: 2),
            const _BrandMark(size: 76),
            const SizedBox(height: 15),
            const Text('আমার হিসাব', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _ink)),
            const SizedBox(height: 6),
            const Text('তথ্য প্রস্তুত করা হচ্ছে...', style: TextStyle(color: _muted, fontSize: 14)),
            const SizedBox(height: 28),
            SizedBox(width: 86, height: 86, child: CircularProgressIndicator(
              strokeWidth: 7,
              backgroundColor: const Color(0xFFD9E4FF),
              valueColor: const AlwaysStoppedAnimation(_blue),
            )),
            const Spacer(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .86), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white, width: 1.5)),
              child: Column(children: [
                _LoadingStep(label: widget.isSignup ? 'অ্যাকাউন্ট যাচাই করা হচ্ছে' : 'অ্যাকাউন্ট যাচাই করা হচ্ছে', done: _step >= 1),
                const SizedBox(height: 18),
                _LoadingStep(label: 'আপনার তথ্য লোড করা হচ্ছে', done: _step >= 2),
                const SizedBox(height: 18),
                _LoadingStep(label: 'ড্যাশবোর্ড প্রস্তুত করা হচ্ছে', done: _step >= 3),
                const SizedBox(height: 18),
                Row(children: [
                  SizedBox(width: 21, height: 21, child: _step >= 3 ? const Icon(Icons.info_outline_rounded, color: _blue, size: 20) : const CircularProgressIndicator(strokeWidth: 2.5)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_step >= 3 ? 'API সংযুক্ত না থাকায় Login/Signup এখনো সম্পন্ন করা যায়নি।' : 'প্রস্তুত হচ্ছে...', style: const TextStyle(fontSize: 13, color: _muted))),
                ]),
                if (_step >= 3) ...[
                  const SizedBox(height: 16),
                  _PrimaryButton(label: 'লগইন স্ক্রিনে ফিরুন', onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst)),
                ],
              ]),
            ),
            const Spacer(flex: 2),
          ])),
        ]),
      );
}

class _LoadingStep extends StatelessWidget {
  const _LoadingStep({required this.label, required this.done});
  final String label;
  final bool done;
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(color: done ? _blue : const Color(0xFFE8EEFA), shape: BoxShape.circle),
          child: Icon(done ? Icons.check_rounded : Icons.circle_outlined, size: done ? 17 : 13, color: done ? Colors.white : const Color(0xFF98A6BE)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, color: _ink))),
      ]);
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_blue, _deepBlue]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: _blue.withValues(alpha: .18), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(width: 9),
              const Icon(Icons.arrow_forward_rounded, size: 19),
            ]),
          ),
        ),
      );
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) => Row(children: [
        const Expanded(child: Divider(color: _line)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Text('অথবা', style: TextStyle(color: _muted.withValues(alpha: .9), fontSize: 12))),
        const Expanded(child: Divider(color: _line)),
      ]);
}

void _notice(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}
