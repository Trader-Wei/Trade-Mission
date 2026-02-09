import 'package:flutter/material.dart';

import 'dart:async';

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:syncfusion_flutter_charts/charts.dart';



// 型別轉換工具：防止 Windows 版因為整數/小數不分而崩潰

double toD(dynamic v) => (v is num) ? v.toDouble() : (double.tryParse(v.toString()) ?? 0.0);



String _fmtEntryTime(dynamic ms) {

  if (ms == null) return '--';

  final m = ms is num ? ms.toInt() : int.tryParse(ms.toString());

  if (m == null || m == 0) return '--';

  final d = DateTime.fromMillisecondsSinceEpoch(m);

  return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

}

String _fmtDuration(dynamic entryMs, dynamic settledMs) {

  if (entryMs == null || settledMs == null) return '--';

  final e = entryMs is num ? entryMs.toInt() : int.tryParse(entryMs.toString());

  final s = settledMs is num ? settledMs.toInt() : int.tryParse(settledMs.toString());

  if (e == null || s == null || s <= e) return '--';

  final d = Duration(milliseconds: s - e);

  if (d.inDays > 0) return '${d.inDays}天${d.inHours % 24}小時';

  if (d.inHours > 0) return '${d.inHours}小時${d.inMinutes % 60}分';

  return '${d.inMinutes}分';

}

double _pnlAmount(Map<String, dynamic> p) {

  final u = toD(p['uValue']);

  final ent = toD(p['entry']);

  final cur = toD(p['current']);

  final lev = (p['leverage'] as num).toInt();

  if (ent == 0) return 0;

  final base = u * (cur - ent) / ent * lev;

  final ratio = toD(p['exitRatio']);

  return ratio > 0 ? base * ratio : base;

}

double? _rrValue(Map<String, dynamic> p) {

  final ent = toD(p['entry']);

  final cur = toD(p['current']);

  final sl = toD(p['sl']);

  final risk = ent - sl;

  if (risk <= 0) return null;

  return (cur - ent) / risk;

}

bool _isSettledToday(dynamic p) {

  final ms = p['settledAt'];

  if (ms == null) return false;

  final s = ms is num ? ms.toInt() : int.tryParse(ms.toString());

  if (s == null) return false;

  final d = DateTime.fromMillisecondsSinceEpoch(s);

  final n = DateTime.now();

  return d.year == n.year && d.month == n.month && d.day == n.day;

}

bool _isSettledThisMonth(dynamic p) {

  final ms = p['settledAt'];

  if (ms == null) return false;

  final s = ms is num ? ms.toInt() : int.tryParse(ms.toString());

  if (s == null) return false;

  final d = DateTime.fromMillisecondsSinceEpoch(s);

  final n = DateTime.now();

  return d.year == n.year && d.month == n.month;

}



// TP 出場比例：僅 1 個 TP 時 TP1 全出 100%；2 個為 50%/50%；3 個為 50%/25%/25%
String _tp1RatioFrom(dynamic pos) {
  if (pos == null) return '50%';
  if (toD(pos['tp2']) <= 0 && toD(pos['tp3']) <= 0) return '100%';
  return '50%';
}
String _tp2RatioFrom(dynamic pos) {
  if (pos == null) return '25%';
  if (toD(pos['tp3']) <= 0 && toD(pos['tp2']) > 0) return '50%';
  return '25%';
}
String _tp3RatioFrom(dynamic pos) => '25%';

String _tpLabel(String tp, [dynamic pos]) {
  if (tp == 'TP1') return 'TP1 (${_tp1RatioFrom(pos)})';
  if (tp == 'TP2') return 'TP2 (${_tp2RatioFrom(pos)})';
  if (tp == 'TP3') return 'TP3 (${_tp3RatioFrom(pos)})';
  return tp;
}

// --- 狀態顯示（保留趣味文案）---

String _statusDisplay(String? status, [dynamic pos]) {

  if (status == null) return '--';

  if (status.contains('監控中')) return '監視任務執行中';

  if (status.contains('止盈')) return 'やった！Mission complete ⭐️';

  if (status.contains('止損')) return 'ちー…下次再來 ⚡️';

  if (status.contains('手動出場')) {

    final ratio = pos != null ? (toD(pos['exitRatioDisplay']) > 0 ? toD(pos['exitRatioDisplay']) : toD(pos['exitRatio'])) : 0;

    if (ratio > 0 && ratio < 1) return '手動出場 ${(ratio * 100).toInt()}%';

    return '手動出場';

  }

  return status;

}



// --- 成就定義 ---

const _achievements = [

  {'id': 'first_task', 'title': 'ワクワク初體驗', 'desc': '首次新增監控任務', 'emoji': '🥜'},

  {'id': 'first_tp', 'title': 'Stella 一顆', 'desc': '首次止盈達標', 'emoji': '⭐'},

  {'id': 'first_sl', 'title': '學到教訓', 'desc': '首次止損出局', 'emoji': '📖'},

  {'id': 'tp_5', 'title': '秘密任務達人', 'desc': '累積止盈 5 次', 'emoji': '🕵️'},

  {'id': 'tp_10', 'title': '精英特務', 'desc': '累積止盈 10 次', 'emoji': '🎖️'},

  {'id': 'tasks_3', 'title': '多線作戰', 'desc': '同時監控 3 筆任務', 'emoji': '📋'},

];



const _achievementKey = 'anya_unlocked_achievements';

const _statsKey = 'anya_stats';



/// 取得指定週期的 OI 變動百分比（最近一期），失敗或資料不足回傳 null

