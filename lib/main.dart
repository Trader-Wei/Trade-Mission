import 'package:flutter/material.dart';

import 'dart:async';

import 'dart:convert';

import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:http/http.dart' as http;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:syncfusion_flutter_charts/charts.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:image_picker/image_picker.dart';

import 'bg_image_loader.dart';

import 'dynamic_background.dart';



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

/// 是否為做多（未填或 'long' 視為做多）
bool _isLong(Map<String, dynamic> p) =>
    p['side'] == null || p['side'] == 'long' || p['side'] == '做多';

String _sideLabel(Map<String, dynamic> p) =>
    _isLong(p) ? '做多' : '做空';

double _pnlAmount(Map<String, dynamic> p) {

  final u = toD(p['uValue']);

  final ent = toD(p['entry']);

  final cur = toD(p['current']);

  final lev = (p['leverage'] as num).toInt();

  if (ent == 0) return 0;

  final priceDiff = _isLong(p) ? (cur - ent) : (ent - cur);

  final base = u * priceDiff / ent * lev;

  final ratio = toD(p['exitRatio']);

  return ratio > 0 ? base * ratio : base;

}

double? _rrValue(Map<String, dynamic> p) {

  final ent = toD(p['entry']);

  final cur = toD(p['current']);

  final sl = toD(p['sl']);

  final risk = _isLong(p) ? (ent - sl) : (sl - ent);

  if (risk <= 0) return null;

  final pnlDir = _isLong(p) ? (cur - ent) : (ent - cur);

  return pnlDir / risk;

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

  {'id': 'level_5', 'title': '初出茅廬', 'desc': '達到等級 5', 'emoji': '🌱'},

  {'id': 'level_10', 'title': '小有成就', 'desc': '達到等級 10', 'emoji': '🌿'},

  {'id': 'level_20', 'title': '經驗豐富', 'desc': '達到等級 20', 'emoji': '🌳'},

  {'id': 'profit_streak_3', 'title': '連勝新手', 'desc': '連續 3 天盈利', 'emoji': '🔥'},

  {'id': 'profit_streak_7', 'title': '連勝達人', 'desc': '連續 7 天盈利', 'emoji': '💥'},

  {'id': 'tp_streak_3', 'title': '止盈連擊', 'desc': '連續 3 次止盈', 'emoji': '⚡'},

  {'id': 'tp_streak_5', 'title': '止盈大師', 'desc': '連續 5 次止盈', 'emoji': '✨'},

  {'id': 'daily_all', 'title': '任務全清', 'desc': '單日完成所有每日任務', 'emoji': '🎯'},

];

/// 成就徽章對應的圖示（較精緻的 Material Icons）
IconData _achievementBadgeIcon(String id) {

  switch (id) {

    case 'first_task': return Icons.eco_rounded;

    case 'first_tp': return Icons.star_rounded;

    case 'first_sl': return Icons.menu_book_rounded;

    case 'tp_5': return Icons.search_rounded;

    case 'tp_10': return Icons.military_tech_rounded;

    case 'tasks_3': return Icons.assignment_rounded;

    case 'level_5': return Icons.spa_rounded;

    case 'level_10': return Icons.park_rounded;

    case 'level_20': return Icons.forest_rounded;

    case 'profit_streak_3': return Icons.local_fire_department_rounded;

    case 'profit_streak_7': return Icons.whatshot_rounded;

    case 'tp_streak_3': return Icons.bolt_rounded;

    case 'tp_streak_5': return Icons.auto_awesome_rounded;

    case 'daily_all': return Icons.track_changes_rounded;

    default: return Icons.emoji_events_rounded;

  }

}

/// 單一成就的精美徽章圖（圓形容器 + 漸層/陰影）
Widget _buildAchievementBadge({required String id, required bool isUnlocked}) {

  final icon = _achievementBadgeIcon(id);

  return Container(

    width: 44,

    height: 44,

    decoration: BoxDecoration(

      shape: BoxShape.circle,

      boxShadow: [

        BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 2)),

        if (isUnlocked) BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.25), blurRadius: 8, spreadRadius: 0),

      ],

      gradient: isUnlocked

          ? LinearGradient(

              begin: Alignment.topLeft,

              end: Alignment.bottomRight,

              colors: [const Color(0xFFFFD700), const Color(0xFFB8860B), const Color(0xFF8B6914)],

            )

          : null,

      color: isUnlocked ? null : Colors.grey.shade800,

      border: Border.all(

        color: isUnlocked ? const Color(0xFFFFE55C).withOpacity(0.8) : Colors.grey.shade600,

        width: isUnlocked ? 1.5 : 1,

      ),

    ),

    child: Icon(icon, size: 22, color: isUnlocked ? Colors.white : Colors.grey.shade500),

  );

}

const _achievementKey = 'anya_unlocked_achievements';

const _statsKey = 'anya_stats';

const _levelKey = 'anya_level_data';

const _dailyTasksKey = 'anya_daily_tasks';

const _streakKey = 'anya_streak_data';

const _bgModeKey = 'anya_bg_mode';

const _bgCustomPathKey = 'anya_bg_custom_path';

const _bgCustomImageBase64Key = 'anya_bg_custom_base64';

const _bgDynamicColorKey = 'anya_bg_dynamic_color';

// 網頁版 base64 儲存上限（字元數），避免超過 localStorage 限制
const int _kMaxBgBase64Length = 1400000;

// --- 等級系統：經驗值計算規則 ---

int _calculateExp(Map<String, dynamic> pos) {

  int exp = 0;

  final pnl = _pnlAmount(pos);

  final status = pos['status']?.toString() ?? '';

  if (status.contains('止盈')) {

    exp += 50; // 止盈基礎經驗

    if (pnl > 0) exp += (pnl / 10).floor().clamp(0, 200); // 依營利額外經驗

  } else if (status.contains('止損')) {

    exp += 10; // 止損也有經驗（學習經驗）

  } else if (status.contains('手動出場')) {

    exp += 30; // 手動出場基礎經驗

    if (pnl > 0) exp += (pnl / 15).floor().clamp(0, 150);

  }

  return exp;

}

// 等級計算：每級所需經驗 = 100 * level^1.5（向上取整）

int _expForLevel(int level) => (100 * sqrt(level * level * level)).ceil();

int _levelFromExp(int totalExp) {

  int level = 1;

  while (_expForLevel(level) <= totalExp) level++;

  return level - 1;

}

// --- 每日任務定義 ---

