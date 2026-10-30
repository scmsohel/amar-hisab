import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lottie/lottie.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _AuthApi.loadBaseUrl();
  final preferences = await SharedPreferences.getInstance();
  _appThemeMode.value = preferences.getString(_themePreferenceKey) == 'light'
      ? ThemeMode.light
      : ThemeMode.dark;
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: _appThemeMode.value == ThemeMode.dark ? const Color(0xFF061B2D) : const Color(0xFFF3F8F5),
    statusBarIconBrightness: _appThemeMode.value == ThemeMode.dark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: _appThemeMode.value == ThemeMode.dark ? const Color(0xFF061713) : const Color(0xFFF3F8F5),
    systemNavigationBarIconBrightness: _appThemeMode.value == ThemeMode.dark ? Brightness.light : Brightness.dark,
  ));
  runApp(const AmarHisabApp());
}

const _blue = Color(0xFF00834A);
const _deepBlue = Color(0xFF006B3D);
const _ink = Color(0xFF075B3A);
const _muted = Color(0xFF687C78);
const _line = Color(0xFFDDEBE5);
const _pale = Color(0xFFF2F7FF);

const String _themePreferenceKey = 'amar_hisab_theme_mode';
final ValueNotifier<ThemeMode> _appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);

Future<void> _setAppThemeMode(ThemeMode mode) async {
  _appThemeMode.value = mode;
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(_themePreferenceKey, mode == ThemeMode.light ? 'light' : 'dark');
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: mode == ThemeMode.dark ? const Color(0xFF061B2D) : const Color(0xFFF3F8F5),
    statusBarIconBrightness: mode == ThemeMode.dark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: mode == ThemeMode.dark ? const Color(0xFF061713) : const Color(0xFFF3F8F5),
    systemNavigationBarIconBrightness: mode == ThemeMode.dark ? Brightness.light : Brightness.dark,
  ));
}

class _AuthApi {
  static const String _baseUrlPreferenceKey = 'amar_hisab_server_url';
  static const String _sessionCookieKey = 'amar_hisab_session_cookie';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  static String? _baseUrl;
  static String? _sessionCookie;

  static String? get baseUrl => _baseUrl;

