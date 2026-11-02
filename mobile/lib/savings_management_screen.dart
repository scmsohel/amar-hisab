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
  Future<void> persist(List<Map<String,dynamic>> g,List<Map<String,dynamic>> t)async{setState(()=>busy=true);try{await widget.onSave(g,t);if(mounted)setState(()=>busy=false);}catch(e){if(mounted){setState(()=>busy=false);msg('সংরক্ষণ করা যায়নি: $e');}}}
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
  Future<void> paymentForm(Map<String,dynamic> g,{Map<String,dynamic>? old})async{
    final amount=TextEditingController(text:old==null?(n(g['goalInstallmentAmount'])>0?n(g['goalInstallmentAmount']).clamp(0,remaining(g)).toString():remaining(g).toString()):n(old['amount']).toString()),note=TextEditingController(text:(old?['notes']??'').toString());
    final linkedTx=old==null?null:transactions.where((t)=>t['id']==old['transactionId']).toList();var day=(linkedTx!=null&&linkedTx.isNotEmpty?linkedTx.first['dateInput']:old?['date'])?.toString()??iso(DateTime.now()),wallet=(old?['wallet']??widget.walletNames.first).toString();final key=GlobalKey<FormState>();final max=remaining(g)+(old==null?0:n(old['amount']));
    final ok=await showModalBottomSheet<bool>(context:context,isScrollControlled:true,showDragHandle:true,builder:(c)=>StatefulBuilder(builder:(c,set)=>Padding(padding:EdgeInsets.fromLTRB(16,8,16,MediaQuery.of(c).viewInsets.bottom+18),child:Form(key:key,child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(old==null?'সঞ্চয় জমা করুন':'জমা সম্পাদনা',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
      Text('লক্ষ্য ${money(n(g['amount']))} • বাকি ${money(remaining(g))}',style:const TextStyle(fontSize:12)),
      TextFormField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'জমার পরিমাণ (৳)'),validator:(v)=>n(v)>0&&n(v)<=max?null:'সঠিক পরিমাণ দিন'),
      ListTile(contentPadding:EdgeInsets.zero,title:const Text('জমার তারিখ'),subtitle:Text(dateLabel(day)),trailing:const Icon(Icons.calendar_month),onTap:()async{final d=date(day)??DateTime.now();final p=await showDatePicker(context:c,initialDate:d,firstDate:DateTime(2000),lastDate:DateTime(2100));if(p!=null)set(()=>day=iso(p));}),
      DropdownButtonFormField<String>(initialValue:widget.walletNames.contains(wallet)?wallet:widget.walletNames.first,decoration:const InputDecoration(labelText:'ওয়ালেট'),items:widget.walletNames.map((w)=>DropdownMenuItem(value:w,child:Text(w))).toList(),onChanged:(v)=>set(()=>wallet=v??wallet)),
      TextFormField(controller:note,decoration:const InputDecoration(labelText:'নোট (ঐচ্ছিক)')),
      const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>Navigator.pop(c,false),child:const Text('বাতিল'))),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:(){if(key.currentState!.validate())Navigator.pop(c,true);},child:const Text('জমা সংরক্ষণ')))])
    ])))));
    if(ok==true){final value=n(amount.text),pid=old?['id']??DateTime.now().millisecondsSinceEpoch,tid=old?['transactionId']??(DateTime.now().millisecondsSinceEpoch+1);final ps=payments(g),p=<String,dynamic>{'id':pid,'amount':value,'date':dateLabel(day),'wallet':wallet,'notes':note.text.trim(),'transactionId':tid};final updatedPs=old==null?[...ps,p]:ps.map((x)=>x['id']==old['id']?p:x).toList();final sum=updatedPs.fold<double>(0,(a,x)=>a+n(x['amount']));final updated=<String,dynamic>{...g,'payments':updatedPs,'status':sum+1e-8>=n(g['amount'])?'সম্পন্ন':'চলমান','updatedAt':dateLabel(iso(DateTime.now()))};final tx=<String,dynamic>{'id':tid,'title':'সঞ্চয় জমা — ${g['title']}','category':'সঞ্চয়','date':dateLabel(day),'dateInput':day,'time':'','wallet':wallet,'amount':value,'kind':'ব্যয়','note':note.text.trim()};final txs=old==null?[tx,...transactions]:transactions.map((x)=>x['id']==old['transactionId']?tx:x).toList();await persist(goals.map((x)=>x['id']==g['id']?updated:x).toList(),txs);}
    amount.dispose();note.dispose();
  }
  Future<void> deleteGoal(Map<String,dynamic> g)async{final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('সঞ্চয় মুছবেন?'),content:Text('${g['title']} পরিকল্পনাটি মুছে যাবে।'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('বাতিল')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('মুছুন'))]));if(yes==true)await persist(goals.where((x)=>x['id']!=g['id']).toList(),transactions.where((x)=>!(x['category']=='সঞ্চয়'&&x['title']=='সঞ্চয় জমা — ${g['title']}')).toList());}
  Future<void> detail(Map<String,dynamic> g)async{await showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,builder:(c)=>StatefulBuilder(builder:(c,set){final ps=payments(g)..sort((a,b)=>n(b['id']).compareTo(n(a['id'])));return Padding(padding:const EdgeInsets.all(16),child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text(g['title'].toString(),style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900)),const SizedBox(height:10),Text('লক্ষ্য ${money(n(g['amount']))}   •   জমা ${money(paid(g))}   •   বাকি ${money(remaining(g))}'),const SizedBox(height:8),LinearProgressIndicator(value:n(g['amount'])>0?(paid(g)/n(g['amount'])).clamp(0,1):0,minHeight:7),const SizedBox(height:12),const Text('জমার ইতিহাস',style:TextStyle(fontWeight:FontWeight.w900)),if(ps.isEmpty)const Padding(padding:EdgeInsets.all(12),child:Text('এখনো কোনো জমা যোগ করা হয়নি।')), ...ps.map((p)=>ListTile(dense:true,contentPadding:EdgeInsets.zero,title:Text('জমা • ${p['date']}'),subtitle:Text('${p['wallet']} • ${p['notes']??''}'),leading:const Icon(Icons.savings_outlined),trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text(money(n(p['amount']))),IconButton(onPressed:(){Navigator.pop(c);paymentForm(g,old:p);},icon:const Icon(Icons.edit_outlined,size:18)),IconButton(onPressed:(){Navigator.pop(c);final ps2=payments(g)..removeWhere((x)=>x['id']==p['id']);final total=ps2.fold<double>(0,(a,x)=>a+n(x['amount']));final up=<String,dynamic>{...g,'payments':ps2,'status':total>=n(g['amount'])?'সম্পন্ন':'চলমান'};persist(goals.map((x)=>x['id']==g['id']?up:x).toList(),transactions.where((x)=>x['id']!=p['transactionId']).toList());},icon:const Icon(Icons.delete_outline,size:18))]))),if(remaining(g)>0)SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:(){Navigator.pop(c);paymentForm(g);},icon:const Icon(Icons.add),label:const Text('জমা যোগ করুন')))])));}));}
  Widget summary(String t,String v,String sub,IconData icon,Color color,Color tint)=>Expanded(
    child:Container(
      constraints:const BoxConstraints(minHeight:92),
      padding:const EdgeInsets.symmetric(horizontal:11,vertical:12),
      decoration:BoxDecoration(
        color:tint.withValues(alpha:.72),
        borderRadius:BorderRadius.circular(18),
        border:Border.all(color:color.withValues(alpha:.42)),
      ),
      child:Row(children:[
        Container(width:42,height:42,decoration:BoxDecoration(color:color.withValues(alpha:.13),shape:BoxShape.circle),child:Icon(icon,color:color,size:24)),
        const SizedBox(width:10),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
          Text(t,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:11,fontWeight:FontWeight.w700,color:color.withValues(alpha:.9))),
          const SizedBox(height:3),
          FittedBox(alignment:Alignment.centerLeft,fit:BoxFit.scaleDown,child:Text(v,style:TextStyle(fontSize:21,fontWeight:FontWeight.w900,color:color))),
          Text(sub,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:9,color:Colors.blueGrey)),
        ])),
      ]),
    ),
  );
  String dueLabel(DateTime? d){
    if(d==null)return 'জমা সম্পন্ন';
    final days=d.difference(DateTime.now()).inDays;
    if(days<0)return '${days.abs()} দিন পেরিয়েছে';
    if(days==0)return 'আজ জমা';
    if(days==1)return '১ দিন পরে';
    return '\$days দিন পরে';
  }
  Widget _goalCard(Map<String,dynamic> g,Color surface,Color line,Color ink) {
    final p=paid(g),target=n(g['amount']),left=remaining(g);
    final progress=target>0?(p/target).clamp(0.0,1.0).toDouble():0.0;
    final isDone=done(g),next=nextDate(g);
    final accent=isDone?green:blue;
    final freq=(g['goalFrequency']??'monthly')=='weekly'?'সাপ্তাহিক':'মাসিক';
    final count=n(g['goalInstallmentCount']).toInt().clamp(0,100000);
    final per=n(g['goalInstallmentAmount']);
    final cycles=per>0?(p/per+1e-8).floor():payments(g).length;
    return InkWell(
      borderRadius:BorderRadius.circular(22),
      onTap:()=>detail(g),
      child:Container(
        padding:const EdgeInsets.fromLTRB(13,12,12,12),
        decoration:BoxDecoration(color:surface,borderRadius:BorderRadius.circular(22),border:Border.all(color:line.withValues(alpha:.9)),boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:.045),blurRadius:9,offset:const Offset(0,3))]),
        child:Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
          Container(width:48,height:48,decoration:BoxDecoration(color:accent.withValues(alpha:.13),shape:BoxShape.circle),child:Icon(Icons.account_balance_wallet_outlined,color:accent,size:26)),
          const SizedBox(width:12),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              Expanded(child:Text(g['title'].toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:16,fontWeight:FontWeight.w900,color:ink))),
              Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),decoration:BoxDecoration(color:(isDone?green:next!=null&&next.difference(DateTime.now()).inDays<0?red:green).withValues(alpha:.11),borderRadius:BorderRadius.circular(18)),child:Text(isDone?'সম্পন্ন':next!=null&&next.difference(DateTime.now()).inDays<0?'দিন বাকি':'চলমান',style:TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:isDone?green:next!=null&&next.difference(DateTime.now()).inDays<0?red:green))),
              PopupMenuButton<String>(padding:EdgeInsets.zero,constraints:const BoxConstraints(minWidth:125),icon:Icon(Icons.more_horiz,color:ink.withValues(alpha:.65),size:21),onSelected:(v){if(v=='edit'){goalForm(old:g);}else if(v=='delete'){deleteGoal(g);}},itemBuilder:(_)=>const [PopupMenuItem(value:'edit',child:Text('সম্পাদনা')),PopupMenuItem(value:'delete',child:Text('মুছে ফেলুন'))]),
            ]),
            const SizedBox(height:3),
            Row(children:[
              Icon(Icons.calendar_today_outlined,size:14,color:ink.withValues(alpha:.65)),
              const SizedBox(width:5),
              Text(dateLabel(g['goalStartDate']??g['date']),style:TextStyle(fontSize:11,color:ink.withValues(alpha:.78))),
              const SizedBox(width:10),
              Icon(Icons.layers_outlined,size:14,color:ink.withValues(alpha:.65)),
              const SizedBox(width:4),
              Text(freq,style:TextStyle(fontSize:11,color:ink.withValues(alpha:.78))),
            ]),
            const SizedBox(height:8),
            Row(children:[
              Text(money(p),style:const TextStyle(fontSize:16,fontWeight:FontWeight.w900,color:green)),
              Text(' / ${money(target)}',style:TextStyle(fontSize:13,color:ink.withValues(alpha:.85))),
            ]),
            const SizedBox(height:5),
            Row(children:[
              Expanded(child:ClipRRect(borderRadius:BorderRadius.circular(8),child:LinearProgressIndicator(value:progress,minHeight:8,backgroundColor:const Color(0xFFD7E0EA),color:accent))),
              const SizedBox(width:8),
              SizedBox(width:38,child:Text('${(progress*100).toStringAsFixed(1)}%',textAlign:TextAlign.end,style:TextStyle(fontSize:11,fontWeight:FontWeight.w800,color:ink))),
            ]),
            const SizedBox(height:3),
            Text('${cycles.clamp(0,count)} / $count কিস্তি • বাকি ${money(left)}',style:const TextStyle(fontSize:9,color:Colors.blueGrey)),
          ])),
          const SizedBox(width:8),
          Container(
            constraints:const BoxConstraints(minWidth:76,maxWidth:102),
            padding:const EdgeInsets.symmetric(horizontal:8,vertical:10),
            decoration:BoxDecoration(color:const Color(0xFFFFEEF2),borderRadius:BorderRadius.circular(15)),
            child:Column(mainAxisSize:MainAxisSize.min,children:[
              const Icon(Icons.calendar_month_outlined,color:red,size:20),
              const SizedBox(height:3),
              const Text('পরবর্তী জমা',style:TextStyle(fontSize:9,color:Color(0xFF475569))),
              Text(dueLabel(next),textAlign:TextAlign.center,maxLines:2,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900,color:red)),
            ]),
          ),
          const SizedBox(width:2),
          Icon(Icons.chevron_right,color:ink.withValues(alpha:.8),size:23),
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
        preferredSize:const Size.fromHeight(91),
        child:AppBar(
          toolbarHeight:91,backgroundColor:bg,surfaceTintColor:Colors.transparent,elevation:0,
          leading:IconButton(onPressed:()=>Navigator.pop(context),icon:Icon(Icons.arrow_back,color:ink,size:25)),
          titleSpacing:0,
          title:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
            Text('সঞ্চয়',style:TextStyle(fontSize:25,fontWeight:FontWeight.w900,color:ink)),
            Text('আপনার সঞ্চয় পরিকল্পনা, সঞ্চয়ের অগ্রগতি ও লক্ষ্য',maxLines:2,style:TextStyle(fontSize:11,color:ink.withValues(alpha:.75))),
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
        Padding(padding:const EdgeInsets.fromLTRB(12,5,12,10),child:Column(children:[
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
              contentPadding:const EdgeInsets.symmetric(vertical:14),
              enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(17),borderSide:BorderSide(color:line)),
              focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(17),borderSide:const BorderSide(color:green)),
            ))),
            const SizedBox(width:9),
            Container(
              width:54,height:54,
              decoration:BoxDecoration(color:surface,borderRadius:BorderRadius.circular(17),border:Border.all(color:line)),
              child:IconButton(
                onPressed:(){
                  FocusScope.of(context).unfocus();
                  showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Padding(
                    padding:const EdgeInsets.all(16),
                    child:Column(mainAxisSize:MainAxisSize.min,children:[
                      const Text('ফিল্টার',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900)),
                      const SizedBox(height:12),
                      Row(children:[filter(status,const ['সব স্ট্যাটাস','চলমান','সম্পন্ন'],(v)=>status=v),const SizedBox(width:7),filter(period,const ['সব সময়','তারিখ আছে','তারিখ নেই'],(v)=>period=v)]),
                      const SizedBox(height:8),
                      Row(children:[filter(sort,const ['সর্বশেষ আগে','পুরোনো আগে','পরিমাণ বেশি আগে','পরিমাণ কম আগে'],(v)=>sort=v)]),
                    ]),
                  )));
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
            Expanded(child:Text('সকল সঞ্চয়',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900,color:ink))),
            Text('${rows.length}টি রেকর্ড',style:const TextStyle(fontSize:10,color:Colors.blueGrey)),
          ]),
        ])),
        Expanded(child:rows.isEmpty
          ?Center(child:Text(goals.isEmpty?'এখনো কোনো সঞ্চয় যোগ করা হয়নি।':'কোনো রেকর্ড পাওয়া যায়নি।',style:TextStyle(color:ink)))
          :ListView.separated(
            padding:const EdgeInsets.fromLTRB(12,0,12,18),
            itemCount:rows.length,
            separatorBuilder:(_,_)=>const SizedBox(height:9),
            itemBuilder:(context,index)=>_goalCard(rows[index],surface,line,ink),
          ),
        ),
      ])),
    );
  }

}
