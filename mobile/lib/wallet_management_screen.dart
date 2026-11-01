import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class WalletManagementScreen extends StatefulWidget {
  const WalletManagementScreen({
    super.key,
    required this.walletBalances,
    required this.transactions,
    required this.onRefresh,
    required this.onEditTransaction,
    required this.onAddWallet,
  });

  final Map<String, double> walletBalances;
  final List<Map<String, dynamic>> transactions;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Map<String, dynamic>) onEditTransaction;
  final Future<void> Function(String) onAddWallet;

  @override
  State<WalletManagementScreen> createState() => _WalletManagementScreenState();
}

class _WalletManagementScreenState extends State<WalletManagementScreen> {
  bool _loading = false;
  late Map<String, double> _balances;
  late List<Map<String, dynamic>> _transactions;
  String _filterWallet = 'সব ওয়ালেট';
  String _filterTime = 'সব সময়';

  @override
  void initState() {
    super.initState();
    _balances = Map<String, double>.from(widget.walletBalances);
    _transactions = List<Map<String, dynamic>>.from(_transactions);
  }

  static const _wallets = <(String, IconData, Color)>[
    ('ক্যাশ', Icons.account_balance_wallet_rounded, Color(0xFF00A86B)),
    ('ব্যাংক', Icons.account_balance_rounded, Color(0xFF2478F5)),
    ('বিকাশ', Icons.payments_rounded, Color(0xFFEA398A)),
    ('নগদ', Icons.account_balance_wallet_rounded, Color(0xFFFF7900)),
  ];