  static Future<void> loadBaseUrl() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_baseUrlPreferenceKey);
    _baseUrl = saved == null || saved.trim().isEmpty ? null : _normalizeUrl(saved);
    _sessionCookie = await _secureStorage.read(key: _sessionCookieKey);
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
    if (_baseUrl != normalized) {
      _sessionCookie = null;
      await _secureStorage.delete(key: _sessionCookieKey);
    }
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
      await _secureStorage.write(key: _sessionCookieKey, value: _sessionCookie);
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
          'অনুরোধ ব্যর্থ হয়েছে (${response.statusCode})।');
    }
    return data;
  }

  static Future<Map<String, dynamic>> _get(String path) async {
    await _ensureConfigured();
    final request = await _client.getUrl(Uri.parse('$_baseUrl$path'));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (_sessionCookie != null) {
      request.headers.set(HttpHeaders.cookieHeader, _sessionCookie!);
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await response.transform(utf8.decoder).join();
    Map<String, dynamic> data = {};
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } on FormatException {
        data = {'error': 'সার্ভার থেকে সঠিক উত্তর পাওয়া যায়নি।'};
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error']?.toString() ?? 'ডেটা আনা যায়নি।');
    }
    return data;
  }

  static Future<bool> restoreSession() async {
    if (_sessionCookie == null || _sessionCookie!.isEmpty || _baseUrl == null) {
      return false;
    }
    try {
      await _get('/auth/me');
      return true;
    } catch (_) {
      await clearSession();
      return false;
    }
  }

  static Future<void> clearSession() async {
    _sessionCookie = null;
    await _secureStorage.delete(key: _sessionCookieKey);
  }

  static Future<Map<String, dynamic>> loadDashboardData() async {
    final results = await Future.wait([
      _get('/auth/me'),
      _get('/data/wallets'),
      _get('/data/transactions'),
    ]);
    return {'user': results[0]['user'], 'wallets': results[1]['data'], 'transactions': results[2]['data']};
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
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: _appThemeMode,
        builder: (context, mode, _) => MaterialApp(
          title: 'আমার হিসাব',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            fontFamily: 'Roboto',
            scaffoldBackgroundColor: const Color(0xFFF3F8F5),
            colorScheme: ColorScheme.fromSeed(seedColor: _blue, brightness: Brightness.light),
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
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            fontFamily: 'Roboto',
            scaffoldBackgroundColor: const Color(0xFF061713),
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4DE2B2), brightness: Brightness.dark),
          ),
          home: const SplashScreen(),
        ),
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
    _openInitialScreen();
  }

  Future<void> _openInitialScreen() async {
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    if (!mounted) return;
    final hasSession = await _AuthApi.restoreSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => hasSession
            ? const DashboardScreen()
            : const LoginScreen(),
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
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

class _CloudBackground extends StatelessWidget {
  const _CloudBackground();

  @override
  Widget build(BuildContext context) => const Positioned.fill(
        child: CustomPaint(painter: _CloudPainter()),
      );
}

class _CloudPainter extends CustomPainter {
  const _CloudPainter();

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

    {
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
  bool shouldRepaint(covariant _CloudPainter oldDelegate) => false;
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
      Navigator.of(context).pushReplacement(_route(const DashboardScreen()));
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
                Transform.translate(offset: const Offset(-12, 10), child: SizedBox(width: 220, height: 135, child: ClipRect(child: Align(alignment: Alignment.topCenter, heightFactor: .30, child: Image.asset('assets/animations/logo.png', width: 220, fit: BoxFit.contain))))),
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

  String _apiUrl() => 'https://${_serverUrl.text.trim()}/api';

  String? _validateDomain(String? value) {
    final domain = (value ?? '').trim();
    if (domain.isEmpty) return 'আপনার domain লিখুন।';
    if (domain.contains('://') ||
        domain.contains('/') ||
        domain.contains('?') ||
        domain.contains('#') ||
        domain.contains('@') ||
        domain.contains(' ')) {
      return 'শুধু domain লিখুন, https:// বা /api নয়।';
    }
    return _AuthApi.validateUrl(_apiUrl());
  }

  @override
  void initState() {
    super.initState();
    final saved = _AuthApi.baseUrl ?? '';
    final savedDomain = saved
        .replaceFirst(RegExp(r'^https://'), '')
        .replaceFirst(RegExp(r'/api/?$'), '');
    _serverUrl = TextEditingController(text: savedDomain);
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
      await _AuthApi.saveBaseUrl(_apiUrl());
      if (!mounted) return;
      _notice(context, 'Server সংযোগ সফল। Address সংরক্ষণ হয়েছে।');
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
      await _AuthApi.testServerUrl(_apiUrl());
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
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.link_rounded),
                        prefixText: 'https://',
                        suffixText: '/api',
                        hintText: 'your-domain.example',
                        labelText: 'Server Domain',
                      ),
                      validator: _validateDomain,
                    ),
                    const SizedBox(height: 8),
                    const Text('শুধু domain লিখুন। https:// এবং /api স্বয়ংক্রিয়ভাবে যোগ হবে। উদাহরণ: amr.scsohel.site', style: TextStyle(fontSize: 12, height: 1.5, color: _muted)),
                    const SizedBox(height: 18),
                    _PrimaryButton(label: _testing && !_saving ? 'সংযোগ পরীক্ষা হচ্ছে...' : 'শুধু সংযোগ পরীক্ষা', onPressed: _testing || _saving ? null : _testOnly),
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
                      const Text('আপনার public HTTPS domain-এর /api/health endpoint থেকে {"status":"ok"} আসতে হবে। শুধু domain লিখবেন; scheme ও API path স্বয়ংক্রিয়ভাবে যুক্ত হবে। Server বদলালে নতুন server-এর account ও data আলাদা হতে পারে.', style: TextStyle(fontSize: 12.5, height: 1.6, color: _muted)),
                    ],
                  ])),
                ),
              )),
            )),
          ])),
        ]),
      );
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  bool _hidden = false;
  String? _error;
  double _balance = 0;
  double? _monthChangePercent;
  String _monthChangeMessage = 'গত মাসের তুলনার ডেটা নেই';
  List<Map<String, dynamic>> _transactions = <Map<String, dynamic>>[];
  int _chartRangeDays = 30;
  int _incomeDonutMonthOffset = 0;
  int _expenseDonutMonthOffset = 0;
  Map<String, double> _walletBalances = {'ক্যাশ': 0, 'ব্যাংক': 0, 'বিকাশ': 0, 'নগদ': 0};

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _amount(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

  DateTime? _parseTransactionDate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final direct = DateTime.tryParse(raw);
    if (direct != null) return direct;
    final normalized = raw
        .replaceAll('০', '0').replaceAll('১', '1').replaceAll('২', '2')
        .replaceAll('৩', '3').replaceAll('৪', '4').replaceAll('৫', '5')
        .replaceAll('৬', '6').replaceAll('৭', '7').replaceAll('৮', '8')
        .replaceAll('৯', '9').replaceAll('.', '').trim();
    final match = RegExp(r'(\d{1,2})\s+([^,\s]+)[, ]+\s*(\d{4})').firstMatch(normalized);
    if (match == null) return null;
    const months = <String>[
      'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
      'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
    ];
    final token = match.group(2)!;
    final month = months.indexWhere((name) => name.startsWith(token) || token.startsWith(name));
    if (month < 0) return null;
    return DateTime.tryParse('${match.group(3)}-${(month + 1).toString().padLeft(2, '0')}-${match.group(1)!.padLeft(2, '0')}');
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _AuthApi.loadDashboardData();
      final wallets = data['wallets'] is List ? data['wallets'] as List : <dynamic>[];
      final transactions = data['transactions'] is List ? data['transactions'] as List : <dynamic>[];
      final opening = <String, double>{'ক্যাশ': 0, 'ব্যাংক': 0, 'বিকাশ': 0, 'নগদ': 0};
      for (final item in wallets) {
        if (item is Map) opening[(item['name'] ?? '').toString()] = _amount(item['base']);
      }
      final walletBalances = Map<String, double>.from(opening);
      final openingTotal = opening.values.fold<double>(0, (sum, value) => sum + value);
      final now = DateTime.now();
      final currentMonthStart = DateTime(now.year, now.month);
      final nextMonthStart = DateTime(now.year, now.month + 1);
      final previousMonthStart = DateTime(now.year, now.month - 1);
      final previousMonthEnd = currentMonthStart;
      var total = openingTotal;
      var currentMonthIncome = 0.0;
      var currentMonthExpense = 0.0;
      var previousMonthIncome = 0.0;
      var previousMonthExpense = 0.0;
      for (final item in transactions) {
        if (item is! Map) continue;
        final amount = _amount(item['amount']);
        final kind = (item['kind'] ?? '').toString();
        final rawDate = item['dateInput'] ?? item['date_input'] ?? item['date'] ?? item['createdAt'] ?? item['created_at'];
        final transactionDate = _parseTransactionDate(rawDate);
        if (transactionDate != null) {
          if (transactionDate.isBefore(nextMonthStart)) {
            if (kind == 'আয়') total += amount;
            if (kind == 'ব্যয়') total -= amount;
          }
          if (!transactionDate.isBefore(currentMonthStart) && transactionDate.isBefore(nextMonthStart)) {
            if (kind == 'আয়') currentMonthIncome += amount;
            if (kind == 'ব্যয়') currentMonthExpense += amount;
          } else if (!transactionDate.isBefore(previousMonthStart) && transactionDate.isBefore(previousMonthEnd)) {
            if (kind == 'আয়') previousMonthIncome += amount;
            if (kind == 'ব্যয়') previousMonthExpense += amount;
          }
        }
        final walletName = (item['wallet'] ?? item['walletName'] ?? item['wallet_name'] ?? item['accountName'] ?? item['account'] ?? '').toString();
        if (walletBalances.containsKey(walletName)) {
          if (kind == 'আয়') walletBalances[walletName] = walletBalances[walletName]! + amount;
          if (kind == 'ব্যয়') walletBalances[walletName] = walletBalances[walletName]! - amount;
        }
      }
      final currentNet = currentMonthIncome - currentMonthExpense;
      final previousNet = previousMonthIncome - previousMonthExpense;
      final double? monthChangePercent = previousNet == 0 ? null : ((currentNet - previousNet) / previousNet.abs()) * 100;
      final monthChangeMessage = currentNet == 0 && previousNet == 0
          ? 'এখনো কোনো লেনদেন নেই'
          : previousNet == 0
              ? 'এই মাসে নতুন লেনদেন'
              : '${monthChangePercent!.abs().toStringAsFixed(1)}% গত মাসের তুলনায়';
      if (!mounted) return;
      setState(() {
        _balance = total;
        _walletBalances = walletBalances;
        _monthChangePercent = monthChangePercent;
        _monthChangeMessage = monthChangeMessage;
        _transactions = transactions.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  String _money(double value) => '৳ ${value.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF061B2D) : const Color(0xFFF3F8F5),
          statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF061713) : const Color(0xFFF3F8F5),
          systemNavigationBarIconBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        ),
        child: Scaffold(
        body: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: Theme.of(context).brightness == Brightness.dark
                      ? const [Color(0xFF061B2D), Color(0xFF041827), Color(0xFF031A1B), Color(0xFF061713)]
                      : const [Color(0xFFF3F8F5), Color(0xFFEAF5EF), Color(0xFFF7FBF8), Color(0xFFF3F8F5)],
                  stops: const [0.0, 0.34, 0.72, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                children: [
                  Transform.translate(
                    offset: const Offset(0, -4),
                    child: SizedBox(
                      height: 36,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('আমার হিসাব', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF4DE2B2) : const Color(0xFF087A5B), fontSize: 23, fontWeight: FontWeight.w900, height: 1.0)),
                              Transform.translate(
                                offset: const Offset(0, -2),
                                child: Text('আপনার আয়-ব্যয়ের সহজ সঙ্গী', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFB8D9D7) : const Color(0xFF587267), fontSize: 10.5, height: 1.0)),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Transform.translate(
                              offset: const Offset(0, -2),
                              child: IconButton(
                                tooltip: 'মেনু',
                                onPressed: () => _showDashboardMenu(context),
                                icon: Icon(Icons.menu_rounded, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFD7FFF4) : const Color(0xFF087A5B), size: 27),
                              ),
                            ),
                            const Spacer(),
                            Transform.translate(
                              offset: const Offset(0, -5),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  IconButton(
                                    tooltip: 'নোটিফিকেশন',
                                    onPressed: () => _notice(context, 'এখন কোনো নতুন নোটিফিকেশন নেই।'),
                                    icon: Icon(Icons.notifications_none_rounded, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFD7FFF4) : const Color(0xFF087A5B), size: 25),
                                  ),
                                  Positioned(
                                    right: 9,
                                    top: 8,
                                    child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFE53935), shape: BoxShape.circle)),
                                  ),
                                ],
                              ),
                            ),
                            Transform.translate(
                              offset: const Offset(0, -5),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Color(0xFF4DE2B2), Color(0xFF087A5B)],
                                  ),
                                  border: Border.all(color: const Color(0xFFE7FFF7), width: 1.5),
                                  boxShadow: [
                                    BoxShadow(color: const Color(0xFF00E7A0).withValues(alpha: .14), blurRadius: 8),
                                  ],
                                ),
                                child: const Icon(Icons.person_rounded, color: Colors.white, size: 26),
                              ),
                            ),
                          ],
                        ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 0),
                  Transform.translate(
                    offset: const Offset(0, 3),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(15, 0, 8, 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF00E7A0).withValues(alpha: .78)
                              : const Color(0xFF79DDB8),
                          width: 1.25,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: Theme.of(context).brightness == Brightness.dark
                              ? const [Color(0xD908302B), Color(0xD904232B), Color(0xD9021725)]
                              : const [Color(0xFFF9FFFC), Color(0xFFEAFBF3), Color(0xFFF5FFFA)],
                        ),
                        boxShadow: Theme.of(context).brightness == Brightness.dark
                            ? [
                                BoxShadow(color: const Color(0xFF00F0A0).withValues(alpha: .08), blurRadius: 14, spreadRadius: 0, offset: const Offset(0, 3)),
                                BoxShadow(color: const Color(0xFF00111E).withValues(alpha: .14), blurRadius: 10, offset: const Offset(0, 4)),
                              ]
                            : [
                                BoxShadow(color: const Color(0xFF39B98A).withValues(alpha: .10), blurRadius: 18, offset: const Offset(0, 7)),
                                BoxShadow(color: const Color(0xFF0B5B43).withValues(alpha: .035), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            right: -18,
                            bottom: -16,
                            width: 330,
                            height: 150,
                            child: ClipRect(child: IgnorePointer(child: CustomPaint(painter: _BalanceNeonChartPainter(isDark: Theme.of(context).brightness == Brightness.dark)))),
                          ),
                          Transform.translate(
                            offset: const Offset(0, -3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                              Row(
                                children: [
                                  Text('মোট ব্যালেন্স', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF0FFF9) : const Color(0xFF155A45), fontSize: 13, height: 1, fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 0),
                                  IconButton(
                                    constraints: const BoxConstraints.tightFor(width: 24, height: 28),
                                    padding: EdgeInsets.zero,
                                    tooltip: _hidden ? 'ব্যালেন্স দেখান' : 'ব্যালেন্স লুকান',
                                    onPressed: () => setState(() => _hidden = !_hidden),
                                    icon: Icon(_hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFB9FBE5) : const Color(0xFF168565), size: 18),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? const Color(0xFF32DDB0).withValues(alpha: .12)
                                          : const Color(0xFFBDF5DF).withValues(alpha: .48),
                                      border: Border.all(
                                        color: Theme.of(context).brightness == Brightness.dark
                                            ? const Color(0xFF43E8BE).withValues(alpha: .34)
                                            : const Color(0xFF6FD9B2).withValues(alpha: .58),
                                      ),
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('এই মাস', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFD7FFF4) : const Color(0xFF155A45), fontSize: 12, fontWeight: FontWeight.w700)),
                                        SizedBox(width: 5),
                                        Icon(Icons.keyboard_arrow_down_rounded, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFD7FFF4) : const Color(0xFF155A45), size: 17),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 0),
                              if (_loading)
                                Transform.translate(
                                  offset: const Offset(18, -19),
                                  child: SizedBox(height: 30, child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF00E7A0) : const Color(0xFF00A875))))),
                                )
                              else if (_error != null)
                                Text(_error!, style: const TextStyle(color: Color(0xFFFF6868), fontSize: 12))
                              else
                                Transform.translate(
                                  offset: const Offset(0, -19),
                                  child: Text(
                                    _hidden ? '৳ ••••••' : _money(_balance),
                                    style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF075B45), fontSize: 29, fontWeight: FontWeight.w900, letterSpacing: .2),
                                  ),
                                ),
                              const SizedBox(height: 0),
                              SizedBox(
                                height: 4,
                                child: OverflowBox(
                                  alignment: Alignment.topCenter,
                                  minHeight: 28,
                                  maxHeight: 28,
                                  child: Transform.translate(
                                    offset: const Offset(0, -24),
                                    child: Row(
                                      children: [
                                    Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? const Color(0xFF00E7A0).withValues(alpha: .16)
                                          : const Color(0xFFB5F2D9),
                                      border: Border.all(
                                        color: Theme.of(context).brightness == Brightness.dark
                                            ? const Color(0xFF00E7A0).withValues(alpha: .62)
                                            : const Color(0xFF72DDB5),
                                      ),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.trending_up_rounded, size: 15, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF00F0A0) : const Color(0xFF008D62)),
                                        SizedBox(width: 3),
                                        Text(
                                          _monthChangePercent == null
                                              ? _monthChangeMessage
                                              : '${_monthChangePercent! >= 0 ? '+' : '-'}${_monthChangePercent!.abs().toStringAsFixed(1)}% গত মাসের তুলনায়',
                                          style: TextStyle(
                                            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFBFFFF0) : const Color(0xFF17634A),
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      _loading ? 'ব্যালেন্স লোড হচ্ছে...' : _error != null ? 'সার্ভার থেকে ডেটা পাওয়া যায়নি' : '',
                                      style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFB8D9D7) : const Color(0xFF55796B), fontSize: 11),
                                    ),
                                  ),
                                      ],
                                    ),
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
                  const SizedBox(height: 11),
                  SizedBox(
                    height: 86,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _walletCard('ক্যাশ', Icons.account_balance_wallet_rounded, const Color(0xFF16B981))),
                        const SizedBox(width: 7),
                        Expanded(child: _walletCard('ব্যাংক', Icons.account_balance_rounded, const Color(0xFF1688D4))),
                        const SizedBox(width: 7),
                        Expanded(child: _walletCard('বিকাশ', Icons.payments_rounded, const Color(0xFFE83E8C))),
                        const SizedBox(width: 7),
                        Expanded(child: _walletCard('নগদ', Icons.account_balance_wallet_rounded, const Color(0xFFFF8A00))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 11),
                  _incomeExpenseChart(),
                  const SizedBox(height: 11),
                  _incomeExpenseDonuts(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('আবার চেষ্টা করুন')),
                  ],
                ],
              ),
            ),
          ),

        ]),
        ),
      );

  Widget _incomeExpenseChart() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final rangeEnd = DateTime(now.year, now.month, now.day + 1);
    final rangeStart = rangeEnd.subtract(Duration(days: _chartRangeDays));
    final days = _chartRangeDays;
    final income = List<double>.filled(days, 0);
    final expense = List<double>.filled(days, 0);
    for (final tx in _transactions) {
      final date = _parseTransactionDate(tx['dateInput'] ?? tx['date_input'] ?? tx['date'] ?? tx['createdAt'] ?? tx['created_at']);
      if (date == null || date.isBefore(rangeStart) || !date.isBefore(rangeEnd)) continue;
      final index = date.difference(rangeStart).inDays;
      if (index < 0 || index >= days) continue;
      final amount = _amount(tx['amount']);
      if (tx['kind'] == 'আয়') income[index] += amount;
      if (tx['kind'] == 'ব্যয়') expense[index] += amount;
    }
    final totalIncome = income.fold<double>(0, (sum, value) => sum + value);
    final totalExpense = expense.fold<double>(0, (sum, value) => sum + value);
    final maximum = <double>[...income, ...expense].fold<double>(0, (maxValue, value) => value > maxValue ? value : maxValue);
    final chartMax = maximum <= 0 ? 1.0 : maximum * 1.2;
    final textColor = isDark ? const Color(0xFFDDFBF1) : const Color(0xFF164F40);
    final mutedColor = isDark ? const Color(0xFF9ABBB4) : const Color(0xFF64877C);
    final cardColor = isDark ? const Color(0xFF062537) : const Color(0xFFF9FFFC);
    final borderColor = isDark ? const Color(0xFF12605D) : const Color(0xFFD7EEE5);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 7, 3),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: (isDark ? const Color(0xFF00E7A0) : const Color(0xFF168565)).withValues(alpha: isDark ? .07 : .045),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, color: Color(0xFF00A878), size: 21),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'আয় ও খরচের হিসাব',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              PopupMenuButton<int>(
                initialValue: _chartRangeDays,
                tooltip: 'গ্রাফের সময় নির্বাচন করুন',
                onSelected: (value) => setState(() => _chartRangeDays = value),
                color: isDark ? const Color(0xFF102A38) : const Color(0xFFFFFFFF),
                surfaceTintColor: Colors.transparent,
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isDark ? const Color(0xFF245363) : const Color(0xFFD9E9E4)),
                ),
                constraints: const BoxConstraints(maxHeight: 190, minWidth: 112, maxWidth: 112),
                itemBuilder: (context) => [
                  PopupMenuItem<int>(
                    enabled: false,
                    height: 112,
                    padding: EdgeInsets.zero,
                    child: SizedBox(
                      height: 112,
                      width: 112,
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            for (final option in const <(int, String)>[
                              (3, '৩ দিন'), (7, '৭ দিন'), (15, '১৫ দিন'),
                              (30, '১ মাস'), (90, '৩ মাস'), (180, '৬ মাস'), (365, '১ বছর'),
                            ])
                              InkWell(
                                onTap: () {
                                  Navigator.of(context).pop();
                                  setState(() => _chartRangeDays = option.$1);
                                },
                                child: Container(
                                  height: 34,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  color: _chartRangeDays == option.$1
                                      ? (isDark ? const Color(0xFF31505A) : const Color(0xFFE0F5ED))
                                      : Colors.transparent,
                                  child: Row(children: [
                                    if (_chartRangeDays == option.$1)
                                      const Icon(Icons.check_rounded, size: 13, color: Color(0xFF00B982))
                                    else
                                      const SizedBox(width: 13),
                                    const SizedBox(width: 5),
                                    Text(option.$2, style: TextStyle(
                                      color: _chartRangeDays == option.$1 ? const Color(0xFF00B982) : textColor,
                                      fontSize: 10.5,
                                      fontWeight: _chartRangeDays == option.$1 ? FontWeight.w800 : FontWeight.w600,
                                    )),
                                  ]),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF00E7A0).withValues(alpha: .12) : const Color(0xFFDDF9EE),
                    border: Border.all(color: isDark ? const Color(0xFF00E7A0).withValues(alpha: .25) : const Color(0xFFB9EBDD)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      _chartRangeDays == 3 ? '৩ দিন' : _chartRangeDays == 7 ? '৭ দিন' : _chartRangeDays == 15 ? '১৫ দিন' : _chartRangeDays == 30 ? '১ মাস' : _chartRangeDays == 90 ? '৩ মাস' : _chartRangeDays == 180 ? '৬ মাস' : '১ বছর',
                      style: TextStyle(color: textColor, fontSize: 10.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.keyboard_arrow_down_rounded, color: textColor, size: 15),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 115,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Column(
                      children: [
                        Expanded(
                          child: CustomPaint(
                            painter: _IncomeExpenseChartPainter(
                              income: income,
                              expense: expense,
                              maxValue: chartMax,
                              isDark: isDark,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(6, (index) {
                            final dayOffset = ((days - 1) * index / 5).round();
                            final labelDate = rangeStart.add(Duration(days: dayOffset));
                            return Text('${labelDate.day}', style: TextStyle(color: mutedColor, fontSize: 8.5));
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF00C98B), shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text('আয়', style: TextStyle(color: mutedColor, fontSize: 10)),
                          const SizedBox(width: 10),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(_money(totalIncome), style: TextStyle(color: textColor, fontSize: 10.5, fontWeight: FontWeight.w800)),
                          ),
                        ]),
                        const SizedBox(height: 5),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFFFF5757), shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text('খরচ', style: TextStyle(color: mutedColor, fontSize: 10)),
                          const SizedBox(width: 10),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(_money(totalExpense), style: TextStyle(color: textColor, fontSize: 10.5, fontWeight: FontWeight.w800)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _incomeExpenseDonuts() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _donutSummaryCard(isIncome: true, monthOffset: _incomeDonutMonthOffset)),
        const SizedBox(width: 8),
        Expanded(child: _donutSummaryCard(isIncome: false, monthOffset: _expenseDonutMonthOffset)),
      ],
    );
  }

  Widget _donutSummaryCard({required bool isIncome, required int monthOffset}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final selectedMonth = DateTime(now.year, now.month - monthOffset);
    final nextMonth = DateTime(selectedMonth.year, selectedMonth.month + 1);
    final totals = <String, double>{};
    for (final tx in _transactions) {
      final date = _parseTransactionDate(tx['dateInput'] ?? tx['date_input'] ?? tx['date'] ?? tx['createdAt'] ?? tx['created_at']);
      if (date == null || date.isBefore(DateTime(selectedMonth.year, selectedMonth.month)) || !date.isBefore(nextMonth)) continue;
      if ((tx['kind'] ?? '').toString() != (isIncome ? 'আয়' : 'ব্যয়')) continue;
      final category = (tx['categoryName'] ?? tx['category_name'] ?? tx['category'] ?? tx['categoryTitle'] ?? tx['category_title'] ?? tx['subcategory'] ?? '').toString().trim();
      final key = category.isEmpty ? 'অন্যান্য' : category;
      totals[key] = (totals[key] ?? 0) + _amount(tx['amount']);
    }
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final shown = entries.take(5).toList();
    final remainder = entries.skip(5).fold<double>(0, (sum, entry) => sum + entry.value);
    if (remainder > 0) {
      final otherIndex = shown.indexWhere((entry) => entry.key == 'অন্যান্য');
      if (otherIndex >= 0) {
        shown[otherIndex] = MapEntry('অন্যান্য', shown[otherIndex].value + remainder);
      } else {
        shown.add(MapEntry('অন্যান্য', remainder));
      }
    }
    final total = entries.fold<double>(0, (sum, entry) => sum + entry.value);
    const palette = <Color>[
      Color(0xFF00B982), Color(0xFFFF625B), Color(0xFFFFA62B),
      Color(0xFF1688D4), Color(0xFFC13EE8), Color(0xFF00C9A7),
    ];
    final title = isIncome ? 'আয়ের উৎস' : 'খরচের বিভাগ';
    final cardColor = isDark ? const Color(0xFF062537) : const Color(0xFFF9FFFC);
    final borderColor = isDark ? const Color(0xFF12605D) : const Color(0xFFD7EEE5);
    final textColor = isDark ? const Color(0xFFDDFBF1) : const Color(0xFF164F40);
    final mutedColor = isDark ? const Color(0xFF9ABBB4) : const Color(0xFF64877C);
    final monthLabel = monthOffset == 0 ? 'এই মাস' : monthOffset == 1 ? 'গত মাস' : '$monthOffset মাস আগে';
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 6, 2),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w800))),
              PopupMenuButton<int>(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 90, maxWidth: 110),
                tooltip: 'মাস নির্বাচন করুন',
                onSelected: (value) => setState(() {
                  if (isIncome) {
                    _incomeDonutMonthOffset = value;
                  } else {
                    _expenseDonutMonthOffset = value;
                  }
                }),
                color: isDark ? const Color(0xFF102A38) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                itemBuilder: (context) => [
                  for (var offset = 0; offset < 6; offset++)
                    PopupMenuItem<int>(
                      value: offset,
                      height: 34,
                      child: Text(offset == 0 ? 'এই মাস' : offset == 1 ? 'গত মাস' : '$offset মাস আগে', style: TextStyle(color: textColor, fontSize: 10.5)),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF00E7A0).withValues(alpha: .12) : const Color(0xFFDDF9EE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(monthLabel, style: TextStyle(color: textColor, fontSize: 9, fontWeight: FontWeight.w700)),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 12, color: textColor),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 80,
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: _DonutSummaryPainter(values: shown.map((entry) => entry.value).toList(), colors: List<Color>.generate(shown.length, (i) => palette[i % palette.length])),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 44,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(_money(total), style: TextStyle(color: textColor, fontSize: 9, fontWeight: FontWeight.w900)),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(isIncome ? 'মোট আয়' : 'মোট খরচ', style: TextStyle(color: mutedColor, fontSize: 7.5)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < shown.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Row(
                            children: [
                              Container(width: 6, height: 6, decoration: BoxDecoration(color: palette[i % palette.length], shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Expanded(child: Text(shown[i].key, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mutedColor, fontSize: 8))),
                              const SizedBox(width: 2),
                              Text(total > 0 ? '${(shown[i].value / total * 100).round()}%' : '0%', style: TextStyle(color: textColor, fontSize: 8, fontWeight: FontWeight.w700)),
                            ],
                          ),
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

  Widget _walletCard(String name, IconData icon, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final balance = _walletBalances[name] ?? 0;
    final formattedBalance = balance.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    final isBikash = name == 'বিকাশ';
    final isNagad = name == 'নগদ';
    final lightGradientColors = isBikash
        ? const [Color(0xFFFFD6E7), Color(0xFFFFF7FA)]
        : isNagad
            ? const [Color(0xFFFFE2C7), Color(0xFFFFFBF6)]
            : name == 'ক্যাশ'
                ? const [Color(0xFFCCF7E7), Color(0xFFF7FFFB)]
                : const [Color(0xFFD7E7FF), Color(0xFFF8FBFF)];
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xB8072638) : null,
        gradient: isDark
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: lightGradientColors,
              ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? accent.withValues(alpha: .48) : lightGradientColors.first.withValues(alpha: .75),
        ),
        boxShadow: isDark
            ? [BoxShadow(color: accent.withValues(alpha: .06), blurRadius: 9, offset: const Offset(0, 3))]
            : [BoxShadow(color: accent.withValues(alpha: .12), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: isBikash
                ? SvgPicture.asset('assets/wallets/bkash-mark.svg', fit: BoxFit.contain)
                : isNagad
                    ? SvgPicture.asset('assets/wallets/nagad-mark.svg', fit: BoxFit.contain)
                    : Icon(icon, color: accent, size: 30),
          ),
          const SizedBox(height: 1),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? const Color(0xFFE8FFF7) : const Color(0xFF155A45), fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 1),
          FittedBox(fit: BoxFit.scaleDown, child: Text(_hidden ? '৳ •••••' : '৳ ' + formattedBalance, maxLines: 1, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF073F32), fontSize: 13, fontWeight: FontWeight.w900))),
        ],
      ),
    );
  }

  void _showDashboardMenu(BuildContext context) {
    final isDark = _appThemeMode.value == ThemeMode.dark;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF0A2527) : Colors.white,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(
            secondary: Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
            title: Text(isDark ? 'Dark Future Mode' : 'Light Mode'),
            subtitle: Text(isDark ? 'Premium dark theme চালু' : 'Light theme চালু'),
            value: isDark,
            onChanged: (value) async {
              await _setAppThemeMode(value ? ThemeMode.dark : ThemeMode.light);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
          ),
          ListTile(leading: const Icon(Icons.refresh_rounded), title: const Text('ডেটা রিফ্রেশ'), onTap: () { Navigator.pop(sheetContext); _load(); }),
          ListTile(leading: const Icon(Icons.dns_outlined), title: const Text('Server Settings'), onTap: () { Navigator.pop(sheetContext); Navigator.of(context).push(_route(const ServerSettingsScreen())); }),
          ListTile(leading: const Icon(Icons.logout_rounded), title: const Text('লগআউট'), onTap: () async { Navigator.pop(sheetContext); await _AuthApi.clearSession(); if (context.mounted) Navigator.of(context).pushAndRemoveUntil(_route(const LoginScreen()), (route) => false); }),
        ]),
      ),
    );
  }
}



