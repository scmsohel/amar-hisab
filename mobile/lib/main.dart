import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lottie/lottie.dart';
import 'offline_sync.dart';
import 'wallet_management_screen.dart';
import 'savings_management_screen.dart';

class _ControllerDisposalScope extends StatefulWidget {
  const _ControllerDisposalScope({
    required this.controllers,
    required this.child,
  });

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<_ControllerDisposalScope> createState() => _ControllerDisposalScopeState();
}

class _ControllerDisposalScopeState extends State<_ControllerDisposalScope> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _AuthApi.loadBaseUrl();
  final preferences = await SharedPreferences.getInstance();
  _appThemeMode.value = preferences.getString(_themePreferenceKey) == 'light'
      ? ThemeMode.light
      : ThemeMode.dark;
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: _appThemeMode.value == ThemeMode.dark ? const Color(0xFF071827) : const Color(0xFFF3F8F5),
    statusBarIconBrightness: _appThemeMode.value == ThemeMode.dark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: _appThemeMode.value == ThemeMode.dark ? const Color(0xFF071827) : const Color(0xFFF3F8F5),
    systemNavigationBarIconBrightness: _appThemeMode.value == ThemeMode.dark ? Brightness.light : Brightness.dark,
  ));
  runApp(const AmarHisabApp());
}

const _blue = Color(0xFF287FCB);
const _deepBlue = Color(0xFF1C5F9D);
const _ink = Color(0xFF174A72);
const _muted = Color(0xFF687C78);
const _line = Color(0xFFDCE6F0);

const String _themePreferenceKey = 'amar_hisab_theme_mode';
final ValueNotifier<ThemeMode> _appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);

Future<void> _setAppThemeMode(ThemeMode mode) async {
  _appThemeMode.value = mode;
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(_themePreferenceKey, mode == ThemeMode.light ? 'light' : 'dark');
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: mode == ThemeMode.dark ? const Color(0xFF071827) : const Color(0xFFF3F8F5),
    statusBarIconBrightness: mode == ThemeMode.dark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: mode == ThemeMode.dark ? const Color(0xFF071827) : const Color(0xFFF3F8F5),
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

  static Future<void> cacheTransactions(List<dynamic> items) =>
      OfflineSyncStore.instance.cacheRemoteRecords('transactions', items);

  static Future<List<Map<String, dynamic>>> localTransactions() =>
      OfflineSyncStore.instance.records('transactions');

  static Future<void> saveTransactionOffline(Map<String, dynamic> item) async {
    await OfflineSyncStore.instance.save('transactions', item);
    await trySyncPending();
  }

  static Future<void> deleteTransactionOffline(Map<String, dynamic> item) async {
    final id = (item['_syncId'] ?? item['id'] ?? '').toString();
    if (id.isEmpty) throw Exception('লেনদেনের পরিচয় পাওয়া যায়নি।');
    await OfflineSyncStore.instance.delete('transactions', id);
    await trySyncPending();
  }

  static Future<void> trySyncPending() async {
    final cookie = _sessionCookie;
    final base = _baseUrl;
    if (cookie == null || cookie.isEmpty || base == null) return;
    final engine = OfflineSyncEngine(baseUrl: base, sessionCookie: cookie);
    try { await engine.syncOnce(); } catch (_) {
      // Keep the durable outbox for the next retry.
    } finally { engine.dispose(); }
  }

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

  static Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) async {
    await _ensureConfigured();
    final request = await _client.putUrl(Uri.parse('$_baseUrl$path'));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (_sessionCookie != null) request.headers.set(HttpHeaders.cookieHeader, _sessionCookie!);
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final text = await response.transform(utf8.decoder).join();
    Map<String, dynamic> data = {};
    if (text.isNotEmpty) {
      try { final decoded = jsonDecode(text); if (decoded is Map<String, dynamic>) data = decoded; }
      on FormatException { data = {'error': 'সার্ভার থেকে সঠিক উত্তর পাওয়া যায়নি।'}; }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error']?.toString() ?? 'অনুরোধ ব্যর্থ হয়েছে (${response.statusCode})।');
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
      _get('/data/debts'),
      _get('/data/bills'),
      _get('/data/goals'),
    ]);
    return {
      'user': results[0]['user'], 'wallets': results[1]['data'],
      'transactions': results[2]['data'], 'debts': results[3]['data'],
      'bills': results[4]['data'], 'goals': results[5]['data'],
    };
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
            scaffoldBackgroundColor: const Color(0xFF071827),
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6CCBFF), brightness: Brightness.dark),
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


class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _user = {};
  DateTime? _joinedAt;
  DateTime? _lastSyncAt;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final results = await Future.wait([
        _AuthApi._get('/auth/me'),
        _AuthApi._get('/data/wallets'),
        _AuthApi._get('/data/transactions'),
      ]);
      if (!mounted) return;
      final data = results[0]['user'];
      final joined = data is Map ? (data['createdAt'] ?? data['created_at'] ?? data['joinedAt'] ?? data['joined_at']) : null;
      final synced = data is Map ? (data['lastSyncAt'] ?? data['last_sync_at'] ?? data['syncedAt'] ?? data['synced_at']) : null;
      setState(() {
        _user = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        _joinedAt = joined == null ? null : DateTime.tryParse(joined.toString());
        _lastSyncAt = synced == null ? null : DateTime.tryParse(synced.toString());
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  String _bn(String value) => value
      .replaceAll('0','০').replaceAll('1','১').replaceAll('2','২').replaceAll('3','৩')
      .replaceAll('4','৪').replaceAll('5','৫').replaceAll('6','৬').replaceAll('7','৭')
      .replaceAll('8','৮').replaceAll('9','৯');

  String get _memberSince {
    if (_joinedAt == null) return 'তথ্য পাওয়া যায়নি';
    var years = DateTime.now().year - _joinedAt!.year;
    if (DateTime(DateTime.now().year, _joinedAt!.month, _joinedAt!.day).isAfter(DateTime.now())) years--;
    return years <= 0 ? '১ বছরের কম আগে' : '${_bn(years.toString())} বছর আগে';
  }

  String get _lastSync {
    if (_lastSyncAt == null) return 'তথ্য পাওয়া যায়নি';
    final d = DateTime.now().difference(_lastSyncAt!);
    if (d.inMinutes < 1) return 'এইমাত্র';
    if (d.inHours < 1) return '${_bn(d.inMinutes.toString())} মিনিট আগে';
    if (d.inDays < 1) return '${_bn(d.inHours.toString())} ঘণ্টা আগে';
    return '${_bn(d.inDays.toString())} দিন আগে';
  }

  Future<void> _editPersonalInfo() async {
    final nameController = TextEditingController(text: (_user['name'] ?? '').toString());
    final mobileController = TextEditingController(text: (_user['mobile'] ?? '').toString());
    final formKey = GlobalKey<FormState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF08A66A);
    final surface = dark ? const Color(0xFF12283A) : Colors.white;
    final fieldFill = dark ? const Color(0xFF1B3548) : const Color(0xFFF7FAF9);
    final ink = dark ? const Color(0xFFEAF4F0) : const Color(0xFF142B25);
    final muted = dark ? const Color(0xFFB2C3BC) : const Color(0xFF60756D);
    final line = dark ? const Color(0xFF345346) : const Color(0xFFDCEBE4);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: line.withValues(alpha: .8)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .28 : .12), blurRadius: 30, offset: const Offset(0, 14))],
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: dark ? [const Color(0xFF173A32), surface, surface] : [const Color(0xFFF0FFF7), Colors.white, Colors.white]),
            ),
            child: SingleChildScrollView(child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 54, height: 54, decoration: BoxDecoration(color: accent.withValues(alpha: .12), shape: BoxShape.circle),
                    child: const Icon(Icons.person_rounded, color: accent, size: 29)),
                  const SizedBox(width: 13),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ব্যক্তিগত তথ্য', style: TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('আপনার ব্যক্তিগত তথ্য আপডেট করুন', style: TextStyle(color: muted, fontSize: 11.5)),
                  ])),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: () => Navigator.pop(dialogContext, false),
                    icon: Icon(Icons.close_rounded, color: muted, size: 22)),
                ]),
                const SizedBox(height: 20),
                Text('নাম', style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: nameController,
                  style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'আপনার নাম লিখুন',
                    prefixIcon: Icon(Icons.person_outline_rounded, color: accent, size: 20),
                    filled: true, fillColor: fieldFill, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: line)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: accent, width: 1.4)),
                    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent)),
                    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent)),
                  ),
                  validator: (value) => (value ?? '').trim().length < 2 ? 'কমপক্ষে ২ অক্ষরের নাম দিন।' : null,
                ),
                const SizedBox(height: 14),
                Text('মোবাইল নম্বর', style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: mobileController,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'মোবাইল নম্বর লিখুন',
                    prefixIcon: Icon(Icons.call_outlined, color: accent, size: 20),
                    filled: true, fillColor: fieldFill, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: line)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: accent, width: 1.4)),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(color: accent.withValues(alpha: dark ? .13 : .08), borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const Icon(Icons.mail_outline_rounded, color: accent, size: 21),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('ইমেইল', style: TextStyle(color: muted, fontSize: 10.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text((_user['email'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ])),
                    Icon(Icons.lock_rounded, color: muted, size: 17),
                  ]),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    style: OutlinedButton.styleFrom(foregroundColor: accent, side: BorderSide(color: accent.withValues(alpha: .35)),
                      backgroundColor: accent.withValues(alpha: .05), padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: const StadiumBorder()),
                    child: const Text('বাতিল', style: TextStyle(fontWeight: FontWeight.w700)),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton.icon(
                    onPressed: () { if (formKey.currentState?.validate() ?? false) Navigator.pop(dialogContext, true); },
                    icon: const Icon(Icons.check_rounded, size: 19),
                    label: const Text('সংরক্ষণ', style: TextStyle(fontWeight: FontWeight.w800)),
                    style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13), shape: const StadiumBorder()),
                  )),
                ]),
              ]),
            )),
          ),
        ),
      ),
    );
    if (result != true) { nameController.dispose(); mobileController.dispose(); return; }
    try {
      final response = await _AuthApi._put('/auth/profile', {
        'name': nameController.text.trim(),
        'mobile': mobileController.text.trim(),
      });
      if (!mounted) return;
      final user = response['user'];
      if (user is Map) setState(() => _user = Map<String, dynamic>.from(user));
      _notice(context, 'ব্যক্তিগত তথ্য সংরক্ষণ হয়েছে।');
    } catch (error) {
      if (mounted) _notice(context, error.toString().replaceFirst('Exception: ', ''));
    } finally {
      nameController.dispose();
      mobileController.dispose();
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var hideCurrent = true;
    var hideNext = true;
    var hideConfirm = true;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF08A66A);
    final surface = dark ? const Color(0xFF12283A) : Colors.white;
    final fieldFill = dark ? const Color(0xFF1B3548) : const Color(0xFFF7FAF9);
    final ink = dark ? const Color(0xFFEAF4F0) : const Color(0xFF142B25);
    final muted = dark ? const Color(0xFFB2C3BC) : const Color(0xFF60756D);
    final line = dark ? const Color(0xFF345346) : const Color(0xFFDCEBE4);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) {
        Widget passwordField({
          required TextEditingController controller,
          required String label,
          required bool hidden,
          required VoidCallback toggleVisibility,
          required String? Function(String?) validator,
        }) => TextFormField(
          controller: controller,
          obscureText: hidden,
          style: TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: label,
            hintStyle: TextStyle(color: muted, fontSize: 12.5, fontWeight: FontWeight.w500),
            prefixIcon: Icon(Icons.lock_outline_rounded, color: accent.withValues(alpha: .85), size: 19),
            suffixIcon: IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: toggleVisibility,
              icon: Icon(hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: muted, size: 19),
            ),
            filled: true,
            fillColor: fieldFill,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: accent, width: 1.4)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent)),
            focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent)),
          ),
          validator: validator,
        );

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: line.withValues(alpha: .8)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .28 : .12), blurRadius: 30, offset: const Offset(0, 14))],
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: dark ? [const Color(0xFF173A32), surface, surface] : [const Color(0xFFF0FFF7), Colors.white, Colors.white]),
              ),
              child: SingleChildScrollView(child: Form(
                key: formKey,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 54, height: 54, decoration: BoxDecoration(color: accent.withValues(alpha: .12), shape: BoxShape.circle),
                      child: const Icon(Icons.lock_reset_rounded, color: accent, size: 28)),
                    const SizedBox(width: 13),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('পাসওয়ার্ড পরিবর্তন', style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text('আপনার অ্যাকাউন্ট সুরক্ষিত রাখুন', style: TextStyle(color: muted, fontSize: 11.5)),
                    ])),
                    IconButton(visualDensity: VisualDensity.compact, onPressed: () => Navigator.pop(dialogContext, false),
                      icon: Icon(Icons.close_rounded, color: muted, size: 22)),
                  ]),
                  const SizedBox(height: 18),
                  passwordField(
                    controller: current,
                    label: 'বর্তমান পাসওয়ার্ড',
                    hidden: hideCurrent,
                    toggleVisibility: () => setDialogState(() => hideCurrent = !hideCurrent),
                    validator: (v) => (v ?? '').isEmpty ? 'বর্তমান পাসওয়ার্ড দিন।' : null,
                  ),
                  const SizedBox(height: 10),
                  passwordField(
                    controller: next,
                    label: 'নতুন পাসওয়ার্ড (কমপক্ষে ১২ অক্ষর)',
                    hidden: hideNext,
                    toggleVisibility: () => setDialogState(() => hideNext = !hideNext),
                    validator: (v) => (v ?? '').length < 12 ? 'নতুন পাসওয়ার্ড কমপক্ষে ১২ অক্ষরের হতে হবে।' : null,
                  ),
                  const SizedBox(height: 10),
                  passwordField(
                    controller: confirm,
                    label: 'নতুন পাসওয়ার্ড আবার লিখুন',
                    hidden: hideConfirm,
                    toggleVisibility: () => setDialogState(() => hideConfirm = !hideConfirm),
                    validator: (v) => v != next.text ? 'পাসওয়ার্ড দুটি মিলছে না।' : null,
                  ),
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: OutlinedButton.styleFrom(foregroundColor: accent, side: BorderSide(color: accent.withValues(alpha: .35)),
                        backgroundColor: accent.withValues(alpha: .05), padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: const StadiumBorder()),
                      child: const Text('বাতিল', style: TextStyle(fontWeight: FontWeight.w700)),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton(
                      onPressed: () { if (formKey.currentState?.validate() ?? false) Navigator.pop(dialogContext, true); },
                      style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13), shape: const StadiumBorder()),
                      child: const Text('পরিবর্তন করুন', style: TextStyle(fontWeight: FontWeight.w800)),
                    )),
                  ]),
                ]),
              )),
            ),
          ),
        );
      }),
    );
    if (result != true) { current.dispose(); next.dispose(); confirm.dispose(); return; }
    try {
      await _AuthApi._post('/auth/password', {'currentPassword': current.text, 'newPassword': next.text});
      if (mounted) _notice(context, 'পাসওয়ার্ড পরিবর্তন হয়েছে।');
    } catch (error) {
      if (mounted) _notice(context, error.toString().replaceFirst('Exception: ', ''));
    } finally {
      current.dispose(); next.dispose(); confirm.dispose();
    }
  }

  Future<void> _notificationSettings() async {
    final preferences = await SharedPreferences.getInstance();
    var transactions = preferences.getBool('profile_notify_transactions') ?? true;
    var bills = preferences.getBool('profile_notify_bills') ?? true;
    var reminders = preferences.getBool('profile_notify_reminders') ?? true;
    if (!mounted) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF08A66A);
    final surface = dark ? const Color(0xFF12283A) : Colors.white;
    final ink = dark ? const Color(0xFFEAF4F0) : const Color(0xFF142B25);
    final muted = dark ? const Color(0xFFB2C3BC) : const Color(0xFF60756D);
    final line = dark ? const Color(0xFF345346) : const Color(0xFFDCEBE4);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) {
        Widget preferenceRow({required IconData icon, required Color tint, required String title, required String subtitle,
          required bool value, required ValueChanged<bool> onChanged}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: tint.withValues(alpha: .11), shape: BoxShape.circle),
              child: Icon(icon, color: tint, size: 21)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(color: muted, fontSize: 10.5), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: 8),
            Switch.adaptive(value: value, activeTrackColor: accent, onChanged: onChanged),
          ]),
        );
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                color: surface, borderRadius: BorderRadius.circular(28), border: Border.all(color: line.withValues(alpha: .8)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .28 : .12), blurRadius: 30, offset: const Offset(0, 14))],
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: dark ? [const Color(0xFF173A32), surface, surface] : [const Color(0xFFF0FFF7), Colors.white, Colors.white]),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Container(width: 54, height: 54, decoration: BoxDecoration(color: accent.withValues(alpha: .12), shape: BoxShape.circle),
                    child: const Icon(Icons.notifications_active_rounded, color: accent, size: 27)),
                  const SizedBox(width: 13),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('নোটিফিকেশন পছন্দ', style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('কোন কোন নোটিফিকেশন পেতে চান', style: TextStyle(color: muted, fontSize: 11.5)),
                  ])),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: () => Navigator.pop(dialogContext),
                    icon: Icon(Icons.close_rounded, color: muted, size: 22)),
                ]),
                const SizedBox(height: 14),
                preferenceRow(icon: Icons.swap_horiz_rounded, tint: const Color(0xFF08A66A), title: 'লেনদেনের আপডেট',
                  subtitle: 'নতুন লেনদেনের তথ্য জানান', value: transactions,
                  onChanged: (v) async { setDialogState(() => transactions = v); await preferences.setBool('profile_notify_transactions', v); }),
                Divider(height: 1, color: line),
                preferenceRow(icon: Icons.calendar_month_rounded, tint: const Color(0xFF1688F8), title: 'বিলের রিমাইন্ডার',
                  subtitle: 'বিলের তারিখের আগে মনে করিয়ে দেবে', value: bills,
                  onChanged: (v) async { setDialogState(() => bills = v); await preferences.setBool('profile_notify_bills', v); }),
                Divider(height: 1, color: line),
                preferenceRow(icon: Icons.shield_outlined, tint: const Color(0xFF0AAE75), title: 'অন্যান্য সতর্কতা',
                  subtitle: 'গুরুত্বপূর্ণ আপডেট ও নিরাপত্তা সতর্কতা', value: reminders,
                  onChanged: (v) async { setDialogState(() => reminders = v); await preferences.setBool('profile_notify_reminders', v); }),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: accent.withValues(alpha: dark ? .14 : .08), borderRadius: BorderRadius.circular(15)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline_rounded, color: accent, size: 19),
                    const SizedBox(width: 9),
                    Expanded(child: Text('এই পছন্দগুলো আপনার ডিভাইসে সংরক্ষিত থাকবে। Push Notification পেতে অ্যাপের অনুমতি ও সার্ভার সাপোর্ট প্রয়োজন।',
                      style: TextStyle(color: muted, fontSize: 10.5, height: 1.45))),
                  ]),
                ),
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerRight, child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: OutlinedButton.styleFrom(foregroundColor: accent, side: BorderSide(color: accent.withValues(alpha: .35)),
                    backgroundColor: accent.withValues(alpha: .05), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: const StadiumBorder()),
                  child: const Text('বন্ধ করুন', style: TextStyle(fontWeight: FontWeight.w700)),
                )),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _chooseTheme() async {
    final current = _appThemeMode.value;
    var selectedTheme = current;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF08A66A);
    final surface = dark ? const Color(0xFF12283A) : Colors.white;
    final ink = dark ? const Color(0xFFEAF4F0) : const Color(0xFF142B25);
    final muted = dark ? const Color(0xFFB2C3BC) : const Color(0xFF60756D);
    final line = dark ? const Color(0xFF345346) : const Color(0xFFDCEBE4);
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) {
        Widget themeCard({required ThemeMode mode, required String title, required IconData icon, required bool isDark}) {
          final active = selectedTheme == mode;
          final previewBg = isDark ? const Color(0xFF102B2A) : const Color(0xFFF1FBF6);
          final previewSurface = isDark ? const Color(0xFF1E4540) : Colors.white;
          return Expanded(child: InkWell(
            borderRadius: BorderRadius.circular(19),
            onTap: () => setDialogState(() => selectedTheme = mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 13),
              decoration: BoxDecoration(
                color: active ? accent.withValues(alpha: dark ? .16 : .07) : surface,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: active ? accent : line, width: active ? 1.6 : 1),
              ),
              child: Column(children: [
                Row(children: [
                  Icon(icon, color: isDark ? const Color(0xFF607D8B) : const Color(0xFFE6A800), size: 22),
                  const Spacer(),
                  Icon(active ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: active ? accent : muted, size: 20),
                ]),
                const SizedBox(height: 11),
                Container(
                  height: 72, width: double.infinity, padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: previewBg, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(height: 7, width: 48, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(5))),
                    const SizedBox(height: 7),
                    Container(height: 22, decoration: BoxDecoration(color: previewSurface, borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: Container(height: 9, decoration: BoxDecoration(color: accent.withValues(alpha: .65), borderRadius: BorderRadius.circular(5)))),
                      const SizedBox(width: 5),
                      Expanded(child: Container(height: 9, decoration: BoxDecoration(color: previewSurface, borderRadius: BorderRadius.circular(5)))),
                    ]),
                  ]),
                ),
                const SizedBox(height: 10),
                Text(title, style: TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(isDark ? 'চোখের জন্য আরামদায়ক' : 'উজ্জ্বল ও পরিষ্কার ইন্টারফেস',
                  textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 10, height: 1.35)),
              ]),
            ),
          ));
        }
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                color: surface, borderRadius: BorderRadius.circular(28), border: Border.all(color: line.withValues(alpha: .8)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .28 : .12), blurRadius: 30, offset: const Offset(0, 14))],
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: dark ? [const Color(0xFF173A32), surface, surface] : [const Color(0xFFF0FFF7), Colors.white, Colors.white]),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Container(width: 54, height: 54, decoration: BoxDecoration(color: accent.withValues(alpha: .12), shape: BoxShape.circle),
                    child: const Icon(Icons.palette_rounded, color: accent, size: 27)),
                  const SizedBox(width: 13),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('অ্যাপের থিম', style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('আপনার পছন্দের থিম নির্বাচন করুন', style: TextStyle(color: muted, fontSize: 11.5)),
                  ])),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: () => Navigator.pop(dialogContext),
                    icon: Icon(Icons.close_rounded, color: muted, size: 22)),
                ]),
                const SizedBox(height: 18),
                Row(children: [
                  themeCard(mode: ThemeMode.light, title: 'লাইট মোড', icon: Icons.light_mode_rounded, isDark: false),
                  const SizedBox(width: 10),
                  themeCard(mode: ThemeMode.dark, title: 'ডার্ক মোড', icon: Icons.dark_mode_rounded, isDark: true),
                ]),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: OutlinedButton.styleFrom(foregroundColor: accent, side: BorderSide(color: accent.withValues(alpha: .35)),
                      backgroundColor: accent.withValues(alpha: .05), padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: const StadiumBorder()),
                    child: const Text('বাতিল', style: TextStyle(fontWeight: FontWeight.w700)),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, selectedTheme),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('প্রয়োগ করুন', style: TextStyle(fontWeight: FontWeight.w800)),
                    style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13), shape: const StadiumBorder()),
                  )),
                ]),
              ]),
            ),
          ),
        );
      }),
    );
    if (selected != null) await _setAppThemeMode(selected);
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'আমার হিসাব',
      applicationVersion: '0.1.0+1',
      applicationIcon: const Icon(Icons.account_balance_wallet_rounded, size: 34, color: Color(0xFF08A66A)),
      children: const [
        Text('ব্যক্তিগত আয়-ব্যয়ের হিসাব, ওয়ালেট, সঞ্চয় ও আর্থিক ব্যবস্থাপনার অ্যাপ।'),
        SizedBox(height: 8),
        Text('গোপনীয়তা: আপনার আর্থিক তথ্য আপনার অ্যাকাউন্টের সঙ্গে সার্ভারে সংরক্ষিত থাকে।'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF071827) : const Color(0xFFF4FAF8);
    final surface = dark ? const Color(0xFF12283A) : Colors.white;
    final ink = dark ? const Color(0xFFEAF4FF) : const Color(0xFF111827);
    final muted = dark ? const Color(0xFFB2C3D5) : const Color(0xFF405274);
    final line = dark ? const Color(0xFF30485D) : const Color(0xFFE3EAF1);
    final name = (_user['name'] ?? _user['fullName'] ?? _user['full_name'] ?? 'ব্যবহারকারী').toString();
    final email = (_user['email'] ?? '').toString();
    final photo = (_user['avatarUrl'] ?? _user['avatar_url'] ?? _user['photoUrl'] ?? _user['photo_url'] ?? '').toString();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: bg,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: bg,
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
                child: Row(children: [
                  IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: ink, size: 29)),
                  Expanded(child: Text('প্রোফাইল', style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w900))),
                  _actionIcon(dark ? Icons.wb_sunny_rounded : Icons.nightlight_round, muted, () => _setAppThemeMode(dark ? ThemeMode.light : ThemeMode.dark)),
                  const SizedBox(width: 8),
                  _actionIcon(Icons.settings_rounded, const Color(0xFF1688F8), () => Navigator.of(context).push(_route(const ServerSettingsScreen()))),
                ]),
              ),
              Expanded(
                child: Stack(children: [
                  Positioned.fill(child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: dark ? const [Color(0xFF0B2534), Color(0xFF071827), Color(0xFF102A32)] : const [Color(0xFFEFFFF7), Color(0xFFFAFCFF), Color(0xFFF0FAF7)]),
                  )))),
                  RefreshIndicator(
                    onRefresh: _loadProfile,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 3, 12, 7),
                      children: [
                        Center(child: Stack(clipBehavior: Clip.none, children: [
                          Container(
                            width: 88, height: 88, padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFB9EED5), width: 5),
                              boxShadow: [BoxShadow(color: const Color(0xFF22B86B).withValues(alpha: .13), blurRadius: 18, spreadRadius: 2)]),
                            child: Container(
                              decoration: BoxDecoration(shape: BoxShape.circle, color: dark ? const Color(0xFF203B50) : const Color(0xFFE8F5EF),
                                border: Border.all(color: surface, width: 4),
                                image: photo.isNotEmpty ? DecorationImage(image: NetworkImage(photo), fit: BoxFit.cover) : null),
                              child: photo.isEmpty ? Icon(Icons.person_rounded, size: 64, color: dark ? const Color(0xFF9CCDEB) : const Color(0xFF1688F8)) : null,
                            ),
                          ),
                          Positioned(right: 0, bottom: 4, child: Material(
                            color: const Color(0xFF08B83D), shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 3)), elevation: 3,
                            child: InkWell(customBorder: const CircleBorder(), onTap: () => _notice(context, 'প্রোফাইল ছবি আপলোডের জন্য Backend Upload API প্রয়োজন।'),
                              child: const SizedBox(width: 32, height: 32, child: Icon(Icons.edit_rounded, color: Colors.white, size: 17))),
                          )),
                        ])),
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Flexible(child: Text(_loading ? 'লোড হচ্ছে...' : name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w900))),
                          const SizedBox(width: 9),
                          const Icon(Icons.verified_rounded, color: Color(0xFF0DBB39), size: 34),
                        ]),
                        const SizedBox(height: 2),
                        Center(child: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 14))),
                        const SizedBox(height: 10),
                        if ((_user['role'] ?? '').toString().toLowerCase() == 'admin') ...[
                          Center(child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                            decoration: BoxDecoration(
                              color: dark ? const Color(0xFF173A32) : const Color(0xFFE8F8EF),
                              borderRadius: BorderRadius.circular(40),
                              border: Border.all(color: const Color(0xFF08A66A).withValues(alpha: .45), width: 1.1),
                              boxShadow: [BoxShadow(color: const Color(0xFF08A66A).withValues(alpha: .10), blurRadius: 9, offset: const Offset(0, 4))]),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.verified_rounded, color: Color(0xFF08A66A), size: 19), SizedBox(width: 8),
                              Text('Owner', style: TextStyle(color: Color(0xFF078653), fontSize: 13, fontWeight: FontWeight.w800)),
                            ]),
                          )),
                          const SizedBox(height: 10),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                          decoration: BoxDecoration(color: dark ? const Color(0xFF142C3D) : const Color(0xFFFFFCF9),
                            borderRadius: BorderRadius.circular(25), border: Border.all(color: dark ? const Color(0xFF38556A) : const Color(0xFFE8C9DD)),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 12, offset: const Offset(0, 4))]),
                          child: Row(children: [
                            Expanded(child: _info(Icons.calendar_month_rounded, 'সদস্য হয়েছেন', _memberSince, dark)),
                            _infoDivider(dark),
                            Expanded(child: _info(Icons.cloud_done_rounded, 'সর্বশেষ Sync', _lastSync, dark)),
                            _infoDivider(dark),
                            Expanded(child: _info(Icons.check_circle_rounded, 'সব ডেটা', _loading ? 'যাচাই হচ্ছে' : 'Sync Status', dark)),
                          ]),
                        ),
                        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(28),
                            boxShadow: [BoxShadow(color: const Color(0xFF345A64).withValues(alpha: dark ? .10 : .12), blurRadius: 18, offset: const Offset(0, 8))]),
                          child: Column(children: [
                            _menuRow(Icons.person_rounded, const Color(0xFF1688F8), 'ব্যক্তিগত তথ্য', 'নাম, মোবাইল নম্বর ও ইমেইল', _editPersonalInfo, dark, ink, muted, line),
                            _menuRow(Icons.verified_user_rounded, const Color(0xFF10B83F), 'নিরাপত্তা', 'পাসওয়ার্ড পরিবর্তন', _changePassword, dark, ink, muted, line),
                            _menuRow(Icons.notifications_active_rounded, const Color(0xFFFFB000), 'নোটিফিকেশন', 'লেনদেন, বিল ও অন্যান্য সতর্কতা', _notificationSettings, dark, ink, muted, line),
                            _menuRow(Icons.palette_rounded, const Color(0xFF9B35E8), 'থিম', 'লাইট ও ডার্ক মোড পরিবর্তন', _chooseTheme, dark, ink, muted, line),
                            _menuRow(Icons.info_rounded, const Color(0xFF1688F8), 'অ্যাপ সম্পর্কে', 'ভার্সন 0.1.0 • গোপনীয়তা নীতি', _showAbout, dark, ink, muted, line, last: true),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 5, 16, 10),
                child: SizedBox(width: double.infinity, height: 46, child: OutlinedButton.icon(
                  onPressed: () async {
                    await _AuthApi.clearSession();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(_route(const LoginScreen()), (route) => false);
                  },
                  icon: const Icon(Icons.logout_rounded, size: 25),
                  label: const Text('লগ আউট', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE91E35),
                    backgroundColor: dark ? const Color(0xFF351D2A) : const Color(0xFFFFF0F2),
                    side: const BorderSide(color: Color(0xFFFF5266), width: 1.2), shape: const StadiumBorder()),
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionIcon(IconData icon, Color color, VoidCallback onTap) => Material(
    color: color.withValues(alpha: .08), shape: const CircleBorder(),
    child: InkWell(customBorder: const CircleBorder(), onTap: onTap,
      child: SizedBox(width: 36, height: 36, child: Icon(icon, color: color, size: 20))),
  );

  Widget _info(IconData icon, String heading, String value, bool dark) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Column(children: [
      Icon(icon, color: const Color(0xFF1688F8), size: 23), const SizedBox(height: 5),
      Text(heading, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: dark ? Colors.white : const Color(0xFF111827), fontSize: 9, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFF1688F8).withValues(alpha: .10), borderRadius: BorderRadius.circular(18)),
        child: Text(value, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: dark ? const Color(0xFFD7E9FF) : const Color(0xFF173B91), fontSize: 8, fontWeight: FontWeight.w800))),
    ]),
  );

  Widget _infoDivider(bool dark) => Container(width: 1, height: 36, color: dark ? const Color(0xFF42617B) : const Color(0xFF55A9F2));

  Widget _menuRow(IconData icon, Color accent, String heading, String subtitle, VoidCallback onTap,
      bool dark, Color ink, Color muted, Color line, {bool last = false}) => Column(children: [
    InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: accent.withValues(alpha: .13), shape: BoxShape.circle),
          child: Icon(icon, color: accent, size: 24)),
        const SizedBox(width: 17),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(heading, style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 10.5)),
        ])),
        Icon(Icons.chevron_right_rounded, color: dark ? const Color(0xFFB7C9DA) : const Color(0xFF34466E), size: 23),
      ]),
    )),
    if (!last) Padding(padding: const EdgeInsets.only(left: 55), child: Divider(height: 1, thickness: 1, color: line)),
  ]);
}

