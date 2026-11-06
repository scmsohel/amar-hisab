import 'package:flutter/material.dart';

typedef SavingsReload = Future<({List<Map<String,dynamic>> goals,List<Map<String,dynamic>> transactions})> Function();
typedef SavingsSave = Future<void> Function(List<Map<String,dynamic>> goals,List<Map<String,dynamic>> transactions);

class SavingsManagementScreen extends StatefulWidget {
  const SavingsManagementScreen({super.key,required this.initialGoals,required this.initialTransactions,required this.walletNames,required this.onRefresh,required this.onSave});
  final List<Map<String,dynamic>> initialGoals,initialTransactions;
  final List<String> walletNames;
  final SavingsReload onRefresh;
  final SavingsSave onSave;
  @override State<SavingsManagementScreen> createState()=>_SavingsManagementScreenState();
}
class _SavingsManagementScreenState extends State<SavingsManagementScreen>{
  late List<Map<String,dynamic>> goals,transactions;
  final search=TextEditingController();
  String status='সব স্ট্যাটাস',period='সব সময়',sort='সর্বশেষ আগে';
  bool busy=false;
  static const green=Color(0xFF00A875),blue=Color(0xFF287FF5),red=Color(0xFFFF5364),purple=Color(0xFF9657F5);
  @override void initState(){super.initState();goals=widget.initialGoals.map((e)=>Map<String,dynamic>.from(e)).toList();transactions=widget.initialTransactions.map((e)=>Map<String,dynamic>.from(e)).toList();}
  @override void dispose(){search.dispose();super.dispose();}
  double n(dynamic v)=>v is num?v.toDouble():double.tryParse((v??'').toString())??0;
  List<Map<String,dynamic>> payments(Map<String,dynamic> g)=>(g['payments'] is List?g['payments'] as List:[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  double paid(Map<String,dynamic> g){final p=payments(g);if(p.isEmpty&&['সম্পন্ন','পরিশোধিত'].contains(g['status']))return n(g['amount']);return p.fold<double>(0,(a,e)=>a+n(e['amount']));}
  double remaining(Map<String,dynamic> g)=>(n(g['amount'])-paid(g)).clamp(0,double.infinity).toDouble();
  bool done(Map<String,dynamic> g)=>['সম্পন্ন','পরিশোধিত'].contains(g['status'])||remaining(g)<=0;
  String money(num v)=>'৳ ${v.toStringAsFixed(v%1==0?0:2)}';
  DateTime? date(dynamic v)=>v==null?null:DateTime.tryParse(v.toString());
  String dateLabel(dynamic v){final d=date(v);if(d==null)return 'তারিখ নেই';const m=['জানু','ফেব্রু','মার্চ','এপ্রিল','মে','জুন','জুলাই','আগস্ট','সেপ্টে','অক্টো','নভে','ডিসে'];return '${d.day} ${m[d.month-1]}, ${d.year}';}
  String iso(DateTime d)=>'${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  DateTime addPeriod(DateTime d,int count,String freq){if(freq=='weekly')return d.add(Duration(days:7*count));final m=d.month-1+count,y=d.year+m~/12,mo=m%12+1,last=DateTime(y,mo+1,0).day;return DateTime(y,mo,d.day.clamp(1,last));}
  DateTime? nextDate(Map<String,dynamic> g){if(done(g))return null;final start=date(g['goalStartDate']??g['date']);if(start==null)return null;final count=n(g['goalInstallmentCount']).toInt();final per=n(g['goalInstallmentAmount']);final cycle=per>0?(paid(g)/per+1e-8).floor():payments(g).length;if(cycle>=count)return null;return addPeriod(start,cycle,(g['goalFrequency']??'monthly').toString());}
  void msg(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));
  Future<void> persist(List<Map<String,dynamic>> g,List<Map<String,dynamic>> t)async{setState(()=>busy=true);try{await widget.onSave(g,t);if(mounted)setState((){goals=g.map((x)=>Map<String,dynamic>.from(x)).toList();transactions=t.map((x)=>Map<String,dynamic>.from(x)).toList();busy=false;});}catch(e){if(mounted){setState(()=>busy=false);msg('সংরক্ষণ করা যায়নি: $e');}}}
  Future<void> refresh()async{setState(()=>busy=true);try{final d=await widget.onRefresh();if(mounted)setState((){goals=d.goals;transactions=d.transactions;busy=false;});}catch(e){if(mounted){setState(()=>busy=false);msg(e.toString());}}}
  Future<void> goalForm({Map<String,dynamic>? old})async{
    final title=TextEditingController(text:(old?['title']??'').toString()),per=TextEditingController(text:old==null?'':n(old['goalInstallmentAmount']).toString()),count=TextEditingController(text:old==null?'':n(old['goalInstallmentCount']).toInt().toString()),notes=TextEditingController(text:(old?['notes']??'').toString());
    var freq=(old?['goalFrequency']??'monthly').toString(),st=(old?['status']??'চলমান').toString(),start=(old?['goalStartDate']??old?['date']??iso(DateTime.now())).toString();
    final key=GlobalKey<FormState>();
    final ok=await showModalBottomSheet<bool>(context:context,isScrollControlled:true,showDragHandle:true,builder:(c)=>StatefulBuilder(builder:(c,set)=>Padding(padding:EdgeInsets.fromLTRB(16,8,16,MediaQuery.of(c).viewInsets.bottom+18),child:Form(key:key,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(old==null?'সঞ্চয় যোগ করুন':'সঞ্চয় সম্পাদনা',style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
      TextFormField(controller:title,decoration:const InputDecoration(labelText:'সঞ্চয়ের নাম'),validator:(v)=>v==null||v.trim().isEmpty?'নাম দিন':null),
      TextFormField(controller:per,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'প্রতি কিস্তিতে জমা (৳)'),validator:(v)=>n(v)>0?null:'সঠিক টাকা দিন'),
      DropdownButtonFormField<String>(initialValue:freq,decoration:const InputDecoration(labelText:'কিস্তির ধরন'),items:const [DropdownMenuItem(value:'monthly',child:Text('মাসিক')),DropdownMenuItem(value:'weekly',child:Text('সাপ্তাহিক'))],onChanged:(v)=>set(()=>freq=v??freq)),
      TextFormField(controller:count,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'মোট কিস্তির সংখ্যা'),validator:(v)=>int.tryParse(v??'')!=null&&int.parse(v!)>0?null:'সংখ্যা দিন'),
      ListTile(contentPadding:EdgeInsets.zero,title:const Text('জমা শুরুর তারিখ'),subtitle:Text(dateLabel(start)),trailing:const Icon(Icons.calendar_month),onTap:()async{final d=date(start)??DateTime.now();final p=await showDatePicker(context:c,initialDate:d,firstDate:DateTime(2000),lastDate:DateTime(2100));if(p!=null)set(()=>start=iso(p));}),
      DropdownButtonFormField<String>(initialValue:st,decoration:const InputDecoration(labelText:'অবস্থা'),items:const [DropdownMenuItem(value:'চলমান',child:Text('চলমান')),DropdownMenuItem(value:'সম্পন্ন',child:Text('সম্পন্ন'))],onChanged:(v)=>set(()=>st=v??st)),
      TextFormField(controller:notes,decoration:const InputDecoration(labelText:'নোট (ঐচ্ছিক)')),
      const SizedBox(height:12),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>Navigator.pop(c,false),child:const Text('বাতিল'))),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:(){if(key.currentState!.validate())Navigator.pop(c,true);},child:const Text('সংরক্ষণ')))])
    ]))))));
    if(ok==true){final cnt=int.parse(count.text),begin=date(start)??DateTime.now(),end=addPeriod(begin,cnt-1,freq);final item=<String,dynamic>{'id':old?['id']??DateTime.now().millisecondsSinceEpoch,'title':title.text.trim(),'amount':n(per.text)*cnt,'date':iso(end),'icon':old?['icon']??'PiggyBank','updatedAt':dateLabel(iso(DateTime.now())),'status':st,'notes':notes.text.trim(),'goalFrequency':freq,'goalInstallmentAmount':n(per.text),'goalInstallmentCount':cnt,'goalStartDate':start,'payments':old==null?<dynamic>[]:payments(old)};await persist(old==null?[item,...goals]:goals.map((g)=>g['id']==old['id']?item:g).toList(),transactions);}
    title.dispose();per.dispose();count.dispose();notes.dispose();
  }
  Future<void> deleteGoal(Map<String,dynamic> g)async{final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('সঞ্চয় মুছবেন?'),content:Text('${g['title']} পরিকল্পনাটি মুছে যাবে।'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('বাতিল')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('মুছুন'))]));if(yes==true)await persist(goals.where((x)=>x['id']!=g['id']).toList(),transactions.where((x)=>!(x['category']=='সঞ্চয়'&&x['title']=='সঞ্চয় জমা — ${g['title']}')).toList());}
  Future<void> detail(Map<String,dynamic> goal) async {
    final amountController = TextEditingController(text: (n(goal['goalInstallmentAmount']) > 0 ? n(goal['goalInstallmentAmount']).clamp(0, remaining(goal)) : remaining(goal)).toString());
    final noteController = TextEditingController();
    var paymentDate = iso(DateTime.now());
    var wallet = widget.walletNames.isNotEmpty ? widget.walletNames.first : 'ক্যাশ';
    dynamic editingId;
    var saving = false;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFE8F2EE) : const Color(0xFF1B3040);
    final muted = dark ? const Color(0xFFA5B8B0) : const Color(0xFF81909D);
    final panel = dark ? const Color(0xFF10291F) : const Color(0xFFEAF8F2);
    final border = dark ? const Color(0xFF2B5141) : const Color(0xFFB7E5D3);
    final surface = dark ? const Color(0xFF19372B) : Colors.white;

    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
      backgroundColor: dark ? const Color(0xFF101F2D) : Colors.white,
      builder: (sheetContext) => StatefulBuilder(builder: (sheetContext, setSheet) {
        final current = goals.firstWhere((item) => item['id'].toString() == goal['id'].toString(), orElse: () => goal);
        final history = payments(current)..sort((a, b) => n(b['id']).compareTo(n(a['id'])));
        final total = n(current['amount']), deposited = paid(current), left = remaining(current);
        final progress = total > 0 ? (deposited / total).clamp(0.0, 1.0) : 0.0;
        final suggested = n(current['goalInstallmentAmount']);
        final installmentLeft = suggested > 0 ? (suggested < left ? suggested : left) : left;
        InputDecoration inputDecoration(String label, String hint) {
          return InputDecoration(
            labelText: label, hintText: hint, isDense: true, filled: true,
            fillColor: dark ? const Color(0xFF172B3B) : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: border)),
          );
        }
        Widget metric(String label, double value, Color color) => Expanded(child: Container(
          constraints: const BoxConstraints(minHeight: 68), padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
          decoration: BoxDecoration(color: dark ? const Color(0xFF172B3B) : const Color(0xFFF7FAFC), borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dark ? const Color(0xFF294158) : const Color(0xFFE2EAF0))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: muted)),
            const SizedBox(height: 5),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(money(value), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color))),
          ]),
        ));
        Future<void> savePayment() async {
          final value = double.tryParse(amountController.text.trim());
          final old = editingId == null ? null : history.where((item) => item['id'].toString() == editingId.toString()).firstOrNull;
          final maxAllowed = left + n(old?['amount']);
          if (value == null || !value.isFinite || value <= 0 || value > maxAllowed) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value != null && value > maxAllowed ? 'লক্ষ্যের বাকি টাকার চেয়ে বেশি জমা দেওয়া যাবে না।' : 'সঠিক জমার পরিমাণ দিন।')));
            return;
          }
          setSheet(() => saving = true);
          try {
            final pid = editingId ?? DateTime.now().millisecondsSinceEpoch;
            final tid = old?['transactionId'] ?? (DateTime.now().millisecondsSinceEpoch + 1);
            final savedDate = paymentDate;
            final payment = <String, dynamic>{'id': pid, 'amount': value, 'date': dateLabel(savedDate), 'dateInput': savedDate, 'wallet': wallet, 'notes': noteController.text.trim(), 'transactionId': tid};
            final nextPayments = old == null ? [...history, payment] : history.map((item) => item['id'].toString() == pid.toString() ? payment : item).toList();
            final sum = nextPayments.fold<double>(0, (v, item) => v + n(item['amount']));
            final updatedGoal = <String, dynamic>{...current, 'payments': nextPayments, 'status': sum + 1e-8 >= total ? 'সম্পন্ন' : 'চলমান', 'updatedAt': dateLabel(iso(DateTime.now()))};
            final transaction = <String, dynamic>{
              'id': tid, 'title': 'সঞ্চয় জমা — ${current['title']}', 'category': 'সঞ্চয়',
              'date': dateLabel(savedDate), 'dateInput': savedDate, 'time': '', 'wallet': wallet,
              'amount': value, 'kind': 'ব্যয়', 'note': noteController.text.trim(),
            };
            final nextTransactions = old == null ? [transaction, ...transactions] : transactions.map((item) => item['id'].toString() == old['transactionId'].toString() ? transaction : item).toList();
            await persist(goals.map((item) => item['id'].toString() == current['id'].toString() ? updatedGoal : item).toList(), nextTransactions);
            if (!mounted || !sheetContext.mounted) return;
            final newRemaining = (total - sum).clamp(0, double.infinity).toDouble();
            setSheet(() {
              saving = false; editingId = null;
              amountController.text = n(updatedGoal['goalInstallmentAmount']) > 0 ? n(updatedGoal['goalInstallmentAmount']).clamp(0, newRemaining).toString() : newRemaining.toString();
              noteController.clear(); paymentDate = iso(DateTime.now());
              wallet = widget.walletNames.isNotEmpty ? widget.walletNames.first : 'ক্যাশ';
            });
          } catch (e) {
            if (sheetContext.mounted) setSheet(() => saving = false);
            msg('জমা সংরক্ষণ করা যায়নি: $e');
          }
        }
        Future<void> removePayment(Map<String, dynamic> payment) async {
          final yes = await showDialog<bool>(context: sheetContext, builder: (dialogContext) => AlertDialog(
            title: const Text('জমা মুছবেন?'), content: const Text('এই জমার রেকর্ড এবং সংশ্লিষ্ট লেনদেন মুছে ফেলা হবে।'),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('বাতিল')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('মুছুন'))],
          ));
          if (yes != true) return;
          final nextPayments = history.where((item) => item['id'].toString() != payment['id'].toString()).toList();
          final sum = nextPayments.fold<double>(0, (v, item) => v + n(item['amount']));
          final updatedGoal = <String, dynamic>{...current, 'payments': nextPayments, 'status': sum + 1e-8 >= total ? 'সম্পন্ন' : 'চলমান', 'updatedAt': dateLabel(iso(DateTime.now()))};
          await persist(goals.map((item) => item['id'].toString() == current['id'].toString() ? updatedGoal : item).toList(),
            transactions.where((item) => item['id'].toString() != payment['transactionId'].toString()).toList());
          if (sheetContext.mounted) setSheet(() {});
        }
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * .92),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.of(sheetContext).viewInsets.bottom + 16),
            child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(current['title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: ink)),
                  const SizedBox(height: 3), Text('সঞ্চয়ের লক্ষ্য জমা করুন', style: TextStyle(fontSize: 11, color: muted)),
                ])),
                IconButton(onPressed: () => Navigator.pop(sheetContext), icon: Icon(Icons.close_rounded, color: muted)),
              ]),
              const SizedBox(height: 7),
              Row(children: [metric('লক্ষ্য পরিমাণ', total, ink), const SizedBox(width: 7), metric('জমা হয়েছে', deposited, green), const SizedBox(width: 7), metric('এখনো বাকি', left, red)]),
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, minHeight: 6, color: green, backgroundColor: dark ? const Color(0xFF294158) : const Color(0xFFE2EAF0))),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(13), border: Border.all(color: border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text('জমার ইতিহাস', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: ink))), Text('${history.length}টি লেনদেন', style: TextStyle(fontSize: 10, color: muted))]),
                  const SizedBox(height: 8),
                  if (history.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Center(child: Text('এখনো কোনো জমা যোগ করা হয়নি।', style: TextStyle(fontSize: 11, color: muted))))
                  else ...history.map((payment) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: dark ? const Color(0xFF2B5141) : const Color(0xFFE2EEE7)),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .08 : .035), blurRadius: 7, offset: const Offset(0, 2))]),
                      child: Row(children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 19, color: ink), const SizedBox(width: 9),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('জমা · ${payment['date'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink)),
                          Text((payment['wallet'] ?? 'ক্যাশ').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: muted)),
                          if ((payment['notes'] ?? '').toString().trim().isNotEmpty) Text(payment['notes'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: muted)),
                        ])),
                        Text(money(n(payment['amount'])), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: green)),
                        IconButton(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                          onPressed: saving ? null : () {
                            final linked = transactions.where((item) => item['id'].toString() == payment['transactionId'].toString()).toList();
                            setSheet(() {
                              editingId = payment['id']; amountController.text = n(payment['amount']).toString();
                              noteController.text = (payment['notes'] ?? '').toString();
                              paymentDate = (linked.isNotEmpty ? linked.first['dateInput'] : payment['dateInput'] ?? payment['date'])?.toString() ?? iso(DateTime.now());
                              wallet = (payment['wallet'] ?? 'ক্যাশ').toString();
                            });
                          }, icon: Icon(Icons.edit_outlined, size: 17, color: muted)),
                        IconButton(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                          onPressed: saving ? null : () => removePayment(payment), icon: const Icon(Icons.delete_outline_rounded, size: 17, color: red)),
                      ]),
                    ),
                  )),
                ]),
              ),
              const SizedBox(height: 12),
              Text(editingId == null ? 'জমা যোগ করুন' : 'জমা সম্পাদনা', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: ink)),
              const SizedBox(height: 8),
              TextField(controller: amountController, enabled: !saving, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: inputDecoration('পরিমাণ (৳)', suggested > 0 ? 'প্রস্তাবিত ${money(suggested)}' : 'জমার পরিমাণ')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: saving ? null : () async {
                    final picked = await showDatePicker(context: sheetContext, initialDate: date(paymentDate) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (picked != null) setSheet(() => paymentDate = iso(picked));
                  },
                  icon: const Icon(Icons.calendar_month_outlined, size: 16), label: Text(dateLabel(paymentDate), maxLines: 1, overflow: TextOverflow.ellipsis),
                )),
                const SizedBox(width: 8),
                Expanded(child: DropdownButtonFormField<String>(
                  initialValue: widget.walletNames.contains(wallet) ? wallet : (widget.walletNames.isNotEmpty ? widget.walletNames.first : null),
                  isExpanded: true, decoration: inputDecoration('ওয়ালেট', ''),
                  items: widget.walletNames.map((name) => DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: saving ? null : (value) => setSheet(() => wallet = value ?? wallet),
                )),
              ]),
              const SizedBox(height: 8),
              TextField(controller: noteController, enabled: !saving, maxLines: 2, decoration: inputDecoration('নোট (ঐচ্ছিক)', 'যেমন: প্রথম কিস্তি')),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(color: dark ? const Color(0xFF172B3B) : const Color(0xFFEDF9F4), borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('প্রস্তাবিত কিস্তি', style: TextStyle(fontSize: 10, color: muted)), const SizedBox(height: 4),
                    Text(money(suggested), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: ink)),
                  ])),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('বর্তমান কিস্তির বাকি', style: TextStyle(fontSize: 10, color: muted)), const SizedBox(height: 4),
                    Text(money(installmentLeft), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: ink)),
                  ])),
                ]),
              ),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: saving || (left <= 0 && editingId == null) ? null : savePayment,
                icon: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded, size: 17),
                label: Text(saving ? 'সংরক্ষণ হচ্ছে...' : editingId == null ? 'জমা সংরক্ষণ' : 'পরিবর্তন সংরক্ষণ করুন'),
                style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )),
            ])),
          ),
        );
      }),
    );
    amountController.dispose();
    noteController.dispose();
  }
  Widget filter(String value,List<String> options,ValueChanged<String> onChanged) {
    return Expanded(
      child: PopupMenuButton<String>(
        initialValue:null,
        onSelected:(v)=>setState(()=>onChanged(v)),
        itemBuilder:(context)=>options.map((v)=>PopupMenuItem<String>(value:v,child:Text(v))).toList(),
        child:Container(
          height:36,
          padding:const EdgeInsets.symmetric(horizontal:8),
          decoration:BoxDecoration(
            color:Colors.white,
            border:Border.all(color:const Color(0xFFDCE5F0)),
            borderRadius:BorderRadius.circular(15),
          ),
          child:Row(children:[
            Expanded(child:Text(value,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,fontWeight:FontWeight.w600))),
            const Icon(Icons.keyboard_arrow_down,size:18,color:Colors.blueGrey),
          ]),
        ),
      ),
    );
  }
  Widget summary(String t,String v,String sub,IconData icon,Color color,Color tint)=>Expanded(
    child:Container(
      constraints:const BoxConstraints(minHeight:78),
      padding:const EdgeInsets.symmetric(horizontal:8,vertical:7),
      decoration:BoxDecoration(
        color:tint.withValues(alpha:.72),
        borderRadius:BorderRadius.circular(18),
        border:Border.all(color:color.withValues(alpha:.42)),
      ),
      child:Row(children:[
        Container(width:34,height:34,decoration:BoxDecoration(color:color.withValues(alpha:.13),shape:BoxShape.circle),child:Icon(icon,color:color,size:19)),
        const SizedBox(width:10),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
          Text(t,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:9,fontWeight:FontWeight.w700,color:color.withValues(alpha:.9))),
          const SizedBox(height:3),
          FittedBox(alignment:Alignment.centerLeft,fit:BoxFit.scaleDown,child:Text(v,style:TextStyle(fontSize:18,fontWeight:FontWeight.w900,color:color))),
          Text(sub,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:7,color:Colors.blueGrey)),
        ])),
      ]),
    ),
  );
  String dueLabel(DateTime? d){
    if(d==null)return 'জমা সম্পন্ন';
    final days=d.difference(DateTime.now()).inDays;
    if(days<0)return 'জমা বাকি';
    if(days==0)return 'আজ জমা';
    if(days==1)return '১ দিন পরে';
    return '$days দিন পরে';
  }
  Widget _goalCard(Map<String,dynamic> g,Color surface,Color line,Color ink) {
    final p=paid(g),target=n(g['amount']),left=remaining(g);
    final progress=target>0?(p/target).clamp(0.0,1.0).toDouble():0.0;
    final isDone=done(g),next=nextDate(g);
    final now=DateTime.now();
    final dueDays=next==null?null:DateTime(next.year,next.month,next.day).difference(DateTime(now.year,now.month,now.day)).inDays;
    final dueColor=isDone?green:dueDays==null?green:dueDays<0?red:dueDays==0?const Color(0xFFF59E0B):dueDays<=3?blue:green;
    final accent=isDone?green:blue;
    final freq=(g['goalFrequency']??'monthly')=='weekly'?'সাপ্তাহিক':'মাসিক';
    final count=n(g['goalInstallmentCount']).toInt().clamp(0,100000);
    final per=n(g['goalInstallmentAmount']);
    final cycles=per>0?(p/per+1e-8).floor():payments(g).length;
    final late=!isDone&&dueDays!=null&&dueDays<0;
    return InkWell(
      borderRadius:BorderRadius.circular(18),
      onTap:()=>detail(g),
      child:Container(
        constraints:const BoxConstraints(minHeight:108),
        padding:const EdgeInsets.fromLTRB(8,8,6,8),
        decoration:BoxDecoration(
          color:surface,
          borderRadius:BorderRadius.circular(22),
          border:Border.all(color:line.withValues(alpha:.9)),
          boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:.055),blurRadius:12,offset:const Offset(0,4))],
        ),
        child:Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
          Container(width:36,height:36,decoration:BoxDecoration(color:accent.withValues(alpha:.13),shape:BoxShape.circle),child:Icon(Icons.account_balance_wallet_outlined,color:accent,size:20)),
          const SizedBox(width:8),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
            SizedBox(height:18,child:Row(children:[
              Expanded(child:Text(g['title'].toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:14,fontWeight:FontWeight.w900,color:ink))),
              Container(padding:const EdgeInsets.symmetric(horizontal:5,vertical:1),decoration:BoxDecoration(color:dueColor.withValues(alpha:.12),borderRadius:BorderRadius.circular(20)),child:Text(isDone?'সম্পন্ন':late?'জমা বাকি':'চলমান',style:TextStyle(fontSize:8,fontWeight:FontWeight.w800,color:dueColor))),
              PopupMenuButton<String>(padding:EdgeInsets.zero,constraints:const BoxConstraints(minWidth:20,minHeight:18),icon:Icon(Icons.more_horiz,color:ink.withValues(alpha:.65),size:14),onSelected:(v){if(v=='edit'){goalForm(old:g);}else if(v=='delete'){deleteGoal(g);}},itemBuilder:(_)=>const [PopupMenuItem(value:'edit',child:Text('সম্পাদনা')),PopupMenuItem(value:'delete',child:Text('মুছে ফেলুন'))]),
            ])),
            const SizedBox(height:0),
            SizedBox(height:13,child:Row(children:[
              Icon(Icons.calendar_today_outlined,size:10,color:ink.withValues(alpha:.68)),
              const SizedBox(width:4),
              Flexible(child:Text(dateLabel(g['goalStartDate']??g['date']),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:9,color:ink.withValues(alpha:.82)))),
              const SizedBox(width:6),
              Icon(Icons.layers_outlined,size:10,color:ink.withValues(alpha:.68)),
              const SizedBox(width:3),
              Text(freq,style:TextStyle(fontSize:9,color:ink.withValues(alpha:.82))),
            ])),
            const SizedBox(height:4),
            Row(children:[
              Text(money(p),style:const TextStyle(fontSize:16,fontWeight:FontWeight.w900,color:green)),
              Text(' / ${money(target)}',style:TextStyle(fontSize:14,color:ink.withValues(alpha:.9))),
            ]),
            const SizedBox(height:4),
            Row(children:[
              Expanded(child:ClipRRect(borderRadius:BorderRadius.circular(9),child:LinearProgressIndicator(value:progress,minHeight:6,backgroundColor:const Color(0xFFD7E0EA),color:accent))),
              const SizedBox(width:6),
              SizedBox(width:34,child:Text('${(progress*100).toStringAsFixed(1)}%',textAlign:TextAlign.end,style:TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:ink))),
            ]),
            const SizedBox(height:3),
            Text('${cycles.clamp(0,count)} / $count কিস্তি • বাকি ${money(left)}',style:const TextStyle(fontSize:9,color:Colors.blueGrey)),
          ])),
          const SizedBox(width:7),
          Container(
            width:76,
            constraints:const BoxConstraints(minHeight:84),
            padding:const EdgeInsets.symmetric(horizontal:4,vertical:6),
            decoration:BoxDecoration(color:dueColor.withValues(alpha:.12),borderRadius:BorderRadius.circular(16)),
            child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
              Icon(Icons.calendar_month_outlined,color:dueColor,size:16),
              const SizedBox(height:3),
              const Text('পরবর্তী জমা',style:TextStyle(fontSize:8,color:Color(0xFF475569))),
              Text(dueLabel(next),textAlign:TextAlign.center,maxLines:2,style:TextStyle(fontSize:9,fontWeight:FontWeight.w900,color:dueColor)),
            ]),
          ),
          Icon(Icons.chevron_right,color:ink.withValues(alpha:.8),size:20),
        ]),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final dark=Theme.of(context).brightness==Brightness.dark;
    final bg=dark?const Color(0xFF071827):const Color(0xFFF4F7FC);
    final surface=dark?const Color(0xFF10283D):Colors.white;
    final line=dark?const Color(0xFF294158):const Color(0xFFDCE5F0);
    final ink=dark?Colors.white:const Color(0xFF172B43);
    final q=search.text.toLowerCase();
    final completed=goals.where(done).length;
    final active=goals.length-completed;
    final total=goals.fold<double>(0,(a,g)=>a+n(g['amount']));
    final rows=goals.where((g){
      final text='${g['title']} ${g['notes']} ${g['status']}'.toLowerCase();
      if(q.isNotEmpty&&!text.contains(q))return false;
      if(status=='চলমান'&&done(g))return false;
      if(status=='সম্পন্ন'&&!done(g))return false;
      final nd=nextDate(g);
      if(period=='তারিখ আছে'&&nd==null)return false;
      if(period=='তারিখ নেই'&&nd!=null)return false;
      return true;
    }).toList();
    rows.sort((a,b){
      if(sort=='পুরোনো আগে')return (date(a['date'])??DateTime(2000)).compareTo(date(b['date'])??DateTime(2000));
      if(sort=='পরিমাণ বেশি আগে')return n(b['amount']).compareTo(n(a['amount']));
      if(sort=='পরিমাণ কম আগে')return n(a['amount']).compareTo(n(b['amount']));
      return (date(b['date'])??DateTime(2000)).compareTo(date(a['date'])??DateTime(2000));
    });
    return Scaffold(
      backgroundColor:bg,
      appBar:PreferredSize(
        preferredSize:const Size.fromHeight(76),
        child:AppBar(
          toolbarHeight:76,backgroundColor:bg,surfaceTintColor:Colors.transparent,elevation:0,
          leading:IconButton(onPressed:()=>Navigator.pop(context),icon:Icon(Icons.arrow_back,color:ink,size:25)),
          titleSpacing:0,
          title:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
            Text('সঞ্চয়',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900,color:ink)),
            Text('আপনার সঞ্চয় পরিকল্পনা, সঞ্চয়ের অগ্রগতি ও লক্ষ্য',maxLines:2,style:TextStyle(fontSize:9,color:ink.withValues(alpha:.75))),
          ]),
          actions:[
            IconButton(onPressed:refresh,icon:busy?const SizedBox(width:19,height:19,child:CircularProgressIndicator(strokeWidth:2)):Icon(Icons.refresh,color:ink,size:25)),
            Padding(padding:const EdgeInsets.only(right:10),child:FilledButton.icon(
              style:FilledButton.styleFrom(backgroundColor:const Color(0xFF008B55),foregroundColor:Colors.white,padding:const EdgeInsets.symmetric(horizontal:12,vertical:11),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16))),
              onPressed:()=>goalForm(),icon:const Icon(Icons.add,size:19),label:const Text('নতুন সঞ্চয়',style:TextStyle(fontSize:12,fontWeight:FontWeight.w800)),
            )),
          ],
        ),
      ),
      body:SafeArea(top:false,child:Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(10,4,10,7),child:Column(children:[
          Row(children:[
            summary('মোট সঞ্চয় পরিকল্পনা',goals.length.toString(),'সঞ্চয়ের লক্ষ্য রেকর্ড',Icons.track_changes,green,const Color(0xFFEAF8F2)),
            const SizedBox(width:9),
            summary('মোট সঞ্চয়ের পরিমাণ',money(total),'সব সঞ্চয় পরিকল্পনার মোট টাকা',Icons.currency_exchange,red,const Color(0xFFFFF0F1)),
          ]),
          const SizedBox(height:9),
          Row(children:[
            summary('সম্পন্ন সঞ্চয়',completed.toString(),'সম্পন্ন বা অর্জিত',Icons.check,blue,const Color(0xFFEDF5FF)),
            const SizedBox(width:9),
            summary('চলমান সঞ্চয়',active.toString(),'এখনো সম্পন্ন হয়নি',Icons.calendar_month,purple,const Color(0xFFF4EEFF)),
          ]),
          const SizedBox(height:13),
          Row(children:[
            Expanded(child:TextField(controller:search,onChanged:(_)=>setState((){}),decoration:InputDecoration(
              hintText:'সঞ্চয় বা নোট খুঁজুন...',prefixIcon:Icon(Icons.search,color:ink.withValues(alpha:.65)),filled:true,fillColor:surface,
              contentPadding:const EdgeInsets.symmetric(vertical:10),
              enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(17),borderSide:BorderSide(color:line)),
              focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(17),borderSide:const BorderSide(color:green)),
            ))),
            const SizedBox(width:9),
            Container(
              width:44,height:44,
              decoration:BoxDecoration(color:surface,borderRadius:BorderRadius.circular(17),border:Border.all(color:line)),
              child:IconButton(
                onPressed:(){
                  FocusScope.of(context).unfocus();
                  showModalBottomSheet<void>(
                    context:context,
                    showDragHandle:true,
                    builder:(c)=>SafeArea(
                      child:Padding(
                        padding:const EdgeInsets.all(16),
                        child:Column(
                          mainAxisSize:MainAxisSize.min,
                          children:[
                            const Text('ফিল্টার',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900)),
                            const SizedBox(height:12),
                            Row(children:[
                              filter(status,const ['সব স্ট্যাটাস','চলমান','সম্পন্ন'],(v)=>status=v),
                              const SizedBox(width:8),
                              filter(period,const ['সব সময়','তারিখ আছে','তারিখ নেই'],(v)=>period=v),
                            ]),
                            const SizedBox(height:8),
                            Row(children:[
                              filter(sort,const ['সর্বশেষ আগে','পুরোনো আগে','পরিমাণ বেশি আগে','পরিমাণ কম আগে'],(v)=>sort=v),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                icon:Icon(Icons.filter_list,color:ink),
              ),
            ),
          ]),
          const SizedBox(height:9),
          Row(children:[
            filter(status,const ['সব স্ট্যাটাস','চলমান','সম্পন্ন'],(v)=>status=v),
            const SizedBox(width:7),filter(period,const ['সব সময়','তারিখ আছে','তারিখ নেই'],(v)=>period=v),
            const SizedBox(width:7),filter(sort,const ['সর্বশেষ আগে','পুরোনো আগে','পরিমাণ বেশি আগে','পরিমাণ কম আগে'],(v)=>sort=v),
          ]),
          const SizedBox(height:10),
          Row(children:[
            Expanded(child:Text('সকল সঞ্চয়',style:TextStyle(fontSize:15,fontWeight:FontWeight.w900,color:ink))),
            Text('${rows.length}টি রেকর্ড',style:const TextStyle(fontSize:10,color:Colors.blueGrey)),
          ]),
        ])),
        Expanded(child:rows.isEmpty
          ?Center(child:Text(goals.isEmpty?'এখনো কোনো সঞ্চয় যোগ করা হয়নি।':'কোনো রেকর্ড পাওয়া যায়নি।',style:TextStyle(color:ink)))
          :ListView.separated(
            padding:const EdgeInsets.fromLTRB(12,0,12,16),
            itemCount:rows.length,
            separatorBuilder:(_,_)=>const SizedBox(height:7),
            itemBuilder:(context,index)=>_goalCard(rows[index],surface,line,ink),
          ),
        ),
      ])),
    );
  }

}