  double get _total => _balances.values.fold(0, (a, b) => a + b);
  double _amount(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
  String _money(double value) => '৳ ${value.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  List<Map<String, dynamic>> get _filteredTransactions {
    final rows = _transactions.where((tx) {
      final wallet = (tx['wallet'] ?? tx['walletName'] ?? tx['wallet_name'] ?? tx['account'] ?? '').toString();
      if (_filterWallet != 'সব ওয়ালেট' && wallet != _filterWallet) return false;
      if (_filterTime == 'এই মাস') {
        final raw = tx['dateInput'] ?? tx['date_input'] ?? tx['date'] ?? tx['createdAt'] ?? tx['created_at'];
        final date = DateTime.tryParse(raw?.toString() ?? '');
        final now = DateTime.now();
        if (date == null || date.year != now.year || date.month != now.month) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => (b['createdAt'] ?? b['created_at'] ?? b['dateInput'] ?? b['date_input'] ?? b['date'] ?? '').toString()
          .compareTo((a['createdAt'] ?? a['created_at'] ?? a['dateInput'] ?? a['date_input'] ?? a['date'] ?? '').toString()));
    return rows;
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final fresh = await widget.onRefresh();
      if (mounted) setState(() { _balances = fresh.balances; _transactions = fresh.transactions; });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAddWallet() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('নতুন ওয়ালেট যোগ করুন'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'ওয়ালেটের নাম', hintText: 'যেমন: সেভিংস'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('যোগ করুন')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      await widget.onAddWallet(name);
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ওয়ালেট যোগ হয়েছে।')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF071827) : const Color(0xFFF5F9FC);
    final surface = dark ? const Color(0xFF10283A) : Colors.white;
    final ink = dark ? const Color(0xFFEAF4FA) : const Color(0xFF101F33);
    final muted = dark ? const Color(0xFF9CB1C3) : const Color(0xFF58708C);
    final line = dark ? const Color(0xFF29465A) : const Color(0xFFE2EAF1);
    final income = widget.transactions.where((e) => e['kind'] == 'আয়').fold<double>(0, (s, e) => s + _amount(e['amount']));
    final expense = widget.transactions.where((e) => e['kind'] == 'ব্যয়').fold<double>(0, (s, e) => s + _amount(e['amount']));
    final rows = _filteredTransactions;
    final knownWallets = <String>{..._balances.keys};
    for (final tx in widget.transactions) {
      final name = (tx['wallet'] ?? tx['walletName'] ?? tx['wallet_name'] ?? '').toString();
      if (name.isNotEmpty) knownWallets.add(name);
    }
    final entries = knownWallets.toList()..sort();
    final palette = _wallets.map((e) => e.$3).toList();

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                sliver: SliverList(delegate: SliverChildListDelegate([
                  Row(children: [
                    IconButton(onPressed: () => Navigator.maybePop(context), icon: Icon(Icons.arrow_back_rounded, color: ink, size: 28)),
                    const SizedBox(width: 4),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('ওয়ালেট ম্যানেজমেন্ট', style: TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w900)),
                      Text('আপনার সব ওয়ালেটের ব্যালেন্স ও লেনদেন', style: TextStyle(color: muted, fontSize: 11.5)),
                    ])),
                    IconButton(onPressed: _loading ? null : _refresh, icon: Icon(Icons.refresh_rounded, color: ink)),
                    FilledButton.icon(onPressed: _showAddWallet, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('ওয়ালেট যোগ')),
                  ]),
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFEAF9F3), Color(0xFFDDF4EF)]),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFB8E8D7)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(width: 58, height: 58, decoration: const BoxDecoration(color: Color(0xFFCFF3E5), shape: BoxShape.circle), child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF009B61), size: 34)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('মোট ব্যালেন্স', style: TextStyle(color: Color(0xFF10233B), fontWeight: FontWeight.w800, fontSize: 14)),
                          Text(_money(_total), style: const TextStyle(color: Color(0xFF008D4B), fontWeight: FontWeight.w900, fontSize: 25)),
                          const Text('সকল ওয়ালেটের বর্তমান ব্যালেন্স', style: TextStyle(color: Color(0xFF58708C), fontSize: 10.5)),
                        ])),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: _summaryPill('↗', 'আয় (মোট)', _money(income), const Color(0xFF009B58), const Color(0xFFE0F8EC))),
                        const SizedBox(width: 6),
                        Expanded(child: _summaryPill('↙', 'ব্যয় (মোট)', _money(expense), const Color(0xFFE32645), const Color(0xFFFFE8EC))),
                        const SizedBox(width: 6),
                        Expanded(child: _summaryPill('⇄', 'লেনদেন', '${_transactions.length}', const Color(0xFF1768D8), const Color(0xFFE4EEFF))),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.52,
                    children: [
                      for (final wallet in _wallets)
                        _walletCard(wallet.$1, wallet.$2, wallet.$3, _balances[wallet.$1] ?? 0, surface, ink, muted),
                      for (final name in entries.where((e) => !_wallets.any((w) => w.$1 == e)))
                        _walletCard(name, Icons.account_balance_wallet_rounded, const Color(0xFF64748B), widget.walletBalances[name] ?? 0, surface, ink, muted),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: line), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .08 : .04), blurRadius: 16, offset: const Offset(0, 5))]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('ওয়ালেট ব্যালেন্স (চার্ট)', style: TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w900)),
                      Text('সকল ওয়ালেটের ব্যালেন্সের তুলনা', style: TextStyle(color: muted, fontSize: 11.5)),
                      const SizedBox(height: 12),
                      Row(children: [
                        SizedBox(width: 150, height: 150, child: CustomPaint(painter: _WalletDonutPainter(
                          values: _wallets.map((w) => (widget.walletBalances[w.$1] ?? 0).abs()).toList(),
                          colors: palette,
                          centerText: _money(_total),
                          textColor: ink,
                          mutedColor: muted,
                        ))),
                        const SizedBox(width: 14),
                        Expanded(child: Wrap(spacing: 10, runSpacing: 12, children: [
                          for (var i = 0; i < _wallets.length; i++)
                            SizedBox(width: 115, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: palette[i], shape: BoxShape.circle)), const SizedBox(width: 6), Text(_wallets[i].$1, style: TextStyle(color: muted, fontSize: 12))]),
                              const SizedBox(height: 2),
                              Text(_money(widget.walletBalances[_wallets[i].$1] ?? 0), style: TextStyle(color: ink, fontWeight: FontWeight.w900, fontSize: 13)),
                              Text(_total > 0 ? '${((widget.walletBalances[_wallets[i].$1] ?? 0) / _total * 100).toStringAsFixed(1)}%' : '0.0%', style: TextStyle(color: muted, fontSize: 11)),
                            ])),
                        ])),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                    decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: line), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .08 : .04), blurRadius: 16, offset: const Offset(0, 5))]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('লেনদেনের তালিকা', style: TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w900)),
                          Text('সকল ওয়ালেটের সাম্প্রতিক লেনদেন', style: TextStyle(color: muted, fontSize: 11.5)),
                        ])),
                        DropdownButtonHideUnderline(child: DropdownButton<String>(value: _filterWallet, items: ['সব ওয়ালেট', ...entries].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 11)))).toList(), onChanged: (v) => setState(() => _filterWallet = v ?? 'সব ওয়ালেট'))),
                        const SizedBox(width: 8),
                        DropdownButtonHideUnderline(child: DropdownButton<String>(value: _filterTime, items: const ['সব সময়', 'এই মাস'].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 11)))).toList(), onChanged: (v) => setState(() => _filterTime = v ?? 'সব সময়'))),
                      ]),
                      const SizedBox(height: 8),
                      Divider(height: 1, color: line),
                      if (rows.isEmpty)
                        Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('কোনো লেনদেন পাওয়া যায়নি', style: TextStyle(color: muted))))
                      else
                        for (final tx in rows)
                          _transactionRow(tx, ink, muted, line),
                    ]),
                  ),
                ])),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryPill(String icon, String label, String value, Color color, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .8), borderRadius: BorderRadius.circular(13)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 23, height: 23, decoration: BoxDecoration(color: bg, shape: BoxShape.circle), child: Center(child: Text(icon, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)))),
        const SizedBox(width: 4),
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF536B86), fontSize: 9.5))),
      ]),
      const SizedBox(height: 4),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900))),
    ]),
  );

  Widget _walletCard(String name, IconData icon, Color accent, double balance, Color surface, Color ink, Color muted) {
    final isBikash = name == 'বিকাশ';
    final isNagad = name == 'নগদ';
    final bg = isBikash ? const Color(0xFFFFF5F9) : isNagad ? const Color(0xFFFFF8F1) : name == 'ক্যাশ' ? const Color(0xFFF2FCF7) : const Color(0xFFF3F7FF);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: surface == Colors.white ? bg : surface, borderRadius: BorderRadius.circular(19), border: Border.all(color: accent.withValues(alpha: .55)), boxShadow: [BoxShadow(color: accent.withValues(alpha: .07), blurRadius: 10, offset: const Offset(0, 3))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: accent.withValues(alpha: .10), shape: BoxShape.circle), child: Center(child: SizedBox(width: 24, height: 24, child: isBikash ? SvgPicture.asset('assets/wallets/bkash-mark.svg') : isNagad ? SvgPicture.asset('assets/wallets/nagad-mark.svg') : Icon(icon, color: accent, size: 24)))),
          const Spacer(),
          Icon(Icons.more_horiz_rounded, color: muted),
        ]),
        const Spacer(),
        Text(name, style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w900)),
        Text(_money(balance), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: accent, fontSize: 19, fontWeight: FontWeight.w900)),
        Text('বর্তমান ব্যালেন্স', style: TextStyle(color: muted, fontSize: 10.5)),
      ]),
    );
  }

  Widget _transactionRow(Map<String, dynamic> tx, Color ink, Color muted, Color line) {
    final kind = (tx['kind'] ?? '').toString();
    final isIncome = kind == 'আয়';
    final wallet = (tx['wallet'] ?? tx['walletName'] ?? tx['wallet_name'] ?? '').toString();
    final title = (tx['title'] ?? tx['description'] ?? tx['note'] ?? tx['category'] ?? 'লেনদেন').toString();
    final date = (tx['date'] ?? tx['dateInput'] ?? tx['date_input'] ?? tx['createdAt'] ?? tx['created_at'] ?? '').toString();
    final amount = _amount(tx['amount']);
    final color = isIncome ? const Color(0xFF009447) : const Color(0xFFE52336);
    final accent = wallet == 'ব্যাংক' ? const Color(0xFF2478F5) : wallet == 'বিকাশ' ? const Color(0xFFEA398A) : wallet == 'নগদ' ? const Color(0xFFFF7900) : const Color(0xFF00A86B);
    return InkWell(
      onTap: () => widget.onEditTransaction(tx),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: line))),
        child: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: accent.withValues(alpha: .11), shape: BoxShape.circle), child: Icon(Icons.account_balance_wallet_rounded, color: accent, size: 19)),
          const SizedBox(width: 7),
          SizedBox(width: 76, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(date, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ink, fontSize: 9.5, fontWeight: FontWeight.w700)),
            Text(wallet, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 9.5)),
          ])),
          const SizedBox(width: 6),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ink, fontSize: 11.5, fontWeight: FontWeight.w800)),
            Text('${kind} • ${(tx['category'] ?? tx['categoryName'] ?? '').toString()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 9.5)),
          ])),
          const SizedBox(width: 4),
          SizedBox(width: 88, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text('${isIncome ? '+' : '−'} ${_money(amount)}', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900))),
            Icon(Icons.edit_outlined, color: muted, size: 15),
          ])),
        ]),        ]),
      ),
    );
  }
}

class _WalletDonutPainter extends CustomPainter {
  const _WalletDonutPainter({required this.values, required this.colors, required this.centerText, required this.textColor, required this.mutedColor});
  final List<double> values;
  final List<Color> colors;
  final String centerText;
  final Color textColor;
  final Color mutedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final base = Paint()..color = mutedColor.withValues(alpha: .10)..style = PaintingStyle.stroke..strokeWidth = 17;
    canvas.drawCircle(center, radius, base);
    if (total > 0) {
      var start = -1.5708;
      for (var i = 0; i < values.length; i++) {
        if (values[i] <= 0) continue;
        final sweep = values[i] / total * 6.28318;
        final paint = Paint()..color = colors[i % colors.length]..style = PaintingStyle.stroke..strokeWidth = 17..strokeCap = StrokeCap.butt;
        canvas.drawArc(rect, start, sweep, false, paint);
        start += sweep;
      }
    }
    final tp = TextPainter(text: TextSpan(text: centerText, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w900)), textDirection: TextDirection.rtl, maxLines: 1)..layout(maxWidth: size.width - 8);
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _WalletDonutPainter oldDelegate) => oldDelegate.values != values || oldDelegate.centerText != centerText || oldDelegate.textColor != textColor;
}