class _DebtsScreen extends StatefulWidget {
  const _DebtsScreen({required this.debts, required this.onReload, this.wallets = const ['ক্যাশ','ব্যাংক','বিকাশ','নগদ']});
  final List<Map<String, dynamic>> debts;
  final List<String> wallets;
  final Future<List<Map<String, dynamic>>> Function() onReload;
  @override
  State<_DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<_DebtsScreen> {
  final TextEditingController _search = TextEditingController();
  late List<Map<String, dynamic>> _items;
  String _kind = 'সব ধরনের', _status = 'সব স্ট্যাটাস', _period = 'সব সময়', _sort = 'সর্বশেষ আগে';
  bool _loading = false;
  @override
  void initState() { super.initState(); _items = List<Map<String, dynamic>>.from(widget.debts); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse((v ?? '').toString()) ?? 0;
  DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
  String _kindOf(Map<String,dynamic> e) => (e['debtKind'] ?? e['kind'] ?? e['status'] ?? '').toString();
  String _name(Map<String,dynamic> e) => (e['personName'] ?? e['name'] ?? e['person'] ?? e['title'] ?? 'নাম নেই').toString();
  double _paid(Map<String,dynamic> e) {
    final p = e['payments'] is List ? e['payments'] as List : <dynamic>[];
    return p.whereType<Map>().where((b) => (b['eventType'] ?? '') != 'withdrawal').fold<double>(0, (a,b) => a + _num(b['amount']));
  }
  double _left(Map<String,dynamic> e) => (_num(e['amount']) - _paid(e)).clamp(0,double.infinity).toDouble();
  DateTime? _due(Map<String,dynamic> e) => _date(e['nextDate'] ?? e['dueDate'] ?? e['nextPaymentDate'] ?? e['due_date']);
  bool _done(Map<String,dynamic> e) => ['পরিশোধিত','সম্পন্ন'].contains((e['status'] ?? '').toString());
  String _dateLabel(DateTime? d) {
    if (d == null) return 'তারিখ নেই';
    const m = ['জানু','ফেব্রু','মার্চ','এপ্রিল','মে','জুন','জুলাই','আগস্ট','সেপ্টে','অক্টো','নভে','ডিসে'];
    return '${d.day.toString().padLeft(2,'0')} ${m[d.month-1]}, ${d.year}';
  }
  Future<void> _refresh() async {
    setState(() => _loading = true);
    try { final data = await widget.onReload(); if (!mounted) return; setState(() { _items = data; _loading = false; }); }
    catch (e) { if (!mounted) return; setState(() => _loading = false); _notice(context,e.toString().replaceFirst('Exception: ','')); }
  }
  void _todo(String label) => _notice(context,'$label সুবিধাটি API সংযোগসহ পরবর্তী ধাপে যুক্ত করতে হবে।');

  Future<void> _openCreateDebtModal({bool credit = false}) async {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final installmentController = TextEditingController();
    final noteController = TextEditingController();
    var kind = credit ? 'দেনা' : 'পাওনা';
    var rule = credit ? 'installment' : 'one-time';
    var frequency = 'monthly';
    var iconName = credit ? 'CreditCard' : 'Banknote';
    var entryDate = DateTime.now();
    var saving = false;
    var saved = false;
    String? error;
    String dateValue(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    String dateLabel(DateTime d) => '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    if (!mounted) {
      amountController.dispose();
      noteController.dispose();
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setModal) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.of(ctx).size.height * .88),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(credit ? 'নতুন ক্রেডিট হিসাব' : 'নতুন হিসাব', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                  IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close)),
                ]),
                const Text('আপনার তথ্য অ্যাকাউন্টে সংরক্ষিত হবে।', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                const SizedBox(height: 12),
                Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ব্যক্তি/বিবরণ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  TextField(controller: nameController, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'নাম বা বিবরণ')),
                  const SizedBox(height: 12),
                  const Text('আইকন নির্বাচন', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Builder(builder: (selectorContext) {
                    final iconOptions = <(String, IconData)>[
                      ('Briefcase', Icons.work_outline_rounded), ('Banknote', Icons.payments_outlined),
                      ('CircleDollarSign', Icons.monetization_on_outlined), ('Coins', Icons.toll_outlined),
                      ('CreditCard', Icons.credit_card_outlined), ('Wallet', Icons.account_balance_wallet_outlined),
                      ('WalletCards', Icons.wallet_outlined), ('HandCoins', Icons.volunteer_activism_outlined),
                      ('BadgeDollarSign', Icons.price_check_rounded), ('ReceiptText', Icons.receipt_long_outlined),
                      ('ChartNoAxesCombined', Icons.query_stats_rounded), ('TrendingUp', Icons.trending_up_rounded),
                      ('TrendingDown', Icons.trending_down_rounded), ('Calculator', Icons.calculate_outlined),
                      ('Percent', Icons.percent_rounded), ('Store', Icons.storefront_outlined),
                      ('ShoppingCart', Icons.shopping_cart_outlined), ('ShoppingBag', Icons.shopping_bag_outlined),
                      ('ShoppingBasket', Icons.shopping_basket_outlined), ('Tag', Icons.sell_outlined),
                      ('Gift', Icons.card_giftcard_outlined), ('Package', Icons.inventory_2_outlined),
                      ('PackageOpen', Icons.unarchive_outlined), ('House', Icons.home_outlined),
                      ('BedDouble', Icons.bed_outlined), ('Sofa', Icons.weekend_outlined),
                      ('Lamp', Icons.light_outlined), ('Lightbulb', Icons.lightbulb_outline_rounded),
                      ('Plug', Icons.power_outlined), ('HousePlug', Icons.electrical_services_outlined),
                      ('Droplets', Icons.water_drop_outlined), ('Flame', Icons.local_fire_department_outlined),
                      ('Wifi', Icons.wifi_rounded), ('Smartphone', Icons.smartphone_rounded),
                      ('Laptop', Icons.laptop_outlined), ('Monitor', Icons.desktop_windows_outlined),
                      ('Tv', Icons.tv_outlined), ('Router', Icons.router_outlined),
                      ('Printer', Icons.print_outlined), ('Camera', Icons.camera_alt_outlined),
                      ('Headphones', Icons.headphones_outlined), ('Gamepad2', Icons.sports_esports_outlined),
                      ('Car', Icons.directions_car_outlined), ('CarFront', Icons.directions_car_filled_outlined),
                      ('Bus', Icons.directions_bus_outlined), ('BusFront', Icons.directions_bus_filled_outlined),
                      ('Train', Icons.train_outlined), ('Bike', Icons.pedal_bike_outlined),
                      ('Plane', Icons.flight_outlined), ('PlaneTakeoff', Icons.flight_takeoff_rounded),
                      ('Ship', Icons.directions_boat_outlined), ('Fuel', Icons.local_gas_station_outlined),
                      ('MapPin', Icons.location_on_outlined), ('Route', Icons.alt_route_rounded),
                      ('Utensils', Icons.restaurant_outlined), ('UtensilsCrossed', Icons.restaurant_menu_rounded),
                      ('CookingPot', Icons.soup_kitchen_outlined), ('Coffee', Icons.coffee_outlined),
                      ('Pizza', Icons.local_pizza_outlined), ('Salad', Icons.eco_outlined),
                      ('Sandwich', Icons.lunch_dining_outlined), ('Cake', Icons.cake_outlined),
                      ('IceCream', Icons.icecream_outlined), ('Apple', Icons.apple_rounded),
                      ('Carrot', Icons.grass_rounded), ('Pill', Icons.medication_outlined),
                      ('Stethoscope', Icons.medical_services_outlined), ('HeartPulse', Icons.monitor_heart_outlined),
                      ('Cross', Icons.add_rounded), ('Syringe', Icons.vaccines_outlined),
                      ('Hospital', Icons.local_hospital_outlined), ('Bandage', Icons.healing_outlined),
                      ('Dumbbell', Icons.fitness_center_rounded), ('GraduationCap', Icons.school_outlined),
                      ('BookOpen', Icons.menu_book_outlined), ('Book', Icons.book_outlined),
                      ('School', Icons.cast_for_education_outlined), ('Notebook', Icons.note_alt_outlined),
                      ('FileText', Icons.description_outlined), ('Music', Icons.music_note_rounded),
                      ('Film', Icons.movie_outlined), ('Clapperboard', Icons.video_camera_back_outlined),
                      ('Theater', Icons.theater_comedy_outlined), ('Popcorn', Icons.local_movies_outlined),
                      ('PartyPopper', Icons.celebration_outlined), ('Ticket', Icons.confirmation_number_outlined),
                      ('Trophy', Icons.emoji_events_outlined), ('Turtle', Icons.pets_outlined),
                      ('Dog', Icons.pets_rounded), ('Cat', Icons.pets_rounded),
                      ('PawPrint', Icons.pets_outlined), ('Bone', Icons.cruelty_free_outlined),
                      ('Shirt', Icons.checkroom_outlined), ('Footprints', Icons.directions_walk_rounded),
                      ('Watch', Icons.watch_outlined), ('Glasses', Icons.visibility_outlined),
                      ('Gem', Icons.diamond_outlined), ('Users', Icons.groups_outlined),
                      ('Baby', Icons.child_care_outlined), ('Heart', Icons.favorite_border_rounded),
                      ('Flower2', Icons.local_florist_outlined), ('Sprout', Icons.grass_outlined),
                      ('TreePine', Icons.park_outlined), ('Leaf', Icons.eco_outlined),
                      ('Sun', Icons.wb_sunny_outlined), ('CloudRain', Icons.cloudy_snowing),
                      ('Snowflake', Icons.ac_unit_rounded), ('Umbrella', Icons.umbrella_outlined),
                      ('Wrench', Icons.build_outlined), ('Hammer', Icons.handyman_outlined),
                      ('Paintbrush', Icons.brush_outlined), ('Scissors', Icons.content_cut_rounded),
                      ('Trash2', Icons.delete_outline_rounded), ('Recycle', Icons.recycling_rounded),
                      ('CalendarDays', Icons.calendar_month_outlined), ('Clock', Icons.schedule_rounded),
                      ('Bell', Icons.notifications_none_rounded), ('ShieldCheck', Icons.verified_user_outlined),
                      ('KeyRound', Icons.key_outlined), ('Ellipsis', Icons.more_horiz_rounded),
                    ];
                    final selected = iconOptions.firstWhere((e) => e.$1 == iconName, orElse: () => iconOptions[1]);
                    return Row(children: [
                      Container(width: 38, height: 38, decoration: BoxDecoration(
                        color: const Color(0xFF059669).withValues(alpha: .10), borderRadius: BorderRadius.circular(10)),
                        child: Icon(selected.$2, color: const Color(0xFF059669), size: 21)),
                      const SizedBox(width: 9),
                      Expanded(child: PopupMenuButton<String>(
                        tooltip: 'আইকন বেছে নিন',
                        onSelected: (value) => setModal(() => iconName = value),
                        itemBuilder: (menuContext) => [
                          PopupMenuItem<String>(
                            enabled: false, padding: const EdgeInsets.all(8),
                            child: Builder(builder: (popupContext) => SizedBox(
                              width: 300, height: 220,
                              child: GridView.builder(
                                padding: EdgeInsets.zero, itemCount: iconOptions.length,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 6, mainAxisSpacing: 5, crossAxisSpacing: 5),
                                itemBuilder: (gridContext, index) {
                                  final entry = iconOptions[index];
                                  final isSelected = iconName == entry.$1;
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => Navigator.of(popupContext).pop(entry.$1),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFF059669).withValues(alpha: .12) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: isSelected ? const Color(0xFF059669) : Colors.transparent)),
                                      child: Icon(entry.$2, size: 22, color: isSelected ? const Color(0xFF059669) : Colors.blueGrey)),
                                  );
                                },
                              ),
                            )),
                          ),
                        ],
                        child: Container(height: 42, decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0))),
                          child: const Center(child: Icon(Icons.grid_view_rounded, color: Color(0xFF1E293B), size: 21))),
                      )),
                    ]);
                  }),
                  const SizedBox(height: 12),
                  if (!credit) ...[
                    const Text('মোট দেনা/পাওনা (৳)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: '৳ 0')),
                    const SizedBox(height: 12),
                  ],
                  const Text('হিসাবের নিয়ম', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<String>(
                    initialValue: rule,
                    items: [
                      const DropdownMenuItem(value: 'one-time', child: Text('সহজ হিসাব (একবার)')),
                      DropdownMenuItem(value: 'installment', child: Text(credit ? 'মাসিক হিসাব' : 'কিস্তির হিসাব')),
                    ],
                    onChanged: (v) => setModal(() => rule = v ?? 'one-time'),
                  ),
                  if (rule == 'installment') ...[
                    if (!credit) ...[
                      const SizedBox(height: 12),
                      const Text('প্রতি কিস্তির পরিমাণ (৳)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      TextField(controller: installmentController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: '৳ 0')),
                    ],
                    const SizedBox(height: 12),
                    const Text('কিস্তির বিরতি', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    DropdownButtonFormField<String>(
                      initialValue: frequency,
                      items: const [
                        DropdownMenuItem(value: 'weekly', child: Text('প্রতি সপ্তাহে')),
                        DropdownMenuItem(value: 'monthly', child: Text('প্রতি মাসে')),
                      ],
                      onChanged: (v) => setModal(() => frequency = v ?? 'monthly'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(rule == 'installment' ? 'প্রথম কিস্তির তারিখ' : 'তারিখ (দিন/মাস/বছর)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final selected = await showDatePicker(context: dialogContext, initialDate: entryDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                      if (selected != null && ctx.mounted) setModal(() => entryDate = selected);
                    },
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(dateLabel(entryDate)),
                  ),
                  const SizedBox(height: 4),
                  const Text('তারিখ নির্বাচন করুন। Save করার আগে তারিখ যাচাই হবে।', style: TextStyle(fontSize: 10, color: Colors.blueGrey)),
                  const SizedBox(height: 12),
                  const Text('ধরন', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    items: const [
                      DropdownMenuItem(value: 'পাওনা', child: Text('পাওনা')),
                      DropdownMenuItem(value: 'দেনা', child: Text('দেনা')),
                    ],
                    onChanged: (v) => setModal(() => kind = v ?? 'পাওনা'),
                  ),
                  const SizedBox(height: 12),
                  const Text('নোট', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  TextField(controller: noteController, maxLines: 2, decoration: const InputDecoration(hintText: 'ঐচ্ছিক নোট')),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ]))),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('বাতিল'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.icon(
                    onPressed: saving ? null : () async {
                      final name = nameController.text.trim();
                      final total = double.tryParse(amountController.text.trim());
                      final per = double.tryParse(installmentController.text.trim());
                      if (name.isEmpty || (!credit && (total == null || !total.isFinite || total <= 0))) {
                        setModal(() => error = 'সঠিক নাম ও টাকার পরিমাণ দিন।');
                        return;
                      }
                      if (!credit && rule == 'installment' && (per == null || !per.isFinite || per <= 0 || per > total!)) {
                        setModal(() => error = 'কিস্তির পরিমাণ মোট দেনা-পাওনার চেয়ে বেশি হতে পারবে না।');
                        return;
                      }
                      setModal(() { saving = true; error = null; });
                      try {
                        final response = await _AuthApi._get('/data/debts');
                        final records = (response['data'] as List).map((x) => Map<String,dynamic>.from(x as Map)).toList();
                        final id = DateTime.now().millisecondsSinceEpoch;
                        final chosenDate = dateValue(entryDate);
                        final item = <String,dynamic>{
                          'id': id,
                          'title': name,
                          'personName': name,
                          'name': name,
                          'amount': credit ? 0 : total,
                          'date': chosenDate,
                          'dateInput': chosenDate,
                          'icon': iconName,
                          'status': kind,
                          'debtKind': kind,
                          if (credit) 'debtLabel': 'ক্রেডিট কার্ড',
                          'debtRule': rule,
                          'notes': noteController.text.trim(),
                          'updatedAt': dateLabel(DateTime.now()),
                          'payments': <Map<String,dynamic>>[],
                          if (!credit && rule == 'installment') 'installmentAmount': per,
                          if (rule == 'installment') 'installmentFrequency': frequency,
                          if (rule == 'installment') 'firstInstallmentDate': chosenDate,
                          if (!credit && rule == 'installment') 'totalInstallments': (total! / per!).ceil(),
                        };
                        records.insert(0, item);
                        await _AuthApi._put('/data/debts', {'data': records});
                        if (!dialogContext.mounted) return;
                        saved = true;
                        Navigator.pop(dialogContext);
                      } catch (e) {
                        if (!dialogContext.mounted) return;
                        setModal(() { saving = false; error = e.toString().replaceFirst('Exception: ', ''); });
                      }
                    },
                    icon: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check, size: 16),
                    label: Text(saving ? 'সংরক্ষণ হচ্ছে...' : 'সংরক্ষণ'),
                  )),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    nameController.dispose();
    amountController.dispose();
    installmentController.dispose();
    noteController.dispose();
    if (saved && mounted) {
      await _refresh();
      if (mounted) _notice(context, credit ? 'নতুন ক্রেডিট হিসাব সংরক্ষণ হয়েছে।' : 'নতুন দেনা-পাওনার হিসাব সংরক্ষণ হয়েছে।');
    }
  }

  Future<void> _openEditDebtModal(Map<String,dynamic> debt) async {
    final nameController = TextEditingController(text: (debt['personName'] ?? debt['name'] ?? debt['person'] ?? debt['title'] ?? '').toString());
    final amountController = TextEditingController(text: (debt['amount'] ?? '').toString());
    final installmentController = TextEditingController(text: (debt['installmentAmount'] ?? debt['installment_amount'] ?? '').toString());
    final noteController = TextEditingController(text: (debt['notes'] ?? debt['note'] ?? '').toString());
    var kind = (debt['debtKind'] ?? debt['kind'] ?? debt['status'] ?? 'পাওনা').toString();
    if (!['পাওনা','দেনা'].contains(kind)) kind = 'পাওনা';
    var rule = (debt['debtRule'] ?? debt['accountType'] ?? 'one-time').toString();
    if (!['one-time','installment'].contains(rule)) rule = rule.contains('কিস্তি') ? 'installment' : 'one-time';
    var frequency = (debt['installmentFrequency'] ?? debt['installment_frequency'] ?? 'monthly').toString();
    if (!['weekly','monthly'].contains(frequency)) frequency = 'monthly';
    var iconName = (debt['icon'] ?? 'Banknote').toString();
    var entryDate = DateTime.tryParse((debt['date'] ?? debt['dateInput'] ?? '').toString()) ?? DateTime.now();
    var saving = false;
    var saved = false;
    String? error;
    String dateValue(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    String dateLabel(DateTime d) => '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setModal) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.of(ctx).size.height * .88),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(child: Text('রেকর্ড সম্পাদনা', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                  IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close)),
                ]),
                const Text('আপনার তথ্য অ্যাকাউন্টে সংরক্ষিত হবে।', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                const SizedBox(height: 12),
                Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ব্যক্তি/বিবরণ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  TextField(controller: nameController, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'নাম বা বিবরণ')),
                  const SizedBox(height: 12),
                  const Text('আইকন নির্বাচন', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Builder(builder: (selectorContext) {
                    final iconOptions = <(String, IconData)>[
                      ('Briefcase', Icons.work_outline_rounded), ('Banknote', Icons.payments_outlined),
                      ('CircleDollarSign', Icons.monetization_on_outlined), ('Coins', Icons.toll_outlined),
                      ('CreditCard', Icons.credit_card_outlined), ('Wallet', Icons.account_balance_wallet_outlined),
                      ('WalletCards', Icons.wallet_outlined), ('HandCoins', Icons.volunteer_activism_outlined),
                      ('BadgeDollarSign', Icons.price_check_rounded), ('ReceiptText', Icons.receipt_long_outlined),
                      ('ChartNoAxesCombined', Icons.query_stats_rounded), ('TrendingUp', Icons.trending_up_rounded),
                      ('TrendingDown', Icons.trending_down_rounded), ('Calculator', Icons.calculate_outlined),
                      ('Percent', Icons.percent_rounded), ('Store', Icons.storefront_outlined),
                      ('ShoppingCart', Icons.shopping_cart_outlined), ('ShoppingBag', Icons.shopping_bag_outlined),
                      ('ShoppingBasket', Icons.shopping_basket_outlined), ('Tag', Icons.sell_outlined),
                      ('Gift', Icons.card_giftcard_outlined), ('Package', Icons.inventory_2_outlined),
                      ('PackageOpen', Icons.unarchive_outlined), ('House', Icons.home_outlined),
                      ('BedDouble', Icons.bed_outlined), ('Sofa', Icons.weekend_outlined),
                      ('Lamp', Icons.light_outlined), ('Lightbulb', Icons.lightbulb_outline_rounded),
                      ('Plug', Icons.power_outlined), ('HousePlug', Icons.electrical_services_outlined),
                      ('Droplets', Icons.water_drop_outlined), ('Flame', Icons.local_fire_department_outlined),
                      ('Wifi', Icons.wifi_rounded), ('Smartphone', Icons.smartphone_rounded),
                      ('Laptop', Icons.laptop_outlined), ('Monitor', Icons.desktop_windows_outlined),
                      ('Tv', Icons.tv_outlined), ('Router', Icons.router_outlined),
                      ('Printer', Icons.print_outlined), ('Camera', Icons.camera_alt_outlined),
                      ('Headphones', Icons.headphones_outlined), ('Gamepad2', Icons.sports_esports_outlined),
                      ('Car', Icons.directions_car_outlined), ('CarFront', Icons.directions_car_filled_outlined),
                      ('Bus', Icons.directions_bus_outlined), ('BusFront', Icons.directions_bus_filled_outlined),
                      ('Train', Icons.train_outlined), ('Bike', Icons.pedal_bike_outlined),
                      ('Plane', Icons.flight_outlined), ('PlaneTakeoff', Icons.flight_takeoff_rounded),
                      ('Ship', Icons.directions_boat_outlined), ('Fuel', Icons.local_gas_station_outlined),
                      ('MapPin', Icons.location_on_outlined), ('Route', Icons.alt_route_rounded),
                      ('Utensils', Icons.restaurant_outlined), ('UtensilsCrossed', Icons.restaurant_menu_rounded),
                      ('CookingPot', Icons.soup_kitchen_outlined), ('Coffee', Icons.coffee_outlined),
                      ('Pizza', Icons.local_pizza_outlined), ('Salad', Icons.eco_outlined),
                      ('Sandwich', Icons.lunch_dining_outlined), ('Cake', Icons.cake_outlined),
                      ('IceCream', Icons.icecream_outlined), ('Apple', Icons.apple_rounded),
                      ('Carrot', Icons.grass_rounded), ('Pill', Icons.medication_outlined),
                      ('Stethoscope', Icons.medical_services_outlined), ('HeartPulse', Icons.monitor_heart_outlined),
                      ('Cross', Icons.add_rounded), ('Syringe', Icons.vaccines_outlined),
                      ('Hospital', Icons.local_hospital_outlined), ('Bandage', Icons.healing_outlined),
                      ('Dumbbell', Icons.fitness_center_rounded), ('GraduationCap', Icons.school_outlined),
                      ('BookOpen', Icons.menu_book_outlined), ('Book', Icons.book_outlined),
                      ('School', Icons.cast_for_education_outlined), ('Notebook', Icons.note_alt_outlined),
                      ('FileText', Icons.description_outlined), ('Music', Icons.music_note_rounded),
                      ('Film', Icons.movie_outlined), ('Clapperboard', Icons.video_camera_back_outlined),
                      ('Theater', Icons.theater_comedy_outlined), ('Popcorn', Icons.local_movies_outlined),
                      ('PartyPopper', Icons.celebration_outlined), ('Ticket', Icons.confirmation_number_outlined),
                      ('Trophy', Icons.emoji_events_outlined), ('Turtle', Icons.pets_outlined),
                      ('Dog', Icons.pets_rounded), ('Cat', Icons.pets_rounded),
                      ('PawPrint', Icons.pets_outlined), ('Bone', Icons.cruelty_free_outlined),
                      ('Shirt', Icons.checkroom_outlined), ('Footprints', Icons.directions_walk_rounded),
                      ('Watch', Icons.watch_outlined), ('Glasses', Icons.visibility_outlined),
                      ('Gem', Icons.diamond_outlined), ('Users', Icons.groups_outlined),
                      ('Baby', Icons.child_care_outlined), ('Heart', Icons.favorite_border_rounded),
                      ('Flower2', Icons.local_florist_outlined), ('Sprout', Icons.grass_outlined),
                      ('TreePine', Icons.park_outlined), ('Leaf', Icons.eco_outlined),
                      ('Sun', Icons.wb_sunny_outlined), ('CloudRain', Icons.cloudy_snowing),
                      ('Snowflake', Icons.ac_unit_rounded), ('Umbrella', Icons.umbrella_outlined),
                      ('Wrench', Icons.build_outlined), ('Hammer', Icons.handyman_outlined),
                      ('Paintbrush', Icons.brush_outlined), ('Scissors', Icons.content_cut_rounded),
                      ('Trash2', Icons.delete_outline_rounded), ('Recycle', Icons.recycling_rounded),
                      ('CalendarDays', Icons.calendar_month_outlined), ('Clock', Icons.schedule_rounded),
                      ('Bell', Icons.notifications_none_rounded), ('ShieldCheck', Icons.verified_user_outlined),
                      ('KeyRound', Icons.key_outlined), ('Ellipsis', Icons.more_horiz_rounded),
                    ];
                    final selected = iconOptions.firstWhere((e) => e.$1 == iconName, orElse: () => iconOptions[1]);
                    return Row(children: [
                      Container(width: 38, height: 38, decoration: BoxDecoration(
                        color: const Color(0xFF059669).withValues(alpha: .10), borderRadius: BorderRadius.circular(10)),
                        child: Icon(selected.$2, color: const Color(0xFF059669), size: 21)),
                      const SizedBox(width: 9),
                      Expanded(child: PopupMenuButton<String>(
                        tooltip: 'আইকন বেছে নিন',
                        onSelected: (value) => setModal(() => iconName = value),
                        itemBuilder: (menuContext) => [
                          PopupMenuItem<String>(
                            enabled: false, padding: const EdgeInsets.all(8),
                            child: Builder(builder: (popupContext) => SizedBox(
                              width: 300, height: 220,
                              child: GridView.builder(
                                padding: EdgeInsets.zero, itemCount: iconOptions.length,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 6, mainAxisSpacing: 5, crossAxisSpacing: 5),
                                itemBuilder: (gridContext, index) {
                                  final entry = iconOptions[index];
                                  final isSelected = iconName == entry.$1;
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => Navigator.of(popupContext).pop(entry.$1),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFF059669).withValues(alpha: .12) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: isSelected ? const Color(0xFF059669) : Colors.transparent)),
                                      child: Icon(entry.$2, size: 22, color: isSelected ? const Color(0xFF059669) : Colors.blueGrey)),
                                  );
                                },
                              ),
                            )),
                          ),
                        ],
                        child: Container(height: 42, decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0))),
                          child: const Center(child: Icon(Icons.grid_view_rounded, color: Color(0xFF1E293B), size: 21))),
                      )),
                    ]);
                  }),
                  const SizedBox(height: 12),
                  const Text('মোট দেনা/পাওনা (৳)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: '৳ 0')),
                  const SizedBox(height: 12),
                  const Text('হিসাবের নিয়ম', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<String>(
                    initialValue: rule,
                    items: const [
                      DropdownMenuItem(value: 'one-time', child: Text('সহজ হিসাব (একবার)')),
                      DropdownMenuItem(value: 'installment', child: Text('কিস্তির হিসাব')),
                    ],
                    onChanged: (v) => setModal(() => rule = v ?? 'one-time'),
                  ),
                  if (rule == 'installment') ...[
                    const SizedBox(height: 12),
                    const Text('প্রতি কিস্তির পরিমাণ (৳)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    TextField(controller: installmentController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: '৳ 0')),
                    const SizedBox(height: 12),
                    const Text('কিস্তির বিরতি', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    DropdownButtonFormField<String>(
                      initialValue: frequency,
                      items: const [
                        DropdownMenuItem(value: 'weekly', child: Text('প্রতি সপ্তাহে')),
                        DropdownMenuItem(value: 'monthly', child: Text('প্রতি মাসে')),
                      ],
                      onChanged: (v) => setModal(() => frequency = v ?? 'monthly'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(rule == 'installment' ? 'প্রথম কিস্তির তারিখ' : 'তারিখ (দিন/মাস/বছর)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final selected = await showDatePicker(context: dialogContext, initialDate: entryDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                      if (selected != null && ctx.mounted) setModal(() => entryDate = selected);
                    },
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(dateLabel(entryDate)),
                  ),
                  const SizedBox(height: 4),
                  const Text('তারিখ নির্বাচন করুন। Save করার আগে তারিখ যাচাই হবে।', style: TextStyle(fontSize: 10, color: Colors.blueGrey)),
                  const SizedBox(height: 12),
                  const Text('ধরন', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    items: const [
                      DropdownMenuItem(value: 'পাওনা', child: Text('পাওনা')),
                      DropdownMenuItem(value: 'দেনা', child: Text('দেনা')),
                    ],
                    onChanged: (v) => setModal(() => kind = v ?? 'পাওনা'),
                  ),
                  const SizedBox(height: 12),
                  const Text('নোট', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  TextField(controller: noteController, maxLines: 2, decoration: const InputDecoration(hintText: 'ঐচ্ছিক নোট')),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ]))),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('বাতিল'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.icon(
                    onPressed: saving ? null : () async {
                      final name = nameController.text.trim();
                      final total = double.tryParse(amountController.text.trim());
                      final per = double.tryParse(installmentController.text.trim());
                      if (name.isEmpty || total == null || !total.isFinite || total <= 0) {
                        setModal(() => error = 'সঠিক নাম ও টাকার পরিমাণ দিন।');
                        return;
                      }
                      if (rule == 'installment' && (per == null || !per.isFinite || per <= 0 || per > total)) {
                        setModal(() => error = 'কিস্তির পরিমাণ মোট দেনা-পাওনার চেয়ে বেশি হতে পারবে না।');
                        return;
                      }
                      setModal(() { saving = true; error = null; });
                      try {
                        final response = await _AuthApi._get('/data/debts');
                        final records = (response['data'] as List).map((x) => Map<String,dynamic>.from(x as Map)).toList();
                        final chosenDate = dateValue(entryDate);
                        final existingPayments = debt['payments'] is List ? List<dynamic>.from(debt['payments'] as List) : <dynamic>[];
                        if (total < _paid(debt)) {
                          setModal(() { saving = false; error = 'মোট টাকা ইতিমধ্যে পরিশোধিত টাকার চেয়ে কম হতে পারবে না।'; });
                          return;
                        }
                        final item = <String,dynamic>{
                          ...debt,
                          'id': debt['id'],
                          'title': name,
                          'personName': name,
                          'name': name,
                          'amount': total,
                          'date': chosenDate,
                          'dateInput': chosenDate,
                          'icon': iconName,
                          'status': kind,
                          'debtKind': kind,
                          'debtRule': rule,
                          'notes': noteController.text.trim(),
                          'updatedAt': dateLabel(DateTime.now()),
                          'payments': existingPayments,
                          if (rule == 'installment') 'installmentAmount': per,
                          if (rule == 'installment') 'installmentFrequency': frequency,
                          if (rule == 'installment') 'firstInstallmentDate': chosenDate,
                          if (rule == 'installment') 'totalInstallments': (total / per!).ceil(),
                        };
                        final recordIndex = records.indexWhere((record) => record['id'].toString() == debt['id'].toString());
                        if (recordIndex < 0) throw Exception('রেকর্ডটি পাওয়া যায়নি। তালিকা Refresh করে আবার চেষ্টা করুন।');
                        records[recordIndex] = item;
                        await _AuthApi._put('/data/debts', {'data': records});
                        if (!dialogContext.mounted) return;
                        saved = true;
                        Navigator.pop(dialogContext);
                      } catch (e) {
                        if (!dialogContext.mounted) return;
                        setModal(() { saving = false; error = e.toString().replaceFirst('Exception: ', ''); });
                      }
                    },
                    icon: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check, size: 16),
                    label: Text(saving ? 'সংরক্ষণ হচ্ছে...' : 'পরিবর্তন সংরক্ষণ করুন'),
                  )),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    nameController.dispose();
    amountController.dispose();
    installmentController.dispose();
    noteController.dispose();
    if (saved && mounted) {
      await _refresh();
      if (mounted) _notice(context, 'দেনা-পাওনার তথ্য আপডেট হয়েছে।');
    }
  }

  Future<void> _openPaymentModal(Map<String,dynamic> debt) async {
    final amount=TextEditingController(), note=TextEditingController();
    final payments=(debt['payments'] is List?(debt['payments'] as List).whereType<Map>().map((p)=>Map<String,dynamic>.from(p)).toList():<Map<String,dynamic>>[]);
    final wallets=widget.wallets.isEmpty?['ক্যাশ','ব্যাংক','বিকাশ','নগদ']:widget.wallets;
    var wallet='ক্যাশ', date=DateTime.now(), saving=false, saved=false, withdrawalMode=false;
    final isCredit = debt['debtLabel'] == 'ক্রেডিট কার্ড';
    String? savedMessage;
    int? editing;
    String dateLabel(DateTime d)=>'${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    double paid()=>payments.where((p)=>(p['eventType']??'')!='withdrawal').fold<double>(0,(s,p)=>s+_num(p['amount']));
    await showDialog<void>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(ctx,setModal)=>Dialog(
      insetPadding:const EdgeInsets.symmetric(horizontal:16,vertical:22),
      child:ConstrainedBox(constraints:BoxConstraints(maxWidth:520,maxHeight:(MediaQuery.of(ctx).size.height-MediaQuery.of(ctx).viewInsets.bottom-44).clamp(240.0,MediaQuery.of(ctx).size.height*.88)),
        child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.max,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text(_name(debt),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))),IconButton(onPressed:()=>Navigator.pop(dialogContext),icon:const Icon(Icons.close))]),
          Text(isCredit ? 'ক্রেডিট কার্ডের ব্যবহার ও পরিশোধের হিসাব' : _kindOf(debt)=='দেনা'?'আপনার পরিশোধ করতে হবে':'আপনার পাওনা আদায় করতে হবে',style:TextStyle(fontSize:11,color:Colors.grey.shade600)),
          const SizedBox(height:12),
          Row(children:[
            for(final entry in [(isCredit?'ব্যবহৃত ক্রেডিট':'মূল হিসাব',_num(debt['amount']),const Color(0xFF172B43)),('পরিশোধিত',paid(),const Color(0xFF00A875)),('এখনো বাকি',(_num(debt['amount'])-paid()).clamp(0,double.infinity).toDouble(),const Color(0xFFFF625B))])
              Expanded(child:Container(margin:const EdgeInsets.only(right:5),padding:const EdgeInsets.all(9),decoration:BoxDecoration(color:const Color(0xFFF6F8FA),borderRadius:BorderRadius.circular(11)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(entry.$1,style:const TextStyle(fontSize:10,color:Colors.blueGrey)),Text('৳ ${entry.$2.round()}',style:TextStyle(fontSize:14,fontWeight:FontWeight.w900,color:entry.$3))]))),
          ]),
          const SizedBox(height:12),
          ClipRRect(borderRadius:BorderRadius.circular(8),child:LinearProgressIndicator(value:_num(debt['amount'])<=0?0:(paid()/_num(debt['amount'])).clamp(0,1),minHeight:6,color:const Color(0xFF00A875),backgroundColor:const Color(0xFFE6EBF0))),
          const SizedBox(height:12),
          Row(children:[const Expanded(child:Text('পরিশোধের ইতিহাস',style:TextStyle(fontSize:14,fontWeight:FontWeight.w900))),Text('${payments.length}টি লেনদেন',style:const TextStyle(fontSize:10,color:Colors.blueGrey))]),
          const SizedBox(height:6),
          Expanded(child:Container(padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:Theme.of(ctx).brightness==Brightness.dark?const Color(0xFF10291F):const Color(0xFFEAF8F2),borderRadius:BorderRadius.circular(12)),child:payments.isEmpty?const Center(child:Text('এখনো কোনো লেনদেন যোগ করা হয়নি।',style:TextStyle(fontSize:11,color:Colors.blueGrey))):ListView.separated(shrinkWrap:false,physics:const AlwaysScrollableScrollPhysics(),itemCount:payments.length,separatorBuilder:(_,_)=>const SizedBox(height:8),itemBuilder:(context,i){final p=payments[i];final dark=Theme.of(context).brightness==Brightness.dark;final withdrawal=p['eventType']=='withdrawal';return Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:7),decoration:BoxDecoration(color:dark?const Color(0xFF19372B):Colors.white,borderRadius:BorderRadius.circular(11),border:Border.all(color:dark?const Color(0xFF2B5141):const Color(0xFFE2EEE7)),boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:dark ? 0.08 : 0.035),blurRadius:7,offset:const Offset(0,2))]),child:Row(children:[Container(width:34,height:34,decoration:BoxDecoration(color:withdrawal?const Color(0xFFEAF2FF):const Color(0xFFE8F7EF),borderRadius:BorderRadius.circular(10)),child:Icon(withdrawal?Icons.south_west_rounded:Icons.account_balance_wallet_rounded,size:18,color:withdrawal?const Color(0xFF3978C8):const Color(0xFF159568))),const SizedBox(width:8),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${withdrawal?'উত্তোলন':'পরিশোধ'} · ${p['date']??''}',maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:11.5,fontWeight:FontWeight.w800,color:dark?const Color(0xFFE7F2EE):const Color(0xFF263B35))),Text((p['wallet']??'ক্যাশ').toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:10,color:dark?const Color(0xFFA5BDB3):const Color(0xFF71847C))),if((p['notes']??'').toString().isNotEmpty)Text(p['notes'].toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:9,color:dark?const Color(0xFFA5BDB3):const Color(0xFF71847C)))])),Text('৳ ${_num(p['amount']).round()}',style:TextStyle(fontSize:11.5,fontWeight:FontWeight.w900,color:withdrawal?const Color(0xFF3978C8):(dark?const Color(0xFF7DDBB0):const Color(0xFF159568)))),IconButton(visualDensity:VisualDensity.compact,padding:EdgeInsets.zero,constraints:const BoxConstraints.tightFor(width:30,height:30),onPressed:(p['eventType']=='withdrawal')?null:(){setModal((){withdrawalMode=false;editing=_num(p['id']).toInt();amount.text=_num(p['amount']).toString();note.text=(p['notes']??'').toString();wallet=(p['wallet']??'ক্যাশ').toString();date=DateTime.tryParse((p['dateInput']??'').toString())??date;});},icon:const Icon(Icons.edit_outlined,size:17)),IconButton(visualDensity:VisualDensity.compact,padding:EdgeInsets.zero,constraints:const BoxConstraints.tightFor(width:30,height:30),onPressed:()async{final yes=await showDialog<bool>(context:dialogContext,builder:(c)=>AlertDialog(title:Text(p['eventType']=='withdrawal'?'উত্তোলন মুছুন':'পরিশোধ মুছুন'),content:Text(p['eventType']=='withdrawal'?'এই উত্তোলন মুছলে ব্যবহৃত ক্রেডিট ও ওয়ালেটের হিসাব থেকে টাকাটি বাদ হবে।':'এই পরিশোধের রেকর্ড মুছে ফেলবেন?'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('বাতিল')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('মুছুন'))]));if(yes!=true){return;}try{final dr=await _AuthApi._get('/data/debts'),tr=await _AuthApi._get('/data/transactions');final ds=(dr['data'] as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();final ts=(tr['data'] as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();final next=payments.where((x)=>x['id'].toString()!=p['id'].toString()).toList();final sum=next.where((x)=>(x['eventType']??'')!='withdrawal').fold<double>(0,(s,x)=>s+_num(x['amount']));final nextAmount=isCredit&&p['eventType']=='withdrawal'?(_num(debt['amount'])-_num(p['amount'])).clamp(0,double.infinity).toDouble():_num(debt['amount']);final ix=ds.indexWhere((x)=>x['id'].toString()==debt['id'].toString());ds[ix]={...ds[ix],'amount':nextAmount,'payments':next,'status':(isCredit?nextAmount>0: true)&&sum>=nextAmount?'পরিশোধিত':_kindOf(debt)};if(p['transactionId']!=null){ts.removeWhere((x)=>x['id'].toString()==p['transactionId'].toString());}await _AuthApi._put('/data/debts',{'data':ds});await _AuthApi._put('/data/transactions',{'data':ts});payments.removeWhere((x)=>x['id'].toString()==p['id'].toString());setModal((){});await _refresh();}catch(e){if(!dialogContext.mounted){return;}_notice(dialogContext,e.toString());}},icon:const Icon(Icons.delete_outline,size:17,color:Colors.red))]));}))),
          const SizedBox(height:10),
          if(isCredit) SegmentedButton<bool>(segments:const [ButtonSegment(value:false,label:Text('পরিশোধ')),ButtonSegment(value:true,label:Text('উত্তোলন'))],selected:{withdrawalMode},onSelectionChanged:editing==null?(v)=>setModal(()=>withdrawalMode=v.first):null),
          Text(editing==null?(withdrawalMode?'ক্রেডিট উত্তোলন যোগ করুন':'পরিশোধ / জমা যোগ করুন'):'পরিশোধের তথ্য এডিট করুন',style:const TextStyle(fontSize:14,fontWeight:FontWeight.w900)),
          const SizedBox(height:6),
          Flexible(child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
            TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'পরিমাণ (৳)',hintText:'0.00')),
            Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()async{final d=await showDatePicker(context:dialogContext,initialDate:date,firstDate:DateTime(2000),lastDate:DateTime(2100));if(d!=null)setModal(()=>date=d);},icon:const Icon(Icons.calendar_today_outlined,size:15),label:Text(dateLabel(date)))),const SizedBox(width:6),Expanded(child:DropdownButtonFormField<String>(initialValue:wallets.contains(wallet)?wallet:'ক্যাশ',decoration:const InputDecoration(labelText:'ওয়ালেট'),items:wallets.map((w)=>DropdownMenuItem(value:w,child:Text(w))).toList(),onChanged:(v){if(v!=null)setModal(()=>wallet=v);} ))]),
            TextField(controller:note,maxLines:2,decoration:const InputDecoration(labelText:'নোট (ঐচ্ছিক)')),
          ]))),
          const SizedBox(height:10),
          SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:saving?null:()async{final formattedTime=TimeOfDay.now().format(context);final value=double.tryParse(amount.text.trim());if(value==null||value<=0){_notice(context,'সঠিক পরিমাণ দিন।');return;}final old=editing==null?null:payments.where((p)=>p['id'].toString()==editing.toString()).firstOrNull;if(!withdrawalMode && value>(_num(debt['amount'])-paid()+_num(old?['amount']))){_notice(context,'বাকি টাকার চেয়ে বেশি পরিশোধ করা যাবে না।');return;}setModal(()=>saving=true);try{final dr=await _AuthApi._get('/data/debts'),tr=await _AuthApi._get('/data/transactions');final ds=(dr['data'] as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();final ts=(tr['data'] as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();final id=editing??DateTime.now().millisecondsSinceEpoch;final txid=old?['transactionId']??(id+1);final item={'id':id,'amount':value,'date':dateLabel(date),'dateInput':'${date.year.toString().padLeft(4,'0')}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}','wallet':wallet,'notes':note.text.trim(),'transactionId':txid,if(withdrawalMode)'eventType':'withdrawal'};final next=editing==null?[...payments,item]:payments.map((p)=>p['id'].toString()==editing.toString()?item:p).toList();final sum=next.where((p)=>(p['eventType']??'')!='withdrawal').fold<double>(0,(s,p)=>s+_num(p['amount']));final nextAmount=withdrawalMode?_num(debt['amount'])+value:_num(debt['amount']);final ix=ds.indexWhere((x)=>x['id'].toString()==debt['id'].toString());ds[ix]={...ds[ix],'amount':nextAmount,'payments':next,'status':sum>=nextAmount?'পরিশোধিত':_kindOf(debt)};final kind=withdrawalMode?'আয়':_kindOf(debt)=='দেনা'?'ব্যয়':'আয়';final tx={'id':txid,'title':withdrawalMode?'ক্রেডিট কার্ড উত্তোলন — ${_name(debt)}':'${kind=='ব্যয়'?'দেনা পরিশোধ — ':'পাওনা জমা — '}${_name(debt)}','category':'দেনা-পাওনা','date':dateLabel(date),'dateInput':'${date.year.toString().padLeft(4,'0')}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}','time':formattedTime,'wallet':wallet,'amount':value,'kind':kind,'icon':(debt['icon']??debt['iconName']??debt['icon_name']??'Banknote').toString(),'debtId':debt['id'],'debtPaymentId':id,'debtEventType':withdrawalMode?'withdrawal':'payment','note':note.text.trim()};final ti=ts.indexWhere((x)=>x['id'].toString()==txid.toString());if(ti<0){ts.insert(0,tx);}else{ts[ti]=tx;}await _AuthApi._put('/data/debts',{'data':ds});await _AuthApi._put('/data/transactions',{'data':ts});if(!dialogContext.mounted){return;}saved=true;savedMessage=withdrawalMode?'ক্রেডিট উত্তোলন সংরক্ষণ হয়েছে।':editing==null?'পরিশোধ যোগ হয়েছে।':'পরিশোধ আপডেট হয়েছে।';Navigator.pop(dialogContext);}catch(e){if(!dialogContext.mounted){return;}setModal(()=>saving=false);_notice(dialogContext,e.toString().replaceFirst('Exception: ',''));}},icon:saving?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.check),label:Text(saving?'সংরক্ষণ হচ্ছে...':editing==null?'পরিশোধ সংরক্ষণ':'পরিবর্তন সংরক্ষণ করুন'))),
        ]))),
    )));
    // Wait until the dialog route has completed its removal before disposing
    // controllers still referenced by the TextField elements.
    await WidgetsBinding.instance.endOfFrame;
    amount.dispose();
    note.dispose();
    if(saved && mounted){
      await _refresh();
      if(mounted && savedMessage!=null){_notice(context,savedMessage!);}
    }
  }

  Widget _pill(String label, Color fg, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal:8,vertical:5),
    decoration: BoxDecoration(color:bg,borderRadius:BorderRadius.circular(18)),
    child: Text(label,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:fg,fontSize:10,fontWeight:FontWeight.w800)));
  Widget _filter(String value,List<String> values,ValueChanged<String> change) => Expanded(child: DropdownButtonFormField<String>(
    initialValue:value,isExpanded:true,decoration:const InputDecoration(contentPadding:EdgeInsets.symmetric(horizontal:8,vertical:9)),
    items:values.map((v)=>DropdownMenuItem(value:v,child:Text(v,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11)))).toList(),
    onChanged:(v){if(v!=null)setState(()=>change(v));}));
  @override
  Widget build(BuildContext context) {
    final dark=Theme.of(context).brightness==Brightness.dark;
    final bg=dark?const Color(0xFF071827):const Color(0xFFF5F7FB);
    final surface=dark?const Color(0xFF10283D):Colors.white;
    final muted=dark?const Color(0xFFA4B8CA):const Color(0xFF8191A4);
    final line=dark?const Color(0xFF294158):const Color(0xFFE4EAF1);
    const green=Color(0xFF00A875), red=Color(0xFFFF4D55), blue=Color(0xFF287FF5), purple=Color(0xFF9657F5);
    final q=_search.text.trim().toLowerCase();
    final rows=_items.where((e){
      final k=_kindOf(e), done=_done(e), due=_due(e);
      if(q.isNotEmpty && !('${_name(e)} ${(e['note']??'').toString()}').toLowerCase().contains(q)) return false;
      if(_kind!='সব ধরনের' && k!=_kind) return false;
      if(_status=='চলমান' && done || _status=='সম্পন্ন' && !done) return false;
      if(_period=='বকেয়া' && (due==null || !due.isBefore(DateTime.now()))) return false;
      if(_period=='আসন্ন' && (due==null || due.isBefore(DateTime.now()))) return false;
      return true;
    }).toList();
    rows.sort((a,b){
      final da=_date(a['date']??a['dateInput']??a['createdAt'])??DateTime(2000);
      final db=_date(b['date']??b['dateInput']??b['createdAt'])??DateTime(2000);
      if(_sort=='পুরনো আগে') return da.compareTo(db);
      if(_sort=='বেশি টাকা আগে') return _left(b).compareTo(_left(a));
      if(_sort=='কম টাকা আগে') return _left(a).compareTo(_left(b));
      return db.compareTo(da);
    });
    final receivable=_items.where((e)=>_kindOf(e)=='পাওনা'&&!_done(e)).fold<double>(0,(a,e)=>a+_left(e));
    final payable=_items.where((e)=>_kindOf(e)=='দেনা'&&!_done(e)).fold<double>(0,(a,e)=>a+_left(e));
    final people=_items.map(_name).toSet().length;
    final upcoming=_items.where((e){final d=_due(e);return !_done(e)&&d!=null&&!d.isBefore(DateTime.now())&&d.isBefore(DateTime.now().add(const Duration(days:7)));}).length;
    Widget summary(String title,String value,String sub,IconData icon,Color accent,Color tint)=>Expanded(child:Container(
      padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:dark?accent.withValues(alpha:.12):tint,borderRadius:BorderRadius.circular(16),border:Border.all(color:accent.withValues(alpha:.24))),
      child:Row(children:[Container(width:36,height:36,decoration:BoxDecoration(color:accent.withValues(alpha:.13),shape:BoxShape.circle),child:Icon(icon,color:accent,size:20)),const SizedBox(width:7),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:TextStyle(color:muted,fontSize:10,fontWeight:FontWeight.w700)),
        FittedBox(fit:BoxFit.scaleDown,alignment:Alignment.centerLeft,child:Text(value,style:TextStyle(color:accent,fontSize:17,fontWeight:FontWeight.w900))),
        Text(sub,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:muted,fontSize:9)),
      ]))])));
    return Scaffold(
      backgroundColor:bg,
      appBar:AppBar(backgroundColor:bg,surfaceTintColor:Colors.transparent,
        leading:IconButton(icon:const Icon(Icons.arrow_back_rounded),onPressed:()=>Navigator.pop(context)),
        title:const Text('দেনা-পাওনা',style:TextStyle(fontWeight:FontWeight.w900)),
        actions:[IconButton(onPressed:_refresh,icon:_loading?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.refresh_rounded)),const SizedBox(width:5)]),
      body:SafeArea(top:false,child:Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(13,8,13,0),child:Column(children:[
          Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>_openCreateDebtModal(credit:true),icon:const Icon(Icons.credit_card_rounded,size:17),label:const Text('নতুন ক্রেডিট হিসাব'),style:OutlinedButton.styleFrom(foregroundColor:const Color(0xFF287FF5),side:const BorderSide(color:Color(0xFF287FF5))))),const SizedBox(width:8),Expanded(child:FilledButton.icon(onPressed:()=>_openCreateDebtModal(),icon:const Icon(Icons.add_rounded,size:17),label:const Text('নতুন হিসাব'),style:FilledButton.styleFrom(backgroundColor:const Color(0xFF00A875))))]),
          const SizedBox(height:10),
          Row(children:[summary('মোট পাওনা','৳ ${receivable.round()}', 'বাকি পাওনার পরিমাণ',Icons.south_west_rounded,green,const Color(0xFFEAF8F2)),const SizedBox(width:8),summary('মোট দেনা','৳ ${payable.round()}','দিতে হবে',Icons.trending_down_rounded,red,const Color(0xFFFFEFF0))]),
          const SizedBox(height:8),
          Row(children:[summary('মোট ব্যক্তি',people.toString(),'সকল দেনা-পাওনার ব্যক্তি',Icons.people_outline_rounded,blue,const Color(0xFFEDF5FF)),const SizedBox(width:8),summary('আসন্ন তারিখ',upcoming.toString(),'আগামী ৭ দিনের মধ্যে',Icons.calendar_month_rounded,purple,const Color(0xFFF4EEFF))]),
          const SizedBox(height:12),
          TextField(controller:_search,onChanged:(_)=>setState((){}),decoration:InputDecoration(hintText:'নাম বা নোট খুঁজুন...',prefixIcon:const Icon(Icons.search_rounded),filled:true,fillColor:surface,contentPadding:const EdgeInsets.symmetric(vertical:13),border:OutlineInputBorder(borderRadius:BorderRadius.circular(18),borderSide:BorderSide(color:line)),enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(18),borderSide:BorderSide(color:line)))),
          const SizedBox(height:9),
          Row(children:[_filter(_kind,['সব ধরনের','দেনা','পাওনা'],(v)=>_kind=v),const SizedBox(width:6),_filter(_status,['সব স্ট্যাটাস','চলমান','সম্পন্ন'],(v)=>_status=v),const SizedBox(width:6),_filter(_period,['সব সময়','বকেয়া','আসন্ন'],(v)=>_period=v)]),
          const SizedBox(height:0),
          SizedBox(height:34,child:Row(children:[Expanded(child:Text('সকল দেনা-পাওনা',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900,color:dark?Colors.white:const Color(0xFF172B43)))),DropdownButton<String>(value:_sort,underline:const SizedBox.shrink(),icon:const Icon(Icons.keyboard_arrow_down_rounded),items:const ['সর্বশেষ আগে','পুরনো আগে','বেশি টাকা আগে','কম টাকা আগে'].map((v)=>DropdownMenuItem(value:v,child:Text(v,style:const TextStyle(fontSize:11)))).toList(),onChanged:(v){if(v!=null)setState(()=>_sort=v);},isDense:true)])),
        ])),
        Expanded(child:rows.isEmpty?Center(child:Text('কোনো দেনা-পাওনা পাওয়া যায়নি',style:TextStyle(color:muted))):ListView.separated(
          padding:const EdgeInsets.fromLTRB(13,0,13,18),itemCount:rows.length,separatorBuilder:(_,_)=>const SizedBox(height:4),
          itemBuilder:(context,index){
            final e=rows[index], debt=_kindOf(e)=='দেনা', done=_done(e), due=_due(e);
            final date=_date(e['date']??e['dateInput']??e['createdAt']);
            final overdue=!done&&due!=null&&due.isBefore(DateTime.now());
            final accent=debt?red:green;
            return Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:8),decoration:BoxDecoration(color:surface,borderRadius:BorderRadius.circular(18),border:Border.all(color:line),boxShadow:dark?[]:[BoxShadow(color:const Color(0xFF1D3557).withValues(alpha:.04),blurRadius:7,offset:const Offset(0,2))]),
              child:Row(children:[
                Container(width:40,height:40,decoration:BoxDecoration(color:(debt?purple:blue).withValues(alpha:.12),shape:BoxShape.circle),child:Icon(_transactionIconOptions[(e['icon']??e['iconName']??e['icon_name']??'').toString()]??Icons.account_balance_wallet_outlined,color:debt?purple:blue,size:21)),
                const SizedBox(width:6),
                Expanded(flex:5,child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
                  Text(_name(e),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:14,fontWeight:FontWeight.w900,height:1.1)),
                  const SizedBox(height:2),
                  Row(children:[Icon(Icons.calendar_today_outlined,size:11,color:muted),const SizedBox(width:3),Flexible(child:Text(_dateLabel(date),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:9,color:muted)))]),
                  const SizedBox(height:3),
                  Wrap(spacing:4,runSpacing:3,children:[_pill(_kindOf(e),accent,debt?const Color(0xFFFFE9EB):const Color(0xFFE1F8EC)),_pill((e['accountType']??e['debtType']??e['type']??'সহজ হিসাব').toString(),blue,const Color(0xFFEAF2FF))]),
                ])),
                Container(width:1,height:54,color:line,margin:const EdgeInsets.symmetric(horizontal:5)),
                SizedBox(width:150,child:Row(
                  crossAxisAlignment:CrossAxisAlignment.center,
                  children:[
                    Expanded(child:Column(
                      crossAxisAlignment:CrossAxisAlignment.start,
                      mainAxisSize:MainAxisSize.min,
                      children:[
                        Text('৳ ${_left(e).round()}',maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:16,fontWeight:FontWeight.w900,color:done?muted:accent)),
                        const SizedBox(height:3),
                        _pill(done?'সম্পন্ন':'●  চলমান',done?muted:green,const Color(0xFFE1F8EC)),
                        if(due!=null)...[const SizedBox(height:3),_pill('${_dateLabel(due)}${overdue ? ' ওভারডিউ' : ''}',overdue?red:muted,overdue?const Color(0xFFFFE8EA):const Color(0xFFF0F3F7))],
                      ],
                    )),
                    const SizedBox(width:3),
                    SizedBox(width:69,child:Row(
                      mainAxisAlignment:MainAxisAlignment.spaceBetween,
                      mainAxisSize:MainAxisSize.min,
                      children:[
                        SizedBox(width:21,height:28,child:IconButton(visualDensity:VisualDensity.compact,constraints:const BoxConstraints.expand(),padding:EdgeInsets.zero,onPressed:()=>_openPaymentModal(e),icon:const Icon(Icons.volunteer_activism_outlined,size:16,color:Color(0xFF00A875)))),
                        SizedBox(width:21,height:28,child:IconButton(visualDensity:VisualDensity.compact,constraints:const BoxConstraints.expand(),padding:EdgeInsets.zero,onPressed:()=>_openEditDebtModal(e),icon:const Icon(Icons.edit_outlined,size:16,color:Color(0xFF8292A4)))),
                        SizedBox(width:21,height:28,child:PopupMenuButton<String>(padding:EdgeInsets.zero,iconSize:17,icon:const Icon(Icons.more_horiz_rounded,color:Color(0xFF8292A4)),onSelected:(v){if(v=='edit'){_openEditDebtModal(e);}else{_todo('রিমাইন্ডার');}},itemBuilder:(_)=>const [PopupMenuItem(value:'remind',child:Text('রিমাইন্ডার')),PopupMenuItem(value:'edit',child:Text('এডিট'))])),
                      ],
                    )),
                  ],
                )),
              ]));
          })),
      ])),
    );
  }
}
class _BillsScreen extends StatefulWidget {
  const _BillsScreen({required this.bills, required this.onReload});
  final List<Map<String, dynamic>> bills;
  final Future<List<Map<String, dynamic>>> Function() onReload;
  @override
  State<_BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<_BillsScreen> {
  final _search = TextEditingController();
  late List<Map<String, dynamic>> _items;
  String _status = 'সব', _sort = 'সর্বশেষ আগে';
  bool _loading = false;

  @override
  void initState() { super.initState(); _items = List<Map<String, dynamic>>.from(widget.bills); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse((v ?? '').toString()) ?? 0;
  DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
  String _name(Map<String,dynamic> e) => (e['name'] ?? e['title'] ?? e['billName'] ?? e['bill_name'] ?? 'নাম নেই').toString();
  String _category(Map<String,dynamic> e) => (e['category'] ?? e['billType'] ?? e['type'] ?? 'অন্যান্য').toString();
  DateTime? _due(Map<String,dynamic> e) => _date(e['dueDate'] ?? e['due_date'] ?? e['nextDate'] ?? e['date']);
  double _paid(Map<String,dynamic> e) {
    final payments = e['payments'] is List ? e['payments'] as List : <dynamic>[];
    final cycle = (e['date'] ?? '').toString();
    return payments.whereType<Map>().where((p) {
      final paymentCycle = (p['cycleDate'] ?? '').toString();
      return paymentCycle.isEmpty || paymentCycle == cycle;
    }).fold<double>(0, (sum,p) => sum + _num(p['amount']));
  }
  double _left(Map<String,dynamic> e) => (_num(e['amount']) - _paid(e)).clamp(0,double.infinity).toDouble();
  bool _done(Map<String,dynamic> e) => _left(e) <= 0 || ['পরিশোধিত','সম্পন্ন','paid'].contains((e['status'] ?? '').toString().toLowerCase());
  bool _overdue(Map<String,dynamic> e) {
    final d = _due(e), now = DateTime.now();
    return !_done(e) && d != null && d.isBefore(DateTime(now.year,now.month,now.day));
  }
  String _dateLabel(DateTime? d) {
    if (d == null) return 'তারিখ নির্ধারিত নয়';
    const m = ['জানুয়ারি','ফেব্রুয়ারি','মার্চ','এপ্রিল','মে','জুন','জুলাই','আগস্ট','সেপ্টেম্বর','অক্টোবর','নভেম্বর','ডিসেম্বর'];
    return '${d.day} ${m[d.month-1]}, ${d.year}';
  }
  String _money(double v) => '৳ ${v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  Future<void> _openCreateBillModal([Map<String, dynamic>? billToEdit]) async {
    final isEditing = billToEdit != null;
    final nameController = TextEditingController(text: isEditing ? _name(billToEdit) : '');
    final amountController = TextEditingController(text: isEditing ? _num(billToEdit['amount']).toString() : '');
    final noteController = TextEditingController(text: isEditing ? (billToEdit['notes'] ?? billToEdit['note'] ?? '').toString() : '');
    DateTime dueDate = _date(billToEdit?['date']) ?? DateTime.now();
    String iconName = (billToEdit?['icon'] ?? 'ReceiptText').toString();
    String recurrence = (billToEdit?['billRule'] ?? 'one-time').toString();
    if (!['one-time', 'weekly', 'monthly', 'yearly'].contains(recurrence)) recurrence = 'one-time';
    String reminder = (billToEdit?['reminderDays'] ?? 3).toString();
    if (!['0', '1', '3', '7', '14'].contains(reminder)) reminder = '3';
    String status = (billToEdit?['status'] ?? 'বাকি').toString();
    if (!['বাকি', 'পরিশোধিত'].contains(status)) status = 'বাকি';
    bool saving = false;
    String dateLabel(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setModal) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          final surface = dark ? const Color(0xFF10283D) : Colors.white;
          final ink = dark ? Colors.white : const Color(0xFF172B43);
          final muted = dark ? const Color(0xFFA4B8CA) : const Color(0xFF8191A4);
          final line = dark ? const Color(0xFF294158) : const Color(0xFFE1E8F0);
          InputDecoration decoration(String hint) => InputDecoration(
            hintText: hint, filled: true, fillColor: dark ? const Color(0xFF0B2032) : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
          );
          Widget fieldLabel(String value) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted)),
          );
          Widget dropdown<T>(String label, T value, List<DropdownMenuItem<T>> items, ValueChanged<T?> changed) =>
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              fieldLabel(label),
              DropdownButtonFormField<T>(
                initialValue: value, isExpanded: true,
                decoration: decoration('নির্বাচন করুন'),
                items: items, onChanged: saving ? null : changed,
              ),
            ]);
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            backgroundColor: surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.of(context).size.height * .88),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 17, 12, 10),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(isEditing ? 'বিল সম্পাদনা' : 'বিল যোগ করুন', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: ink)),
                      const SizedBox(height: 3),
                      Text('আপনার তথ্য অ্যাকাউন্টে সংরক্ষিত হবে।', style: TextStyle(fontSize: 11, color: muted)),
                    ])),
                    IconButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), icon: Icon(Icons.close_rounded, color: muted)),
                  ]),
                ),
                Divider(height: 1, color: line),
                Flexible(child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 15, 18, 18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    fieldLabel('বিলের নাম'),
                    TextField(controller: nameController, enabled: !saving, decoration: decoration('নাম বা বিবরণ')),
                    const SizedBox(height: 13),
                    fieldLabel('আইকন নির্বাচন'),
                    Builder(builder: (selectorContext) {
                      final selectedIcon = _transactionIconOptions[iconName] ?? Icons.receipt_long_outlined;
                      return Row(children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00A875).withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(selectedIcon, color: const Color(0xFF00A875), size: 21),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: PopupMenuButton<String>(
                            tooltip: 'আইকন বেছে নিন',
                            enabled: !saving,
                            onSelected: (value) => setModal(() => iconName = value),
                            itemBuilder: (menuContext) => [
                              PopupMenuItem<String>(
                                enabled: false,
                                padding: const EdgeInsets.all(8),
                                child: Builder(builder: (popupContext) => SizedBox(
                                  width: 280,
                                  height: 220,
                                  child: GridView.builder(
                                    padding: EdgeInsets.zero,
                                    itemCount: _transactionIconOptions.length,
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 6,
                                      mainAxisSpacing: 5,
                                      crossAxisSpacing: 5,
                                    ),
                                    itemBuilder: (gridContext, index) {
                                      final entry = _transactionIconOptions.entries.elementAt(index);
                                      final isSelected = iconName == entry.key;
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () => Navigator.of(popupContext).pop(entry.key),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF00A875).withValues(alpha: .13)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isSelected
                                                  ? const Color(0xFF00A875)
                                                  : Colors.transparent,
                                            ),
                                          ),
                                          child: Icon(
                                            entry.value,
                                            size: 22,
                                            color: isSelected
                                                ? const Color(0xFF00A875)
                                                : (dark ? const Color(0xFFB7C7D6) : const Color(0xFF64748B)),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                )),
                              ),
                            ],
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: dark ? const Color(0xFF0B2032) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: line),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.grid_view_rounded,
                                  color: dark ? const Color(0xFFD4E0EA) : const Color(0xFF1E293B),
                                  size: 21,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]);
                    }),
                    const SizedBox(height: 13),
                    fieldLabel('টাকার পরিমাণ'),
                    TextField(controller: amountController, enabled: !saving, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: decoration('৳ 0')),
                    const SizedBox(height: 13),
                    fieldLabel('পরিশোধের তারিখ (দিন/মাস/বছর)'),
                    InkWell(
                      onTap: saving ? null : () async {
                        final picked = await showDatePicker(context: context, initialDate: dueDate, firstDate: DateTime(2000), lastDate: DateTime(2100), helpText: 'পরিশোধের তারিখ নির্বাচন করুন');
                        if (picked != null) setModal(() => dueDate = picked);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 15),
                        decoration: BoxDecoration(color: dark ? const Color(0xFF0B2032) : const Color(0xFFF8FAFC), border: Border.all(color: line), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [Icon(Icons.calendar_month_outlined, size: 19, color: muted), const SizedBox(width: 10), Expanded(child: Text(dateLabel(dueDate), style: TextStyle(color: ink))), Icon(Icons.keyboard_arrow_down_rounded, color: muted)]),
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: dropdown<String>('বিলের পুনরাবৃত্তি', recurrence, const [
                        DropdownMenuItem(value: 'one-time', child: Text('একবার')),
                        DropdownMenuItem(value: 'weekly', child: Text('প্রতি সপ্তাহে')),
                        DropdownMenuItem(value: 'monthly', child: Text('প্রতি মাসে')),
                        DropdownMenuItem(value: 'yearly', child: Text('প্রতি বছরে')),
                      ], (v) => setModal(() => recurrence = v ?? 'one-time'))),
                      const SizedBox(width: 10),
                      Expanded(child: dropdown<String>('রিমাইন্ডার', reminder, const [
                        DropdownMenuItem(value: '0', child: Text('রিমাইন্ডার বন্ধ')),
                        DropdownMenuItem(value: '1', child: Text('১ দিন আগে')),
                        DropdownMenuItem(value: '3', child: Text('৩ দিন আগে')),
                        DropdownMenuItem(value: '7', child: Text('৭ দিন আগে')),
                        DropdownMenuItem(value: '14', child: Text('১৪ দিন আগে')),
                      ], (v) => setModal(() => reminder = v ?? '3'))),
                    ]),
                    const SizedBox(height: 13),
                    dropdown<String>('অবস্থা', status, const [
                      DropdownMenuItem(value: 'বাকি', child: Text('বাকি')),
                      DropdownMenuItem(value: 'পরিশোধিত', child: Text('পরিশোধিত')),
                    ], (v) => setModal(() => status = v ?? 'বাকি')),
                    const SizedBox(height: 13),
                    fieldLabel('নোট'),
                    TextField(controller: noteController, enabled: !saving, minLines: 1, maxLines: 3, decoration: decoration('ঐচ্ছিক নোট')),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.pop(dialogContext),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: const Text('বাতিল'),
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: FilledButton.icon(
                        onPressed: saving ? null : () async {
                          final name = nameController.text.trim();
                          final amount = double.tryParse(amountController.text.trim());
                          if (name.isEmpty || amount == null || !amount.isFinite || amount <= 0) {
                            _notice(context, 'বিলের নাম ও সঠিক টাকার পরিমাণ দিন।');
                            return;
                          }
                          setModal(() => saving = true);
                          try {
                            final date = '${dueDate.year.toString().padLeft(4, '0')}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}';
                            final id = billToEdit?['id'] ?? DateTime.now().millisecondsSinceEpoch;
                            final oldDate = (billToEdit?['date'] ?? '').toString();
                            final oldPayments = billToEdit?['payments'] is List
                                ? (billToEdit!['payments'] as List).whereType<Map>().map((p) {
                                    final payment = Map<String, dynamic>.from(p);
                                    final cycle = (payment['cycleDate'] ?? '').toString();
                                    if (cycle.isEmpty || cycle == oldDate) payment['cycleDate'] = date;
                                    return payment;
                                  }).toList()
                                : null;
                            final updatedBill = <String, dynamic>{
                              ...?billToEdit,
                              'id': id, 'title': name, 'amount': amount, 'date': date,
                              'icon': iconName, 'updatedAt': _dateLabel(DateTime.now()),
                              'status': status, 'notes': noteController.text.trim(),
                              'billRule': recurrence, 'billDay': dueDate.day,
                              'reminderDays': int.parse(reminder),
                              ...?(oldPayments == null ? null : {'payments': oldPayments}),
                              if (recurrence != 'one-time') 'recurringId': billToEdit?['recurringId'] ?? id,
                              if (recurrence == 'one-time') 'recurringId': null,
                              'cycleKey': billToEdit?['cycleKey'] ?? date.substring(0, 7),
                            };
                            final updated = List<Map<String, dynamic>>.from(_items);
                            if (isEditing) {
                              final index = updated.indexWhere((item) => item['id'].toString() == billToEdit['id'].toString());
                              if (index < 0) throw Exception('বিলটি পাওয়া যায়নি। Refresh করে আবার চেষ্টা করুন।');
                              updated[index] = updatedBill;
                            } else {
                              updated.insert(0, updatedBill);
                            }
                            await _AuthApi._put('/data/bills', {'data': updated});
                            if (!mounted || !dialogContext.mounted) return;
                            setState(() => _items = updated);
                            Navigator.pop(dialogContext);
                            if (!mounted) return;
                            _notice(context, isEditing ? 'বিলের তথ্য আপডেট হয়েছে।' : 'নতুন বিল সংরক্ষণ হয়েছে।');
                          } catch (e) {
                            if (mounted && dialogContext.mounted) {
                              setModal(() => saving = false);
                              _notice(context, e.toString().replaceFirst('Exception: ', ''));
                            }
                          }
                        },
                        icon: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_rounded, size: 18),
                        label: Text(saving ? 'সংরক্ষণ হচ্ছে' : isEditing ? 'পরিবর্তন সংরক্ষণ' : 'সংরক্ষণ'),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF009B70), foregroundColor: Colors.white, minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      )),
                    ]),
                  ]),
                )),
              ]),
            ),
          );
        },
      ),
    );
    nameController.dispose();
    amountController.dispose();
    noteController.dispose();
  }

  Future<void> _openBillPaymentModal(Map<String, dynamic> bill) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final currentBill = Map<String, dynamic>.from(bill);
    final payments = currentBill['payments'] is List
        ? (currentBill['payments'] as List).whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList()
        : <Map<String, dynamic>>[];
    var wallets = <String>['ক্যাশ', 'ব্যাংক', 'বিকাশ', 'নগদ'];
    var wallet = 'ক্যাশ';
    var paymentDate = DateTime.now();
    var saving = false;
    int? editingPaymentId;
    String? message;
    final billCycle = (currentBill['date'] ?? '').toString();

    String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    String displayDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    double paid() => payments.where((p) {
      final cycle = (p['cycleDate'] ?? '').toString();
      return cycle.isEmpty || cycle == billCycle;
    }).fold<double>(0, (sum, p) => sum + _num(p['amount']));
    double remaining() => (_num(currentBill['amount']) - paid()).clamp(0, double.infinity).toDouble();
    DateTime nextDueDate(DateTime date, String rule) {
      if (rule == 'weekly') return date.add(const Duration(days: 7));
      final next = rule == 'yearly' ? DateTime(date.year + 1, date.month, 1) : DateTime(date.year, date.month + 1, 1);
      final lastDay = DateTime(next.year, next.month + 1, 0).day;
      return DateTime(next.year, next.month, date.day > lastDay ? lastDay : date.day);
    }

    try {
      final response = await _AuthApi._get('/data/wallets');
      final data = response['data'];
      if (data is List) {
        final names = data.whereType<Map>().map((x) => (x['name'] ?? '').toString().trim()).where((x) => x.isNotEmpty);
        wallets = <String>{...wallets, ...names}.toList();
      }
    } catch (_) {}

    if (!mounted) {
      amountController.dispose();
      noteController.dispose();
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setModal) {
          final dark = Theme.of(ctx).brightness == Brightness.dark;
          final surface = dark ? const Color(0xFF10283D) : Colors.white;
          final ink = dark ? const Color(0xFFEAF2FA) : const Color(0xFF172B43);
          final muted = dark ? const Color(0xFFA4B8CA) : const Color(0xFF8191A4);
          final line = dark ? const Color(0xFF294158) : const Color(0xFFE1E8F0);
          const green = Color(0xFF00A875), red = Color(0xFFFF625B);
          final total = _num(currentBill['amount']);
          final left = remaining();
          final progress = total <= 0 ? 0.0 : (paid() / total).clamp(0.0, 1.0);
          InputDecoration decoration(String label, String hint) => InputDecoration(
            labelText: label, hintText: hint, filled: true,
            fillColor: dark ? const Color(0xFF0B2032) : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: line)),
          );
          Widget metric(String label, double value, Color color) => Expanded(child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: dark ? const Color(0xFF0B2032) : const Color(0xFFF7F9FB), borderRadius: BorderRadius.circular(11), border: Border.all(color: line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: muted)),
              const SizedBox(height: 4),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(_money(value), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color))),
            ]),
          ));
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            backgroundColor: surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 520, maxHeight: (MediaQuery.of(ctx).size.height - MediaQuery.of(ctx).viewInsets.bottom - 40).clamp(260.0, MediaQuery.of(ctx).size.height * .90).toDouble()),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 12, 15, 14),
                child: Column(mainAxisSize: MainAxisSize.max, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_name(currentBill), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: ink)),
                      const SizedBox(height: 3),
                      Text('আপনার বিল পরিশোধ করতে হবে', style: TextStyle(fontSize: 11, color: muted)),
                    ])),
                    IconButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), icon: Icon(Icons.close_rounded, color: muted)),
                  ]),
                  const SizedBox(height: 7),
                  Row(children: [metric('মূল হিসাব', total, ink), const SizedBox(width: 6), metric('পরিশোধিত', paid(), green), const SizedBox(width: 6), metric('এখনো বাকি', left, left > 0 ? red : green)]),
                  const SizedBox(height: 10),
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, minHeight: 6, color: green, backgroundColor: dark ? const Color(0xFF294158) : const Color(0xFFE8EDF2))),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Text('পরিশোধের ইতিহাস', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: ink))),
                    Text('${payments.length}টি লেনদেন', style: TextStyle(fontSize: 10, color: muted)),
                  ]),
                  const SizedBox(height: 7),
                  Expanded(child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: dark ? const Color(0xFF0B2A32) : const Color(0xFFEAF8F2), borderRadius: BorderRadius.circular(12), border: Border.all(color: dark ? const Color(0xFF245343) : const Color(0xFFB7E5D3))),
                    child: payments.isEmpty
                      ? Center(child: Text('এখনো কোনো পেমেন্ট যোগ করা হয়নি।', style: TextStyle(fontSize: 11, color: muted)))
                      : ListView.separated(
                          itemCount: payments.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (rowContext, index) {
                            final payment = payments[payments.length - 1 - index];
                            final paymentId = _num(payment['id']).toInt();
                            final isEditing = editingPaymentId == paymentId;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: dark ? const Color(0xFF19372B) : Colors.white,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(color: dark ? const Color(0xFF2B5141) : const Color(0xFFE2EEE7)),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.08 : 0.035), blurRadius: 7, offset: const Offset(0, 2))],
                              ),
                              child: Row(children: [
                                SizedBox(width: 30, height: 30, child: Icon(Icons.account_balance_wallet_outlined, size: 18, color: dark ? const Color(0xFFE7F2EE) : ink)),
                                const SizedBox(width: 9),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('পরিশোধ · ${(payment['date'] ?? '').toString()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink)),
                                  Text((payment['wallet'] ?? 'ক্যাশ').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: muted)),
                                  if ((payment['notes'] ?? '').toString().trim().isNotEmpty) Text(payment['notes'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: muted)),
                                ])),
                                Text(_money(_num(payment['amount'])), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: green)),
                                IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 30, height: 32), padding: EdgeInsets.zero, tooltip: 'এডিট',
                                  onPressed: saving ? null : () {
                                    final parsed = DateTime.tryParse((payment['dateInput'] ?? '').toString());
                                    setModal(() {
                                      editingPaymentId = paymentId;
                                      amountController.text = _num(payment['amount']).toString();
                                      noteController.text = (payment['notes'] ?? '').toString();
                                      wallet = (payment['wallet'] ?? 'ক্যাশ').toString();
                                      if (!wallets.contains(wallet)) wallets.add(wallet);
                                      if (parsed != null) paymentDate = parsed;
                                    });
                                  }, icon: Icon(Icons.edit_outlined, size: 16, color: isEditing ? green : muted)),
                                IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 30, height: 32), padding: EdgeInsets.zero, tooltip: 'মুছুন',
                                  onPressed: saving ? null : () async {
                                    final confirm = await showDialog<bool>(context: dialogContext, builder: (c) => AlertDialog(
                                      title: const Text('পেমেন্ট মুছুন'),
                                      content: const Text('এই পেমেন্টের রেকর্ড এবং সংশ্লিষ্ট লেনদেন মুছে ফেলা হবে।'),
                                      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('বাতিল')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('মুছুন'))],
                                    ));
                                    if (confirm != true) return;
                                    setModal(() => saving = true);
                                    try {
                                      final br = await _AuthApi._get('/data/bills'), tr = await _AuthApi._get('/data/transactions');
                                      final bills = (br['data'] as List).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
                                      final txs = (tr['data'] as List).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
                                      final ix = bills.indexWhere((x) => x['id'].toString() == currentBill['id'].toString());
                                      if (ix < 0) throw Exception('বিলটি পাওয়া যায়নি। Refresh করে আবার চেষ্টা করুন।');
                                      final next = payments.where((x) => x['id'].toString() != payment['id'].toString()).toList();
                                      final sum = next.where((x) { final c = (x['cycleDate'] ?? '').toString(); return c.isEmpty || c == billCycle; }).fold<double>(0, (v, x) => v + _num(x['amount']));
                                      bills[ix] = {...bills[ix], 'payments': next, 'status': sum >= total ? 'পরিশোধিত' : 'বাকি', 'updatedAt': _dateLabel(DateTime.now())};
                                      if (payment['transactionId'] != null) txs.removeWhere((x) => x['id'].toString() == payment['transactionId'].toString());
                                      await _AuthApi._put('/data/bills', {'data': bills});
                                      await _AuthApi._put('/data/transactions', {'data': txs});
                                      payments..clear()..addAll(next);
                                      currentBill['payments'] = payments;
                                      currentBill['status'] = sum >= total ? 'পরিশোধিত' : 'বাকি';
                                      setModal(() { saving = false; if (editingPaymentId == paymentId) { editingPaymentId = null; amountController.clear(); noteController.clear(); } });
                                      await _refresh();
                                      if (dialogContext.mounted) setModal(() {});
                                    } catch (e) {
                                      if (dialogContext.mounted) { setModal(() => saving = false); _notice(dialogContext, e.toString().replaceFirst('Exception: ', '')); }
                                    }
                                  }, icon: const Icon(Icons.delete_outline_rounded, size: 17, color: red)),
                              ]),
                            );
                          },
                        ),
                  )),
                  const SizedBox(height: 10),
                  if (left > 0 || editingPaymentId != null) ...[
                    Text(editingPaymentId == null ? 'পরিশোধ / জমা যোগ করুন' : 'পরিশোধ সম্পাদনা', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: ink)),
                    const SizedBox(height: 6),
                    Flexible(child: SingleChildScrollView(child: Column(children: [
                      TextField(controller: amountController, enabled: !saving, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: decoration('পরিমাণ (৳)', '0.00')),
                      const SizedBox(height: 7),
                      Row(children: [
                        Expanded(child: OutlinedButton.icon(
                          onPressed: saving ? null : () async {
                            final picked = await showDatePicker(context: dialogContext, initialDate: paymentDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                            if (picked != null) setModal(() => paymentDate = picked);
                          },
                          icon: const Icon(Icons.calendar_month_outlined, size: 16), label: Text(displayDate(paymentDate), maxLines: 1, overflow: TextOverflow.ellipsis),
                        )),
                        const SizedBox(width: 7),
                        Expanded(child: DropdownButtonFormField<String>(
                          initialValue: wallets.contains(wallet) ? wallet : wallets.first,
                          isExpanded: true, decoration: decoration('ওয়ালেট', ''),
                          items: wallets.map((w) => DropdownMenuItem(value: w, child: Text(w, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: saving ? null : (v) { if (v != null) setModal(() => wallet = v); },
                        )),
                      ]),
                      const SizedBox(height: 7),
                      TextField(controller: noteController, enabled: !saving, maxLines: 2, decoration: decoration('নোট (ঐচ্ছিক)', 'পেমেন্টের বিবরণ')),
                      const SizedBox(height: 8),
                      Row(children: [
                        if (editingPaymentId != null) ...[
                          Expanded(child: OutlinedButton(onPressed: saving ? null : () => setModal(() { editingPaymentId = null; amountController.clear(); noteController.clear(); paymentDate = DateTime.now(); wallet = wallets.first; }), child: const Text('বাতিল'))),
                          const SizedBox(width: 7),
                        ],
                        Expanded(child: FilledButton.icon(
                          onPressed: saving ? null : () async {
                            final value = double.tryParse(amountController.text.trim());
                            final old = editingPaymentId == null ? null : payments.where((p) => p['id'].toString() == editingPaymentId.toString()).firstOrNull;
                            if (value == null || !value.isFinite || value <= 0) { _notice(dialogContext, 'শূন্যের বেশি সঠিক পরিমাণ দিন।'); return; }
                            if (value > remaining() + _num(old?['amount'])) { _notice(dialogContext, 'এই বিলের বাকি টাকার চেয়ে বেশি পরিশোধ করা যাবে না।'); return; }
                            setModal(() => saving = true);
                            try {
                              final br = await _AuthApi._get('/data/bills'), tr = await _AuthApi._get('/data/transactions');
                              final bills = (br['data'] as List).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
                              final txs = (tr['data'] as List).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
                              final ix = bills.indexWhere((x) => x['id'].toString() == currentBill['id'].toString());
                              if (ix < 0) throw Exception('বিলটি পাওয়া যায়নি। Refresh করে আবার চেষ্টা করুন।');
                              final paymentId = editingPaymentId ?? DateTime.now().millisecondsSinceEpoch;
                              final txId = old?['transactionId'] ?? (DateTime.now().millisecondsSinceEpoch + 1);
                              final date = isoDate(paymentDate);
                              final payment = <String, dynamic>{
                                'id': paymentId, 'amount': value, 'date': displayDate(paymentDate), 'dateInput': date,
                                'wallet': wallet, 'notes': noteController.text.trim(), 'transactionId': txId,
                                'cycleDate': (old?['cycleDate'] ?? billCycle).toString(),
                              };
                              final next = old == null ? [...payments, payment] : payments.map((p) => p['id'].toString() == paymentId.toString() ? payment : p).toList();
                              final sum = next.where((p) { final c = (p['cycleDate'] ?? '').toString(); return c.isEmpty || c == billCycle; }).fold<double>(0, (v, p) => v + _num(p['amount']));
                              final complete = sum + 1e-8 >= total;
                              final rule = (currentBill['billRule'] ?? 'one-time').toString();
                              final due = _date(currentBill['date']);
                              final nextDue = complete && due != null && rule != 'one-time' ? nextDueDate(due, rule) : null;
                              final normalizedPayments = next.map((p) => (p['cycleDate'] ?? '').toString().isEmpty ? {...p, 'cycleDate': billCycle} : p).toList();
                              final updated = <String, dynamic>{
                                ...bills[ix], 'payments': normalizedPayments,
                                'status': complete ? (nextDue == null ? 'পরিশোধিত' : 'বাকি') : 'বাকি',
                                'updatedAt': _dateLabel(DateTime.now()),
                                if (nextDue != null) 'date': isoDate(nextDue),
                                if (nextDue != null) 'cycleKey': rule == 'weekly' ? isoDate(nextDue) : rule == 'yearly' ? nextDue.year.toString() : isoDate(nextDue).substring(0, 7),
                              };
                              bills[ix] = updated;
                              if (!dialogContext.mounted) return;
                              final tx = <String, dynamic>{
                                'id': txId, 'title': 'বিল পরিশোধ — ${_name(currentBill)}', 'category': 'বিল',
                                'date': displayDate(paymentDate), 'dateInput': date, 'time': TimeOfDay.now().format(dialogContext),
                                'wallet': wallet, 'amount': value, 'kind': 'ব্যয়',
                                'icon': (currentBill['icon'] ?? 'ReceiptText').toString(),
                                'billId': currentBill['id'], 'billPaymentId': paymentId, 'note': noteController.text.trim(),
                              };
                              final txIndex = txs.indexWhere((x) => x['id'].toString() == txId.toString());
                              if (txIndex < 0) { txs.insert(0, tx); } else { txs[txIndex] = tx; }
                              await _AuthApi._put('/data/bills', {'data': bills});
                              await _AuthApi._put('/data/transactions', {'data': txs});
                              if (!dialogContext.mounted) return;
                              payments..clear()..addAll(normalizedPayments);
                              currentBill..clear()..addAll(updated);
                              message = old == null ? 'পেমেন্ট যোগ হয়েছে।' : 'পেমেন্ট আপডেট হয়েছে।';
                              setModal(() { saving = false; editingPaymentId = null; amountController.clear(); noteController.clear(); paymentDate = DateTime.now(); wallet = wallets.first; });
                              await _refresh();
                              if (dialogContext.mounted) setModal(() {});
                            } catch (e) {
                              if (dialogContext.mounted) { setModal(() => saving = false); _notice(dialogContext, e.toString().replaceFirst('Exception: ', '')); }
                            }
                          },
                          icon: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_rounded, size: 17),
                          label: Text(saving ? 'সংরক্ষণ হচ্ছে...' : editingPaymentId == null ? 'পরিশোধ সংরক্ষণ' : 'পরিবর্তন সংরক্ষণ'),
                          style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white),
                        )),
                      ]),
                    ]))),
                  ] else ...[
                    const SizedBox(height: 10),
                    Center(child: Text('সম্পূর্ণ পরিশোধিত', style: TextStyle(color: green, fontWeight: FontWeight.w800))),
                  ],
                ]),
              ),
            ),
          );
        },
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    amountController.dispose();
    noteController.dispose();
    if (mounted && message != null) _notice(context, message!);
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final fresh = await widget.onReload();
      if (!mounted) return;
      setState(() { _items = fresh; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _notice(context,e.toString().replaceFirst('Exception: ',''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF071827) : const Color(0xFFF5F7FB);
    final surface = dark ? const Color(0xFF10283D) : Colors.white;
    final ink = dark ? Colors.white : const Color(0xFF172B43);
    final muted = dark ? const Color(0xFFA4B8CA) : const Color(0xFF8191A4);
    final line = dark ? const Color(0xFF294158) : const Color(0xFFE1E8F0);
    const green = Color(0xFF00A875), red = Color(0xFFFF4D55), blue = Color(0xFF287FF5), purple = Color(0xFF9657F5);
    final q = _search.text.trim().toLowerCase();
    final rows = _items.where((e) {
      final text = '${_name(e)} ${_category(e)} ${(e['note'] ?? '').toString()}'.toLowerCase();
      if (q.isNotEmpty && !text.contains(q)) return false;
      if (_status == 'বাকি' && _done(e)) return false;
      if (_status == 'পরিশোধিত' && !_done(e)) return false;
      if (_status == 'ওভারডিউ' && !_overdue(e)) return false;
      return true;
    }).toList();
    rows.sort((a,b) {
      final da = _due(a) ?? _date(a['date']) ?? DateTime(2000);
      final db = _due(b) ?? _date(b['date']) ?? DateTime(2000);
      return _sort == 'পুরোনো আগে' ? da.compareTo(db) : db.compareTo(da);
    });
    final unpaid = _items.where((e) => !_done(e)).toList();
    final remaining = unpaid.fold<double>(0,(s,e) => s + _left(e));
    final paid = _items.fold<double>(0, (sum, e) { final recorded = _paid(e); return sum + (recorded > 0 ? recorded : _done(e) ? _num(e['amount']) : 0); });
    final overdue = _items.where(_overdue).length;
    final upcoming = _items.where((e) {
      final d = _due(e);
      return !_done(e) && d != null && !d.isBefore(DateTime.now()) && d.isBefore(DateTime.now().add(const Duration(days:7)));
    }).length;

    Widget summary(String title,String value,String sub,IconData icon,Color color,Color tint) =>
      Expanded(child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:dark?color.withValues(alpha:.12):tint,borderRadius:BorderRadius.circular(16),border:Border.all(color:color.withValues(alpha:.24))),child:Row(children:[
        Container(width:36,height:36,decoration:BoxDecoration(color:color.withValues(alpha:.13),shape:BoxShape.circle),child:Icon(icon,color:color,size:20)),
        const SizedBox(width:7),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(title,style:TextStyle(color:muted,fontSize:10,fontWeight:FontWeight.w700)),
          FittedBox(fit:BoxFit.scaleDown,alignment:Alignment.centerLeft,child:Text(value,style:TextStyle(color:color,fontSize:16,fontWeight:FontWeight.w900))),
          Text(sub,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:muted,fontSize:9)),
        ])),
      ])));

    return Scaffold(
      backgroundColor:bg,
      appBar:AppBar(backgroundColor:bg,surfaceTintColor:Colors.transparent,leading:IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.arrow_back_rounded)),title:const Text('বিল',style:TextStyle(fontWeight:FontWeight.w900)),actions:[
        IconButton(onPressed:_loading?null:_refresh,icon:_loading?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.refresh_rounded)),
        IconButton(onPressed:_openCreateBillModal,icon:const Icon(Icons.add_rounded,size:28)),const SizedBox(width:5),
      ]),
      body:SafeArea(top:false,child:Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(13,8,13,0),child:Column(children:[
          Row(children:[summary('মোট বাকি',_money(remaining),'${unpaid.length} টি পরিশোধ বাকি',Icons.receipt_long_rounded,red,const Color(0xFFFFEFF0)),const SizedBox(width:8),summary('পরিশোধিত',_money(paid),'পরিশোধ করা হয়েছে',Icons.check_circle_outline_rounded,green,const Color(0xFFEAF8F2))]),
          const SizedBox(height:8),
          Row(children:[summary('মোট বিল',_items.length.toString(),'সকল বিলের হিসাব',Icons.calendar_month_rounded,blue,const Color(0xFFEDF5FF)),const SizedBox(width:8),summary('ওভারডিউ',overdue.toString(),'$upcoming টি আসন্ন',Icons.notifications_active_outlined,purple,const Color(0xFFF4EEFF))]),
          const SizedBox(height:12),
          TextField(controller:_search,onChanged:(_)=>setState((){}),decoration:InputDecoration(hintText:'বিলের নাম বা ক্যাটাগরি খুঁজুন...',prefixIcon:const Icon(Icons.search_rounded),filled:true,fillColor:surface,contentPadding:const EdgeInsets.symmetric(vertical:13),border:OutlineInputBorder(borderRadius:BorderRadius.circular(18),borderSide:BorderSide(color:line)),enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(18),borderSide:BorderSide(color:line)))),
          const SizedBox(height:9),
          SizedBox(
            height:39,
            child:ListView(
              scrollDirection:Axis.horizontal,
              children:['সব','বাকি','পরিশোধিত','ওভারডিউ'].map((v)=>Padding(
                padding:const EdgeInsets.only(right:6),
                child:ChoiceChip(
                  label:Text(v,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w700)),
                  selected:_status==v,
                  onSelected:(_)=>setState(()=>_status=v),
                ),
              )).toList(),
            ),
          ),
          SizedBox(height:38,child:Row(children:[Expanded(child:Text('সকল বিল',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900,color:ink))),DropdownButton<String>(value:_sort,underline:const SizedBox.shrink(),isDense:true,items:const ['সর্বশেষ আগে','পুরোনো আগে'].map((v)=>DropdownMenuItem(value:v,child:Text(v,style:const TextStyle(fontSize:11)))).toList(),onChanged:(v){if(v!=null)setState(()=>_sort=v);})])),
        ])),
        Expanded(child:_loading?const Center(child:CircularProgressIndicator()):rows.isEmpty?Center(child:Text('কোনো বিল পাওয়া যায়নি',style:TextStyle(color:muted))):ListView.separated(
          padding:const EdgeInsets.fromLTRB(13,2,13,18),itemCount:rows.length,separatorBuilder:(_,_)=>const SizedBox(height:7),
          itemBuilder:(context,index){
            final e=rows[index],done=_done(e),late=_overdue(e),due=_due(e);
            final accent=done?green:late?red:blue;
            final tint=done?const Color(0xFFF8FCFA):late?const Color(0xFFFFFAFA):const Color(0xFFEDF5FF);
            final category=_category(e).toLowerCase();
            final icon=category.contains('বিদ্যুৎ')?Icons.bolt_rounded:category.contains('ইন্টারনেট')?Icons.wifi_rounded:category.contains('ভাড়া')?Icons.home_work_outlined:Icons.receipt_long_rounded;
            final dueText=due==null?'তারিখ নেই':_dateLabel(due);
            return Container(
              padding:const EdgeInsets.symmetric(horizontal:8,vertical:8),
              decoration:BoxDecoration(
                color:dark?Color.lerp(surface,accent,.09):tint,
                borderRadius:BorderRadius.circular(18),
                border:Border.all(color:accent.withValues(alpha:dark ? .24 : .15)),
                boxShadow:dark?[]:[BoxShadow(color:accent.withValues(alpha:.045),blurRadius:7,offset:const Offset(0,2))],
              ),
              child:Row(children:[
                Container(
                  width:40,height:40,
                  decoration:BoxDecoration(color:accent.withValues(alpha:.09),shape:BoxShape.circle),
                  child:Icon(icon,color:accent,size:21),
                ),
                const SizedBox(width:6),
                Expanded(flex:5,child:Column(
                  crossAxisAlignment:CrossAxisAlignment.start,
                  mainAxisSize:MainAxisSize.min,
                  children:[
                    Text(_name(e),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:14,fontWeight:FontWeight.w900,color:ink,height:1.1)),
                    const SizedBox(height:2),
                    Text(_category(e),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:10,color:muted)),
                    const SizedBox(height:3),
                    Row(children:[
                      Icon(Icons.calendar_today_outlined,size:11,color:muted),
                      const SizedBox(width:3),
                      Flexible(child:Text(_dateLabel(_date(e['date']??e['createdAt'])??due),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:9,color:muted))),
                    ]),
                  ],
                )),
                Container(width:1,height:54,color:line,margin:const EdgeInsets.symmetric(horizontal:5)),
                Expanded(flex:5,child:Row(
                  crossAxisAlignment:CrossAxisAlignment.center,
                  children:[
                    Expanded(child:Column(
                      crossAxisAlignment:CrossAxisAlignment.start,
                      mainAxisSize:MainAxisSize.min,
                      children:[
                        Text(_money(_left(e)),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:15,fontWeight:FontWeight.w900,color:done?muted:accent)),
                        const SizedBox(height:3),
                        Container(
                          padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
                          decoration:BoxDecoration(color:accent.withValues(alpha:.08),borderRadius:BorderRadius.circular(18)),
                          child:Text(done?'●  পরিশোধিত':late?'●  ওভারডিউ':'●  বাকি',maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:9,fontWeight:FontWeight.w800,color:accent)),
                        ),
                        const SizedBox(height:3),
                        Text(dueText,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:9,color:muted)),
                      ],
                    )),
                    const SizedBox(width:2),
                    SizedBox(width:63,child:Row(
                      mainAxisAlignment:MainAxisAlignment.spaceBetween,
                      mainAxisSize:MainAxisSize.min,
                      children:[
                        SizedBox(width:19,height:28,child:IconButton(visualDensity:VisualDensity.compact,constraints:const BoxConstraints.expand(),padding:EdgeInsets.zero,tooltip:'পেমেন্ট',onPressed:()=>_openBillPaymentModal(e),icon:const Icon(Icons.payments_outlined,size:17,color:Color(0xFF00A875)))),
                        SizedBox(width:19,height:28,child:IconButton(visualDensity:VisualDensity.compact,constraints:const BoxConstraints.expand(),padding:EdgeInsets.zero,tooltip:'এডিট',onPressed:()=>_openCreateBillModal(e),icon:const Icon(Icons.edit_outlined,size:16,color:Color(0xFF8292A4)))),
                        SizedBox(width:19,height:28,child:PopupMenuButton<String>(padding:EdgeInsets.zero,constraints:const BoxConstraints.expand(),iconSize:17,icon:const Icon(Icons.more_horiz_rounded,color:Color(0xFF8292A4)),onSelected:(v){if(v=='edit'){_openCreateBillModal(e);}else{_notice(context,'বিল রিমাইন্ডার সুবিধাটি পরবর্তী ধাপে যুক্ত হবে।');}},itemBuilder:(_)=>const [PopupMenuItem(value:'remind',child:Text('রিমাইন্ডার')),PopupMenuItem(value:'edit',child:Text('এডিট'))])),
                      ],
                    )),
                  ],
                )),
              ]),
            );
          },
        )),
      ])),
    );
  }
}