Future<double?> _fetchOiChange(String symbol, String period) async {

  try {

    final res = await http.get(Uri.parse(

      'https://fapi.binance.com/futures/data/openInterestHist?symbol=$symbol&period=$period&limit=2',

    ));

    if (res.statusCode != 200) return null;

    final list = json.decode(res.body) as List;

    if (list.length < 2) return null;

    final oldOi = toD((list[0] as Map)['sumOpenInterest']);

    final newOi = toD((list[1] as Map)['sumOpenInterest']);

    if (oldOi == 0) return null;

    return (newOi - oldOi) / oldOi * 100;

  } catch (_) {

    return null;

  }

}



void main() async {

  WidgetsFlutterBinding.ensureInitialized();

  runApp(const AnyaProfessionalApp());

}



class AnyaProfessionalApp extends StatelessWidget {

  const AnyaProfessionalApp({super.key});

  @override

  Widget build(BuildContext context) {

    return MaterialApp(

      debugShowCheckedModeBanner: false,

      theme: ThemeData.dark().copyWith(

        primaryColor: const Color(0xFFFFC0CB),

        scaffoldBackgroundColor: const Color(0xFF0D0D0D),

      ),

      home: const CryptoDashboard(),

    );

  }

}



class Candle {

  Candle(this.x, this.low, this.high, this.open, this.close);

  final DateTime x; final double low; final double high; final double open; final double close;

}

Future<List<Candle>> _fetchKlines(String symbol) async {

  try {

    final res = await http.get(Uri.parse('https://fapi.binance.com/fapi/v1/klines?symbol=$symbol&interval=15m&limit=40'));

    if (res.statusCode != 200) return [];

    final data = json.decode(res.body) as List;

    return data.map((e) => Candle(DateTime.fromMillisecondsSinceEpoch(e[0]), toD(e[3]), toD(e[2]), toD(e[1]), toD(e[4]))).toList();

  } catch (_) { return []; }

}

List<dynamic> _serializeCandles(List<Candle> c) => c.map((e) => [e.x.millisecondsSinceEpoch, e.open, e.high, e.low, e.close]).toList();

List<Candle> _deserializeCandles(List<dynamic> raw) => raw.map((e) {

  final L = e as List;

  return Candle(DateTime.fromMillisecondsSinceEpoch(L[0] as int), toD(L[3]), toD(L[2]), toD(L[1]), toD(L[4]));

}).toList();

CartesianChartAnnotation _chartLine(dynamic p, Color c, String t) => CartesianChartAnnotation(

  widget: Text("-- $t ($p)", style: TextStyle(color: c, fontSize: 10)),

  coordinateUnit: CoordinateUnit.point, y: toD(p), x: DateTime.now(),

);

Widget _chartBox(String l, String v) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(v)]);