class _DonutSummaryPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  const _DonutSummaryPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final side = size.width < size.height ? size.width : size.height;
    final stroke = side * .14;
    final rect = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: side - stroke, height: side - stroke);
    final base = Paint()..color = const Color(0xFF8A9B9A).withValues(alpha: .12)..style = PaintingStyle.stroke..strokeWidth = stroke;
    canvas.drawCircle(rect.center, rect.width / 2, base);
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    var start = -1.57079632679;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 6.28318530718;
      final paint = Paint()
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + sweep,
          colors: [colors[i].withValues(alpha: .72), colors[i], colors[i].withValues(alpha: .9)],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt
        ..strokeWidth = stroke;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutSummaryPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}

class _IncomeExpenseChartPainter extends CustomPainter {
  final List<double> income;
  final List<double> expense;
  final double maxValue;
  final bool isDark;

  const _IncomeExpenseChartPainter({
    required this.income,
    required this.expense,
    required this.maxValue,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final plot = Rect.fromLTWH(0, 4, size.width, size.height - 8);
    final gridPaint = Paint()
      ..color = (isDark ? const Color(0xFF1A5360) : const Color(0xFFDDEFE9)).withValues(alpha: .75)
      ..strokeWidth = .7;
    for (var i = 0; i <= 4; i++) {
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    for (var i = 0; i <= 5; i++) {
      final x = plot.left + plot.width * i / 5;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
    }
    if (income.isEmpty || expense.isEmpty) return;
    final incomePath = _makePath(income, plot, maxValue);
    final expensePath = _makePath(expense, plot, maxValue);
    final incomeFill = Path.from(incomePath)
      ..lineTo(plot.right, plot.bottom)
      ..lineTo(plot.left, plot.bottom)
      ..close();
    final expenseFill = Path.from(expensePath)
      ..lineTo(plot.right, plot.bottom)
      ..lineTo(plot.left, plot.bottom)
      ..close();
    final incomePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF00D99A).withValues(alpha: .42),
          const Color(0xFF00D99A).withValues(alpha: .035),
        ],
      ).createShader(plot);
    final expensePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFF6262).withValues(alpha: .36),
          const Color(0xFFFF6262).withValues(alpha: .025),
        ],
      ).createShader(plot);
    canvas.drawPath(incomeFill, incomePaint);
    canvas.drawPath(expenseFill, expensePaint);
    canvas.drawPath(incomePath, Paint()
      ..color = const Color(0xFF00D99A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(expensePath, Paint()
      ..color = const Color(0xFFFF6262)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    if (income.any((value) => value > 0)) {
      final peakIndex = income.indexOf(income.reduce((a, b) => a > b ? a : b));
      final point = _pointAt(income, peakIndex, plot, maxValue);
      canvas.drawCircle(point, 3, Paint()..color = const Color(0xFF00D99A));
      canvas.drawCircle(point, 5, Paint()..color = const Color(0xFF00D99A).withValues(alpha: .18));
    }
    if (expense.any((value) => value > 0)) {
      final peakIndex = expense.indexOf(expense.reduce((a, b) => a > b ? a : b));
      final point = _pointAt(expense, peakIndex, plot, maxValue);
      canvas.drawCircle(point, 2.5, Paint()..color = const Color(0xFFFF6262));
    }
  }

  Path _makePath(List<double> values, Rect plot, double max) {
    final path = Path();
    if (values.isEmpty) return path;
    for (var i = 0; i < values.length; i++) {
      final point = _pointAt(values, i, plot, max);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        final previous = _pointAt(values, i - 1, plot, max);
        final midX = (previous.dx + point.dx) / 2;
        path.cubicTo(midX, previous.dy, midX, point.dy, point.dx, point.dy);
      }
    }
    return path;
  }

  Offset _pointAt(List<double> values, int index, Rect plot, double max) {
    final x = values.length <= 1 ? plot.left : plot.left + plot.width * index / (values.length - 1);
    final y = plot.bottom - (values[index] / max).clamp(0.0, 1.0) * plot.height;
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _IncomeExpenseChartPainter oldDelegate) =>
      oldDelegate.income != income ||
      oldDelegate.expense != expense ||
      oldDelegate.maxValue != maxValue ||
      oldDelegate.isDark != isDark;
}