const Map<String, IconData> _transactionIconOptions = {
    'Briefcase': Icons.work_outline_rounded,
    'Banknote': Icons.payments_outlined,
    'CircleDollarSign': Icons.monetization_on_outlined,
    'Coins': Icons.toll_outlined,
    'CreditCard': Icons.credit_card_outlined,
    'Wallet': Icons.account_balance_wallet_outlined,
    'WalletCards': Icons.wallet_outlined,
    'HandCoins': Icons.volunteer_activism_outlined,
    'BadgeDollarSign': Icons.price_check_rounded,
    'ReceiptText': Icons.receipt_long_outlined,
    'ChartNoAxesCombined': Icons.query_stats_rounded,
    'TrendingUp': Icons.trending_up_rounded,
    'TrendingDown': Icons.trending_down_rounded,
    'Calculator': Icons.calculate_outlined,
    'Percent': Icons.percent_rounded,
    'Store': Icons.storefront_outlined,
    'ShoppingCart': Icons.shopping_cart_outlined,
    'ShoppingBag': Icons.shopping_bag_outlined,
    'ShoppingBasket': Icons.shopping_basket_outlined,
    'Tag': Icons.sell_outlined,
    'Gift': Icons.card_giftcard_outlined,
    'Package': Icons.inventory_2_outlined,
    'PackageOpen': Icons.unarchive_outlined,
    'House': Icons.home_outlined,
    'BedDouble': Icons.bed_outlined,
    'Sofa': Icons.weekend_outlined,
    'Lamp': Icons.light_outlined,
    'Lightbulb': Icons.lightbulb_outline_rounded,
    'Plug': Icons.power_outlined,
    'HousePlug': Icons.electrical_services_outlined,
    'Droplets': Icons.water_drop_outlined,
    'Flame': Icons.local_fire_department_outlined,
    'Wifi': Icons.wifi_rounded,
    'Smartphone': Icons.smartphone_rounded,
    'Laptop': Icons.laptop_outlined,
    'Monitor': Icons.desktop_windows_outlined,
    'Tv': Icons.tv_outlined,
    'Router': Icons.router_outlined,
    'Printer': Icons.print_outlined,
    'Camera': Icons.camera_alt_outlined,
    'Headphones': Icons.headphones_outlined,
    'Gamepad2': Icons.sports_esports_outlined,
    'Car': Icons.directions_car_outlined,
    'CarFront': Icons.directions_car_filled_outlined,
    'Bus': Icons.directions_bus_outlined,
    'BusFront': Icons.directions_bus_filled_outlined,
    'Train': Icons.train_outlined,
    'Bike': Icons.pedal_bike_outlined,
    'Plane': Icons.flight_outlined,
    'PlaneTakeoff': Icons.flight_takeoff_rounded,
    'Ship': Icons.directions_boat_outlined,
    'Fuel': Icons.local_gas_station_outlined,
    'MapPin': Icons.location_on_outlined,
    'Route': Icons.alt_route_rounded,
    'Utensils': Icons.restaurant_outlined,
    'UtensilsCrossed': Icons.restaurant_menu_rounded,
    'CookingPot': Icons.soup_kitchen_outlined,
    'Coffee': Icons.coffee_outlined,
    'Pizza': Icons.local_pizza_outlined,
    'Salad': Icons.eco_outlined,
    'Sandwich': Icons.lunch_dining_outlined,
    'Cake': Icons.cake_outlined,
    'IceCream': Icons.icecream_outlined,
    'Apple': Icons.apple_rounded,
    'Carrot': Icons.grass_rounded,
    'Pill': Icons.medication_outlined,
    'Stethoscope': Icons.medical_services_outlined,
    'HeartPulse': Icons.monitor_heart_outlined,
    'Cross': Icons.add_rounded,
    'Syringe': Icons.vaccines_outlined,
    'Hospital': Icons.local_hospital_outlined,
    'Bandage': Icons.healing_outlined,
    'Dumbbell': Icons.fitness_center_rounded,
    'GraduationCap': Icons.school_outlined,
    'BookOpen': Icons.menu_book_outlined,
    'Book': Icons.book_outlined,
    'School': Icons.cast_for_education_outlined,
    'Notebook': Icons.note_alt_outlined,
    'FileText': Icons.description_outlined,
    'Music': Icons.music_note_rounded,
    'Film': Icons.movie_outlined,
    'Clapperboard': Icons.video_camera_back_outlined,
    'Theater': Icons.theater_comedy_outlined,
    'Popcorn': Icons.local_movies_outlined,
    'PartyPopper': Icons.celebration_outlined,
    'Ticket': Icons.confirmation_number_outlined,
    'Trophy': Icons.emoji_events_outlined,
    'Turtle': Icons.pets_outlined,
    'Dog': Icons.pets_rounded,
    'Cat': Icons.pets_rounded,
    'PawPrint': Icons.pets_outlined,
    'Bone': Icons.cruelty_free_outlined,
    'Shirt': Icons.checkroom_outlined,
    'Footprints': Icons.directions_walk_rounded,
    'Watch': Icons.watch_outlined,
    'Glasses': Icons.visibility_outlined,
    'Gem': Icons.diamond_outlined,
    'Users': Icons.groups_outlined,
    'Baby': Icons.child_care_outlined,
    'Heart': Icons.favorite_border_rounded,
    'Flower2': Icons.local_florist_outlined,
    'Sprout': Icons.grass_outlined,
    'TreePine': Icons.park_outlined,
    'Leaf': Icons.eco_outlined,
    'Sun': Icons.wb_sunny_outlined,
    'CloudRain': Icons.cloudy_snowing,
    'Snowflake': Icons.ac_unit_rounded,
    'Umbrella': Icons.umbrella_outlined,
    'Wrench': Icons.build_outlined,
    'Hammer': Icons.handyman_outlined,
    'Paintbrush': Icons.brush_outlined,
    'Scissors': Icons.content_cut_rounded,
    'Trash2': Icons.delete_outline_rounded,
    'Recycle': Icons.recycling_rounded,
    'CalendarDays': Icons.calendar_month_outlined,
    'Clock': Icons.schedule_rounded,
    'Bell': Icons.notifications_none_rounded,
    'ShieldCheck': Icons.verified_user_outlined,
    'KeyRound': Icons.key_outlined,
    'Ellipsis': Icons.more_horiz_rounded,
};

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}