Widget _chartOiChip(String period, double? change) {

  if (change == null) return Text("$period: --", style: const TextStyle(fontSize: 11, color: Colors.grey));

  final isUp = change >= 0;

  final sign = isUp ? '+' : '';

  return Text("$period: $sign${change.toStringAsFixed(2)}%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isUp ? Colors.green : Colors.red));

}



class CryptoDashboard extends StatefulWidget {

  const CryptoDashboard({super.key});

  @override

  State<CryptoDashboard> createState() => _CryptoDashboardState();

}



class _CryptoDashboardState extends State<CryptoDashboard> {

  Timer? _timer;

  List<dynamic> positions = [];

  bool isLoading = true;



  @override

  void initState() {

    super.initState();

    _initData();

  }



  Future<void> _initData() async {

    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getString('anya_pro_v2026_final');

    if (data != null) {

      setState(() {

        positions = json.decode(data);

        for (final p in positions) {

          if (p is! Map) continue;

          final status = p['status']?.toString() ?? '';

          if (!status.contains('手動出場')) continue;

          final ratio = toD(p['exitRatio']);

          if (ratio <= 0 || ratio >= 1) continue;

          if (p['exitRatioDisplay'] != null) continue;

          final oldU = toD(p['uValue']);

          p['uValue'] = oldU * ratio;

          p['exitRatio'] = 1.0;

          p['exitRatioDisplay'] = ratio;

        }

      });

      await _persistPositions();

    }

    setState(() => isLoading = false);

    _timer = Timer.periodic(const Duration(seconds: 5), (t) => _refresh());

  }



  Future<void> _persistPositions() async {

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('anya_pro_v2026_final', json.encode(positions));

  }



  Future<void> _refresh() async {

    final oldStatuses = positions.map((p) => p['status'].toString()).toList();

    for (int i = 0; i < positions.length; i++) {

      if (!positions[i]['status'].toString().contains('監控中')) continue;

      try {

        final res = await http.get(Uri.parse('https://fapi.binance.com/fapi/v1/ticker/price?symbol=${positions[i]['symbol']}'));

        if (res.statusCode == 200) {

          setState(() {

            positions[i]['current'] = double.parse(json.decode(res.body)['price']);

            _checkLogic(i);

          });

        }

      } catch (_) {}

    }

    for (int i = 0; i < positions.length; i++) {

      if (oldStatuses[i] != positions[i]['status'].toString()) {

        final s = positions[i]['status'].toString();

        if (s.contains('止盈') || s.contains('止損')) {

          positions[i]['settledAt'] = DateTime.now().millisecondsSinceEpoch;

          if (s.contains('止盈')) {

            final cur = toD(positions[i]['current']);

            final tp1 = toD(positions[i]['tp1']), tp2 = toD(positions[i]['tp2']), tp3 = toD(positions[i]['tp3']);

            if (tp3 > 0 && cur >= tp3) positions[i]['hitTp'] = 'TP3';

            else if (tp2 > 0 && cur >= tp2) positions[i]['hitTp'] = 'TP2';

            else if (tp1 > 0 && cur >= tp1) positions[i]['hitTp'] = 'TP1';

          }

          final c = await _fetchKlines(positions[i]['symbol'] as String);

          if (c.isNotEmpty) positions[i]['candles'] = _serializeCandles(c);

        }

      }

    }

    await _persistPositions();

    bool hitTp = false, hitSl = false;

    for (int i = 0; i < positions.length; i++) {

      if (oldStatuses[i] != positions[i]['status'].toString()) {

        if (positions[i]['status'].toString().contains('止盈')) hitTp = true;

        if (positions[i]['status'].toString().contains('止損')) hitSl = true;

      }

    }

    if (hitTp) await _onHitTp();

    if (hitSl) await _onHitSl();

  }



  void _checkLogic(int i) {

    double cur = toD(positions[i]['current']);

    double sl = toD(positions[i]['sl']);

    double tp1 = toD(positions[i]['tp1']);

    double tp2 = toD(positions[i]['tp2']);

    double tp3 = toD(positions[i]['tp3']);

    double targetTp = tp3 > 0 ? tp3 : (tp2 > 0 ? tp2 : tp1);

    if (cur <= sl) positions[i]['status'] = '止損出局 ⚡️';

    else if (targetTp > 0 && cur >= targetTp) positions[i]['status'] = '止盈達標 ⭐️';

  }



  Future<Map<String, int>> _getStats() async {

    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_statsKey);

    if (raw == null) return {'totalTp': 0, 'totalSl': 0};

    try {

      final m = json.decode(raw) as Map<String, dynamic>;

      return {'totalTp': (m['totalTp'] as num?)?.toInt() ?? 0, 'totalSl': (m['totalSl'] as num?)?.toInt() ?? 0};

    } catch (_) {

      return {'totalTp': 0, 'totalSl': 0};

    }

  }



  Future<void> _saveStats(Map<String, int> stats) async {

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_statsKey, json.encode(stats));

  }



  Future<Set<String>> _getUnlocked() async {

    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_achievementKey);

    if (raw == null) return {};

    try {

      final list = json.decode(raw) as List;

      return Set<String>.from(list.cast<String>());

    } catch (_) {

      return {};

    }

  }



  Future<void> _unlock(String id) async {

    final unlocked = await _getUnlocked();

    if (unlocked.contains(id)) return;

    unlocked.add(id);

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_achievementKey, json.encode(unlocked.toList()));

    if (!mounted) return;

    final a = _achievements.cast<Map<String, dynamic>>().firstWhere((e) => e['id'] == id, orElse: () => {});

    ScaffoldMessenger.of(context).showSnackBar(

      SnackBar(

        content: Text("🏆 解鎖稱號：${a['emoji']} ${a['title']}"),

        backgroundColor: const Color(0xFFE91E8C),

        behavior: SnackBarBehavior.floating,

      ),

    );

  }



  Future<void> _onHitTp() async {

    final stats = await _getStats();

    stats['totalTp'] = (stats['totalTp'] ?? 0) + 1;

    await _saveStats(stats);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(

      const SnackBar(content: Text("やった！Mission complete ⭐️"), backgroundColor: Color(0xFF4CAF50), behavior: SnackBarBehavior.floating),

    );

    final unlocked = await _getUnlocked();

    if (!unlocked.contains('first_tp')) await _unlock('first_tp');

    if (stats['totalTp']! >= 5 && !unlocked.contains('tp_5')) await _unlock('tp_5');

    if (stats['totalTp']! >= 10 && !unlocked.contains('tp_10')) await _unlock('tp_10');

  }



  Future<void> _onHitSl() async {

    final stats = await _getStats();

    stats['totalSl'] = (stats['totalSl'] ?? 0) + 1;

    await _saveStats(stats);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(

      const SnackBar(content: Text("ちー…下次再來 ⚡️"), backgroundColor: Color(0xFF757575), behavior: SnackBarBehavior.floating),

    );

    final unlocked = await _getUnlocked();

    if (!unlocked.contains('first_sl')) await _unlock('first_sl');

  }



  void _showAchievements() async {

    final unlocked = await _getUnlocked();

    if (!mounted) return;

    showModalBottomSheet(

      context: context,

      backgroundColor: const Color(0xFF1A1A1A),

      builder: (ctx) => Padding(

        padding: const EdgeInsets.all(20),

        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [

          const Text("🏆 成就 / 稱號", style: TextStyle(color: Color(0xFFFFC0CB), fontSize: 20, fontWeight: FontWeight.bold)),

          const SizedBox(height: 12),

          ..._achievements.map((a) {

            final id = a['id'] as String;

            final isUnlocked = unlocked.contains(id);

            return ListTile(

              leading: Text(a['emoji'] as String, style: const TextStyle(fontSize: 24)),

              title: Text(isUnlocked ? a['title'] as String : '???', style: TextStyle(color: isUnlocked ? Colors.white : Colors.grey)),

              subtitle: Text(isUnlocked ? a['desc'] as String : '尚未解鎖', style: const TextStyle(fontSize: 12, color: Colors.grey)),

            );

          }),

        ]),

      ),

    );

  }

  void _showManualExit(Map<String, dynamic> pos) {

    final priceController = TextEditingController(text: (pos['current'] ?? pos['entry'] ?? '').toString());

    final exitRatioNotifier = ValueNotifier<double>(1.0);

    showDialog(

      context: context,

      builder: (ctx) => StatefulBuilder(

        builder: (context, setDialogState) => AlertDialog(

          backgroundColor: const Color(0xFF1A1A1A),

          title: const Text("手動出場", style: TextStyle(color: Color(0xFFFFC0CB))),

          content: SingleChildScrollView(

            child: Column(

              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                TextField(

                  controller: priceController,

                  keyboardType: const TextInputType.numberWithOptions(decimal: true),

                  decoration: const InputDecoration(labelText: "手動出場價格", hintText: "輸入出場時價格"),

                ),

                const SizedBox(height: 16),

                const Text("出場艙位比例", style: TextStyle(fontSize: 12, color: Colors.grey)),

                const SizedBox(height: 8),

                Row(

                  children: [

                    for (final r in [0.25, 0.5, 0.75, 1.0])

                      Padding(

                        padding: const EdgeInsets.only(right: 8),

                        child: ChoiceChip(

                          label: Text(r == 1.0 ? '100%' : '${(r * 100).toInt()}%'),

                          selected: exitRatioNotifier.value == r,

                          onSelected: (_) { exitRatioNotifier.value = r; setDialogState(() {}); },

                          selectedColor: const Color(0xFFFFC0CB).withOpacity(0.5),

                        ),

                      ),

                  ],

                ),

              ],

            ),

          ),

          actions: [

            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),

            FilledButton(

              onPressed: () async {

                final price = toD(priceController.text);

                if (price <= 0) return;

                Navigator.pop(ctx);

                final ratio = exitRatioNotifier.value;

                final c = await _fetchKlines(pos['symbol'] as String);

                if (ratio >= 1.0) {

                  setState(() {

                    pos['current'] = price;

                    pos['status'] = '手動出場';

                    pos['settledAt'] = DateTime.now().millisecondsSinceEpoch;

                    pos['exitRatio'] = ratio;

                    if (c.isNotEmpty) pos['candles'] = _serializeCandles(c);

                  });

                } else {

                  final closedU = toD(pos['uValue']) * ratio;

                  final remainingU = toD(pos['uValue']) * (1 - ratio);

                  final closedPortion = {

                    'symbol': pos['symbol'], 'leverage': pos['leverage'], 'uValue': closedU, 'entry': pos['entry'], 'current': price,

                    'entryTime': pos['entryTime'], 'tp1': pos['tp1'], 'tp2': pos['tp2'], 'tp3': pos['tp3'], 'sl': pos['sl'],

                    'status': '手動出場', 'settledAt': DateTime.now().millisecondsSinceEpoch, 'exitRatio': 1.0, 'exitRatioDisplay': ratio,

                    'candles': c.isNotEmpty ? _serializeCandles(c) : null,

                  };

                  setState(() {

                    positions.add(closedPortion);

                    pos['uValue'] = remainingU;

                    pos['current'] = price;

                  });

                }

                await _persistPositions();

              },

              child: const Text("確認出場"),

            ),

          ],

        ),

      ),

    );

  }

  List<dynamic> get _watching => positions.where((p) => p['status'].toString().contains('監控中')).toList();

  List<dynamic> get _settled => positions.where((p) {

    final s = p['status'].toString();

    return s.contains('止盈') || s.contains('止損') || s.contains('手動出場');

  }).toList();



  @override

  Widget build(BuildContext context) {

    return DefaultTabController(

      length: 2,

      child: Scaffold(

        appBar: AppBar(

          title: const Text('任務看板'),

          actions: [

            IconButton(icon: const Icon(Icons.emoji_events_outlined), onPressed: _showAchievements),

          ],

          bottom: const TabBar(

            tabs: [

              Tab(text: '監控中'),

              Tab(text: '已結算'),

            ],

          ),

        ),

        body: isLoading

            ? const Center(child: CircularProgressIndicator())

            : TabBarView(

                children: [

                  _listForPositions(_watching, emptyLabel: '尚無監控中的任務', isSettled: false),

                  Column(

                    key: ValueKey<String>(_settled.map((p) => '${p['settledAt']}_${p['current']}').join('|')),

                    children: [

                      _buildSettledDailySummary(),

                      _buildSettledMonthlySummary(),

                      Expanded(child: _listForPositions(_settled, emptyLabel: '尚無已結算的任務', isSettled: true)),

                    ],

                  ),

                ],

              ),

        floatingActionButton: FloatingActionButton.extended(

          onPressed: _showAdd,

          label: const Text("新增任務"),

          icon: const Icon(Icons.add),

          backgroundColor: const Color(0xFFFFC0CB),

        ),

      ),

    );

  }



  Widget _buildSettledSummaryCard(List<dynamic> list, String emptyLabel, String titlePnl, String titleWinRate) {

    if (list.isEmpty) {

      return Padding(

        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),

        child: Text(emptyLabel, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),

      );

    }

    double pnl = 0;

    int winCount = 0;

    for (final p in list) {

      pnl += _pnlAmount(p);

      final s = p['status'].toString();

      if (s.contains('止盈') || (s.contains('手動出場') && _pnlAmount(p) > 0)) winCount++;

    }

    final winRate = list.isNotEmpty ? (winCount / list.length * 100) : null;

    return Card(

      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),

      child: Padding(

        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),

        child: Row(

          mainAxisAlignment: MainAxisAlignment.spaceAround,

          children: [

            Column(children: [

              Text(titlePnl, style: const TextStyle(fontSize: 11, color: Colors.grey)),

              Text("${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)} U", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: pnl >= 0 ? Colors.green : Colors.red)),

            ]),

            Column(children: [

              Text(titleWinRate, style: const TextStyle(fontSize: 11, color: Colors.grey)),

              Text(winRate != null ? '${winRate.toStringAsFixed(1)}%' : '--', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: winRate != null && winRate >= 50 ? Colors.green : (winRate != null ? Colors.red : Colors.white))),

            ]),

          ],

        ),

      ),

    );

  }

  Widget _buildSettledDailySummary() => _buildSettledSummaryCard(

    _settled.where((p) => _isSettledToday(p)).toList(),

    "當日尚無結算",

    "當日總盈虧",

    "當日勝率",

  );

  Widget _buildSettledMonthlySummary() => _buildSettledSummaryCard(

    _settled.where((p) => _isSettledThisMonth(p)).toList(),

    "當月尚無結算",

    "當月總盈虧",

    "當月勝率",

  );

  Widget _listForPositions(List<dynamic> list, {String emptyLabel = '尚無資料', bool isSettled = false}) {

    if (list.isEmpty) {

      return Center(

        child: Text(emptyLabel, style: const TextStyle(color: Colors.grey)),

      );

    }

    return ListView.builder(

      itemCount: list.length,

      itemBuilder: (ctx, i) {

        final pos = list[i];

        final subtitle = isSettled

            ? "營利: ${_pnlAmount(pos) >= 0 ? '+' : ''}${_pnlAmount(pos).toStringAsFixed(2)} U | RR: ${_rrValue(pos) != null ? _rrValue(pos)!.toStringAsFixed(2) : '--'} | ROI: ${calculateROI(pos)}% | 結算: ${_fmtEntryTime(pos['settledAt'])} · 持倉 ${_fmtDuration(pos['entryTime'], pos['settledAt'])}${pos['status'].toString().contains('止盈') && pos['hitTp'] != null ? ' · ${_tpLabel(pos['hitTp'].toString(), pos)}' : ''} | ${_statusDisplay(pos['status'], pos)}"

            : "ROI: ${calculateROI(pos)}% | 進場: ${_fmtEntryTime(pos['entryTime'])} | ${_statusDisplay(pos['status'], pos)}";

        return Card(

          margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),

          child: ListTile(

            onTap: () => _showDetail(pos),

            title: Text("${pos['symbol']} (${pos['leverage']}x)"),

            subtitle: Text(subtitle),

            trailing: Row(mainAxisSize: MainAxisSize.min, children: [

              if (!isSettled) IconButton(icon: const Icon(Icons.exit_to_app), tooltip: '手動出場', onPressed: () => _showManualExit(pos)),

              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _showEdit(pos)),

              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { setState(() => positions.remove(pos)); await _persistPositions(); }),

            ]),

          ),

        );

      },

    );

  }



  String calculateROI(Map p) {

    double ent = toD(p['entry']);

    double cur = toD(p['current']);

    int lev = (p['leverage'] as num).toInt();

    final ratio = toD(p['exitRatio']) > 0 ? toD(p['exitRatio']) : 1.0;

    return (((cur - ent) / ent) * 100 * lev * ratio).toStringAsFixed(2);

  }



  // --- 核心：內建繪圖視窗 + OI 變動（已結算＝快照；監控中＝定時重抓）---

  void _showDetail(Map<String, dynamic> pos) async {

    final symbol = pos['symbol'] as String;

    final isSettled = pos['status'].toString().contains('止盈') || pos['status'].toString().contains('止損') || pos['status'].toString().contains('手動出場');

    const oiPeriods = ['5m', '15m', '30m', '1h', '4h'];

    if (isSettled) {

      List<Candle> candles = [];

      if (pos['candles'] != null && (pos['candles'] as List).isNotEmpty) {

        candles = _deserializeCandles(pos['candles'] as List);

      } else {

        candles = await _fetchKlines(symbol);

      }

      if (!mounted) return;

      _showChartDialog(pos: pos, symbol: symbol, candles: candles, oiChanges: <String, double?>{}, oiPeriods: oiPeriods, isSettled: true);

    } else {

      List<Candle> candles = await _fetchKlines(symbol);

      final oiChanges = <String, double?>{};

      await Future.wait(oiPeriods.map((p) async => oiChanges[p] = await _fetchOiChange(symbol, p)));

      if (!mounted) return;

      _showChartDialog(pos: pos, symbol: symbol, candles: candles, oiChanges: oiChanges, oiPeriods: oiPeriods, isSettled: false);

    }

  }

  void _showChartDialog({required Map<String, dynamic> pos, required String symbol, required List<Candle> candles, required Map<String, double?> oiChanges, required List<String> oiPeriods, required bool isSettled}) {

    showDialog(context: context, builder: (ctx) => AlertDialog(

      backgroundColor: const Color(0xFF111111),

      content: SizedBox(

        width: 900, height: 660,

        child: isSettled

            ? _buildChartContent(pos: pos, symbol: symbol, candles: candles, oiChanges: oiChanges, oiPeriods: oiPeriods)

            : _DetailChartLive(pos: pos, symbol: symbol, initialCandles: candles, initialOiChanges: Map.from(oiChanges), oiPeriods: oiPeriods),

      ),

    ));

  }

  Widget _buildChartContent({required Map<String, dynamic> pos, required String symbol, required List<Candle> candles, required Map<String, double?> oiChanges, required List<String> oiPeriods}) {

    return Column(children: [

      Text("$symbol 15m K線${pos['candles'] != null && (pos['candles'] as List).isNotEmpty ? '（結算快照）' : ''}", style: const TextStyle(color: Color(0xFFFFC0CB), fontSize: 20)),

      Expanded(child: SfCartesianChart(

        primaryXAxis: DateTimeAxis(),

        series: <CartesianSeries<Candle, DateTime>>[

          CandleSeries<Candle, DateTime>(

            dataSource: candles, xValueMapper: (c,_) => c.x, lowValueMapper: (c,_) => c.low, highValueMapper: (c,_) => c.high, openValueMapper: (c,_) => c.open, closeValueMapper: (c,_) => c.close,

          ),

        ],

        annotations: [

          _chartLine(pos['entry'], Colors.white, "Entry"),

          if (toD(pos['tp3']) > 0) _chartLine(pos['tp3'], Colors.green, "TP3"),

          if (toD(pos['tp3']) <= 0 && toD(pos['tp2']) > 0) _chartLine(pos['tp2'], Colors.green, "TP2"),

          if (toD(pos['tp3']) <= 0 && toD(pos['tp2']) <= 0 && toD(pos['tp1']) > 0) _chartLine(pos['tp1'], Colors.green, "TP1"),

          _chartLine(pos['sl'], Colors.red, "SL"),

        ],

      )),

      const Divider(),

      if (oiChanges.isNotEmpty && oiChanges.values.any((v) => v != null)) Row(mainAxisAlignment: MainAxisAlignment.center, children: [

        const Text("OI 變動：", style: TextStyle(fontSize: 12, color: Colors.grey)),

        const SizedBox(width: 8),

        ...oiPeriods.map((p) => Padding(padding: const EdgeInsets.only(right: 12), child: _chartOiChip(p, oiChanges[p]))),

      ]) else const SizedBox.shrink(),

      const SizedBox(height: 8),

      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [

        _chartBox("槓桿", "${pos['leverage']}x"),

        _chartBox("價值", "${pos['uValue']}U"),

        _chartBox("進場時間", _fmtEntryTime(pos['entryTime'])),

        _chartBox("TP1 (${_tp1RatioFrom(pos)})", "${pos['tp1']}"),

        if (toD(pos['tp2']) > 0) _chartBox("TP2 (${_tp2RatioFrom(pos)})", "${pos['tp2']}"),

        if (toD(pos['tp3']) > 0) _chartBox("TP3 (${_tp3RatioFrom(pos)})", "${pos['tp3']}"),

      ]),

      if (pos['settledAt'] != null) ...[

        const Divider(),

        const Text("結算紀錄", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),

        const SizedBox(height: 6),

        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [

          Column(children: [

            const Text("營利金額", style: TextStyle(fontSize: 11, color: Colors.grey)),

            Text("${_pnlAmount(pos) >= 0 ? '+' : ''}${_pnlAmount(pos).toStringAsFixed(2)} U", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _pnlAmount(pos) >= 0 ? Colors.green : Colors.red)),

          ]),

          Column(children: [

            const Text("RR 值", style: TextStyle(fontSize: 11, color: Colors.grey)),

            Text(_rrValue(pos) != null ? _rrValue(pos)!.toStringAsFixed(2) : '--', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _rrValue(pos) != null && _rrValue(pos)! >= 0 ? Colors.green : (_rrValue(pos) != null ? Colors.red : Colors.white))),

          ]),

        ]),

        const SizedBox(height: 8),

        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [

          _chartBox("結算時間", _fmtEntryTime(pos['settledAt'])),

          _chartBox("持倉時長", _fmtDuration(pos['entryTime'], pos['settledAt'])),

          _chartBox("達標檔位", pos['status'].toString().contains('止盈') ? _tpLabel((pos['hitTp'] ?? '--').toString(), pos) : (pos['status'].toString().contains('止損') ? '止損' : (pos['status'] ?? '--').toString())),

        ]),

        const SizedBox(height: 8),

        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [

          _chartBox("盈虧率", "${calculateROI(pos)}%"),

          _chartBox("盈虧金額", "${_pnlAmount(pos) >= 0 ? '+' : ''}${_pnlAmount(pos).toStringAsFixed(2)} U"),

          _chartBox("RR", _rrValue(pos) != null ? _rrValue(pos)!.toStringAsFixed(2) : '--'),

        ]),

      ],

    ]);

  }



  // --- 回歸：全功能輸入欄位 ---

  void _showAdd() {

    final cs = {

      'sym': TextEditingController(text: "BTCUSDT"), 'lev': TextEditingController(text: "20"),

      'val': TextEditingController(text: "100"), 'ent': TextEditingController(),

      'tp1': TextEditingController(), 'tp2': TextEditingController(),

      'tp3': TextEditingController(), 'sl': TextEditingController()

    };

    DateTime entryTime = DateTime.now();

    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) {

      return StatefulBuilder(

        builder: (context, setModalState) {

          return Padding(

            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),

            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [

              const Text("🎯 開啟專業監控任務", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFFFC0CB))),

              TextField(controller: cs['sym'], decoration: const InputDecoration(labelText: "交易對")),

              Row(children: [

                Expanded(child: TextField(controller: cs['lev'], decoration: const InputDecoration(labelText: "槓桿"), keyboardType: TextInputType.number)),

                const SizedBox(width: 10),

                Expanded(child: TextField(controller: cs['val'], decoration: const InputDecoration(labelText: "倉位 (U)"), keyboardType: TextInputType.number)),

              ]),

              TextField(controller: cs['ent'], decoration: const InputDecoration(labelText: "進場價"), keyboardType: TextInputType.number),

              const SizedBox(height: 8),

              ListTile(

                contentPadding: EdgeInsets.zero,

                title: const Text("進場時間", style: TextStyle(fontSize: 12, color: Colors.grey)),

                subtitle: Text(

                  "${entryTime.year}-${entryTime.month.toString().padLeft(2, '0')}-${entryTime.day.toString().padLeft(2, '0')} ${entryTime.hour.toString().padLeft(2, '0')}:${entryTime.minute.toString().padLeft(2, '0')}",

                  style: const TextStyle(color: Color(0xFFFFC0CB), fontWeight: FontWeight.w500),

                ),

                trailing: TextButton.icon(

                  icon: const Icon(Icons.calendar_today, size: 18),

                  label: const Text("選擇"),

                  onPressed: () async {

                    final date = await showDatePicker(

                      context: context,

                      initialDate: entryTime,

                      firstDate: DateTime(2020),

                      lastDate: DateTime.now().add(const Duration(days: 365)),

                    );

                    if (date == null || !context.mounted) return;

                    final time = await showTimePicker(

                      context: context,

                      initialTime: TimeOfDay.fromDateTime(entryTime),

                    );

                    if (time == null || !context.mounted) return;

                    setModalState(() => entryTime = DateTime(date.year, date.month, date.day, time.hour, time.minute));

                  },

                ),

              ),

              TextField(controller: cs['tp1'], decoration: const InputDecoration(labelText: "TP1（必填）出場 50%，僅設 TP1 時為全出 100%"), keyboardType: TextInputType.number),

              Row(children: [

                Expanded(child: TextField(controller: cs['tp2'], decoration: const InputDecoration(labelText: "TP2（選填）出場 25%，僅設 TP1+TP2 時為 50%"), keyboardType: TextInputType.number)),

                const SizedBox(width: 8),

                Expanded(child: TextField(controller: cs['tp3'], decoration: const InputDecoration(labelText: "TP3（選填）出場 25%"), keyboardType: TextInputType.number)),

              ]),

              TextField(controller: cs['sl'], decoration: const InputDecoration(labelText: "止損 SL")),

              const SizedBox(height: 20),

              ElevatedButton(

                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: const Color(0xFFFFC0CB)),

                onPressed: () async {

                  setState(() => positions.add({

                    'symbol': cs['sym']!.text.toUpperCase(), 'leverage': int.parse(cs['lev']!.text),

                    'uValue': toD(cs['val']!.text), 'entry': toD(cs['ent']!.text),

                    'current': toD(cs['ent']!.text), 'entryTime': entryTime.millisecondsSinceEpoch,

                    'tp1': toD(cs['tp1']!.text), 'tp2': toD(cs['tp2']!.text), 'tp3': toD(cs['tp3']!.text),

                    'sl': toD(cs['sl']!.text), 'status': '監控中'

                  }));

                  Navigator.pop(ctx);

                  final unlocked = await _getUnlocked();

                  if (!unlocked.contains('first_task')) await _unlock('first_task');

                  final watching = positions.where((p) => p['status'].toString().contains('監控中')).length;

                  if (watching >= 3 && !unlocked.contains('tasks_3')) await _unlock('tasks_3');

                },

                child: const Text("存檔啟動", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))

              ),

              const SizedBox(height: 20),

            ])),

          );

        },

      );

    });

  }

  void _showEdit(Map<String, dynamic> pos) {

    final entryMs = pos['entryTime'];

    final entryTime = entryMs != null ? DateTime.fromMillisecondsSinceEpoch((entryMs is num) ? entryMs.toInt() : int.tryParse(entryMs.toString()) ?? 0) : DateTime.now();

    final isSettledEdit = pos['status'].toString().contains('止盈') || pos['status'].toString().contains('止損') || pos['status'].toString().contains('手動出場');

    final cs = {

      'sym': TextEditingController(text: (pos['symbol'] ?? 'BTCUSDT').toString()),

      'lev': TextEditingController(text: (pos['leverage'] ?? 20).toString()),

      'val': TextEditingController(text: (pos['uValue'] ?? 100).toString()),

      'ent': TextEditingController(text: (pos['entry'] ?? '').toString()),

      'settledPrice': TextEditingController(text: (pos['current'] ?? pos['entry'] ?? '').toString()),

      'tp1': TextEditingController(text: (pos['tp1'] ?? '').toString()),

      'tp2': TextEditingController(text: (pos['tp2'] ?? '').toString()),

      'tp3': TextEditingController(text: (pos['tp3'] ?? '').toString()),

      'sl': TextEditingController(text: (pos['sl'] ?? '').toString()),

    };

    DateTime editEntryTime = entryTime;

    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) {

      return StatefulBuilder(

        builder: (context, setModalState) {

          return Padding(

            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),

            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [

              const Text("✏️ 編輯任務", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFFFC0CB))),

              TextField(controller: cs['sym'], decoration: const InputDecoration(labelText: "交易對")),

              Row(children: [

                Expanded(child: TextField(controller: cs['lev'], decoration: const InputDecoration(labelText: "槓桿"), keyboardType: TextInputType.number)),

                const SizedBox(width: 10),

                Expanded(child: TextField(controller: cs['val'], decoration: const InputDecoration(labelText: "倉位 (U)"), keyboardType: TextInputType.number)),

              ]),

              TextField(controller: cs['ent'], decoration: const InputDecoration(labelText: "進場價"), keyboardType: TextInputType.number),

              if (isSettledEdit) TextField(controller: cs['settledPrice'], decoration: const InputDecoration(labelText: "結算價（已結算單的出場價，用於計算營利與 RR）"), keyboardType: TextInputType.number),

              const SizedBox(height: 8),

              ListTile(

                contentPadding: EdgeInsets.zero,

                title: const Text("進場時間", style: TextStyle(fontSize: 12, color: Colors.grey)),

                subtitle: Text(

                  "${editEntryTime.year}-${editEntryTime.month.toString().padLeft(2, '0')}-${editEntryTime.day.toString().padLeft(2, '0')} ${editEntryTime.hour.toString().padLeft(2, '0')}:${editEntryTime.minute.toString().padLeft(2, '0')}",

                  style: const TextStyle(color: Color(0xFFFFC0CB), fontWeight: FontWeight.w500),

                ),

                trailing: TextButton.icon(

                  icon: const Icon(Icons.calendar_today, size: 18),

                  label: const Text("選擇"),

                  onPressed: () async {

                    final date = await showDatePicker(context: context, initialDate: editEntryTime, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));

                    if (date == null || !context.mounted) return;

                    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(editEntryTime));

                    if (time == null || !context.mounted) return;

                    setModalState(() => editEntryTime = DateTime(date.year, date.month, date.day, time.hour, time.minute));

                  },

                ),

              ),

              TextField(controller: cs['tp1'], decoration: const InputDecoration(labelText: "TP1（必填）出場 50%，僅設 TP1 時為全出 100%"), keyboardType: TextInputType.number),

              Row(children: [

                Expanded(child: TextField(controller: cs['tp2'], decoration: const InputDecoration(labelText: "TP2（選填）出場 25%，僅設 TP1+TP2 時為 50%"), keyboardType: TextInputType.number)),

                const SizedBox(width: 8),

                Expanded(child: TextField(controller: cs['tp3'], decoration: const InputDecoration(labelText: "TP3（選填）出場 25%"), keyboardType: TextInputType.number)),

              ]),

              TextField(controller: cs['sl'], decoration: const InputDecoration(labelText: "止損 SL")),

              const SizedBox(height: 20),

              ElevatedButton(

                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: const Color(0xFFFFC0CB)),

                onPressed: () async {

                  final idx = positions.indexOf(pos);

                  if (idx < 0) { Navigator.pop(ctx); return; }

                  final updated = {

                    'symbol': cs['sym']!.text.toUpperCase(), 'leverage': int.tryParse(cs['lev']!.text) ?? (pos['leverage'] as int? ?? 20),

                    'uValue': toD(cs['val']!.text), 'entry': toD(cs['ent']!.text),

                    'current': isSettledEdit ? toD(cs['settledPrice']!.text) : toD(cs['ent']!.text),

                    'entryTime': editEntryTime.millisecondsSinceEpoch,

                    'tp1': toD(cs['tp1']!.text), 'tp2': toD(cs['tp2']!.text), 'tp3': toD(cs['tp3']!.text),

                    'sl': toD(cs['sl']!.text), 'status': pos['status'],

                  };

                  if (pos['settledAt'] != null) {

                    updated['settledAt'] = pos['settledAt'];

                    updated['hitTp'] = pos['hitTp'];

                    if (pos['candles'] != null) updated['candles'] = pos['candles'];

                    if (pos['exitRatio'] != null) updated['exitRatio'] = pos['exitRatio'];

                  }

                  setState(() => positions[idx] = updated);

                  Navigator.pop(ctx);

                  await _persistPositions();

                  if (mounted) setState(() {});

                },

                child: const Text("儲存修改", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),

              ),

              const SizedBox(height: 20),

            ])),

          );

        },

      );

    });

  }

}