const _dailyTasks = [

  {'id': 'add_task', 'title': '新增任務', 'desc': '新增 1 筆監控任務', 'exp': 20, 'emoji': '📝'},

  {'id': 'settle_task', 'title': '完成結算', 'desc': '完成 1 筆結算（止盈/止損/手動出場）', 'exp': 30, 'emoji': '✅'},

  {'id': 'tp_today', 'title': '今日止盈', 'desc': '今日達成 1 次止盈', 'exp': 50, 'emoji': '⭐'},

  {'id': 'record_3', 'title': '記錄達人', 'desc': '今日記錄 3 筆以上', 'exp': 40, 'emoji': '📊'},

];

// --- 連續紀錄計算 ---

Future<Map<String, dynamic>> _calculateStreaks(List<dynamic> positions) async {

  final prefs = await SharedPreferences.getInstance();

  final raw = prefs.getString(_streakKey);

  Map<String, dynamic> streaks = raw != null ? json.decode(raw) : {};

  final now = DateTime.now();

  final today = DateTime(now.year, now.month, now.day);

  final settled = positions.where((p) => p['status']?.toString().contains('止盈') == true || 

    p['status']?.toString().contains('止損') == true || 

    p['status']?.toString().contains('手動出場') == true).toList();

  // 連續盈利天數

  int profitDays = streaks['profitDays'] ?? 0;

  DateTime? lastProfitDate = streaks['lastProfitDate'] != null ? 

    DateTime.fromMillisecondsSinceEpoch(streaks['lastProfitDate']) : null;

  final todayProfit = settled.where((p) {

    final s = p['settledAt'];

    if (s == null) return false;

    final d = DateTime.fromMillisecondsSinceEpoch(s is num ? s.toInt() : int.parse(s.toString()));

    return d.year == today.year && d.month == today.month && d.day == today.day && _pnlAmount(p) > 0;

  }).isNotEmpty;

  if (todayProfit) {

    if (lastProfitDate == null || (today.difference(DateTime(lastProfitDate.year, lastProfitDate.month, lastProfitDate.day)).inDays > 1)) {

      profitDays = 1;

    } else if (today.difference(DateTime(lastProfitDate.year, lastProfitDate.month, lastProfitDate.day)).inDays == 1) {

      profitDays++;

    }

    streaks['lastProfitDate'] = today.millisecondsSinceEpoch;

  } else if (lastProfitDate != null && today.difference(DateTime(lastProfitDate.year, lastProfitDate.month, lastProfitDate.day)).inDays > 1) {

    profitDays = 0;

  }

  streaks['profitDays'] = profitDays;

  // 連續止盈次數

  int tpStreak = streaks['tpStreak'] ?? 0;

  final lastTp = settled.where((p) => p['status']?.toString().contains('止盈') == true).toList();

  if (lastTp.isNotEmpty) {

    final lastTpTime = lastTp.map((p) => p['settledAt']).whereType<dynamic>().map((s) => 

      s is num ? s.toInt() : int.tryParse(s.toString()) ?? 0).reduce((a, b) => a > b ? a : b);

    // final lastTpDate = DateTime.fromMillisecondsSinceEpoch(lastTpTime); // 未使用，註解掉

    final todayTp = lastTp.where((p) {

      final s = p['settledAt'];

      if (s == null) return false;

      final d = DateTime.fromMillisecondsSinceEpoch(s is num ? s.toInt() : int.parse(s.toString()));

      return d.year == today.year && d.month == today.month && d.day == today.day;

    }).isNotEmpty;

    if (todayTp && (streaks['lastTpDate'] == null || 

      today.difference(DateTime.fromMillisecondsSinceEpoch(streaks['lastTpDate'])).inDays <= 1)) {

      if (streaks['lastTpDate'] == null || 

        today.difference(DateTime.fromMillisecondsSinceEpoch(streaks['lastTpDate'])).inDays == 1) {

        tpStreak++;

      }

      streaks['lastTpDate'] = today.millisecondsSinceEpoch;

    } else if (streaks['lastTpDate'] != null && 

      today.difference(DateTime.fromMillisecondsSinceEpoch(streaks['lastTpDate'])).inDays > 1) {

      tpStreak = 0;

    }

  }

  streaks['tpStreak'] = tpStreak;

  await prefs.setString(_streakKey, json.encode(streaks));

  return streaks;

}



// --- API 設定與多交易所倉位同步 ---

const _apiExchangeKey = 'anya_api_exchange';

const _apiKeyStorageKey = 'anya_api_key';

const _apiSecretStorageKey = 'anya_api_secret';

/// 支援的交易所列舉，value 為下拉顯示名稱

const Map<String, String> kSupportedExchanges = {

  'binance': 'Binance 合約',

  'bittap': 'BitTap (bittap.com)',

  'bybit': 'Bybit（即將支援）',

  'okx': 'OKX（即將支援）',

};

String _binanceSignature(String secret, String queryString) {

  final key = utf8.encode(secret);

  final bytes = utf8.encode(queryString);

  final hmacSha256 = Hmac(sha256, key);

  final digest = hmacSha256.convert(bytes);

  return digest.bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

}

/// 呼叫 Binance GET /fapi/v2/positionRisk，回傳 list 或 null（失敗時）

Future<List<dynamic>?> _fetchBinancePositionRisk(String apiKey, String apiSecret) async {

  try {

    const baseUrl = 'https://fapi.binance.com';

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final query = 'timestamp=$timestamp';

    final signature = _binanceSignature(apiSecret, query);

    final uri = Uri.parse('$baseUrl/fapi/v2/positionRisk?$query&signature=$signature');

    final res = await http.get(uri, headers: {'X-MBX-APIKEY': apiKey});

    if (res.statusCode != 200) return null;

    final list = json.decode(res.body) as List;

    return list;

  } catch (_) {

    return null;

  }

}

/// BitTap 簽名：GET 無參時 data = "&timestamp=xxx&nonce=xxx"，再 HMAC-SHA256(hex)
String _bittapSign(String secret, String signData) {

  final key = utf8.encode(secret);

  final bytes = utf8.encode(signData);

  final hmacSha256 = Hmac(sha256, key);

  final digest = hmacSha256.convert(bytes);

  return digest.bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

}