class _BalanceNeonChartPainter extends CustomPainter {
  const _BalanceNeonChartPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    // Wave follows the marked path: start low on the left, rise gradually
    // to a modest peak, descend to a shallow valley, then lift slightly.
    final path = Path()
      ..moveTo(0, size.height * .96)
      ..cubicTo(size.width * .14, size.height * .96, size.width * .23, size.height * .92, size.width * .34, size.height * .82)
      ..cubicTo(size.width * .44, size.height * .71, size.width * .52, size.height * .48, size.width * .60, size.height * .46)
      ..cubicTo(size.width * .68, size.height * .44, size.width * .74, size.height * .70, size.width * .82, size.height * .78)
      ..cubicTo(size.width * .90, size.height * .85, size.width * .95, size.height * .72, size.width, size.height * .65);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0x3033FFD0), Color(0x0010AFC7)]
              : const [Color(0x4533D9A0), Color(0x00FFFFFF)],
        ).createShader(Offset.zero & size),
    );

    final secondary = Path()
      ..moveTo(0, size.height * .99)
      ..cubicTo(size.width * .18, size.height * .99, size.width * .28, size.height * .95, size.width * .39, size.height * .88)
      ..cubicTo(size.width * .49, size.height * .80, size.width * .56, size.height * .57, size.width * .63, size.height * .56)
      ..cubicTo(size.width * .72, size.height * .54, size.width * .78, size.height * .77, size.width * .85, size.height * .84)
      ..cubicTo(size.width * .92, size.height * .89, size.width * .97, size.height * .80, size.width, size.height * .74);
    canvas.drawPath(
      secondary,
      Paint()
        ..color = (isDark ? const Color(0xFF00DCC5) : const Color(0xFF13C58B)).withValues(alpha: isDark ? .16 : .08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = (isDark ? const Color(0xFF00E7D2) : const Color(0xFF00B981)).withValues(alpha: isDark ? .60 : .28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = isDark ? const Color(0xFF70FFE2) : const Color(0xFF00B981)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Bars begin at the marked lower baseline and rise only to the marked heights.
    // Tall, clearly visible vertical bars across the marked lower-right area.
    const bars = [12.0, 18.0, 27.0, 39.0, 31.0, 46.0, 34.0, 55.0, 40.0, 49.0, 35.0, 44.0, 24.0, 36.0, 29.0, 47.0, 33.0, 42.0, 28.0, 38.0];
    const barWidth = 7.0;
    const gap = 3.0;
    final totalWidth = bars.length * barWidth + (bars.length - 1) * gap;
    // Keep the expanded group left-shifted while adding six bars on its right.
    final startX = size.width - totalWidth - 20.0;
    for (var i = 0; i < bars.length; i++) {
      final barHeight = bars[i];
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(startX + i * (barWidth + gap), size.height - barHeight, barWidth, barHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = (isDark ? const Color(0xFF00E7A0) : const Color(0xFF16B981)).withValues(alpha: isDark ? .38 : .30),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BalanceNeonChartPainter oldDelegate) => true;
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
  int _step = 0;
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
    _name.dispose();
    _email.dispose();
    _mobile.dispose();
    _password.dispose();
    _confirm.dispose();
    _invite.dispose();
    super.dispose();
  }

  void _nextStep() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _step = 1);
  }

  void _previousStep() {
    FocusScope.of(context).unfocus();
    setState(() => _step = 0);
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

  Widget _buildAccountFields() => Column(children: [
        TextFormField(
          controller: _invite,
          readOnly: widget.verifiedInvite.isNotEmpty,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.groups_2_outlined),
            hintText: 'ইনভাইট কোড',
            suffixIcon: widget.verifiedInvite.isNotEmpty
                ? const Icon(Icons.verified_rounded, color: _blue)
                : null,
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'ইনভাইট কোড দিন।' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.person_outline_rounded),
            hintText: 'আপনার নাম লিখুন',
          ),
          validator: (v) =>
              (v == null || v.trim().length < 2) ? 'সঠিক নাম লিখুন।' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.mail_outline_rounded),
            hintText: 'ইমেইল লিখুন',
          ),
          validator: (v) {
            final s = (v ?? '').trim();
            return s.contains('@') && s.contains('.')
                ? null
                : 'সঠিক ইমেইল লিখুন।';
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.phone_iphone_rounded),
            hintText: 'মোবাইল নম্বর লিখুন',
          ),
          validator: (v) =>
              (v ?? '').replaceAll(RegExp(r'\D'), '').length >= 10
                  ? null
                  : 'সঠিক মোবাইল নম্বর লিখুন।',
        ),
      ]);

  Widget _buildSecurityFields() => Column(children: [
        TextFormField(
          controller: _password,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            hintText: 'পাসওয়ার্ড লিখুন',
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _showPassword = !_showPassword),
              icon: Icon(_showPassword
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded),
            ),
          ),
          validator: (v) => (v ?? '').length >= 8
              ? null
              : 'পাসওয়ার্ড কমপক্ষে ৮ অক্ষরের হতে হবে।',
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _confirm,
          obscureText: !_showConfirm,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            hintText: 'পাসওয়ার্ড আবার লিখুন',
            suffixIcon: IconButton(
              onPressed: () => setState(() => _showConfirm = !_showConfirm),
              icon: Icon(_showConfirm
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded),
            ),
          ),
          validator: (v) =>
              v == _password.text ? null : 'পাসওয়ার্ড দুটি মিলছে না।',
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _acceptedTerms,
          onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: const Text(
            'আমি শর্তাবলি এবং গোপনীয়তা নীতি পড়েছি এবং সম্মত আছি',
            style: TextStyle(fontSize: 11.5, color: _ink, height: 1.4),
          ),
        ),
        CheckboxListTile(
          value: _marketing,
          onChanged: (v) => setState(() => _marketing = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: const Text(
            'আমাকে আপডেট ও গুরুত্বপূর্ণ তথ্য জানাবেন',
            style: TextStyle(fontSize: 11.5, color: _muted),
          ),
        ),
      ]);

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
              const SizedBox(height: 32),
              Transform.translate(
                offset: const Offset(-24, 10),
                child: SizedBox(
                  width: 320,
                  height: 165,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: .30,
                      child: Image.asset(
                        'assets/animations/logo.png',
                        width: 320,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 16, 0),
                child: Row(children: [
                  IconButton(
                    onPressed: _step == 1
                        ? _previousStep
                        : () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: _ink),
                  ),
                  const Spacer(),
                  Text(
                    'ধাপ ${_step + 1}/2',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 2, 22, 22),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _step == 0
                                ? 'অ্যাকাউন্ট তৈরি করুন'
                                : 'অ্যাকাউন্ট সুরক্ষিত করুন',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF075B3A),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            _step == 0
                                ? 'ইনভাইট কোড ও আপনার তথ্য দিন'
                                : 'পাসওয়ার্ড সেট করুন এবং সম্মতি দিন',
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.55,
                              color: _muted,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 17, 16, 18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .95),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF244A88)
                                      .withValues(alpha: .06),
                                  blurRadius: 26,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  if (_step == 0)
                                    _buildAccountFields()
                                  else
                                    _buildSecurityFields(),
                                  const SizedBox(height: 12),
                                  _PrimaryButton(
                                    label: _step == 0
                                        ? 'পরবর্তী ধাপ'
                                        : (_submitting
                                            ? 'অ্যাকাউন্ট তৈরি হচ্ছে...'
                                            : 'অ্যাকাউন্ট তৈরি করুন'),
                                    onPressed: _submitting
                                        ? null
                                        : (_step == 0 ? _nextStep : _submit),
                                  ),
                                  const SizedBox(height: 14),
                                  if (_step == 1)
                                    TextButton.icon(
                                      onPressed: _previousStep,
                                      icon: const Icon(
                                        Icons.arrow_back_rounded,
                                        size: 17,
                                      ),
                                      label: const Text('আগের ধাপে ফিরে যান'),
                                    ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Flexible(
                                        child: Text(
                                          'ইতিমধ্যে অ্যাকাউন্ট আছে? ',
                                          style: TextStyle(
                                            color: _muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () =>
                                            Navigator.of(context).pop(),
                                        child: const Text(
                                          'লগইন করুন',
                                          style: TextStyle(
                                            color: _blue,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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