class _DetailChartLive extends StatefulWidget {

  final Map<String, dynamic> pos;

  final String symbol;

  final List<Candle> initialCandles;

  final Map<String, double?> initialOiChanges;

  final List<String> oiPeriods;

  const _DetailChartLive({required this.pos, required this.symbol, required this.initialCandles, required this.initialOiChanges, required this.oiPeriods});

  @override

  State<_DetailChartLive> createState() => _DetailChartLiveState();

}

class _DetailChartLiveState extends State<_DetailChartLive> {

  late List<Candle> candles;

  late Map<String, double?> oiChanges;

  Timer? _timer;

  static const _intervalSec = 5;

  @override

  void initState() {

    super.initState();

    candles = List.from(widget.initialCandles);

    oiChanges = Map.from(widget.initialOiChanges);

    _timer = Timer.periodic(const Duration(seconds: _intervalSec), (_) => _refresh());

  }

  @override

  void dispose() {

    _timer?.cancel();

    super.dispose();

  }

  Future<void> _refresh() async {

    final c = await _fetchKlines(widget.symbol);

    final oi = <String, double?>{};

    await Future.wait(widget.oiPeriods.map((p) async => oi[p] = await _fetchOiChange(widget.symbol, p)));

    if (!mounted) return;

    setState(() { candles = c; oiChanges = oi; });

  }