class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  bool _hidden = false;
  bool _compactCharts = true;
  String? _error;
  double _balance = 0;
  double? _monthChangePercent;
  String _monthChangeMessage = 'গত মাসের তুলনার ডেটা নেই';
  List<Map<String, dynamic>> _transactions = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _debts = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _bills = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _goals = <Map<String, dynamic>>[];
  int _chartRangeDays = 30;
  int _incomeDonutMonthOffset = 0;
  int _expenseDonutMonthOffset = 0;
  String _recentTransactionsMonthKey = _monthKey(DateTime.now());
  String _recentTransactionsCategory = 'সব';
  Map<String, double> _walletBalances = {'ক্যাশ': 0, 'ব্যাংক': 0, 'বিকাশ': 0, 'নগদ': 0};
  bool _showAddTransactionFab = true;

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
      // A manual refresh or app resume must flush the durable outbox first.
      await _AuthApi.trySyncPending();
      final data = await _AuthApi.loadDashboardData();
      final wallets = data['wallets'] is List ? data['wallets'] as List : <dynamic>[];
      final remoteTransactions = data['transactions'] is List ? data['transactions'] as List : <dynamic>[];
      await _AuthApi.cacheTransactions(remoteTransactions);
      final transactions = await _AuthApi.localTransactions();
      final debts = data['debts'] is List ? data['debts'] as List : <dynamic>[];
      final bills = data['bills'] is List ? data['bills'] as List : <dynamic>[];
      final goals = data['goals'] is List ? data['goals'] as List : <dynamic>[];
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
        _debts = debts.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
        _bills = bills.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
        _goals = goals.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
        _loading = false;
      });
    } catch (error) {
      final cachedTransactions = await _AuthApi.localTransactions();
      if (!mounted) return;
      // Reconcile the local transaction delta against the currently displayed
      // totals so offline add/edit/delete updates the dashboard immediately.
      final oldById = {for (final item in _transactions) (item['_syncId'] ?? item['id']).toString(): item};
      final newById = {for (final item in cachedTransactions) (item['_syncId'] ?? item['id']).toString(): item};
      double signedAmount(Map<String, dynamic>? item) {
        if (item == null) return 0;
        final amount = _amount(item['amount']);
        if (item['kind'] == 'আয়') return amount;
        if (item['kind'] == 'ব্যয়') return -amount;
        return 0;
      }
      final changedIds = <String>{...oldById.keys, ...newById.keys};
      var balanceDelta = 0.0;
      final walletDelta = <String, double>{};
      for (final id in changedIds) {
        final before = oldById[id];
        final after = newById[id];
        balanceDelta += signedAmount(after) - signedAmount(before);
        final beforeWallet = (before?['wallet'] ?? before?['walletName'] ?? before?['wallet_name'] ?? '').toString();
        final afterWallet = (after?['wallet'] ?? after?['walletName'] ?? after?['wallet_name'] ?? '').toString();
        if (before != null && beforeWallet.isNotEmpty) {
          walletDelta[beforeWallet] = (walletDelta[beforeWallet] ?? 0) - signedAmount(before);
        }
        if (after != null && afterWallet.isNotEmpty) {
          walletDelta[afterWallet] = (walletDelta[afterWallet] ?? 0) + signedAmount(after);
        }
      }
      setState(() {
        if (cachedTransactions.isNotEmpty || _transactions.isNotEmpty) {
          _balance += balanceDelta;
          for (final entry in walletDelta.entries) {
            if (_walletBalances.containsKey(entry.key)) {
              _walletBalances[entry.key] = _walletBalances[entry.key]! + entry.value;
            }
          }
          _transactions = cachedTransactions;
          _error = null;
        } else {
          _error = error.toString().replaceFirst('Exception: ', '');
        }
        _loading = false;
      });
    }
  }

  int? _reminderDays(dynamic value) {
    final date = _parseTransactionDate(value);
    if (date == null) return null;
    final now = DateTime.now();
    return DateTime(date.year, date.month, date.day)
        .difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  int get _activeReminderCount {
    final billCount = _bills.where((e) {
      if (['পরিশোধিত', 'সম্পন্ন'].contains((e['status'] ?? '').toString())) return false;
      final days = _reminderDays(e['date'] ?? e['dueDate'] ?? e['due_date']);
      final reminder = int.tryParse((e['reminderDays'] ?? 3).toString()) ?? 3;
      return days != null && days >= 0 && days <= reminder;
    }).length;
    final debtCount = _debts.where((e) {
      if (['পরিশোধিত', 'সম্পন্ন'].contains((e['status'] ?? '').toString())) return false;
      final days = _reminderDays(e['date']);
      return days != null && days <= 3;
    }).length;
    return billCount + debtCount;
  }

  String _reminderDateLabel(dynamic value) {
    final date = _parseTransactionDate(value);
    if (date == null) return 'তারিখ পাওয়া যায়নি';
    const months = ['জানুয়ারি','ফেব্রুয়ারি','মার্চ','এপ্রিল','মে','জুন','জুলাই','আগস্ট','সেপ্টেম্বর','অক্টোবর','নভেম্বর','ডিসেম্বর'];
    return '${_bengaliDigits(date.day.toString())} ${months[date.month - 1]}, ${_bengaliDigits(date.year.toString())}';
  }

  Future<void> _showReminderSheet() async {
    if (!mounted) return;
    final billsDue = _bills.where((e) {
      if (['পরিশোধিত','সম্পন্ন'].contains((e['status'] ?? '').toString())) return false;
      final days = _reminderDays(e['date'] ?? e['dueDate'] ?? e['due_date']);
      final reminder = int.tryParse((e['reminderDays'] ?? 3).toString()) ?? 3;
      return days != null && days >= 0 && days <= reminder;
    }).toList();
    final debtsDue = _debts.where((e) {
      if (['পরিশোধিত','সম্পন্ন'].contains((e['status'] ?? '').toString())) return false;
      final days = _reminderDays(e['date']);
      return days != null && days <= 3;
    }).toList();
    var filter = 'সবগুলো';
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final dark = Theme.of(dialogContext).brightness == Brightness.dark;
        final surface = dark ? const Color(0xFF102338) : Colors.white;
        final panel = dark ? const Color(0xFF172D40) : const Color(0xFFF0F3F8);
        final ink = dark ? const Color(0xFFE5F0FA) : const Color(0xFF203447);
        final muted = dark ? const Color(0xFF9BAFC0) : const Color(0xFF8292A4);
        final border = dark ? const Color(0xFF29445B) : const Color(0xFFE3EAF0);
        return StatefulBuilder(builder: (popupContext, setSheetState) {
          List<Map<String,dynamic>> applyFilter(List<Map<String,dynamic>> items) => items.where((e) {
            final days = _reminderDays(e['date'] ?? e['dueDate'] ?? e['due_date']) ?? 0;
            return filter == 'সবগুলো' || (filter == 'আজকের' && days == 0) || (filter == 'আসন্ন' && days > 0);
          }).toList();
          final bills = applyFilter(billsDue), debts = applyFilter(debtsDue);
          final all = [...billsDue, ...debtsDue];
          final todayCount = all.where((e) => _reminderDays(e['date'] ?? e['dueDate'] ?? e['due_date']) == 0).length;
          final upcomingCount = all.where((e) => (_reminderDays(e['date'] ?? e['dueDate'] ?? e['due_date']) ?? -1) > 0).length;
          Widget card(Map<String,dynamic> item, bool isBill) {
            final dateValue = item['date'] ?? item['dueDate'] ?? item['due_date'];
            final days = _reminderDays(dateValue) ?? 0;
            final due = days < 0 ? '${_bengaliDigits(days.abs().toString())} দিন পেরিয়েছে' : days == 0 ? 'আজ' : '${_bengaliDigits(days.toString())} দিন বাকি';
            final title = isBill ? (item['title'] ?? item['name'] ?? 'নাম নেই').toString() : (item['personName'] ?? item['name'] ?? item['person'] ?? item['title'] ?? 'নাম নেই').toString();
            final accent = isBill ? const Color(0xFFFF6472) : const Color(0xFF347FF5);
            final urgent = days <= 1;
            return Material(color: surface, borderRadius: BorderRadius.circular(14), child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.pop(dialogContext);
                Navigator.of(context).push(_route(isBill
                  ? _BillsScreen(bills: _bills, onReload: () async { await _load(); return List<Map<String,dynamic>>.from(_bills); })
                  : _DebtsScreen(debts: _debts, wallets: _walletBalances.keys.toList(), onReload: () async { await _load(); return List<Map<String,dynamic>>.from(_debts); })));
              },
              child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(14)), child: Column(children: [
                Row(children: [
                  Container(width:38,height:38,decoration:BoxDecoration(color:accent.withValues(alpha:.12),borderRadius:BorderRadius.circular(11)),child:Icon(isBill?Icons.receipt_long_rounded:Icons.account_balance_wallet_outlined,color:accent,size:20)),
                  const SizedBox(width:10),
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(title,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:ink,fontSize:13,fontWeight:FontWeight.w800)),
                    const SizedBox(height:3),
                    Text(isBill?_reminderDateLabel(dateValue):'${(item['debtKind']??item['status']??'').toString()} · ${_reminderDateLabel(dateValue)}',style:TextStyle(color:muted,fontSize:10.5),maxLines:1,overflow:TextOverflow.ellipsis),
                  ])),
                  const SizedBox(width:7),
                  Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:6),decoration:BoxDecoration(color:urgent?const Color(0xFFFFF0E5):const Color(0xFFFFF4D9),borderRadius:BorderRadius.circular(9)),child:Text(due,style:TextStyle(color:urgent?const Color(0xFFD65D27):const Color(0xFFB7791F),fontSize:10,fontWeight:FontWeight.w800))),
                  Icon(Icons.chevron_right_rounded,color:muted),
                ]),
                const SizedBox(height:9),
                ClipRRect(borderRadius:BorderRadius.circular(8),child:LinearProgressIndicator(value:days<0?1:((8-days)/8).clamp(.12,1).toDouble(),minHeight:4,backgroundColor:panel,color:urgent?const Color(0xFFEF5350):accent)),
              ])),
            ));
          }
          return Dialog(
            alignment: Alignment.center,
            insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
            width: double.infinity,
            constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.of(dialogContext).size.height * .78),
            decoration: BoxDecoration(color:surface,borderRadius:BorderRadius.circular(22)),
            child: Column(mainAxisSize:MainAxisSize.min,children:[
              const SizedBox(height:9),
              Container(width:38,height:4,decoration:BoxDecoration(color:muted.withValues(alpha:.5),borderRadius:BorderRadius.circular(8))),
              Padding(padding:const EdgeInsets.fromLTRB(18,15,12,12),child:Row(children:[
                Container(width:42,height:42,decoration:BoxDecoration(color:const Color(0xFFEAF0FF),borderRadius:BorderRadius.circular(13)),child:const Icon(Icons.notifications_active_rounded,color:Color(0xFF347FF5))),
                const SizedBox(width:10),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text('রিমাইন্ডার',style:TextStyle(color:ink,fontSize:18,fontWeight:FontWeight.w900)),
                  Text('আপনার বিল এবং দেনা-পাওনার রিমাইন্ডার',style:TextStyle(color:muted,fontSize:10.5)),
                ])),
                IconButton(onPressed:()=>Navigator.pop(dialogContext),icon:Icon(Icons.close,color:muted)),
              ])),
              Divider(height:1,color:border),
              Padding(padding:const EdgeInsets.fromLTRB(15,12,15,9),child:Container(padding:const EdgeInsets.all(4),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(30)),child:Row(children:[
                for(final entry in [('সবগুলো',all.length),('আজকের',todayCount),('আসন্ন',upcomingCount)])
                  Expanded(child:GestureDetector(onTap:()=>setSheetState(()=>filter=entry.$1),child:AnimatedContainer(duration:const Duration(milliseconds:150),padding:const EdgeInsets.symmetric(vertical:10,horizontal:2),decoration:BoxDecoration(color:filter==entry.$1?const Color(0xFF347FF5):Colors.transparent,borderRadius:BorderRadius.circular(24)),child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
                    Text(entry.$1,style:TextStyle(color:filter==entry.$1?Colors.white:muted,fontSize:11,fontWeight:FontWeight.w800)),
                    const SizedBox(width:4),
                    Text(_bengaliDigits(entry.$2.toString()),style:TextStyle(color:filter==entry.$1?Colors.white:ink,fontSize:10,fontWeight:FontWeight.w900)),
                  ])))),
              ]))),
              Flexible(child:ListView(shrinkWrap:true,padding:const EdgeInsets.fromLTRB(15,2,15,18),children:[
                if(bills.isEmpty&&debts.isEmpty) Padding(padding:const EdgeInsets.symmetric(vertical:34),child:Center(child:Text('এখন কোনো রিমাইন্ডার নেই।',style:TextStyle(color:muted,fontSize:12)))),
                if(bills.isNotEmpty)...[
                  Padding(padding:const EdgeInsets.only(top:5,bottom:9),child:Text('বিল',style:TextStyle(color:ink,fontWeight:FontWeight.w900,fontSize:13))),
                  ...bills.map((e)=>Padding(padding:const EdgeInsets.only(bottom:9),child:card(e,true))),
                ],
                if(debts.isNotEmpty)...[
                  Padding(padding:const EdgeInsets.only(top:5,bottom:9),child:Text('দেনা-পাওনা',style:TextStyle(color:ink,fontWeight:FontWeight.w900,fontSize:13))),
                  ...debts.map((e)=>Padding(padding:const EdgeInsets.only(bottom:9),child:card(e,false))),
                ],
              ])),
              Padding(padding:const EdgeInsets.fromLTRB(15,0,15,14),child:SizedBox(width:double.infinity,child:OutlinedButton(onPressed:(){
                Navigator.pop(dialogContext);
                Navigator.of(context).push(_route(debts.isNotEmpty&&bills.isEmpty
                  ? _DebtsScreen(debts:_debts,wallets:_walletBalances.keys.toList(),onReload:()async{await _load();return List<Map<String,dynamic>>.from(_debts);})
                  : _BillsScreen(bills:_bills,onReload:()async{await _load();return List<Map<String,dynamic>>.from(_bills); })));
              },child:const Text('সব দেখুন →')))),
            ]),
              ),
            ),
          );
        });
      },
    );
  }

  Widget _entranceAnimation(Widget child, int _) => child;

  String _money(double value) => '৳ ${value.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF071827) : const Color(0xFFF3F8F5),
          statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF071827) : const Color(0xFFF3F8F5),
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
                      ? const [Color(0xFF071827), Color(0xFF081B2D), Color(0xFF0A1E32), Color(0xFF071827)]
                      : const [Color(0xFFF3F8F5), Color(0xFFEAF5EF), Color(0xFFF7FBF8), Color(0xFFF3F8F5)],
                  stops: const [0.0, 0.34, 0.72, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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
                              Text('আমার হিসাব', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF6CCBFF) : const Color(0xFF087A5B), fontSize: 23, fontWeight: FontWeight.w900, height: 1.0)),
                              Transform.translate(
                                offset: const Offset(0, -2),
                                child: Text('আপনার আয়-ব্যয়ের সহজ সঙ্গী', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFB9CADB) : const Color(0xFF587267), fontSize: 10.5, height: 1.0)),
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
                                icon: Icon(Icons.menu_rounded, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFD9ECFF) : const Color(0xFF087A5B), size: 27),
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
                                    onPressed: _showReminderSheet,
                                    icon: Icon(Icons.notifications_none_rounded, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFD9ECFF) : const Color(0xFF087A5B), size: 25),
                                  ),
                                  Positioned(
                                    right: 9,
                                    top: 8,
                                    child: _activeReminderCount > 0
                                        ? Container(
                                            constraints: const BoxConstraints(minWidth: 8, minHeight: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 3),
                                            decoration: const BoxDecoration(color: Color(0xFFE53935), shape: BoxShape.circle),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ),
                            Transform.translate(
                              offset: const Offset(0, -5),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => Navigator.of(context).push(_route(const ProfileScreen())),
                                child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Color(0xFF8AD8FF), Color(0xFF287FCB)],
                                  ),
                                  border: Border.all(color: const Color(0xFFE7FFF7), width: 1.5),
                                  boxShadow: [
                                    BoxShadow(color: const Color(0xFF4ABEFF).withValues(alpha: .14), blurRadius: 8),
                                  ],
                                ),
                                child: const Icon(Icons.person_rounded, color: Colors.white, size: 26),
                                ),
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
                              ? const Color(0xFF4ABEFF).withValues(alpha: .78)
                              : const Color(0xFF79DDB8),
                          width: 1.25,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: Theme.of(context).brightness == Brightness.dark
                              ? const [Color(0xD9163048), Color(0xD910263C), Color(0xD9081B2D)]
                              : const [Color(0xFFF9FFFC), Color(0xFFEAFBF3), Color(0xFFF5FFFA)],
                        ),
                        boxShadow: Theme.of(context).brightness == Brightness.dark
                            ? [
                                BoxShadow(color: const Color(0xFF65C8FF).withValues(alpha: .08), blurRadius: 14, spreadRadius: 0, offset: const Offset(0, 3)),
                                BoxShadow(color: const Color(0xFF000F20).withValues(alpha: .14), blurRadius: 10, offset: const Offset(0, 4)),
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
                                    icon: Icon(_hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFB8E3FF) : const Color(0xFF168565), size: 18),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? const Color(0xFF55BFFF).withValues(alpha: .12)
                                          : const Color(0xFFBDF5DF).withValues(alpha: .48),
                                      border: Border.all(
                                        color: Theme.of(context).brightness == Brightness.dark
                                            ? const Color(0xFF67C7FF).withValues(alpha: .34)
                                            : const Color(0xFF6FD9B2).withValues(alpha: .58),
                                      ),
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('এই মাস', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFD9ECFF) : const Color(0xFF155A45), fontSize: 12, fontWeight: FontWeight.w700)),
                                        SizedBox(width: 5),
                                        Icon(Icons.keyboard_arrow_down_rounded, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFD9ECFF) : const Color(0xFF155A45), size: 17),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 0),
                              if (_loading)
                                Transform.translate(
                                  offset: const Offset(18, -19),
                                  child: SizedBox(height: 30, child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF4ABEFF) : const Color(0xFF00A875))))),
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
                                          ? const Color(0xFF4ABEFF).withValues(alpha: .16)
                                          : const Color(0xFFE7F5EE),
                                      border: Border.all(
                                        color: Theme.of(context).brightness == Brightness.dark
                                            ? const Color(0xFF4ABEFF).withValues(alpha: .62)
                                            : const Color(0xFFC6E5D5),
                                      ),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.trending_up_rounded, size: 15, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF65C8FF) : const Color(0xFF579779)),
                                        SizedBox(width: 3),
                                        Text(
                                          _monthChangePercent == null
                                              ? _monthChangeMessage
                                              : '${_monthChangePercent! >= 0 ? '+' : '-'}${_monthChangePercent!.abs().toStringAsFixed(1)}% গত মাসের তুলনায়',
                                          style: TextStyle(
                                            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFD6EEFF) : const Color(0xFF527D69),
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
                                      style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFB9CADB) : const Color(0xFF55796B), fontSize: 11),
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
                        Expanded(child: InkWell(onTap: _openWalletManagement, borderRadius: BorderRadius.circular(12), child: _entranceAnimation(_walletCard('ব্যাংক', Icons.account_balance_rounded, const Color(0xFF1688D4)), 1))),
                        const SizedBox(width: 7),
                        Expanded(child: InkWell(onTap: _openWalletManagement, borderRadius: BorderRadius.circular(12), child: _entranceAnimation(_walletCard('ক্যাশ', Icons.account_balance_wallet_rounded, const Color(0xFF16B981)), 2))),
                        const SizedBox(width: 7),
                        Expanded(child: InkWell(onTap: _openWalletManagement, borderRadius: BorderRadius.circular(12), child: _entranceAnimation(_walletCard('বিকাশ', Icons.payments_rounded, const Color(0xFFE83E8C)), 3))),
                        const SizedBox(width: 7),
                        Expanded(child: InkWell(onTap: _openWalletManagement, borderRadius: BorderRadius.circular(12), child: _entranceAnimation(_walletCard('নগদ', Icons.account_balance_wallet_rounded, const Color(0xFFFF8A00)), 4))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  if (_compactCharts)
                    _entranceAnimation(_compactExpenseOverview(), 5)
                  else ...[
                    _entranceAnimation(_incomeExpenseChart(), 5),
                    const SizedBox(height: 6),
                    _entranceAnimation(_incomeExpenseDonuts(), 6),
                  ],
                  const SizedBox(height: 6),

                if (_error != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('আবার চেষ্টা করুন')),
                  ],
                      ],
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _entranceAnimation(_recentTransactionsCard(), 7),
                  ),
                ),
              ],
            ),
          ),
          AnimatedPositioned(
            duration: Duration(milliseconds: _showAddTransactionFab ? 560 : 420),
            curve: _showAddTransactionFab ? Curves.easeOutBack : Curves.easeInCubic,
            right: 28,
            bottom: _showAddTransactionFab ? 30 : -82,
            child: AnimatedScale(
              duration: Duration(milliseconds: _showAddTransactionFab ? 560 : 420),
              curve: _showAddTransactionFab ? Curves.elasticOut : Curves.easeInCubic,
              scale: _showAddTransactionFab ? 1 : 0.72,
              child: AnimatedOpacity(
                duration: Duration(milliseconds: _showAddTransactionFab ? 260 : 360),
                curve: _showAddTransactionFab ? Curves.easeOut : Curves.easeInCubic,
                opacity: _showAddTransactionFab ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !_showAddTransactionFab,
                  child: FloatingActionButton(
                    heroTag: 'add-transaction-fab',
                    backgroundColor: const Color(0xFF187BFA),
                    foregroundColor: Colors.white,
                    onPressed: _showAddTransaction,
                    child: const Icon(Icons.add_rounded, size: 31),
                  ),
                ),
              ),
            ),
          ),
        ]),
        ),
      );


  static String _monthKey(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}';

  String _monthLabel(String key) {
    const months = <String>[
      'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
      'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
    ];
    final parts = key.split('-');
    final year = int.tryParse(parts.first) ?? DateTime.now().year;
    final month = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
    return '${months[(month - 1).clamp(0, 11).toInt()]} ${_bengaliDigits(year.toString())}';
  }

  List<String> _recentTransactionMonthOptions() {
    final keys = <String>{_monthKey(DateTime.now())};
    for (final tx in _transactions) {
      final date = _parseTransactionDate(tx['dateInput'] ?? tx['date_input'] ?? tx['date'] ?? tx['createdAt'] ?? tx['created_at']);
      if (date != null) keys.add(_monthKey(date));
    }
    final sorted = keys.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  String _transactionCategoryLabel(Map<String, dynamic> tx) {
    final value = (tx['categoryName'] ?? tx['category_name'] ?? tx['category'] ?? tx['categoryTitle'] ?? tx['category_title'] ?? tx['subcategory'] ?? '').toString().trim();
    return value.isEmpty ? 'অন্যান্য' : value;
  }

  List<Map<String, dynamic>> _monthFilteredRecentTransactions() {
    final items = _sortedRecentTransactions();
    if (_recentTransactionsMonthKey == 'all') return items;
    return items.where((tx) {
      final date = _parseTransactionDate(tx['dateInput'] ?? tx['date_input'] ?? tx['date'] ?? tx['createdAt'] ?? tx['created_at']);
      return date != null && _monthKey(date) == _recentTransactionsMonthKey;
    }).toList();
  }

  List<MapEntry<String, int>> _recentTransactionCategoryCounts() {
    final counts = <String, int>{};
    for (final tx in _monthFilteredRecentTransactions()) {
      final category = _transactionCategoryLabel(tx);
      counts[category] = (counts[category] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries;
  }

  List<Map<String, dynamic>> _visibleRecentTransactions() {
    final items = _monthFilteredRecentTransactions();
    if (_recentTransactionsCategory == 'সব') return items;
    return items.where((tx) => _transactionCategoryLabel(tx) == _recentTransactionsCategory).toList();
  }

  List<Map<String, dynamic>> _sortedRecentTransactions() {
    final items = List<Map<String, dynamic>>.from(_transactions);
    items.sort((a, b) {
      final aDate = _parseTransactionDate(a['dateInput'] ?? a['date_input'] ?? a['date'] ?? a['createdAt'] ?? a['created_at']);
      final bDate = _parseTransactionDate(b['dateInput'] ?? b['date_input'] ?? b['date'] ?? b['createdAt'] ?? b['created_at']);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return items;
  }

  String _formatTransactionTime(String value) {
    final parts = value.trim().split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return value;
    final clock = parts.first.split(':');
    if (clock.length != 2) return value;

    const bengali = '০১২৩৪৫৬৭৮৯';
    var hourText = clock[0];
    var minuteText = clock[1];
    for (var i = 0; i < bengali.length; i++) {
      hourText = hourText.replaceAll(bengali[i], '$i');
      minuteText = minuteText.replaceAll(bengali[i], '$i');
    }
    var hour = int.tryParse(hourText);
    final minute = int.tryParse(minuteText);
    if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) return value;

    final suppliedPeriod = parts.length > 1 ? parts[1].toUpperCase() : null;
    final period = suppliedPeriod == 'AM' || suppliedPeriod == 'PM'
        ? suppliedPeriod!
        : (hour >= 12 ? 'PM' : 'AM');
    hour %= 12;
    if (hour == 0) hour = 12;
    return '${_bengaliDigits(hour.toString())}:${_bengaliDigits(minute.toString().padLeft(2, '0'))} $period';
  }

  String _transactionDateTimeLabel(Map<String, dynamic> tx) {
    final date = _parseTransactionDate(tx['dateInput'] ?? tx['date_input'] ?? tx['date'] ?? tx['createdAt'] ?? tx['created_at']);
    final time = (tx['timeInput'] ?? tx['time_input'] ?? tx['time'] ?? '').toString().trim();
    if (date == null) return time.isEmpty ? '' : time;
    final dateText = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return time.isEmpty ? dateText : '$dateText, $time';
  }



  IconData? _savedTransactionIcon(Map<String, dynamic> tx) {
    final name = (tx['icon'] ?? tx['iconName'] ?? tx['icon_name'] ?? '').toString();
    return _transactionIconOptions[name];
  }

  ({Color accent, Color tint, IconData icon}) _transactionStyle(Map<String, dynamic> tx) {
    final kind = (tx['kind'] ?? '').toString();
    final value = '${tx['title'] ?? tx['description'] ?? ''} ${tx['categoryName'] ?? tx['category_name'] ?? tx['category'] ?? ''}'.toLowerCase();
    final savedIcon = _savedTransactionIcon(tx);
    if (kind == 'আয়') return (accent: const Color(0xFF00A653), tint: const Color(0xFFF3FBF6), icon: savedIcon ?? Icons.south_rounded);
    if (kind == 'ট্রান্সফার' || kind.toLowerCase() == 'transfer') return (accent: const Color(0xFF1688D4), tint: const Color(0xFFEAF4FF), icon: savedIcon ?? Icons.swap_horiz_rounded);
    if (value.contains('খাবার') || value.contains('food')) return (accent: const Color(0xFFE92743), tint: const Color(0xFFFFF7F8), icon: savedIcon ?? Icons.restaurant_rounded);
    if (value.contains('বাসা') || value.contains('বাড়ি') || value.contains('লোন')) return (accent: const Color(0xFFD96A00), tint: const Color(0xFFFFF1E1), icon: savedIcon ?? Icons.home_rounded);
    if (value.contains('ইন্টারনেট') || value.contains('বিল')) return (accent: const Color(0xFF00A653), tint: const Color(0xFFF3FBF6), icon: savedIcon ?? Icons.router_rounded);
    if (value.contains('উপহার')) return (accent: const Color(0xFF8627D9), tint: const Color(0xFFF5EBFF), icon: savedIcon ?? Icons.card_giftcard_rounded);
    if (value.contains('যাতায়াত') || value.contains('বাস')) return (accent: const Color(0xFF1688D4), tint: const Color(0xFFEAF4FF), icon: savedIcon ?? Icons.directions_bus_rounded);
    return (accent: const Color(0xFFE92743), tint: const Color(0xFFFFF7F8), icon: savedIcon ?? Icons.shopping_cart_rounded);
  }

  Map<String, List<Map<String, dynamic>>> _groupTransactionsByDate(List<Map<String, dynamic>> items) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final tx in items) {
      final date = _parseTransactionDate(tx['dateInput'] ?? tx['date_input'] ?? tx['date'] ?? tx['createdAt'] ?? tx['created_at']);
      final key = date == null ? 'unknown' : '${date.year}-${date.month}-${date.day}';
      groups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(tx);
    }
    return groups;
  }

  String _bengaliDigits(String value) => value
      .replaceAll('0', '০').replaceAll('1', '১').replaceAll('2', '২')
      .replaceAll('3', '৩').replaceAll('4', '৪').replaceAll('5', '৫')
      .replaceAll('6', '৬').replaceAll('7', '৭').replaceAll('8', '৮')
      .replaceAll('9', '৯');

  Widget _transactionDateHeading(List<Map<String, dynamic>> items, bool isDark) {
    final date = items.isEmpty
        ? null
        : _parseTransactionDate(items.first['dateInput'] ?? items.first['date_input'] ?? items.first['date'] ?? items.first['createdAt'] ?? items.first['created_at']);
    const months = <String>[
      'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
      'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
    ];
    final dateLabel = date == null
        ? 'তারিখ পাওয়া যায়নি'
        : '${_bengaliDigits(date.day.toString())} ${months[date.month - 1]}, ${_bengaliDigits(date.year.toString())}';
    final income = items.where((tx) => tx['kind'] == 'আয়')
        .fold<double>(0, (sum, tx) => sum + _amount(tx['amount']));
    final expense = items.where((tx) => tx['kind'] == 'ব্যয়')
        .fold<double>(0, (sum, tx) => sum + _amount(tx['amount']));
    final muted = isDark ? const Color(0xFF9BAEAA) : const Color(0xFF71818C);
    final dateColor = isDark ? const Color(0xFFC3D4D0) : const Color(0xFF526875);

    return Padding(
      padding: const EdgeInsets.fromLTRB(1, 6, 2, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 370;
          final dateFont = compact ? 11.0 : 12.0;
          final infoFont = compact ? 10.0 : 11.0;
          final amountFont = compact ? 10.0 : 11.0;

          return Row(
            children: [
              Text(
                dateLabel,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(color: dateColor, fontSize: dateFont, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 5),
              Text(
                '${_bengaliDigits(items.length.toString())}টি',
                maxLines: 1,
                style: TextStyle(color: muted, fontSize: infoFont),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Divider(
                  height: 1,
                  color: isDark ? const Color(0xFF29433E) : const Color(0xFFDCE4E8),
                ),
              ),
              const SizedBox(width: 7),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('আয়: ', style: TextStyle(color: muted, fontSize: infoFont)),
                    Text(_bengaliDigits(_money(income)),
                      style: TextStyle(color: const Color(0xFF00A653), fontSize: amountFont, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 5),
                    Text('ব্যয়: ', style: TextStyle(color: muted, fontSize: infoFont)),
                    Text(_bengaliDigits(_money(expense)),
                      style: TextStyle(color: const Color(0xFFE92743), fontSize: amountFont, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _recentTransactionRow(Map<String, dynamic> tx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kind = (tx['kind'] ?? '').toString();
    final isIncome = kind == 'আয়';
    final isTransfer = kind == 'ট্রান্সফার' || kind.toLowerCase() == 'transfer';
    final style = _transactionStyle(tx);
    final rawTitle = (tx['title'] ?? tx['description'] ?? tx['note'] ?? tx['name'] ?? 'লেনদেন').toString();
    final paymentTitle = RegExp(r'^(বিল পরিশোধ|দেনা পরিশোধ|পাওনা জমা|ক্রেডিট কার্ড উত্তোলন)\s*[—–-]\s*(.+)$').firstMatch(rawTitle);
    final title = paymentTitle?.group(2)?.trim() ?? rawTitle;
    final category = (tx['categoryName'] ?? tx['category_name'] ?? tx['category'] ?? tx['categoryTitle'] ?? '').toString();
    final wallet = (tx['wallet'] ?? tx['walletName'] ?? tx['wallet_name'] ?? tx['accountName'] ?? tx['account'] ?? '').toString();
    final subtitle = [
      if (paymentTitle != null) paymentTitle.group(1)!.trim(),
      wallet,
    ].where((v) => v.trim().isNotEmpty).join(' • ');
    final amountColor = isIncome ? const Color(0xFF00A653) : isTransfer ? const Color(0xFF1688D4) : const Color(0xFFE92743);
    final cardTint = isIncome
        ? const Color(0xFFF3FBF6)
        : isTransfer
            ? const Color(0xFFEAF4FF)
            : const Color(0xFFFFF7F8);
    final cardDarkBase = isIncome
        ? const Color(0xFF142F27)
        : isTransfer
            ? const Color(0xFF142B40)
            : const Color(0xFF351F28);
    final prefix = isIncome ? '+' : isTransfer ? '↔' : '−';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 3, 2, 3),
      decoration: BoxDecoration(
        color: isDark ? cardDarkBase : cardTint,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: style.accent.withValues(alpha: isDark ? .24 : .05)),

      ),
      child: InkWell(
        onTap: () => _showTransactionDetails(tx),
        borderRadius: BorderRadius.circular(15),
        child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: amountColor.withValues(alpha: isDark ? .18 : .10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(style.icon, color: amountColor, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? const Color(0xFFF1FAF6) : const Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w900)),
          if (subtitle.isNotEmpty) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? const Color(0xFFAABBCD) : const Color(0xFF657481), fontSize: 11.5)),
          Row(children: [Icon(Icons.access_time_rounded, size: 13, color: isDark ? const Color(0xFF91A6BC) : const Color(0xFF7B8993)), const SizedBox(width: 4), Text(_formatTransactionTime(_transactionDateTimeLabel(tx).split(', ').last), style: TextStyle(color: isDark ? const Color(0xFF91A6BC) : const Color(0xFF71808C), fontSize: 10.5))]),
        ])),
        const SizedBox(width: 5),
        SizedBox(width: 98, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text('$prefix ${_money(_amount(tx['amount']))}', maxLines: 1, style: TextStyle(color: amountColor, fontSize: 13, fontWeight: FontWeight.w900))),
          const SizedBox(height: 3),
          if (category.isNotEmpty) Container(
            constraints: const BoxConstraints(maxWidth: 96),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: style.accent.withValues(alpha: .06), borderRadius: BorderRadius.circular(20), border: Border.all(color: style.accent.withValues(alpha: .10))),
            child: Text(category, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: style.accent, fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ])),
        PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          icon: Icon(Icons.more_vert_rounded, color: isDark ? const Color(0xFF9BA9B2) : const Color(0xFF7B8791), size: 20),
          onSelected: (action) {
            if (action == 'edit') _editTransaction(tx);
            if (action == 'delete') _deleteTransaction(tx);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Row(children: [
              Icon(Icons.edit_outlined, size: 18), SizedBox(width: 10), Text('এডিট করুন'),
            ])),
            PopupMenuItem(value: 'delete', child: Row(children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFE53935)),
              SizedBox(width: 10), Text('ডিলিট করুন', style: TextStyle(color: Color(0xFFE53935))),
            ])),
          ],
        ),
        ]),
      ),
    );
  }

  Widget _recentTransactionsCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = _visibleRecentTransactions();
    final categoryCounts = _recentTransactionCategoryCounts();
    final monthOptions = _recentTransactionMonthOptions();
    final selectedMonthLabel = _recentTransactionsMonthKey == 'all'
        ? 'সব মাস'
        : _monthLabel(_recentTransactionsMonthKey);
    final groups = _groupTransactionsByDate(items);
    final titleColor = isDark ? const Color(0xFFE5F8F0) : const Color(0xFF164F40);
    final listChildren = <Widget>[];
    for (final entry in groups.entries) {
      listChildren.add(_transactionDateHeading(entry.value, isDark));
      for (final tx in entry.value) {
        listChildren.add(_recentTransactionRow(tx));
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D2033) : const Color(0xFFFCFEFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF29445D) : const Color(0xFFE2ECE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 5, 2, 2),
            child: Row(children: [
              Expanded(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text('সাম্প্রতিক লেনদেন', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: titleColor, fontSize: 15, fontWeight: FontWeight.w900))),
                  const SizedBox(width: 5),
                  Text('${_bengaliDigits(items.length.toString())}টি', style: TextStyle(color: isDark ? const Color(0xFF94A9BF) : const Color(0xFF71818C), fontSize: 10.5)),
                ]),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 112, maxWidth: 150),
                tooltip: 'মাস নির্বাচন করুন',
                onSelected: (value) => setState(() => _recentTransactionsMonthKey = value),
                color: isDark ? const Color(0xFF102A38) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'all',
                    height: 36,
                    child: Text('সব মাস', style: TextStyle(color: titleColor, fontSize: 11)),
                  ),
                  for (final monthKey in monthOptions)
                    PopupMenuItem<String>(
                      value: monthKey,
                      height: 36,
                      child: Text(_monthLabel(monthKey), style: TextStyle(color: titleColor, fontSize: 11)),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF4ABEFF).withValues(alpha: .12) : const Color(0xFFF0F5F3),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: isDark ? const Color(0xFF385A76) : const Color(0xFFE1EAE5)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(selectedMonthLabel, style: TextStyle(color: isDark ? const Color(0xFFDCEBFA) : const Color(0xFF526875), fontSize: 9.5, fontWeight: FontWeight.w700)),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 13, color: isDark ? const Color(0xFFDCEBFA) : const Color(0xFF526875)),
                  ]),
                ),
              ),
              const SizedBox(width: 3),
              InkWell(
                onTap: _openTransactionsPage,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('সব দেখুন  ›', style: TextStyle(color: isDark ? const Color(0xFF6CCBFF) : const Color(0xFF00A875), fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 34,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _recentCategoryFilterChip(
                    label: 'সব',
                    count: _monthFilteredRecentTransactions().length,
                    selected: _recentTransactionsCategory == 'সব',
                    isDark: isDark,
                    onTap: () => setState(() => _recentTransactionsCategory = 'সব'),
                  ),
                  for (final entry in categoryCounts) ...[
                    const SizedBox(width: 6),
                    _recentCategoryFilterChip(
                      label: entry.key,
                      count: entry.value,
                      selected: _recentTransactionsCategory == entry.key,
                      isDark: isDark,
                      onTap: () => setState(() => _recentTransactionsCategory = entry.key),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_recentTransactionsCategory != 'সব')
            _recentCategorySummary(items, isDark),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(14),
                      children: [
                        Center(
                          child: _loading
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text('এখনো কোনো লেনদেন নেই', style: TextStyle(color: titleColor, fontSize: 11)),
                        ),
                      ],
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is UserScrollNotification && notification.depth == 0) {
                          final visible = notification.direction == ScrollDirection.forward
                              ? true
                              : notification.direction == ScrollDirection.reverse
                                  ? false
                                  : _showAddTransactionFab;
                          if (visible != _showAddTransactionFab && mounted) setState(() => _showAddTransactionFab = visible);
                        }
                        return false;
                      },
                      child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: EdgeInsets.zero, children: listChildren),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentCategorySummary(List<Map<String, dynamic>> items, bool isDark) {
    var income = 0.0;
    var expense = 0.0;
    for (final tx in items) {
      final amount = _amount(tx['amount']);
      final kind = (tx['kind'] ?? '').toString();
      if (kind == 'আয়') income += amount;
      if (kind == 'ব্যয়') expense += amount;
    }
    final remaining = income - expense;
    final background = isDark ? const Color(0xFF102A38) : const Color(0xFFF0F5FA);
    final muted = isDark ? const Color(0xFFB7C9D5) : const Color(0xFF647789);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 7, bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _categorySummaryValue(
              'অবশিষ্ট', remaining,
              remaining >= 0 ? const Color(0xFF1688D4) : const Color(0xFFE27A21),
              muted, TextAlign.left,
            ),
          ),
          Expanded(
            child: _categorySummaryValue(
              'ব্যয়', expense, const Color(0xFFE92743), muted, TextAlign.center,
            ),
          ),
          Expanded(
            child: _categorySummaryValue(
              'আয়', income, const Color(0xFF00A653), muted, TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _categorySummaryValue(
    String label,
    double amount,
    Color valueColor,
    Color muted,
    TextAlign alignment,
  ) {
    return Row(
      mainAxisAlignment: alignment == TextAlign.left
          ? MainAxisAlignment.start
          : alignment == TextAlign.right
              ? MainAxisAlignment.end
              : MainAxisAlignment.center,
      children: [
        Text('$label: ', style: TextStyle(color: muted, fontSize: 9, fontWeight: FontWeight.w600)),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignment == TextAlign.left
                ? Alignment.centerLeft
                : alignment == TextAlign.right
                    ? Alignment.centerRight
                    : Alignment.center,
            child: Text(
              _bengaliDigits(_money(amount)),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(color: valueColor, fontSize: 10.5, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _recentCategoryFilterChip({
    required String label,
    required int count,
    required bool selected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final selectedColor = const Color(0xFF087FF5);
    final foreground = selected
        ? Colors.white
        : isDark ? const Color(0xFFB7C7D8) : const Color(0xFF738292);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? selectedColor
                : isDark ? const Color(0xFF14283A) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? selectedColor
                  : isDark ? const Color(0xFF344B62) : const Color(0xFFE1E8EF),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(color: foreground, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(width: 5),
            Text(_bengaliDigits(count.toString()), style: TextStyle(color: foreground, fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }


  Future<void> _showAddTransaction({String initialWallet = 'ক্যাশ', String initialKind = 'আয়', Map<String, dynamic>? editTransaction}) async {
    final tx = editTransaction;
    final now = DateTime.now();
    final existingDate = tx == null ? now : (DateTime.tryParse((tx['dateInput'] ?? tx['date_input'] ?? '').toString()) ?? _parseTransactionDate(tx['date']) ?? now);
    String to24HourTime(dynamic value) {
      final raw = (value ?? '').toString().trim();
      if (raw.isEmpty) return '';
      final parts = raw.split(RegExp(r'\\s+'));
      final clock = parts.first.split(':');
      if (clock.length != 2) return '';
      var hour = int.tryParse(clock[0]) ?? 0;
      final minute = int.tryParse(clock[1]) ?? 0;
      final suffix = parts.length > 1 ? parts.last.toUpperCase() : '';
      if (suffix == 'PM' && hour < 12) hour += 12;
      if (suffix == 'AM' && hour == 12) hour = 0;
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }
    final existingTime = tx == null ? '' : ((tx['timeInput'] ?? '').toString().isNotEmpty
        ? tx['timeInput'].toString()
        : to24HourTime(tx['time']));
    final title = TextEditingController(text: (tx?['title'] ?? tx?['description'] ?? tx?['note'] ?? '').toString());
    final amount = TextEditingController(text: tx == null ? '' : _amount(tx['amount']).toString());
    final note = TextEditingController(text: (tx?['note'] ?? '').toString());
    final date = TextEditingController(text: '${existingDate.year.toString().padLeft(4, '0')}-${existingDate.month.toString().padLeft(2, '0')}-${existingDate.day.toString().padLeft(2, '0')}');
    final time = TextEditingController(text: existingTime.isNotEmpty ? existingTime : '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}');
    var kind = (tx?['kind'] ?? initialKind).toString(); var category = (tx?['category'] ?? tx?['categoryName'] ?? 'অন্যান্য').toString(); var wallet = (tx?['wallet'] ?? tx?['walletName'] ?? tx?['account'] ?? initialWallet).toString(); var iconName = (tx?['icon'] ?? 'Banknote').toString(); var saving = false;
    final formKey = GlobalKey<FormState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF102638) : Colors.white;
    final ink = dark ? const Color(0xFFEAF5FF) : const Color(0xFF203446);
    final muted = dark ? const Color(0xFF9CB1C2) : const Color(0xFF8191A0);
    final line = dark ? const Color(0xFF29465A) : const Color(0xFFE1EAF0);
    final wallets = <String>{'ক্যাশ', 'ব্যাংক', 'বিকাশ', 'নগদ', ..._walletBalances.keys,
      ..._transactions.map((tx) => (tx['wallet'] ?? tx['walletName'] ?? '').toString()).where((v) => v.isNotEmpty)}.toList();
    await showDialog<void>(
        context: context,
        barrierDismissible: !saving,
        barrierColor: Colors.black.withValues(alpha: dark ? .62 : .30),
        builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) {
          final accent = kind == 'আয়' ? const Color(0xFF10B981) : const Color(0xFFEF4760);
          final defaults = kind == 'আয়' ? <String>['বেতন', 'ব্যবসার আয়', 'অন্যান্য'] : <String>['খাবার', 'বাসা ও ইউটিলিটি', 'যাতায়াত', 'বিল', 'স্বাস্থ্য', 'শিক্ষা', 'কেনাকাটা', 'অন্যান্য'];
          final categories = <String>{...defaults, ..._transactions.where((tx) => tx['kind'] == kind).map(_transactionCategoryLabel)}.toList();
          InputDecoration deco({String? hint, Widget? suffix}) => InputDecoration(
            hintText: hint, suffixIcon: suffix, filled: true,
            hintStyle: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
            fillColor: dark ? const Color(0xFF172F42) : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accent, width: 1.7)));
          Widget fieldLabel(String label) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(label, style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w800)),
          );
          return _ControllerDisposalScope(
            controllers: [title, amount, date, time, note],
            child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  maxHeight: (MediaQuery.of(context).size.height -
                      MediaQuery.of(context).viewInsets.bottom - 48)
                      .clamp(240.0, MediaQuery.of(context).size.height),
                ),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: line.withValues(alpha: .75)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .24 : .10), blurRadius: 28, offset: const Offset(0, 12))],
                ),
                child: Form(key: formKey, child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(18, 15, 18, 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tx == null ? 'নতুন ${kind == 'আয়' ? 'আয়' : 'ব্যয়'} যোগ করুন' : 'লেনদেন এডিট করুন', style: TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3), Text('আপনার হিসাবের তথ্য পূরণ করুন', style: TextStyle(color: muted, fontSize: 11)),
                  ])), IconButton(onPressed: saving ? null : () => Navigator.pop(sheetContext), icon: Icon(Icons.close_rounded, color: muted))]),
                  const SizedBox(height: 12),
                  Row(
                    children: ['আয়', 'ব্যয়'].map((value) {
                      final selected = kind == value;
                      final color = value == 'আয়' ? const Color(0xFF10B981) : const Color(0xFFEF4760);
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: value == 'আয়' ? 7 : 0),
                          child: InkWell(
                            onTap: () => setSheetState(() { kind = value; category = 'অন্যান্য'; }),
                            borderRadius: BorderRadius.circular(11),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: selected ? color.withValues(alpha: .12) : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(color: selected ? color : line),
                              ),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(value == 'আয়' ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                                  size: 17, color: selected ? color : muted),
                                const SizedBox(width: 6),
                                Text(value, style: TextStyle(color: selected ? color : muted,
                                  fontWeight: FontWeight.w800, fontSize: 13)),
                              ]),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 13),
                  fieldLabel('বিবরণ'),
                  TextFormField(controller: title, style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: deco(hint: kind == 'ব্যয়' ? 'যেমন: বাজার, বিদ্যুৎ বিল' : 'যেমন: বেতন, ব্যবসার আয়'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'বিবরণ লিখুন' : null),
                  const SizedBox(height: 13), fieldLabel('আইকন নির্বাচন'),
                  const SizedBox(height: 6),
                  Builder(builder: (selectorContext) {
                    final iconOptions = <(String, IconData)>[
                      ('Briefcase', Icons.work_outline_rounded), ('Banknote', Icons.payments_outlined),
                      ('CircleDollarSign', Icons.monetization_on_outlined), ('Coins', Icons.toll_outlined),
                      ('CreditCard', Icons.credit_card_outlined), ('Wallet', Icons.account_balance_wallet_outlined),
                      ('WalletCards', Icons.wallet_outlined), ('HandCoins', Icons.volunteer_activism_outlined),
                      ('BadgeDollarSign', Icons.price_check_rounded), ('ReceiptText', Icons.receipt_long_outlined),
                      ('ChartNoAxesCombined', Icons.query_stats_rounded), ('TrendingUp', Icons.trending_up_rounded),
                      ('TrendingDown', Icons.trending_down_rounded), ('Calculator', Icons.calculate_outlined),
                      ('Percent', Icons.percent_rounded), ('Store', Icons.storefront_outlined),
                      ('ShoppingCart', Icons.shopping_cart_outlined), ('ShoppingBag', Icons.shopping_bag_outlined),
                      ('ShoppingBasket', Icons.shopping_basket_outlined), ('Tag', Icons.sell_outlined),
                      ('Gift', Icons.card_giftcard_outlined), ('Package', Icons.inventory_2_outlined),
                      ('PackageOpen', Icons.unarchive_outlined), ('House', Icons.home_outlined),
                      ('BedDouble', Icons.bed_outlined), ('Sofa', Icons.weekend_outlined),
                      ('Lamp', Icons.light_outlined), ('Lightbulb', Icons.lightbulb_outline_rounded),
                      ('Plug', Icons.power_outlined), ('HousePlug', Icons.electrical_services_outlined),
                      ('Droplets', Icons.water_drop_outlined), ('Flame', Icons.local_fire_department_outlined),
                      ('Wifi', Icons.wifi_rounded), ('Smartphone', Icons.smartphone_rounded),
                      ('Laptop', Icons.laptop_outlined), ('Monitor', Icons.desktop_windows_outlined),
                      ('Tv', Icons.tv_outlined), ('Router', Icons.router_outlined),
                      ('Printer', Icons.print_outlined), ('Camera', Icons.camera_alt_outlined),
                      ('Headphones', Icons.headphones_outlined), ('Gamepad2', Icons.sports_esports_outlined),
                      ('Car', Icons.directions_car_outlined), ('CarFront', Icons.directions_car_filled_outlined),
                      ('Bus', Icons.directions_bus_outlined), ('BusFront', Icons.directions_bus_filled_outlined),
                      ('Train', Icons.train_outlined), ('Bike', Icons.pedal_bike_outlined),
                      ('Plane', Icons.flight_outlined), ('PlaneTakeoff', Icons.flight_takeoff_rounded),
                      ('Ship', Icons.directions_boat_outlined), ('Fuel', Icons.local_gas_station_outlined),
                      ('MapPin', Icons.location_on_outlined), ('Route', Icons.alt_route_rounded),
                      ('Utensils', Icons.restaurant_outlined), ('UtensilsCrossed', Icons.restaurant_menu_rounded),
                      ('CookingPot', Icons.soup_kitchen_outlined), ('Coffee', Icons.coffee_outlined),
                      ('Pizza', Icons.local_pizza_outlined), ('Salad', Icons.eco_outlined),
                      ('Sandwich', Icons.lunch_dining_outlined), ('Cake', Icons.cake_outlined),
                      ('IceCream', Icons.icecream_outlined), ('Apple', Icons.apple_rounded),
                      ('Carrot', Icons.grass_rounded), ('Pill', Icons.medication_outlined),
                      ('Stethoscope', Icons.medical_services_outlined), ('HeartPulse', Icons.monitor_heart_outlined),
                      ('Cross', Icons.add_rounded), ('Syringe', Icons.vaccines_outlined),
                      ('Hospital', Icons.local_hospital_outlined), ('Bandage', Icons.healing_outlined),
                      ('Dumbbell', Icons.fitness_center_rounded), ('GraduationCap', Icons.school_outlined),
                      ('BookOpen', Icons.menu_book_outlined), ('Book', Icons.book_outlined),
                      ('School', Icons.cast_for_education_outlined), ('Notebook', Icons.note_alt_outlined),
                      ('FileText', Icons.description_outlined), ('Music', Icons.music_note_rounded),
                      ('Film', Icons.movie_outlined), ('Clapperboard', Icons.video_camera_back_outlined),
                      ('Theater', Icons.theater_comedy_outlined), ('Popcorn', Icons.local_movies_outlined),
                      ('PartyPopper', Icons.celebration_outlined), ('Ticket', Icons.confirmation_number_outlined),
                      ('Trophy', Icons.emoji_events_outlined), ('Turtle', Icons.pets_outlined),
                      ('Dog', Icons.pets_rounded), ('Cat', Icons.pets_rounded),
                      ('PawPrint', Icons.pets_outlined), ('Bone', Icons.cruelty_free_outlined),
                      ('Shirt', Icons.checkroom_outlined), ('Footprints', Icons.directions_walk_rounded),
                      ('Watch', Icons.watch_outlined), ('Glasses', Icons.visibility_outlined),
                      ('Gem', Icons.diamond_outlined), ('Users', Icons.groups_outlined),
                      ('Baby', Icons.child_care_outlined), ('Heart', Icons.favorite_border_rounded),
                      ('Flower2', Icons.local_florist_outlined), ('Sprout', Icons.grass_outlined),
                      ('TreePine', Icons.park_outlined), ('Leaf', Icons.eco_outlined),
                      ('Sun', Icons.wb_sunny_outlined), ('CloudRain', Icons.cloudy_snowing),
                      ('Snowflake', Icons.ac_unit_rounded), ('Umbrella', Icons.umbrella_outlined),
                      ('Wrench', Icons.build_outlined), ('Hammer', Icons.handyman_outlined),
                      ('Paintbrush', Icons.brush_outlined), ('Scissors', Icons.content_cut_rounded),
                      ('Trash2', Icons.delete_outline_rounded), ('Recycle', Icons.recycling_rounded),
                      ('CalendarDays', Icons.calendar_month_outlined), ('Clock', Icons.schedule_rounded),
                      ('Bell', Icons.notifications_none_rounded), ('ShieldCheck', Icons.verified_user_outlined),
                      ('KeyRound', Icons.key_outlined), ('Ellipsis', Icons.more_horiz_rounded),
                    ];
                    final selectedIcon = iconOptions.firstWhere((e) => e.$1 == iconName, orElse: () => iconOptions[1]);
                    return Row(children: [
                      Container(width: 38, height: 38, decoration: BoxDecoration(
                        color: accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(10)),
                        child: Icon(selectedIcon.$2, color: accent, size: 21)),
                      const SizedBox(width: 9),
                      Expanded(child: PopupMenuButton<String>(
                        tooltip: 'আইকন বেছে নিন',
                        onSelected: (value) => setSheetState(() => iconName = value),
                        itemBuilder: (menuContext) => [
                          PopupMenuItem<String>(
                            enabled: false,
                            padding: const EdgeInsets.all(8),
                            child: Builder(builder: (popupContext) => SizedBox(
                              width: 300, height: 220,
                              child: GridView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: iconOptions.length,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 6, mainAxisSpacing: 5, crossAxisSpacing: 5,
                                ),
                                itemBuilder: (context, index) {
                                  final entry = iconOptions[index];
                                  final selected = iconName == entry.$1;
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => Navigator.of(popupContext).pop(entry.$1),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: selected ? accent.withValues(alpha: .12) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: selected ? accent : Colors.transparent),
                                      ),
                                      child: Icon(entry.$2, size: 22, color: selected ? accent : ink),
                                    ),
                                  );
                                },
                              ),
                            )),
                          ),
                        ],
                        child: Container(height: 42, decoration: BoxDecoration(
                          color: dark ? const Color(0xFF172F42) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
                          child: Center(child: Icon(Icons.grid_view_rounded, color: ink, size: 21))),
                      )),
                    ]);
                  }),
                  const SizedBox(height: 13), fieldLabel('পরিমাণ (৳)'),
                  TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 13),
                    decoration: deco(hint: '0.00'), validator: (v) { final n = double.tryParse(v?.trim() ?? ''); return n == null || n <= 0 ? 'সঠিক পরিমাণ লিখুন' : null; }),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      fieldLabel('তারিখ'),
                      TextFormField(controller: date, readOnly: true, style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w700),
                        decoration: deco(suffix: Icon(Icons.calendar_today_rounded, size: 17, color: muted)),
                        onTap: () async { final picked = await showDatePicker(context: context, initialDate: DateTime.tryParse(date.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                          if (picked != null && sheetContext.mounted) setSheetState(() => date.text = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}'); }),
                    ])),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      fieldLabel('সময়'),
                      TextFormField(controller: time, readOnly: true, style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w700),
                        decoration: deco(suffix: Icon(Icons.access_time_rounded, size: 17, color: muted)),
                        onTap: () async { final p = time.text.split(':'); final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.tryParse(p.first) ?? 0, minute: int.tryParse(p.last) ?? 0));
                          if (picked != null && sheetContext.mounted) setSheetState(() => time.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'); }),
                    ])),
                  ]),
                  const SizedBox(height: 13), fieldLabel('ক্যাটাগরি'),
                  DropdownButtonFormField<String>(key: ValueKey(kind), initialValue: categories.contains(category) ? category : 'অন্যান্য',
                    decoration: deco(suffix: Icon(Icons.keyboard_arrow_down_rounded, color: muted)), dropdownColor: surface,
                    style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600), items: categories.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: saving ? null : (v) => setSheetState(() => category = v ?? category)),
                  const SizedBox(height: 13), fieldLabel('ওয়ালেট'),
                  DropdownButtonFormField<String>(initialValue: wallets.contains(wallet) ? wallet : wallets.first,
                    decoration: deco(suffix: Icon(Icons.keyboard_arrow_down_rounded, color: muted)), dropdownColor: surface,
                    style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600), items: wallets.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: saving ? null : (v) => setSheetState(() => wallet = v ?? wallet)),
                  const SizedBox(height: 13), fieldLabel('নোট (ঐচ্ছিক)'),
                  TextFormField(controller: note, maxLines: 2, minLines: 1, style: TextStyle(color: ink, fontSize: 13), decoration: deco(hint: 'অতিরিক্ত তথ্য লিখুন'),),
                  const SizedBox(height: 17),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: saving ? null : () => Navigator.pop(sheetContext), child: const Text('বাতিল'))),
                    const SizedBox(width: 9),
                    Expanded(flex: 2, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
                      onPressed: saving ? null : () async {
                        if (!formKey.currentState!.validate()) return;
                        setSheetState(() => saving = true);
                        try {
                          final parsed = DateTime.tryParse(date.text) ?? DateTime.now();
                          final month = _monthLabel(_monthKey(parsed)).split(' ').first;
                          final dateLabel = '${parsed.day.toString().padLeft(2, '0')} $month, ${parsed.year}';
                          final p = time.text.split(':'); final h = int.tryParse(p.first) ?? 0; final m = int.tryParse(p.last) ?? 0;
                          final timeLabel = '${h % 12 == 0 ? 12 : h % 12}:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
                          final item = <String, dynamic>{
                            ...?tx,
                            'id': tx?['id'] ?? DateTime.now().millisecondsSinceEpoch,
                            'title': title.text.trim(), 'description': title.text.trim(),
                            'category': category, 'date': dateLabel, 'time': timeLabel,
                            'icon': iconName, 'dateInput': date.text, 'timeInput': time.text,
                            'wallet': wallet, 'amount': double.parse(amount.text.trim()),
                            'kind': kind, 'note': note.text.trim(),
                          };
                          await _AuthApi.saveTransactionOffline(item);
                          if (!mounted || !sheetContext.mounted) return;
                          Navigator.pop(sheetContext); await _load();
                          if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text(tx == null ? 'নতুন লেনদেন যোগ হয়েছে।' : 'লেনদেন আপডেট হয়েছে।')));
                        } catch (e) {
                          if (sheetContext.mounted) setSheetState(() => saving = false);
                          if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
                        }
                      },
                      child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(tx == null ? '$kind সংরক্ষণ' : 'পরিবর্তন সংরক্ষণ করুন', style: const TextStyle(fontWeight: FontWeight.w800)))),
                  ]),
                ]))),
            ),
          ));
        }),
      );
  }

  Future<void> _editTransaction(Map<String, dynamic> tx) async {
    await _showAddTransaction(
      initialWallet: (tx['wallet'] ?? tx['walletName'] ?? 'ক্যাশ').toString(),
      initialKind: (tx['kind'] ?? 'ব্যয়').toString(),
      editTransaction: tx,
    );
  }

  Future<void> _deleteTransaction(Map<String, dynamic> tx) async {
    final label = (tx['title'] ?? tx['description'] ?? 'এই লেনদেন').toString();
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('লেনদেন ডিলিট করবেন?'),
      content: Text('"$label" লেনদেনটি স্থায়ীভাবে মুছে যাবে।'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('বাতিল')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE53935)), onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ডিলিট করুন')),
      ],
    ));
    if (ok != true || !mounted) return;
    try {
      await _AuthApi.deleteTransactionOffline(tx);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('লেনদেন ডিলিট হয়েছে।')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  void _showTransactionDetails(Map<String, dynamic> tx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = (tx['title'] ?? tx['description'] ?? tx['note'] ?? 'লেনদেন').toString();
    final category = (tx['categoryName'] ?? tx['category_name'] ?? tx['category'] ?? '').toString();
    final wallet = (tx['wallet'] ?? tx['walletName'] ?? tx['wallet_name'] ?? tx['accountName'] ?? '').toString();
    final kind = (tx['kind'] ?? '').toString();
    final isIncome = kind == 'আয়';
    final isTransfer = kind == 'ট্রান্সফার' || kind.toLowerCase() == 'transfer';
    final accent = isIncome
        ? const Color(0xFF079B62)
        : isTransfer
            ? const Color(0xFF1688D4)
            : const Color(0xFFE54855);
    final tint = isIncome
        ? const Color(0xFFEAF8F0)
        : isTransfer
            ? const Color(0xFFEAF4FF)
            : const Color(0xFFFFF0F1);
    final darkSurface = isIncome
        ? const Color(0xFF142F27)
        : isTransfer
            ? const Color(0xFF142B40)
            : const Color(0xFF351F28);
    final typeLabel = isIncome ? 'আয়' : isTransfer ? 'ট্রান্সফার' : 'ব্যয়';
    final style = _transactionStyle(tx);
    final date = _parseTransactionDate(tx['dateInput'] ?? tx['date_input'] ?? tx['date'] ?? tx['createdAt'] ?? tx['created_at']);
    final dateText = date == null
        ? (tx['date'] ?? '').toString()
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    final timeText = (tx['timeInput'] ?? tx['time_input'] ?? tx['time'] ?? '').toString().trim();
    final note = (tx['note'] ?? tx['notes'] ?? '').toString().trim();
    final ink = isDark ? Colors.white : const Color(0xFF172B43);
    final muted = isDark ? Colors.white60 : const Color(0xFF718096);
    final surface = isDark ? const Color(0xFF14283A) : Colors.white;

    Widget detailRow(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: accent.withValues(alpha: isDark ? .18 : .09), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 16, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600))),
        const SizedBox(width: 8),
        Flexible(child: Text(value, textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: ink, fontWeight: FontWeight.w800))),
      ]),
    );

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(13)),
                  child: Icon(style.icon, color: accent, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: ink)),
                  const SizedBox(height: 2),
                  Text(isIncome ? 'আয়ের বিবরণ' : isTransfer ? 'ট্রান্সফারের বিবরণ' : 'ব্যয়ের বিবরণ', style: TextStyle(fontSize: 11, color: muted)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(20)),
                  child: Text(typeLabel, style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 2),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: Icon(Icons.close_rounded, size: 19, color: muted),
                ),
              ]),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? darkSurface : tint,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: accent.withValues(alpha: isDark ? .22 : .12)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('লেনদেনের পরিমাণ', style: TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text('${isIncome ? '+' : isTransfer ? '↔ ' : '− '}${_money(_amount(tx['amount']))}', style: TextStyle(fontSize: 24, height: 1.15, color: accent, fontWeight: FontWeight.w900)),
                ]),
              ),
              const SizedBox(height: 13),
              Text('লেনদেনের বিস্তারিত', style: TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              if (category.isNotEmpty) detailRow(Icons.sell_outlined, 'ক্যাটাগরি', category),
              if (wallet.isNotEmpty) detailRow(Icons.account_balance_wallet_outlined, 'ওয়ালেট', wallet),
              if (dateText.isNotEmpty) detailRow(Icons.calendar_today_outlined, 'তারিখ', dateText),
              if (timeText.isNotEmpty) detailRow(Icons.access_time_rounded, 'সময়', timeText),
              if (note.isNotEmpty) detailRow(Icons.notes_rounded, 'নোট', note),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('বন্ধ করুন', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }


  void _openWalletManagement() {
    Navigator.of(context).push(_route(WalletManagementScreen(
      walletBalances: Map<String, double>.from(_walletBalances),
      transactions: List<Map<String, dynamic>>.from(_transactions),
      onRefresh: () async {
        await _load();
        return (balances: Map<String, double>.from(_walletBalances), transactions: List<Map<String, dynamic>>.from(_transactions));
      },
      onEditTransaction: _editTransaction,
      onAddTransaction: (wallet, kind) => _showAddTransaction(initialWallet: wallet, initialKind: kind),
      onAddWallet: (name) async {
        final response = await _AuthApi._get('/data/wallets');
        final current = response['data'] is List ? (response['data'] as List).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : <Map<String, dynamic>>[];
        if (current.any((wallet) => (wallet['name'] ?? '').toString().trim().toLowerCase() == name.trim().toLowerCase())) {
          throw Exception('এই নামে ওয়ালেট আগে থেকেই আছে।');
        }
        await _AuthApi._put('/data/wallets', {'data': [...current, {'name': name.trim(), 'base': 0}]});
      },
    )));
  }

  void _openSavingsManagement() {
    Navigator.of(context).push(_route(SavingsManagementScreen(
      initialGoals: List<Map<String, dynamic>>.from(_goals),
      initialTransactions: List<Map<String, dynamic>>.from(_transactions),
      walletNames: <String>{'ক্যাশ','ব্যাংক','বিকাশ','নগদ', ..._walletBalances.keys}.toList(),
      onRefresh: () async {
        await _load();
        return (goals: List<Map<String, dynamic>>.from(_goals), transactions: List<Map<String, dynamic>>.from(_transactions));
      },
      onSave: (goals, transactions) async {
        await _AuthApi._put('/data/goals', {'data': goals});
        await _AuthApi._put('/data/transactions', {'data': transactions});
        if (!mounted) return;
        setState(() { _goals = goals; _transactions = transactions; });
        await _load();
      },
    )));
  }

  void _openTransactionsPage() {
    Navigator.of(context).push(_route(TransactionsScreen(
      initialTransactions: _transactions,
      onAdd: _showAddTransaction,
      onEdit: _editTransaction,
      onDelete: _deleteTransaction,
      onReload: () async { await _load(); return List<Map<String, dynamic>>.from(_transactions); },
    )));
  }

  Widget _compactExpenseOverview() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    var monthIncome = 0.0, monthExpense = 0.0, previousMonthIncome = 0.0, previousMonthExpense = 0.0;
    final previousMonthStart = DateTime(now.year, now.month - 1);
    for (final tx in _transactions) {
      final date = _parseTransactionDate(tx['dateInput'] ?? tx['date_input'] ?? tx['date'] ?? tx['createdAt'] ?? tx['created_at']);
      if (date == null) continue;
      final amount = _amount(tx['amount']);
      if (!date.isBefore(monthStart) && date.isBefore(nextMonth)) {
        if (tx['kind'] == 'আয়') monthIncome += amount;
        if (tx['kind'] == 'ব্যয়') monthExpense += amount;
      } else if (!date.isBefore(previousMonthStart) && date.isBefore(monthStart)) {
        if (tx['kind'] == 'আয়') previousMonthIncome += amount;
        if (tx['kind'] == 'ব্যয়') previousMonthExpense += amount;
      }
    }
    double? changePercent(double current, double previous) => previous == 0 ? null : ((current - previous) / previous.abs()) * 100;
    final incomeChange = changePercent(monthIncome, previousMonthIncome);
    final expenseChange = changePercent(monthExpense, previousMonthExpense);
    final unpaidDebts = _debts.where((item) {
      final kind = (item['debtKind'] ?? item['status'] ?? '').toString();
      final status = (item['status'] ?? '').toString();
      return kind == 'দেনা' && status != 'পরিশোধিত' && status != 'সম্পন্ন';
    }).toList();
    final debtTotal = unpaidDebts.fold<double>(0, (sum, item) {
      final payments = item['payments'] is List ? item['payments'] as List : <dynamic>[];
      final paid = payments.whereType<Map>().fold<double>(0, (value, payment) => value + _amount(payment['amount']));
      return sum + (_amount(item['amount']) - paid).clamp(0, double.infinity).toDouble();
    });
    final unpaidBills = _bills.where((item) {
      final status = (item['status'] ?? '').toString();
      return status != 'পরিশোধিত' && status != 'সম্পন্ন';
    }).toList();
    final billTotal = unpaidBills.fold<double>(0, (sum, item) {
      final payments = item['payments'] is List ? item['payments'] as List : <dynamic>[];
      final currentPayments = payments.whereType<Map>().where((payment) {
        final cycleDate = (payment['cycleDate'] ?? '').toString();
        return cycleDate.isEmpty || cycleDate == (item['date'] ?? '').toString();
      });
      final paid = currentPayments.fold<double>(0, (value, payment) => value + _amount(payment['amount']));
      if (currentPayments.isEmpty && payments.isEmpty && ['পরিশোধিত', 'সম্পন্ন'].contains((item['status'] ?? '').toString())) {
        return sum;
      }
      return sum + (_amount(item['amount']) - paid).clamp(0, double.infinity).toDouble();
    });
    Widget summaryCard({required String title, required double amount, required String subtitle, required IconData icon, required Color accent, required Color tint, required bool showTrend, double? change, VoidCallback? onTap}) {
      final foreground = isDark ? const Color(0xFFEAF7F2) : const Color(0xFF183E35);
      final muted = isDark ? const Color(0xFFA9C4BA) : const Color(0xFF617B73);
      return Expanded(child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(13), child: Container(height: 74, padding: const EdgeInsets.fromLTRB(5, 7, 4, 5),
        decoration: BoxDecoration(color: isDark ? accent.withValues(alpha: .13) : tint, borderRadius: BorderRadius.circular(13), border: Border.all(color: accent.withValues(alpha: isDark ? .32 : .13)),
          boxShadow: isDark ? [] : [BoxShadow(color: accent.withValues(alpha: .07), blurRadius: 9, offset: const Offset(0, 3))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Container(width: 25, height: 25, decoration: BoxDecoration(color: accent.withValues(alpha: .16), shape: BoxShape.circle), child: Icon(icon, size: 15, color: accent)),
            const SizedBox(width: 3), Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: muted, fontWeight: FontWeight.w700)))]),
          const Spacer(),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(_hidden ? '৳ •••••' : _money(amount), maxLines: 1, style: TextStyle(fontSize: 12, color: foreground, fontWeight: FontWeight.w900))),
          const SizedBox(height: 1),
          Row(children: [
            if (showTrend) ...[Icon(change == null ? Icons.remove_rounded : change >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 11, color: accent), const SizedBox(width: 2),
              Expanded(child: Text(change == null ? 'নতুন' : '${change >= 0 ? '+' : '-'}${change.abs().toStringAsFixed(1)}%', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8, color: accent, fontWeight: FontWeight.w800)))]
            else ...[Icon(title == 'দেনা' ? Icons.people_alt_rounded : Icons.receipt_long_rounded, size: 10, color: muted), const SizedBox(width: 3),
              Expanded(child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8, color: muted, fontWeight: FontWeight.w700)))]
          ])
        ]))));
    }
    return Row(children: [
      summaryCard(title: 'আয়', amount: monthIncome, subtitle: '', icon: Icons.south_rounded, accent: isDark ? const Color(0xFF39BDF8) : const Color(0xFF00A875), tint: const Color(0xFFE7FBF3), showTrend: true, change: incomeChange),
      const SizedBox(width: 5),
      summaryCard(title: 'ব্যয়', amount: monthExpense, subtitle: '', icon: Icons.north_rounded, accent: const Color(0xFFFF625B), tint: const Color(0xFFFFEEEE), showTrend: true, change: expenseChange),
      const SizedBox(width: 5),
      summaryCard(title: 'দেনা', amount: debtTotal, subtitle: '${unpaidDebts.length} জন', icon: Icons.payments_rounded, accent: const Color(0xFFF29A16), tint: const Color(0xFFFFF6E8), showTrend: false, onTap: () => Navigator.of(context).push(_route(_DebtsScreen(debts: _debts, wallets: _walletBalances.keys.toList(), onReload: () async { await _load(); return List<Map<String, dynamic>>.from(_debts); })))),
      const SizedBox(width: 5),
      summaryCard(title: 'বিল', amount: billTotal, subtitle: '${unpaidBills.length} টি বাকি', icon: Icons.calendar_month_rounded, accent: const Color(0xFF2588F5), tint: const Color(0xFFEEF6FF), showTrend: false, onTap: () => Navigator.of(context).push(_route(_BillsScreen(bills: _bills, onReload: () async { await _load(); return List<Map<String, dynamic>>.from(_bills); })))),
    ]);
  }
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
    final textColor = isDark ? const Color(0xFFDCEBFA) : const Color(0xFF164F40);
    final mutedColor = isDark ? const Color(0xFF94A9BF) : const Color(0xFF64877C);
    final cardColor = isDark ? const Color(0xFF0D2033) : const Color(0xFFF9FFFC);
    final borderColor = isDark ? const Color(0xFF36536F) : const Color(0xFFD7EEE5);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 7, 3),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: (isDark ? const Color(0xFF4ABEFF) : const Color(0xFF168565)).withValues(alpha: isDark ? .07 : .045),
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
              Icon(Icons.bar_chart_rounded, color: isDark ? const Color(0xFF68C5FF) : const Color(0xFF00A878), size: 21),
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
                                      ? (isDark ? const Color(0xFF284B6A) : const Color(0xFFE0F5ED))
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
                    color: isDark ? const Color(0xFF4ABEFF).withValues(alpha: .12) : const Color(0xFFDDF9EE),
                    border: Border.all(color: isDark ? const Color(0xFF4ABEFF).withValues(alpha: .25) : const Color(0xFFB9EBDD)),
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
    final cardColor = isDark ? const Color(0xFF0D2033) : const Color(0xFFF9FFFC);
    final borderColor = isDark ? const Color(0xFF36536F) : const Color(0xFFD7EEE5);
    final textColor = isDark ? const Color(0xFFDCEBFA) : const Color(0xFF164F40);
    final mutedColor = isDark ? const Color(0xFF94A9BF) : const Color(0xFF64877C);
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
                    color: isDark ? const Color(0xFF4ABEFF).withValues(alpha: .12) : const Color(0xFFDDF9EE),
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
          FittedBox(fit: BoxFit.scaleDown, child: Text(_hidden ? '৳ •••••' : '৳ $formattedBalance', maxLines: 1, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF073F32), fontSize: 13, fontWeight: FontWeight.w900))),
        ],
      ),
    );
  }

  void _showDashboardMenu(BuildContext context) {
    final isDark = _appThemeMode.value == ThemeMode.dark;
    final surface = isDark ? const Color(0xFF10243A) : Colors.white;
    final ink = isDark ? const Color(0xFFE6F0FA) : const Color(0xFF172B3A);
    final divider = isDark ? const Color(0xFF294158) : const Color(0xFFE3EAF0);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dashboard menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 14,
                top: 46,
                child: Material(
                  color: Colors.transparent,
                  child: StatefulBuilder(
                    builder: (popupContext, setPopupState) {
                      Widget menuItem({
                        required IconData icon,
                        required Color color,
                        required String title,
                        required VoidCallback onTap,
                        Widget? trailing,
                        bool last = false,
                      }) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 44,
                              child: InkWell(
                                onTap: onTap,
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 11),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        child: Icon(icon, color: color, size: 21),
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: ink,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      trailing ?? Icon(Icons.chevron_right_rounded, color: ink, size: 21),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (!last)
                              Padding(
                                padding: const EdgeInsets.only(left: 12, right: 10),
                                child: Divider(height: 1, thickness: 1, color: divider),
                              ),
                          ],
                        );
                      }

                      return SizedBox(
                        width: MediaQuery.of(popupContext).size.width < 252
                            ? MediaQuery.of(popupContext).size.width - 28
                            : 210,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 19,
                              top: -7,
                              child: Transform.rotate(
                                angle: 0.785398,
                                child: Container(
                                  width: 15,
                                  height: 15,
                                  decoration: BoxDecoration(
                                    color: surface,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: divider.withValues(alpha: .75)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? .24 : .13),
                                    blurRadius: 18,
                                    offset: const Offset(0, 7),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  menuItem(
                                    icon: Icons.account_balance_wallet_rounded,
                                    color: const Color(0xFF08B63C),
                                    title: 'ওয়ালেট ম্যানেজমেন্ট',
                                    onTap: () {
                                      Navigator.pop(popupContext);
                                      _openWalletManagement();
                                    },
                                  ),
                                  menuItem(
                                    icon: Icons.savings_rounded,
                                    color: const Color(0xFF0868D9),
                                    title: 'সঞ্চয়',
                                    onTap: () {
                                      Navigator.pop(popupContext);
                                      _openSavingsManagement();
                                    },
                                  ),
                                  menuItem(
                                    icon: Icons.format_list_bulleted_rounded,
                                    color: const Color(0xFF087A55),
                                    title: 'সব লেনদেন',
                                    onTap: () {
                                      Navigator.pop(popupContext);
                                      _openTransactionsPage();
                                    },
                                  ),
                                  menuItem(
                                    icon: Icons.grid_view_rounded,
                                    color: const Color(0xFF087A55),
                                    title: 'Compact / Expand',
                                    trailing: Transform.scale(
                                      scale: 0.82,
                                      child: Switch(
                                      value: _compactCharts,
                                      activeThumbColor: const Color(0xFF08B63C),
                                      onChanged: (value) {
                                        setState(() => _compactCharts = value);
                                        setPopupState(() {});
                                      },
                                    ),
                                    ),
                                    onTap: () {
                                      final value = !_compactCharts;
                                      setState(() => _compactCharts = value);
                                      setPopupState(() {});
                                    },
                                  ),
                                  menuItem(
                                    icon: Icons.dns_rounded,
                                    color: const Color(0xFF0868D9),
                                    title: 'Server Settings',
                                    last: true,
                                    onTap: () {
                                      Navigator.pop(popupContext);
                                      Navigator.of(context).push(_route(const ServerSettingsScreen()));
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -0.025), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}




class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key,required this.initialTransactions,required this.onAdd,required this.onEdit,required this.onDelete,required this.onReload});
  final List<Map<String,dynamic>> initialTransactions;
  final Future<void> Function() onAdd;
  final Future<void> Function(Map<String,dynamic>) onEdit;
  final Future<void> Function(Map<String,dynamic>) onDelete;
  final Future<List<Map<String,dynamic>>> Function() onReload;
  @override State<TransactionsScreen> createState()=>_TransactionsScreenState();
}
class _TransactionsScreenState extends State<TransactionsScreen>{
  late List<Map<String,dynamic>> data;
  final search=TextEditingController();
  String kind='সব',category='সব ক্যাটাগরি',wallet='সব ওয়ালেট',sort='সর্বশেষ আগে';
  DateTimeRange? range;
  bool loading=false;
  @override void initState(){super.initState();data=List.from(widget.initialTransactions);}
  @override void dispose(){search.dispose();super.dispose();}
  double amount(dynamic v)=>v is num?v.toDouble():double.tryParse(v?.toString()??'')??0;
  String money(double v)=>'৳ ${v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'),(m)=>',')}';
  String bn(String v)=>v.replaceAll('0','০').replaceAll('1','১').replaceAll('2','২').replaceAll('3','৩').replaceAll('4','৪').replaceAll('5','৫').replaceAll('6','৬').replaceAll('7','৭').replaceAll('8','৮').replaceAll('9','৯');
  String titleOf(Map x)=>(x['title']??x['description']??x['note']??'লেনদেন').toString();
  String displayTitleOf(Map x) {
    final match = RegExp(r'^(বিল পরিশোধ|দেনা পরিশোধ|পাওনা জমা|ক্রেডিট কার্ড উত্তোলন)\s*[—–-]\s*(.+)$').firstMatch(titleOf(x));
    return match?.group(2)?.trim() ?? titleOf(x);
  }
  String subtitleOf(Map x) {
    final match = RegExp(r'^(বিল পরিশোধ|দেনা পরিশোধ|পাওনা জমা|ক্রেডিট কার্ড উত্তোলন)\s*[—–-]\s*(.+)$').firstMatch(titleOf(x));
    return [
      if (match != null) match.group(1)!.trim(),
      walletOf(x),
    ].where((v) => v.trim().isNotEmpty).join(' • ');
  }
  String catOf(Map x)=>(x['categoryName']??x['category_name']??x['category']??'অন্যান্য').toString();
  String walletOf(Map x)=>(x['wallet']??x['walletName']??x['wallet_name']??x['accountName']??'').toString();
  String kindOf(Map x)=>(x['kind']??'ব্যয়').toString();
  DateTime? dateOf(Map x)=>DateTime.tryParse((x['dateInput']??x['date_input']??x['date']??x['createdAt']??x['created_at']??'').toString());
  List<Map<String,dynamic>> get filtered{
    final q=search.text.trim().toLowerCase();
    final list=data.where((x){
      final d=dateOf(x);
      if(kind!='সব'&&kindOf(x)!=kind)return false;
      if(category!='সব ক্যাটাগরি'&&catOf(x)!=category)return false;
      if(wallet!='সব ওয়ালেট'&&walletOf(x)!=wallet)return false;
      if(range!=null&&(d==null||d.isBefore(DateTime(range!.start.year,range!.start.month,range!.start.day))||!d.isBefore(DateTime(range!.end.year,range!.end.month,range!.end.day+1))))return false;
      return q.isEmpty||'${titleOf(x)} ${catOf(x)} ${walletOf(x)}'.toLowerCase().contains(q);
    }).toList();
    list.sort((a,b){final x=dateOf(a),y=dateOf(b);if(x==null)return 1;if(y==null)return -1;return sort=='সর্বশেষ আগে'?y.compareTo(x):x.compareTo(y);});
    return list;
  }
  Future<void> reload()async{setState(()=>loading=true);try{final fresh=await widget.onReload();if(mounted)setState(()=>data=fresh);}finally{if(mounted)setState(()=>loading=false);}}
  String dateLabel(DateTime? d){if(d==null)return 'তারিখ পাওয়া যায়নি';const m=['জানুয়ারি','ফেব্রুয়ারি','মার্চ','এপ্রিল','মে','জুন','জুলাই','আগস্ট','সেপ্টেম্বর','অক্টোবর','নভেম্বর','ডিসেম্বর'];return '${bn(d.day.toString())} ${m[d.month-1]}, ${bn(d.year.toString())}';}
  Widget summary(String label,double value,Color color,IconData icon)=>Expanded(child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:color.withValues(alpha:.07),borderRadius:BorderRadius.circular(14),border:Border.all(color:color.withValues(alpha:.2))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:color,size:18),const SizedBox(height:4),Text(label,style:const TextStyle(fontSize:10)),FittedBox(child:Text(money(value),style:TextStyle(fontSize:14,fontWeight:FontWeight.w900,color:color)))])));
  Widget row(Map<String,dynamic> x){
    final dark=Theme.of(context).brightness==Brightness.dark;
    final txKind=kindOf(x),income=txKind=='আয়',transfer=txKind=='ট্রান্সফার'||txKind.toLowerCase()=='transfer';
    final value='${titleOf(x)} ${catOf(x)}'.toLowerCase();
    final name=(x['icon']??x['iconName']??x['icon_name']??'').toString();
const icons = <String, IconData>{
    'Briefcase': Icons.work_outline_rounded,
    'Banknote': Icons.payments_outlined,
    'CircleDollarSign': Icons.monetization_on_outlined,
    'Coins': Icons.toll_outlined,
    'CreditCard': Icons.credit_card_outlined,
    'Wallet': Icons.account_balance_wallet_outlined,
    'WalletCards': Icons.wallet_outlined,
    'HandCoins': Icons.volunteer_activism_outlined,
    'BadgeDollarSign': Icons.price_check_rounded,
    'ReceiptText': Icons.receipt_long_outlined,
    'ChartNoAxesCombined': Icons.query_stats_rounded,
    'TrendingUp': Icons.trending_up_rounded,
    'TrendingDown': Icons.trending_down_rounded,
    'Calculator': Icons.calculate_outlined,
    'Percent': Icons.percent_rounded,
    'Store': Icons.storefront_outlined,
    'ShoppingCart': Icons.shopping_cart_outlined,
    'ShoppingBag': Icons.shopping_bag_outlined,
    'ShoppingBasket': Icons.shopping_basket_outlined,
    'Tag': Icons.sell_outlined,
    'Gift': Icons.card_giftcard_outlined,
    'Package': Icons.inventory_2_outlined,
    'PackageOpen': Icons.unarchive_outlined,
    'House': Icons.home_outlined,
    'BedDouble': Icons.bed_outlined,
    'Sofa': Icons.weekend_outlined,
    'Lamp': Icons.light_outlined,
    'Lightbulb': Icons.lightbulb_outline_rounded,
    'Plug': Icons.power_outlined,
    'HousePlug': Icons.electrical_services_outlined,
    'Droplets': Icons.water_drop_outlined,
    'Flame': Icons.local_fire_department_outlined,
    'Wifi': Icons.wifi_rounded,
    'Smartphone': Icons.smartphone_rounded,
    'Laptop': Icons.laptop_outlined,
    'Monitor': Icons.desktop_windows_outlined,
    'Tv': Icons.tv_outlined,
    'Router': Icons.router_outlined,
    'Printer': Icons.print_outlined,
    'Camera': Icons.camera_alt_outlined,
    'Headphones': Icons.headphones_outlined,
    'Gamepad2': Icons.sports_esports_outlined,
    'Car': Icons.directions_car_outlined,
    'CarFront': Icons.directions_car_filled_outlined,
    'Bus': Icons.directions_bus_outlined,
    'BusFront': Icons.directions_bus_filled_outlined,
    'Train': Icons.train_outlined,
    'Bike': Icons.pedal_bike_outlined,
    'Plane': Icons.flight_outlined,
    'PlaneTakeoff': Icons.flight_takeoff_rounded,
    'Ship': Icons.directions_boat_outlined,
    'Fuel': Icons.local_gas_station_outlined,
    'MapPin': Icons.location_on_outlined,
    'Route': Icons.alt_route_rounded,
    'Utensils': Icons.restaurant_outlined,
    'UtensilsCrossed': Icons.restaurant_menu_rounded,
    'CookingPot': Icons.soup_kitchen_outlined,
    'Coffee': Icons.coffee_outlined,
    'Pizza': Icons.local_pizza_outlined,
    'Salad': Icons.eco_outlined,
    'Sandwich': Icons.lunch_dining_outlined,
    'Cake': Icons.cake_outlined,
    'IceCream': Icons.icecream_outlined,
    'Apple': Icons.apple_rounded,
    'Carrot': Icons.grass_rounded,
    'Pill': Icons.medication_outlined,
    'Stethoscope': Icons.medical_services_outlined,
    'HeartPulse': Icons.monitor_heart_outlined,
    'Cross': Icons.add_rounded,
    'Syringe': Icons.vaccines_outlined,
    'Hospital': Icons.local_hospital_outlined,
    'Bandage': Icons.healing_outlined,
    'Dumbbell': Icons.fitness_center_rounded,
    'GraduationCap': Icons.school_outlined,
    'BookOpen': Icons.menu_book_outlined,
    'Book': Icons.book_outlined,
    'School': Icons.cast_for_education_outlined,
    'Notebook': Icons.note_alt_outlined,
    'FileText': Icons.description_outlined,
    'Music': Icons.music_note_rounded,
    'Film': Icons.movie_outlined,
    'Clapperboard': Icons.video_camera_back_outlined,
    'Theater': Icons.theater_comedy_outlined,
    'Popcorn': Icons.local_movies_outlined,
    'PartyPopper': Icons.celebration_outlined,
    'Ticket': Icons.confirmation_number_outlined,
    'Trophy': Icons.emoji_events_outlined,
    'Turtle': Icons.pets_outlined,
    'Dog': Icons.pets_rounded,
    'Cat': Icons.pets_rounded,
    'PawPrint': Icons.pets_outlined,
    'Bone': Icons.cruelty_free_outlined,
    'Shirt': Icons.checkroom_outlined,
    'Footprints': Icons.directions_walk_rounded,
    'Watch': Icons.watch_outlined,
    'Glasses': Icons.visibility_outlined,
    'Gem': Icons.diamond_outlined,
    'Users': Icons.groups_outlined,
    'Baby': Icons.child_care_outlined,
    'Heart': Icons.favorite_border_rounded,
    'Flower2': Icons.local_florist_outlined,
    'Sprout': Icons.grass_outlined,
    'TreePine': Icons.park_outlined,
    'Leaf': Icons.eco_outlined,
    'Sun': Icons.wb_sunny_outlined,
    'CloudRain': Icons.cloudy_snowing,
    'Snowflake': Icons.ac_unit_rounded,
    'Umbrella': Icons.umbrella_outlined,
    'Wrench': Icons.build_outlined,
    'Hammer': Icons.handyman_outlined,
    'Paintbrush': Icons.brush_outlined,
    'Scissors': Icons.content_cut_rounded,
    'Trash2': Icons.delete_outline_rounded,
    'Recycle': Icons.recycling_rounded,
    'CalendarDays': Icons.calendar_month_outlined,
    'Clock': Icons.schedule_rounded,
    'Bell': Icons.notifications_none_rounded,
    'ShieldCheck': Icons.verified_user_outlined,
    'KeyRound': Icons.key_outlined,
    'Ellipsis': Icons.more_horiz_rounded,
    };
    var color=const Color(0xFFE92743),tint=const Color(0xFFFFF7F8);
    var fallbackIcon=Icons.shopping_cart_outlined;
    if(income){color=const Color(0xFF00A653);tint=const Color(0xFFF3FBF6);fallbackIcon=Icons.south_rounded;}
    else if(transfer){color=const Color(0xFF1688D4);tint=const Color(0xFFEAF4FF);fallbackIcon=Icons.swap_horiz_rounded;}
    else if(value.contains('খাবার')||value.contains('food')){fallbackIcon=Icons.restaurant_rounded;}
    else if(value.contains('বাসা')||value.contains('বাড়ি')||value.contains('লোন')){color=const Color(0xFFD96A00);tint=const Color(0xFFFFF1E1);fallbackIcon=Icons.home_rounded;}
    else if(value.contains('ইন্টারনেট')||value.contains('বিল')){color=const Color(0xFF00A653);tint=const Color(0xFFF3FBF6);fallbackIcon=Icons.router_rounded;}
    else if(value.contains('উপহার')){color=const Color(0xFF8627D9);tint=const Color(0xFFF5EBFF);fallbackIcon=Icons.card_giftcard_rounded;}
    else if(value.contains('যাতায়াত')||value.contains('বাস')){color=const Color(0xFF1688D4);tint=const Color(0xFFEAF4FF);fallbackIcon=Icons.directions_bus_rounded;}
    final icon=icons[name]??fallbackIcon;
    final d=dateOf(x),time=(x['timeInput']??x['time_input']??x['time']??'').toString();
    final borderColor = color.withValues(alpha: dark ? 0.24 : 0.16);
    return Container(
      margin:const EdgeInsets.only(bottom:7),
      padding:const EdgeInsets.symmetric(horizontal:9,vertical:9),
      decoration:BoxDecoration(
        color:dark?Color.lerp(const Color(0xFF12283A),color,.10):tint,
        borderRadius:BorderRadius.circular(16),
        border:Border.all(color:borderColor),
      ),
      child:Row(children:[
        Container(width:42,height:42,decoration:BoxDecoration(color:color.withValues(alpha:.10),shape:BoxShape.circle),child:Icon(icon,color:color,size:21)),
        const SizedBox(width:10),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(displayTitleOf(x),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:12,fontWeight:FontWeight.w800,color:dark?Colors.white:const Color(0xFF1C2F42))),
          Text(subtitleOf(x),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:10,color:dark?Colors.white60:const Color(0xFF718096))),
          Text('${dateLabel(d)}${time.isEmpty?'':' • $time'}',style:TextStyle(fontSize:9,color:dark?Colors.white54:const Color(0xFF8A98A8))),
        ])),
        const SizedBox(width:6),
        Column(crossAxisAlignment:CrossAxisAlignment.end,mainAxisSize:MainAxisSize.min,children:[
          Text('${income?'+ ':transfer?'↔ ':'− '}${money(amount(x['amount']))}',style:TextStyle(fontSize:12,fontWeight:FontWeight.w900,color:color)),
          const SizedBox(height:4),
          Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:4),decoration:BoxDecoration(color:color.withValues(alpha:.09),borderRadius:BorderRadius.circular(18),border:Border.all(color:color.withValues(alpha:.16))),child:Text(catOf(x),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:9,fontWeight:FontWeight.w800,color:color))),
        ]),
        PopupMenuButton<String>(padding:EdgeInsets.zero,onSelected:(v)async{if(v=='edit'){await widget.onEdit(x);await reload();}else{await widget.onDelete(x);await reload();}},itemBuilder:(_)=>const[PopupMenuItem(value:'edit',child:Text('এডিট করুন')),PopupMenuItem(value:'delete',child:Text('ডিলিট করুন'))]),
      ]),
    );
  }
  Widget _buildFilterDropdown({
    required String value,
    required List<String> values,
    required double width,
    required bool dark,
    required ValueChanged<String> onChanged,
  }) {
    final borderColor = dark ? const Color(0xFF35516A) : const Color(0xFFD7E0E9);
    return Container(
      width: width,
      height: 38,
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.only(left: 10, right: 5),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF12283A) : Colors.white,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18,
              color: dark ? Colors.white70 : const Color(0xFF718096)),
          style: TextStyle(
            fontSize: 11,
            color: dark ? Colors.white : const Color(0xFF26384A),
            fontWeight: FontWeight.w500,
          ),
          items: values.map((v) => DropdownMenuItem<String>(
            value: v,
            child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }

  @override Widget build(BuildContext context){
    final dark=Theme.of(context).brightness==Brightness.dark,bg=dark?const Color(0xFF071827):const Color(0xFFF4F8FB),ink=dark?Colors.white:const Color(0xFF203446);
    final items=filtered,income=items.where((x)=>kindOf(x)=='আয়').fold<double>(0,(s,x)=>s+amount(x['amount'])),expense=items.where((x)=>kindOf(x)=='ব্যয়').fold<double>(0,(s,x)=>s+amount(x['amount']));
    final shown=items;
    final cats=data.map(catOf).toSet().toList()..sort(),wallets=data.map(walletOf).where((x)=>x.isNotEmpty).toSet().toList()..sort();
    final groups=<String,List<Map<String,dynamic>>>{};for(final x in shown){final d=dateOf(x),key=d==null?'unknown':d.toString().substring(0,10);groups.putIfAbsent(key,()=>[]).add(x);}
    return Scaffold(backgroundColor:bg,appBar:AppBar(backgroundColor:bg,foregroundColor:ink,elevation:0,title:const Text('লেনদেন',style:TextStyle(fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:loading?null:reload,icon:const Icon(Icons.refresh_rounded)),IconButton(onPressed:()async{await widget.onAdd();await reload();},icon:const Icon(Icons.add_rounded))]),body:SafeArea(child:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(12,4,12,7),child:Row(children:[summary('মোট আয়',income,const Color(0xFF00A875),Icons.trending_up_rounded),const SizedBox(width:7),summary('মোট ব্যয়',expense,const Color(0xFFEF4444),Icons.trending_down_rounded)])),
      Padding(padding:const EdgeInsets.fromLTRB(12,0,12,7),child:Row(children:[summary('নিট ব্যালেন্স',income-expense,const Color(0xFF2588F5),Icons.account_balance_wallet_outlined),const SizedBox(width:7),summary('মোট লেনদেন',items.length.toDouble(),const Color(0xFF8B5CF6),Icons.receipt_long_rounded)])),
      Padding(padding:const EdgeInsets.fromLTRB(12,0,12,7),child:TextField(controller:search,onChanged: (_) => setState(() {}),decoration:InputDecoration(prefixIcon:const Icon(Icons.search_rounded),hintText:'বিবরণ, ক্যাটাগরি, ওয়ালেট খুঁজুন...',filled:true,fillColor:dark?const Color(0xFF12283A):Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12))))),
      SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          children: [
            for(final k in ['সব','আয়','ব্যয়','ট্রান্সফার'])
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: ChoiceChip(
                  label: Text(k),
                  selected: kind==k,
                  onSelected: (_) => setState(() { kind=k; }),
                ),
              ),
            _buildFilterDropdown(
              value: category,
              values: ['সব ক্যাটাগরি', ...cats],
              width: 142,
              dark: dark,
              onChanged: (v) => setState(() { category=v; }),
            ),
            _buildFilterDropdown(
              value: wallet,
              values: ['সব ওয়ালেট', ...wallets],
              width: 130,
              dark: dark,
              onChanged: (v) => setState(() { wallet=v; }),
            ),
            TextButton.icon(
              onPressed: () async {
                final now=DateTime.now();
                final r=await showDateRangePicker(
                  context:context,
                  firstDate:DateTime(2000),
                  lastDate:DateTime(2100),
                  initialDateRange:range??DateTimeRange(start:DateTime(now.year,now.month,1),end:now),
                );
                if(r!=null)setState(() { range=r; });
              },
              icon: const Icon(Icons.calendar_month_rounded,size:16),
              label: Text(range==null?'তারিখ':'নির্বাচিত'),
            ),
            if(range!=null) IconButton(onPressed:()=>setState(() { range=null; }),icon:const Icon(Icons.close_rounded)),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 3, 14, 5),
        child: SizedBox(
          height: 34,
          child: Row(
            children: [
              Text('${bn(items.length.toString())}টি লেনদেন',style:TextStyle(fontSize:10,color:dark?Colors.white60:const Color(0xFF718096))),
              const Spacer(),
              DropdownButton<String>(
                value:sort,
                underline:const SizedBox(),
                items:const ['সর্বশেষ আগে','পুরোনো আগে'].map((v)=>DropdownMenuItem(value:v,child:Text(v,style:const TextStyle(fontSize:10)))).toList(),
                onChanged:(v)=>setState(() { sort=v??sort; }),
              ),
            ],
          ),
        ),
      ),
      Expanded(
        child: loading
          ? const Center(child:CircularProgressIndicator())
          : shown.isEmpty
            ? Center(child:Text('কোনো লেনদেন পাওয়া যায়নি',style:TextStyle(color:dark?Colors.white60:const Color(0xFF718096))))
            : ListView(
                key: ValueKey('$kind|$category|$wallet|$sort|${range?.start}|${range?.end}|${search.text}'),
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                children:[
        for(final g in groups.entries)...[
          Container(padding:const EdgeInsets.symmetric(horizontal:11,vertical:9),decoration:BoxDecoration(color:dark?const Color(0xFF18334B):const Color(0xFFEAF2FC),borderRadius:BorderRadius.circular(10)),child:Text(dateLabel(dateOf(g.value.first)),style:TextStyle(fontSize:11,fontWeight:FontWeight.w800,color:ink))),
          const SizedBox(height: 5),
          for(final x in g.value)row(x),const SizedBox(height:6),
        ],
      ])),
    ])));
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
        ..color = (isDark ? const Color(0xFF3BADEB) : const Color(0xFF13C58B)).withValues(alpha: isDark ? .16 : .08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = (isDark ? const Color(0xFF4ABEFF) : const Color(0xFF00B981)).withValues(alpha: isDark ? .60 : .28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = isDark ? const Color(0xFF9AD9FF) : const Color(0xFF00B981)
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
        Paint()..color = (isDark ? const Color(0xFF4ABEFF) : const Color(0xFF16B981)).withValues(alpha: isDark ? .38 : .30),
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