/// BitTap (bittap.com) 合約持倉 API，依 developers.bittap.com 鑑權認證
Future<List<dynamic>?> _fetchBittapPositions(String apiKey, String apiSecret) async {

  try {

    const baseUrl = 'https://api.bittap.com';

    final ts = DateTime.now().millisecondsSinceEpoch.toString();

    final nonce = '${DateTime.now().millisecondsSinceEpoch}${(1000 + (DateTime.now().microsecond % 900))}';

    final signData = '&timestamp=$ts&nonce=$nonce';

    final signature = _bittapSign(apiSecret, signData);

    final uri = Uri.parse('$baseUrl/api/v1/futures/position/list');

    final res = await http.get(uri, headers: {

      'X-BT-APIKEY': apiKey,

      'X-BT-SIGN': signature,

      'X-BT-TS': ts,

      'X-BT-NONCE': nonce,

      'Content-Type': 'application/json',

    });

    if (res.statusCode != 200) return null;

    final body = json.decode(res.body);

    List<dynamic> rawList = [];

    if (body is List) {

      rawList = body;

    } else if (body is Map && body['data'] is List) {

      rawList = body['data'] as List;

    } else if (body is Map && body['list'] is List) {

      rawList = body['list'] as List;

    } else if (body is Map && body['positions'] is List) {

      rawList = body['positions'] as List;

    }

    final out = <Map<String, dynamic>>[];

    for (final raw in rawList) {

      final m = raw is Map ? Map<String, dynamic>.from(raw as Map) : <String, dynamic>{};

      final symbol = (m['symbol'] ?? m['symbolName'] ?? m['symbolId'] ?? '').toString();

      if (symbol.isEmpty) continue;

      final entryPrice = toD(m['entryPrice'] ?? m['avgPrice'] ?? m['openPrice']);

      final markPrice = toD(m['markPrice'] ?? m['lastPrice'] ?? m['mark'] ?? m['markPrice']);

      if (entryPrice <= 0) continue;

      num amt = toD(m['positionAmt'] ?? m['size'] ?? m['position'] ?? m['quantity'] ?? m['positionSize']);

      final sideStr = (m['side'] ?? m['positionSide'] ?? '').toString().toLowerCase();

      if (amt == 0 && (sideStr == 'short' || sideStr == 'long')) amt = toD(m['size'] ?? m['position'] ?? m['quantity'] ?? m['positionSize']);

      if (sideStr == 'short' && amt > 0) amt = -amt;

      if (amt == 0) continue;

      final leverage = (m['leverage'] is num) ? (m['leverage'] as num).toInt() : int.tryParse(m['leverage']?.toString() ?? '') ?? 1;

      out.add({

        'symbol': symbol,

        'entryPrice': entryPrice,

        'markPrice': markPrice,

        'leverage': leverage < 1 ? 1 : leverage,

        'positionAmt': amt.toDouble(),

      });

    }

    return out;

  } catch (_) {

    return null;

  }

}

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

  Map<String, dynamic>? _levelData;

  Map<String, dynamic>? _streakData;

  String _bgMode = 'default';

  String? _bgCustomPath;

  String? _bgCustomImageBase64;

  Color _bgDynamicColor = const Color(0xFF00e5ff);

  final _secureStorage = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));



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

        for (final p in positions) {

          if (p is! Map) continue;

          if (p['side'] == null) p['side'] = 'long';

        }

      });

      await _persistPositions();

    }

    final bgMode = prefs.getString(_bgModeKey) ?? 'default';

    final bgCustomPath = prefs.getString(_bgCustomPathKey);

    final bgCustomBase64 = prefs.getString(_bgCustomImageBase64Key);

    final bgDynamicColorValue = prefs.getInt(_bgDynamicColorKey);

    final bgDynamicColor = bgDynamicColorValue != null ? Color(bgDynamicColorValue) : const Color(0xFF00e5ff);

    if (mounted) setState(() { _bgMode = bgMode; _bgCustomPath = bgCustomPath; _bgCustomImageBase64 = bgCustomBase64; _bgDynamicColor = bgDynamicColor; });

    _refreshLevelAndStreak();

    setState(() => isLoading = false);

    _timer = Timer.periodic(const Duration(seconds: 5), (t) => _refresh());

  }



  Future<void> _persistPositions() async {

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('anya_pro_v2026_final', json.encode(positions));

  }

  Future<void> _refreshLevelAndStreak() async {

    final level = await _getLevelData();

    final streak = await _calculateStreaks(positions);

    if (mounted) setState(() { _levelData = level; _streakData = streak; });

  }

  Future<String?> _getApiExchange() => _secureStorage.read(key: _apiExchangeKey);

  Future<String?> _getApiKey() => _secureStorage.read(key: _apiKeyStorageKey);

  Future<String?> _getApiSecret() => _secureStorage.read(key: _apiSecretStorageKey);

  Future<void> _setApiCredentials(String exchange, String key, String secret) async {

    await _secureStorage.write(key: _apiExchangeKey, value: exchange);

    await _secureStorage.write(key: _apiKeyStorageKey, value: key);

    await _secureStorage.write(key: _apiSecretStorageKey, value: secret);

  }

  /// 回傳 (錯誤訊息, 成功時加入的筆數)。無錯誤時 error 為 null。
  Future<(String?, int)> _syncPositionsFromApi() async {

    final exchange = await _getApiExchange();

    final apiKey = await _getApiKey();

    final apiSecret = await _getApiSecret();

    if (apiKey == null || apiSecret == null || apiKey.isEmpty || apiSecret.isEmpty) {

      return ('請先填寫並儲存 API Key 與 Secret', 0);

    }

    List<dynamic>? list;

    if (exchange == 'binance') {

      list = await _fetchBinancePositionRisk(apiKey, apiSecret);

    } else if (exchange == 'bittap') {

      list = await _fetchBittapPositions(apiKey, apiSecret);

    } else {

      return ('此交易所尚未支援同步，敬請期待', 0);

    }

    if (list == null) {

      if (exchange == 'bittap') return ('無法取得 BitTap 倉位（請檢查 API 權限、網路或端點路徑）', 0);

      return ('無法取得倉位（請檢查 API 權限與網路）', 0);

    }

    final watchingSymbols = positions.where((p) => p['status'].toString().contains('監控中')).map((p) => p['symbol'] as String).toSet();

    int added = 0;

    final now = DateTime.now();

    for (final raw in list) {

      final map = raw as Map;

      final positionAmt = toD(map['positionAmt']);

      if (positionAmt == 0) continue;

      final symbol = map['symbol'] as String? ?? '';

      if (symbol.isEmpty) continue;

      if (watchingSymbols.contains(symbol)) continue;

      final entryPrice = toD(map['entryPrice']);

      final markPrice = toD(map['markPrice']);

      final leverage = (map['leverage'] is num) ? (map['leverage'] as num).toInt() : int.tryParse(map['leverage']?.toString() ?? '') ?? 1;

      final notional = (positionAmt.abs() * entryPrice);

      final uValue = notional / leverage;

      final side = positionAmt > 0 ? 'long' : 'short';

      positions.add({

        'symbol': symbol,

        'leverage': leverage,

        'uValue': uValue,

        'entry': entryPrice,

        'current': markPrice,

        'entryTime': now.millisecondsSinceEpoch,

        'tp1': 0.0,

        'tp2': 0.0,

        'tp3': 0.0,

        'sl': 0.0,

        'status': '監控中',

        'side': side,

      });

      watchingSymbols.add(symbol);

      added++;

    }

    await _persistPositions();

    if (added == 0 && list.isNotEmpty) return ('目前無新倉位可加入（可能已存在同交易對監控中）', 0);

    if (added == 0) return ('目前無持倉', 0);

    return (null, added);

  }

  void _showApiSettings() async {

    final savedExchange = await _getApiExchange();

    final keyController = TextEditingController(text: await _getApiKey() ?? '');

    final secretController = TextEditingController(text: await _getApiSecret() ?? '');

    String selectedExchange = savedExchange ?? 'binance';

    if (!mounted) return;

    showModalBottomSheet(

      context: context,

      isScrollControlled: true,

      backgroundColor: const Color(0xFF1A1A1A),

      builder: (ctx) => StatefulBuilder(

        builder: (context, setModalState) => Padding(

          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),

          child: SingleChildScrollView(

            child: Column(

              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.stretch,

              children: [

                const Text('API 設定（多交易所）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFFC0CB))),

                const SizedBox(height: 8),

                const Text('用於自動讀取當前持倉並建立監控任務。請使用僅具「讀取」權限的 API，勿勾選提現與交易。', style: TextStyle(fontSize: 11, color: Colors.grey)),

                const SizedBox(height: 16),

                const Text('交易所', style: TextStyle(fontSize: 12, color: Colors.grey)),

                const SizedBox(height: 6),

                DropdownButtonFormField<String>(

                  value: kSupportedExchanges.containsKey(selectedExchange) ? selectedExchange : 'binance',

                  decoration: const InputDecoration(border: OutlineInputBorder()),

                  dropdownColor: const Color(0xFF2A2A2A),

                  items: kSupportedExchanges.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),

                  onChanged: (v) { if (v != null) { selectedExchange = v; setModalState(() {}); } },

                ),

                const SizedBox(height: 16),

                TextField(

                  controller: keyController,

                  decoration: const InputDecoration(labelText: 'API Key', border: OutlineInputBorder()),

                  obscureText: false,

                ),

                const SizedBox(height: 12),

                TextField(

                  controller: secretController,

                  decoration: const InputDecoration(labelText: 'API Secret', border: OutlineInputBorder()),

                  obscureText: true,

                ),

                const SizedBox(height: 20),

                Row(

                  children: [

                    Expanded(

                      child: OutlinedButton.icon(

                        icon: const Icon(Icons.save_outlined),

                        label: const Text('儲存'),

                        onPressed: () async {

                          await _setApiCredentials(selectedExchange, keyController.text.trim(), secretController.text);

                          if (!ctx.mounted) return;

                          Navigator.pop(ctx);

                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API 已儲存'), behavior: SnackBarBehavior.floating));

                        },

                      ),

                    ),

                    const SizedBox(width: 12),

                    Expanded(

                      child: FilledButton.icon(

                        icon: const Icon(Icons.sync),

                        label: const Text('同步倉位'),

                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFC0CB)),

                        onPressed: () async {

                          await _setApiCredentials(selectedExchange, keyController.text.trim(), secretController.text);

                          Navigator.pop(ctx);

                        final messenger = ScaffoldMessenger.of(context);

                        messenger.showSnackBar(const SnackBar(content: Text('正在同步倉位…'), behavior: SnackBarBehavior.floating));

                        final (msg, added) = await _syncPositionsFromApi();

                        if (!mounted) return;

                        setState(() {});

                        messenger.showSnackBar(SnackBar(

                          content: Text(msg ?? '已加入 $added 筆監控任務'),

                          backgroundColor: msg != null ? Colors.orange : Colors.green,

                          behavior: SnackBarBehavior.floating,

                        ));

                      },

                    ),

                  ),

                ],

              ),

            ],

          ),

        ),

      ),

      ),

    );

  }

  void _showBackgroundSettings() async {

    final prefs = await SharedPreferences.getInstance();

    final options = [

      {'id': 'default', 'label': '預設漸層', 'desc': '深色帶淡粉紫'},

      {'id': 'gradient_soft', 'label': '柔和漸層', 'desc': '深藍灰'},

      {'id': 'gradient_midnight', 'label': '午夜藍', 'desc': '藍紫色系'},

      {'id': 'gradient_warm', 'label': '暖色漸層', 'desc': '深褐紅'},

      {'id': 'dynamic', 'label': '動態背景', 'desc': '光球・線條・粒子'},

      {'id': 'custom', 'label': '自訂圖片', 'desc': kIsWeb ? '從本機選擇圖片（網頁版）' : '從相簿選擇'},

    ];

    if (!mounted) return;

    showModalBottomSheet(

      context: context,

      backgroundColor: const Color(0xFF1A1A1A),

      builder: (ctx) => SafeArea(

        child: Padding(

          padding: const EdgeInsets.all(16),

          child: Column(

            mainAxisSize: MainAxisSize.min,

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              const Text('背景設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFFC0CB))),

              const SizedBox(height: 12),

              ...options.map((o) {

                final id = o['id'] as String;

                final selected = _bgMode == id || (id == 'custom' && _bgMode == 'custom');

                return ListTile(

                  leading: Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? const Color(0xFFFFC0CB) : Colors.grey, size: 22),

                  title: Text(o['label'] as String, style: TextStyle(color: Colors.white, fontWeight: selected ? FontWeight.bold : null)),

                  subtitle: Text(o['desc'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),

                  onTap: () async {

                    if (id == 'custom') {

                      final x = await ImagePicker().pickImage(source: ImageSource.gallery);

                      if (x == null || !mounted) return;

                      if (kIsWeb) {

                        final bytes = await x.readAsBytes();

                        final base64 = base64Encode(bytes);

                        if (base64.length > _kMaxBgBase64Length && mounted) {

                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('圖片過大，請選擇較小的圖片（建議 1MB 以內）'), behavior: SnackBarBehavior.floating));

                          return;

                        }

                        await prefs.setString(_bgModeKey, 'custom');

                        await prefs.setString(_bgCustomImageBase64Key, base64);

                        if (mounted) setState(() { _bgMode = 'custom'; _bgCustomPath = null; _bgCustomImageBase64 = base64; });

                      } else {

                        final path = await savePickedImageToAppDir(x);

                        if (path == null || !mounted) {

                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('無法儲存圖片'), behavior: SnackBarBehavior.floating));

                          return;

                        }

                        await prefs.setString(_bgModeKey, 'custom');

                        await prefs.setString(_bgCustomPathKey, path);

                        if (mounted) setState(() { _bgMode = 'custom'; _bgCustomPath = path; _bgCustomImageBase64 = null; });

                      }

                    } else {

                      await prefs.setString(_bgModeKey, id);

                      if (_bgMode == 'custom') {

                        await prefs.remove(_bgCustomPathKey);

                        await prefs.remove(_bgCustomImageBase64Key);

                      }

                      if (mounted) setState(() { _bgMode = id; _bgCustomPath = null; _bgCustomImageBase64 = null; });

                    }

                    if (ctx.mounted) Navigator.pop(ctx);

                  },

                );

              }),

              const Divider(height: 24, color: Colors.grey),

              const Text('動態背景主色', style: TextStyle(fontSize: 12, color: Colors.grey)),

              const SizedBox(height: 8),

              Wrap(

                spacing: 10,

                runSpacing: 8,

                children: [

                  _buildDynamicColorChip(prefs, ctx, const Color(0xFF00e5ff), '青藍'),

                  _buildDynamicColorChip(prefs, ctx, const Color(0xFF00ffea), '電青'),

                  _buildDynamicColorChip(prefs, ctx, const Color(0xFF0088cc), '深藍'),

                  _buildDynamicColorChip(prefs, ctx, const Color(0xFF7b68ee), '紫'),

                  _buildDynamicColorChip(prefs, ctx, const Color(0xFF00ff88), '綠'),

                  _buildDynamicColorChip(prefs, ctx, const Color(0xFFFFC0CB), '粉'),

                  _buildDynamicColorChip(prefs, ctx, const Color(0xFFff6b6b), '紅'),

                  _buildDynamicColorChip(prefs, ctx, const Color(0xFFffd93d), '金'),

                ],

              ),

            ],

          ),

        ),

      ),

    );

  }

  Widget _buildDynamicColorChip(SharedPreferences prefs, BuildContext sheetContext, Color color, String label) {

    final selected = _bgDynamicColor.value == color.value;

    return Tooltip(

      message: label,

      child: GestureDetector(

      onTap: () async {

        await prefs.setInt(_bgDynamicColorKey, color.value);

        if (mounted) setState(() { _bgDynamicColor = color; });

      },

      child: Container(

        width: 36,

        height: 36,

        decoration: BoxDecoration(

          color: color,

          shape: BoxShape.circle,

          border: Border.all(color: selected ? Colors.white : color.withOpacity(0.6), width: selected ? 3 : 1),

          boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: selected ? 8 : 4)],

        ),

        child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,

      ),

    ),

    );

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

            final isLong = _isLong(positions[i]);

            if (isLong) {

              if (tp3 > 0 && cur >= tp3) positions[i]['hitTp'] = 'TP3';

              else if (tp2 > 0 && cur >= tp2) positions[i]['hitTp'] = 'TP2';

              else if (tp1 > 0 && cur >= tp1) positions[i]['hitTp'] = 'TP1';

            } else {

              if (tp3 > 0 && cur <= tp3) positions[i]['hitTp'] = 'TP3';

              else if (tp2 > 0 && cur <= tp2) positions[i]['hitTp'] = 'TP2';

              else if (tp1 > 0 && cur <= tp1) positions[i]['hitTp'] = 'TP1';

            }

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

    _refreshLevelAndStreak();

  }



  void _checkLogic(int i) {

    final pos = positions[i];

    double cur = toD(pos['current']);

    double sl = toD(pos['sl']);

    double tp1 = toD(pos['tp1']);

    double tp2 = toD(pos['tp2']);

    double tp3 = toD(pos['tp3']);

    double targetTp = tp3 > 0 ? tp3 : (tp2 > 0 ? tp2 : tp1);

    final isLong = _isLong(pos);

    if (isLong) {

      if (cur <= sl) pos['status'] = '止損出局 ⚡️';

      else if (targetTp > 0 && cur >= targetTp) pos['status'] = '止盈達標 ⭐️';

    } else {

      if (cur >= sl) pos['status'] = '止損出局 ⚡️';

      else if (targetTp > 0 && cur <= targetTp) pos['status'] = '止盈達標 ⭐️';

    }

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

  // --- 等級系統：取得/儲存等級資料 ---

  Future<Map<String, dynamic>> _getLevelData() async {

    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_levelKey);

    if (raw == null) return {'exp': 0, 'level': 1};

    try {

      return json.decode(raw);

    } catch (_) {

      return {'exp': 0, 'level': 1};

    }

  }

  Future<void> _addExp(int exp, {bool showNotification = true}) async {

    if (exp <= 0) return;

    final data = await _getLevelData();

    final oldExp = data['exp'] ?? 0;

    final oldLevel = _levelFromExp(oldExp);

    final newExp = oldExp + exp;

    final newLevel = _levelFromExp(newExp);

    data['exp'] = newExp;

    data['level'] = newLevel;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_levelKey, json.encode(data));

    if (!mounted) return;

    if (newLevel > oldLevel && showNotification) {

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(

          content: Text("🎉 升級！等級 $oldLevel → $newLevel (+$exp EXP)"),

          backgroundColor: const Color(0xFF9C27B0),

          behavior: SnackBarBehavior.floating,

          duration: const Duration(seconds: 3),

        ),

      );

    } else if (showNotification && exp > 0) {

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(

          content: Text("+$exp EXP (等級 $newLevel)"),

          backgroundColor: const Color(0xFF673AB7),

          behavior: SnackBarBehavior.floating,

          duration: const Duration(seconds: 2),

        ),

      );

    }

  }

  // --- 每日任務：取得/重置/完成檢查 ---

  Future<Map<String, dynamic>> _getDailyTasks() async {

    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_dailyTasksKey);

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

    Map<String, dynamic> tasks = raw != null ? json.decode(raw) : {};

    if (tasks['date'] != today) {

      tasks = {'date': today, 'completed': {}};

      await prefs.setString(_dailyTasksKey, json.encode(tasks));

    }

    return tasks;

  }

  Future<void> _checkDailyTask(String taskId) async {

    final tasks = await _getDailyTasks();

    final completed = Set<String>.from((tasks['completed'] as Map? ?? {}).keys.cast<String>());

    if (completed.contains(taskId)) return;

    final task = _dailyTasks.firstWhere((t) => t['id'] == taskId, orElse: () => {});

    if (task.isEmpty) return;

    completed.add(taskId);

    tasks['completed'] = Map.fromEntries(completed.map((id) => MapEntry(id, true)));

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_dailyTasksKey, json.encode(tasks));

    await _addExp((task['exp'] as num? ?? 0).toInt(), showNotification: true);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(

      SnackBar(

        content: Text("✅ 每日任務完成：${task['emoji']} ${task['title']} (+${task['exp']} EXP)"),

        backgroundColor: const Color(0xFF4CAF50),

        behavior: SnackBarBehavior.floating,

      ),

    );

  }



  Future<void> _onHitTp() async {

    final stats = await _getStats();

    stats['totalTp'] = (stats['totalTp'] ?? 0) + 1;

    await _saveStats(stats);

    // 計算經驗值（從最後一筆止盈的 position）

    final lastTp = positions.where((p) => p['status']?.toString().contains('止盈') == true).toList();

    if (lastTp.isNotEmpty) {

      final exp = _calculateExp(lastTp.last);

      await _addExp(exp, showNotification: false);

    }

    // 檢查每日任務

    await _checkDailyTask('tp_today');

    await _checkDailyTask('settle_task');

                // 檢查連續紀錄和成就

                final streaks = await _calculateStreaks(this.positions);

    final unlocked = await _getUnlocked();

    if (!unlocked.contains('first_tp')) await _unlock('first_tp');

    if (stats['totalTp']! >= 5 && !unlocked.contains('tp_5')) await _unlock('tp_5');

    if (stats['totalTp']! >= 10 && !unlocked.contains('tp_10')) await _unlock('tp_10');

    final tpStreak = streaks['tpStreak'] ?? 0;

    if (tpStreak >= 3 && !unlocked.contains('tp_streak_3')) await _unlock('tp_streak_3');

    if (tpStreak >= 5 && !unlocked.contains('tp_streak_5')) await _unlock('tp_streak_5');

    // 檢查連續盈利天數成就

    final profitDays = streaks['profitDays'] ?? 0;

    if (profitDays >= 3 && !unlocked.contains('profit_streak_3')) await _unlock('profit_streak_3');

    if (profitDays >= 7 && !unlocked.contains('profit_streak_7')) await _unlock('profit_streak_7');

    // 檢查每日任務全部完成成就

    final tasks = await _getDailyTasks();

    final completed = Set<String>.from((tasks['completed'] as Map? ?? {}).keys.cast<String>());

    if (completed.length == _dailyTasks.length && !unlocked.contains('daily_all')) await _unlock('daily_all');

    // 檢查等級成就

    final levelData = await _getLevelData();

    final level = levelData['level'] ?? 1;

    if (level >= 5 && !unlocked.contains('level_5')) await _unlock('level_5');

    if (level >= 10 && !unlocked.contains('level_10')) await _unlock('level_10');

    if (level >= 20 && !unlocked.contains('level_20')) await _unlock('level_20');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(

      const SnackBar(content: Text("やった！Mission complete ⭐️"), backgroundColor: Color(0xFF4CAF50), behavior: SnackBarBehavior.floating),

    );

  }



  Future<void> _onHitSl() async {

    final stats = await _getStats();

    stats['totalSl'] = (stats['totalSl'] ?? 0) + 1;

    await _saveStats(stats);

    // 計算經驗值

    final lastSl = positions.where((p) => p['status']?.toString().contains('止損') == true).toList();

    if (lastSl.isNotEmpty) {

      final exp = _calculateExp(lastSl.last);

      await _addExp(exp, showNotification: false);

    }

    // 檢查每日任務

    await _checkDailyTask('settle_task');

    // 檢查連續紀錄（止損會中斷盈利連續）

    await _calculateStreaks(positions);

    final unlocked = await _getUnlocked();

    if (!unlocked.contains('first_sl')) await _unlock('first_sl');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(

      const SnackBar(content: Text("ちー…下次再來 ⚡️"), backgroundColor: Color(0xFF757575), behavior: SnackBarBehavior.floating),

    );

  }



  void _showLevelAndAchievements() async {

    final levelData = _levelData ?? await _getLevelData();

    final streakData = _streakData ?? await _calculateStreaks(positions);

    final unlocked = await _getUnlocked();

    if (!mounted) return;

    final exp = levelData['exp'] ?? 0;

    final level = levelData['level'] ?? 1;

    final nextExp = _expForLevel(level + 1);

    final currentLevelExp = _expForLevel(level);

    final progress = (nextExp - currentLevelExp) > 0

        ? ((exp - currentLevelExp) / (nextExp - currentLevelExp)).clamp(0.0, 1.0)

        : 1.0;

    final profitDays = streakData['profitDays'] ?? 0;

    final tpStreak = streakData['tpStreak'] ?? 0;

    showModalBottomSheet(

      context: context,

      backgroundColor: const Color(0xFF1A1A1A),

      isScrollControlled: true,

      builder: (ctx) => DraggableScrollableSheet(

        initialChildSize: 0.6,

        minChildSize: 0.3,

        maxChildSize: 0.9,

        expand: false,

        builder: (context, scrollController) => SingleChildScrollView(

          controller: scrollController,

          padding: const EdgeInsets.all(20),

          child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            mainAxisSize: MainAxisSize.min,

            children: [

              Row(

                mainAxisAlignment: MainAxisAlignment.spaceBetween,

                children: [

                  const Text("🏆 等級與經驗", style: TextStyle(color: Color(0xFFFFC0CB), fontSize: 20, fontWeight: FontWeight.bold)),

                  Container(

                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

                    decoration: BoxDecoration(

                      gradient: const LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFF673AB7)]),

                      borderRadius: BorderRadius.circular(20),

                    ),

                    child: Text("Lv.$level", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),

                  ),

                ],

              ),

              const SizedBox(height: 8),

              Text("$exp / $nextExp EXP", style: const TextStyle(fontSize: 12, color: Colors.grey)),

              const SizedBox(height: 6),

              ClipRRect(

                borderRadius: BorderRadius.circular(8),

                child: LinearProgressIndicator(

                  value: progress,

                  minHeight: 8,

                  backgroundColor: Colors.grey.shade800,

                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFC0CB)),

                ),

              ),

              const SizedBox(height: 16),

              Row(

                mainAxisAlignment: MainAxisAlignment.spaceAround,

                children: [

                  Column(children: [

                    const Text("🔥", style: TextStyle(fontSize: 24)),

                    const SizedBox(height: 4),

                    Text("連續盈利", style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),

                    Text("$profitDays 天", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: profitDays >= 3 ? const Color(0xFFFF5722) : Colors.grey)),

                  ]),

                  Column(children: [

                    const Text("⚡", style: TextStyle(fontSize: 24)),

                    const SizedBox(height: 4),

                    Text("連續止盈", style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),

                    Text("$tpStreak 次", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: tpStreak >= 3 ? const Color(0xFF4CAF50) : Colors.grey)),

                  ]),

                ],

              ),

              const SizedBox(height: 24),

              const Text("已獲得成就", style: TextStyle(color: Color(0xFFFFC0CB), fontSize: 16, fontWeight: FontWeight.bold)),

              const SizedBox(height: 8),

              ..._achievements.map((a) {

                final id = a['id'] as String;

                final isUnlocked = unlocked.contains(id);

                return ListTile(

                  leading: _buildAchievementBadge(id: id, isUnlocked: isUnlocked),

                  title: Text(a['title'] as String, style: TextStyle(color: isUnlocked ? Colors.white : Colors.grey, fontSize: 14)),

                  subtitle: Text(isUnlocked ? a['desc'] as String : '尚未解鎖', style: const TextStyle(fontSize: 11, color: Colors.grey)),

                );

              }),

            ],

          ),

        ),

      ),

    );

  }

  void _showDailyTasksPopup() async {

    final tasks = await _getDailyTasks();

    final completed = Set<String>.from((tasks['completed'] as Map? ?? {}).keys.cast<String>());

    final allCompleted = completed.length == _dailyTasks.length;

    if (!mounted) return;

    showModalBottomSheet(

      context: context,

      backgroundColor: const Color(0xFF1A1A1A),

      builder: (ctx) => Padding(

        padding: const EdgeInsets.all(20),

        child: Column(

          mainAxisSize: MainAxisSize.min,

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Row(

              mainAxisAlignment: MainAxisAlignment.spaceBetween,

              children: [

                const Text("📋 每日任務", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFFC0CB))),

                if (allCompleted)

                  Container(

                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

                    decoration: BoxDecoration(

                      color: const Color(0xFF4CAF50),

                      borderRadius: BorderRadius.circular(12),

                    ),

                    child: const Text("全部完成！", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),

                  ),

              ],

            ),

            const SizedBox(height: 16),

            ..._dailyTasks.map((task) {

              final isDone = completed.contains(task['id']);

              return Padding(

                padding: const EdgeInsets.only(bottom: 12),

                child: Row(

                  children: [

                    Container(

                      width: 28,

                      height: 28,

                      decoration: BoxDecoration(

                        color: isDone ? const Color(0xFF4CAF50) : Colors.grey.shade700,

                        shape: BoxShape.circle,

                      ),

                      child: Center(

                        child: isDone ? const Icon(Icons.check, size: 18, color: Colors.white) : Text(task['emoji'] as String, style: const TextStyle(fontSize: 14)),

                      ),

                    ),

                    const SizedBox(width: 12),

                    Expanded(

                      child: Column(

                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [

                          Text(task['title'] as String, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isDone ? Colors.grey.shade400 : Colors.white, decoration: isDone ? TextDecoration.lineThrough : null)),

                          Text(task['desc'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),

                        ],

                      ),

                    ),

                    Text("+${task['exp']} EXP", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDone ? Colors.grey.shade500 : const Color(0xFF9C27B0))),

                  ],

                ),

              );

            }),

          ],

        ),

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

                    'side': pos['side'], 'status': '手動出場', 'settledAt': DateTime.now().millisecondsSinceEpoch, 'exitRatio': 1.0, 'exitRatioDisplay': ratio,

                    'candles': c.isNotEmpty ? _serializeCandles(c) : null,

                  };

                  setState(() {

                    positions.add(closedPortion);

                    pos['uValue'] = remainingU;

                    pos['current'] = price;

                  });

                }

                await _persistPositions();

                // 計算經驗值和檢查每日任務

                final settledPos = ratio >= 1.0 ? pos : positions.lastWhere((p) => p['status']?.toString().contains('手動出場') == true && p['settledAt'] != null, orElse: () => pos);

                final exp = _calculateExp(settledPos);

                await _addExp(exp, showNotification: false);

                await _checkDailyTask('settle_task');

                // 檢查連續紀錄和成就

                final streaks = await _calculateStreaks(this.positions);

                final pnl = _pnlAmount(settledPos);

                if (pnl > 0) {

                  final unlocked = await _getUnlocked();

                  final profitDays = streaks['profitDays'] ?? 0;

                  if (profitDays >= 3 && !unlocked.contains('profit_streak_3')) await _unlock('profit_streak_3');

                  if (profitDays >= 7 && !unlocked.contains('profit_streak_7')) await _unlock('profit_streak_7');

                }

                // 檢查每日任務全部完成成就

                final tasks = await _getDailyTasks();

                final completed = Set<String>.from((tasks['completed'] as Map? ?? {}).keys.cast<String>());

                if (completed.length == _dailyTasks.length) {

                  final unlocked = await _getUnlocked();

                  if (!unlocked.contains('daily_all')) await _unlock('daily_all');

                }

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

  /// 依目前設定繪製背景（漸層或自訂圖）
  Widget _buildBackground() {

    if (_bgMode == 'custom') {

      Widget imageWidget;

      if (kIsWeb && _bgCustomImageBase64 != null && _bgCustomImageBase64!.isNotEmpty) {

        try {

          imageWidget = Image.memory(

            base64Decode(_bgCustomImageBase64!),

            fit: BoxFit.cover,

          );

        } catch (_) {

          imageWidget = Container(color: const Color(0xFF0D0D0D));

        }

      } else if (_bgCustomPath != null && _bgCustomPath!.isNotEmpty) {

        imageWidget = buildBackgroundImageFromPath(_bgCustomPath!);

      } else {

        imageWidget = Container(color: const Color(0xFF0D0D0D));

      }

      return Stack(

        fit: StackFit.expand,

        children: [

          imageWidget,

          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.5), Colors.black.withOpacity(0.75)]))),

        ],

      );

    }

    if (_bgMode == 'dynamic') {

      return Stack(

        fit: StackFit.expand,

        children: [

          DynamicBackground(primaryColor: _bgDynamicColor, meteorCount: positions.length),

          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.25), Colors.black.withOpacity(0.5)]))),

        ],

      );

    }

    List<Color> colors;

    switch (_bgMode) {

      case 'gradient_soft':

        colors = [const Color(0xFF1a1a2e), const Color(0xFF16213e), const Color(0xFF0D0D0D)];

        break;

      case 'gradient_midnight':

        colors = [const Color(0xFF0f0c29), const Color(0xFF302b63), const Color(0xFF24243e), const Color(0xFF0D0D0D)];

        break;

      case 'gradient_warm':

        colors = [const Color(0xFF1c0a0a), const Color(0xFF2d1b1b), const Color(0xFF0D0D0D)];

        break;

      default:

        colors = [const Color(0xFF0D0D0D), const Color(0xFF2d1a28), const Color(0xFF251530), const Color(0xFF1a0d20), const Color(0xFF0D0D0D)];

    }

    return Container(

      decoration: BoxDecoration(

        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),

      ),

    );

  }

  @override

  Widget build(BuildContext context) {

    return DefaultTabController(

      length: 2,

      child: Scaffold(

        backgroundColor: Colors.transparent,

        appBar: AppBar(

          title: const Text('任務看板'),

          actions: [

            InkWell(

              onTap: _showLevelAndAchievements,

              child: Padding(

                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),

                child: Row(

                  mainAxisSize: MainAxisSize.min,

                  children: [

                    const Icon(Icons.emoji_events_outlined, color: Color(0xFFFFC0CB), size: 22),

                    const SizedBox(width: 4),

                    Text(

                      'Lv.${_levelData?['level'] ?? 1}',

                      style: const TextStyle(fontSize: 12, color: Colors.white70),

                    ),

                  ],

                ),

              ),

            ),

            IconButton(

              icon: const Icon(Icons.checklist_rounded),

              tooltip: '每日任務',

              onPressed: _showDailyTasksPopup,

            ),

            IconButton(

              icon: const Icon(Icons.wallpaper),

              tooltip: '背景設定',

              onPressed: _showBackgroundSettings,

            ),

            IconButton(

              icon: const Icon(Icons.key),

              tooltip: 'API 設定 / 同步倉位',

              onPressed: _showApiSettings,

            ),

          ],

          bottom: const TabBar(

            tabs: [

              Tab(text: '監控中'),

              Tab(text: '已結算'),

            ],

          ),

        ),

        body: Stack(

          fit: StackFit.expand,

          children: [

            _buildBackground(),

            isLoading

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

          ],

        ),

        floatingActionButton: FloatingActionButton.extended(

          onPressed: _showAdd,

          label: const Text("新增任務"),

          icon: const Icon(Icons.add),

          backgroundColor: const Color(0xFFFFC0CB),

        ),

        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,

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

            title: Text("${pos['symbol']} (${pos['leverage']}x) ${_sideLabel(pos)}"),

            subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),

            trailing: PopupMenuButton<String>(

              icon: const Icon(Icons.more_vert),

              tooltip: '操作',

              padding: EdgeInsets.zero,

              onSelected: (value) {

                if (value == 'exit') _showManualExit(pos);

                else if (value == 'edit') _showEdit(pos);

                else if (value == 'delete') { setState(() => positions.remove(pos)); _persistPositions(); }

              },

              itemBuilder: (ctx) {

                final items = <PopupMenuItem<String>>[

                  const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined, size: 20), title: Text('編輯', style: TextStyle(fontSize: 14)))),

                  const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, size: 20), title: Text('刪除', style: TextStyle(fontSize: 14)))),

                ];

                if (!isSettled) items.insert(0, const PopupMenuItem(value: 'exit', child: ListTile(leading: Icon(Icons.exit_to_app, size: 20), title: Text('手動出場', style: TextStyle(fontSize: 14)))));

                return items;

              },

            ),

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

    final priceDiff = _isLong(Map<String, dynamic>.from(p)) ? (cur - ent) : (ent - cur);

    return ((priceDiff / ent) * 100 * lev * ratio).toStringAsFixed(2);

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

    bool isLong = true;

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

              const SizedBox(height: 12),

              const Text("方向", style: TextStyle(fontSize: 12, color: Colors.grey)),

              const SizedBox(height: 6),

              Row(children: [

                ChoiceChip(

                  label: const Text("做多"),

                  selected: isLong,

                  onSelected: (_) { isLong = true; setModalState(() {}); },

                  selectedColor: const Color(0xFF4CAF50).withOpacity(0.6),

                ),

                const SizedBox(width: 12),

                ChoiceChip(

                  label: const Text("做空"),

                  selected: !isLong,

                  onSelected: (_) { isLong = false; setModalState(() {}); },

                  selectedColor: const Color(0xFFFF5722).withOpacity(0.6),

                ),

              ]),

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

                    'sl': toD(cs['sl']!.text), 'status': '監控中',

                    'side': isLong ? 'long' : 'short'

                  }));

                  Navigator.pop(ctx);

                  // 檢查每日任務

                  await _checkDailyTask('add_task');

                  final unlocked = await _getUnlocked();

                  if (!unlocked.contains('first_task')) await _unlock('first_task');

                  final watching = positions.where((p) => p['status'].toString().contains('監控中')).length;

                  if (watching >= 3 && !unlocked.contains('tasks_3')) await _unlock('tasks_3');

                  // 檢查記錄達人任務（今日記錄 3 筆以上）

                  final today = DateTime.now();

                  final todayCount = positions.where((p) {

                    final et = p['entryTime'];

                    if (et == null) return false;

                    final d = DateTime.fromMillisecondsSinceEpoch(et is num ? et.toInt() : int.parse(et.toString()));

                    return d.year == today.year && d.month == today.month && d.day == today.day;

                  }).length;

                  if (todayCount >= 3) await _checkDailyTask('record_3');

                  // 檢查每日任務全部完成成就

                  final tasks = await _getDailyTasks();

                  final completed = Set<String>.from((tasks['completed'] as Map? ?? {}).keys.cast<String>());

                  if (completed.length == _dailyTasks.length) {

                    final unlocked = await _getUnlocked();

                    if (!unlocked.contains('daily_all')) await _unlock('daily_all');

                  }

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

                    'side': pos['side'] ?? 'long',

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