  @override

  Widget build(BuildContext context) {

    final pos = widget.pos;

    return Column(children: [

      Text("${widget.symbol} 15m K線（每 $_intervalSec 秒更新）", style: const TextStyle(color: Color(0xFFFFC0CB), fontSize: 20)),

      Expanded(child: SfCartesianChart(

        primaryXAxis: DateTimeAxis(),

        series: <CartesianSeries<Candle, DateTime>>[

          CandleSeries<Candle, DateTime>(

            dataSource: candles, xValueMapper: (c,_) => c.x, lowValueMapper: (c,_) => c.low, highValueMapper: (c,_) => c.high, openValueMapper: (c,_) => c.open, closeValueMapper: (c,_) => c.close,

          ),

        ],

        annotations: [

          _chartLine(pos['entry'], Colors.white, "Entry"),

          if (toD(pos['tp3']) > 0) _chartLine(pos['tp3'], Colors.green, "TP3"),

          if (toD(pos['tp3']) <= 0 && toD(pos['tp2']) > 0) _chartLine(pos['tp2'], Colors.green, "TP2"),

          if (toD(pos['tp3']) <= 0 && toD(pos['tp2']) <= 0 && toD(pos['tp1']) > 0) _chartLine(pos['tp1'], Colors.green, "TP1"),

          _chartLine(pos['sl'], Colors.red, "SL"),

        ],

      )),

      const Divider(),

      Row(mainAxisAlignment: MainAxisAlignment.center, children: [

        const Text("OI 變動：", style: TextStyle(fontSize: 12, color: Colors.grey)),

        const SizedBox(width: 8),

        ...widget.oiPeriods.map((p) => Padding(padding: const EdgeInsets.only(right: 12), child: _chartOiChip(p, oiChanges[p]))),

      ]),

      const SizedBox(height: 8),

      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [

        _chartBox("槓桿", "${pos['leverage']}x"),

        _chartBox("價值", "${pos['uValue']}U"),

        _chartBox("進場時間", _fmtEntryTime(pos['entryTime'])),

        _chartBox("TP1 (${_tp1RatioFrom(pos)})", "${pos['tp1']}"),

        if (toD(pos['tp2']) > 0) _chartBox("TP2 (${_tp2RatioFrom(pos)})", "${pos['tp2']}"),

        if (toD(pos['tp3']) > 0) _chartBox("TP3 (${_tp3RatioFrom(pos)})", "${pos['tp3']}"),

      ]),

    ]);

  }

} 