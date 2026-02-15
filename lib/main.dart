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

/// 網頁版因 CORS 無法直接請求交易所 API，需透過代理轉發。
/// 預設使用 api.cors.lol，易因限流或故障導致 K 線／OI 載入失敗；在設定中填寫自訂 Proxy（如 Cloudflare Worker）後會改走 Proxy，較穩定。
String _webProxyUrl(String url) => kIsWeb ? 'https://api.cors.lol/?url=${Uri.encodeComponent(url)}' : url;

/// 網頁版認證 API 需透過自訂代理（可轉發 Header），proxyUrl 為 Cloudflare Worker 等
Future<http.Response> _webFetchWithAuth(String url, Map<String, String> headers, {String? proxyUrl}) async {
  if (kIsWeb && proxyUrl != null && proxyUrl.trim().isNotEmpty) {
    final proxy = proxyUrl.trim().replaceAll(RegExp(r'/$'), '');
    final res = await http.post(
      Uri.parse(proxy),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'url': url, 'headers': headers}),
    );
    if (res.statusCode == 200) return res;
    return http.Response(res.body, res.statusCode);
  }
  return http.get(Uri.parse(url), headers: headers);
}



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

  if (p['realizedPnl'] != null) return toD(p['realizedPnl']);

  final u = toD(p['uValue']);

  final ent = toD(p['entry']);

  final cur = toD(p['current']);

  final lev = (p['leverage'] is num) ? (p['leverage'] as num).toInt() : 1;

  if (ent == 0) return 0;

  final priceDiff = _isLong(p) ? (cur - ent) : (ent - cur);

  final base = u * priceDiff / ent * lev;

  final ratio = toD(p['exitRatio']);

  final grossPnl = ratio > 0 ? base * ratio : base;

  // 扣除手續費：進場 + 出場（依出場比例）
  // 手續費率：優先使用倉位中的 feeRate，否則使用緩存的手續費率（使用者設定或預設值）
  // 注意：這裡無法直接讀取 SharedPreferences（因為是同步函數），所以使用全局緩存值
  final feeRate = p['feeRate'] != null ? toD(p['feeRate']) : _cachedTradingFeeRate;
  final entryFee = u * feeRate; // 進場手續費
  final exitRatio = ratio > 0 ? ratio : 1.0; // 出場比例，未結算時視為 100%
  final exitFee = u * feeRate * exitRatio; // 出場手續費（依出場比例）
  final totalFee = entryFee + exitFee;

  return grossPnl - totalFee;

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

    // 若為手動出場，依盈虧正負顯示止盈/止損的反饋
    if (pos != null) {
      try {
        final pnl = _pnlAmount(pos is Map<String, dynamic> ? pos : Map<String, dynamic>.from(pos));
        if (pnl > 0) {
          return 'やった！Mission complete ⭐️'; // 止盈反饋
        } else if (pnl < 0) {
          return 'ちー…下次再來 ⚡️'; // 止損反饋
        }
      } catch (_) {
        // 如果計算盈虧失敗，繼續使用原本的顯示邏輯
      }
    }

    final ratio = pos != null ? (toD(pos['exitRatioDisplay']) > 0 ? toD(pos['exitRatioDisplay']) : toD(pos['exitRatio'])) : 0;

    if (ratio > 0 && ratio < 1) return '手動出場 ${(ratio * 100).toInt()}%';

    return '手動出場';

  }

  if (status.contains('完全平倉')) return '完全平倉';

  if (status.contains('部分平倉')) {

    final ratio = pos != null ? (toD(pos['exitRatioDisplay']) > 0 ? toD(pos['exitRatioDisplay']) : toD(pos['exitRatio'])) : 0;

    if (ratio > 0 && ratio < 1) return '部分平倉 ${(ratio * 100).toInt()}%';

    return '部分平倉';

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

  } else if (status.contains('手動出場') || status.contains('完全平倉') || status.contains('部分平倉')) {

    exp += 30; // 手動/完全/部分平倉基礎經驗

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

    p['status']?.toString().contains('手動出場') == true || p['status']?.toString().contains('完全平倉') == true || p['status']?.toString().contains('部分平倉') == true).toList();

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

const _apiProxyUrlKey = 'anya_api_proxy_url';
const _tradingFeeRateKey = 'anya_trading_fee_rate';

/// 預設手續費率：0.055% (0.00055)，買賣皆為此費率
const double _defaultTradingFeeRate = 0.00055;

/// 緩存的手續費率（用於同步讀取，避免 _pnlAmount 需要異步）
double _cachedTradingFeeRate = _defaultTradingFeeRate;

/// 支援的交易所列舉，value 為下拉顯示名稱

const Map<String, String> kSupportedExchanges = {

  'binance': 'Binance 合約',

  'bingx': 'BingX 合約',

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
Future<List<dynamic>?> _fetchBinancePositionRisk(String apiKey, String apiSecret, {String? proxyUrl}) async {

  try {

    const baseUrl = 'https://fapi.binance.com';

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final query = 'timestamp=$timestamp';

    final signature = _binanceSignature(apiSecret, query);

    final url = '$baseUrl/fapi/v2/positionRisk?$query&signature=$signature';

    final res = kIsWeb && proxyUrl != null && proxyUrl.isNotEmpty

        ? await _webFetchWithAuth(url, {'X-MBX-APIKEY': apiKey}, proxyUrl: proxyUrl)

        : await http.get(Uri.parse(kIsWeb ? _webProxyUrl(url) : url), headers: {'X-MBX-APIKEY': apiKey});

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
Future<List<dynamic>?> _fetchBittapPositions(String apiKey, String apiSecret, {String? proxyUrl}) async {

  try {

    const baseUrl = 'https://api.bittap.com';

    final ts = DateTime.now().millisecondsSinceEpoch.toString();

    final nonce = '${DateTime.now().millisecondsSinceEpoch}${(1000 + (DateTime.now().microsecond % 900))}';

    final signData = '&timestamp=$ts&nonce=$nonce';

    final signature = _bittapSign(apiSecret, signData);

    final url = '$baseUrl/api/v1/futures/position/list';

    final headers = {'X-BT-APIKEY': apiKey, 'X-BT-SIGN': signature, 'X-BT-TS': ts, 'X-BT-NONCE': nonce, 'Content-Type': 'application/json'};

    final res = kIsWeb && proxyUrl != null && proxyUrl.isNotEmpty

        ? await _webFetchWithAuth(url, headers, proxyUrl: proxyUrl)

        : await http.get(Uri.parse(kIsWeb ? _webProxyUrl(url) : url), headers: headers);

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

      final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

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

/// BingX 簽名：queryString 依參數排序後 HMAC-SHA256(secret) -> hex
String _bingxSign(String secret, String queryString) {

  final key = utf8.encode(secret);

  final bytes = utf8.encode(queryString);

  final hmacSha256 = Hmac(sha256, key);

  final digest = hmacSha256.convert(bytes);

  return digest.bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

}

/// BingX 合約持倉 API：/openApi/swap/v2/user/positions
Future<List<dynamic>?> _fetchBingxPositions(String apiKey, String apiSecret, {String? proxyUrl}) async {

  try {

    const baseUrl = 'https://open-api.bingx.com';

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final query = 'timestamp=$timestamp';

    final signature = _bingxSign(apiSecret, query);

    final url = '$baseUrl/openApi/swap/v2/user/positions?$query&signature=$signature';

    final headers = {'X-BX-APIKEY': apiKey, 'X-BX-SIGN': signature};

    final res = kIsWeb && proxyUrl != null && proxyUrl.isNotEmpty

        ? await _webFetchWithAuth(url, headers, proxyUrl: proxyUrl)

        : await http.get(Uri.parse(kIsWeb ? _webProxyUrl(url) : url), headers: headers);

    if (res.statusCode != 200) return null;

    final body = json.decode(res.body);

    if (body is! Map) return null;

    final code = body['code'];

    if (code != 0 && code != '0') return null;

    final rawList = body['data'] as List? ?? [];

    final out = <Map<String, dynamic>>[];

    for (final raw in rawList) {

      final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

      final symbolRaw = (m['symbol'] ?? '').toString();

      if (symbolRaw.isEmpty) continue;

      final symbol = symbolRaw.replaceAll('-', '');

      final entryPrice = toD(m['avgPrice'] ?? m['entryPrice'] ?? m['openPrice']);

      final markPrice = toD(m['markPrice'] ?? m['lastPrice'] ?? m['avgPrice'] ?? entryPrice);

      if (entryPrice <= 0) continue;

      num amt = toD(m['positionAmt'] ?? m['position_amt'] ?? m['size'] ?? m['position'] ?? m['quantity']);

      final sideStr = (m['positionSide'] ?? m['position_side'] ?? m['side'] ?? '').toString().toLowerCase();

      if (amt == 0 && (sideStr == 'short' || sideStr == 'long')) amt = toD(m['size'] ?? m['position'] ?? m['quantity']);

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

/// BingX 倉位歷史：/openApi/swap/v2/user/positionHistory（若 API 存在），用於補錄最近一天已平倉
Future<List<dynamic>?> _fetchBingxPositionHistory(String apiKey, String apiSecret, int startTimeMs, int endTimeMs, {String? proxyUrl}) async {

  try {

    const baseUrl = 'https://open-api.bingx.com';

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final query = 'endTime=$endTimeMs&limit=1000&startTime=$startTimeMs&timestamp=$timestamp';

    final signature = _bingxSign(apiSecret, query);

    final url = '$baseUrl/openApi/swap/v2/user/positionHistory?$query&signature=$signature';

    final headers = {'X-BX-APIKEY': apiKey, 'X-BX-SIGN': signature};

    final res = kIsWeb && proxyUrl != null && proxyUrl.isNotEmpty

        ? await _webFetchWithAuth(url, headers, proxyUrl: proxyUrl)

        : await http.get(Uri.parse(kIsWeb ? _webProxyUrl(url) : url), headers: headers);

    if (res.statusCode != 200) return null;

    final body = json.decode(res.body);

    if (body is! Map) return null;

    final code = body['code'];

    if (code != 0 && code != '0') return null;

    return body['data'] as List? ?? [];

  } catch (_) {

    return null;

  }

}

/// BingX 盈虧流水：/openApi/swap/v2/user/income，用於補錄已平倉紀錄（最近 N 天）
Future<List<dynamic>?> _fetchBingxIncome(String apiKey, String apiSecret, int startTimeMs, int endTimeMs, {String? proxyUrl}) async {

  try {

    const baseUrl = 'https://open-api.bingx.com';

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final query = 'endTime=$endTimeMs&limit=1000&startTime=$startTimeMs&timestamp=$timestamp';

    final signature = _bingxSign(apiSecret, query);

    final url = '$baseUrl/openApi/swap/v2/user/income?$query&signature=$signature';

    final headers = {'X-BX-APIKEY': apiKey, 'X-BX-SIGN': signature};

    final res = kIsWeb && proxyUrl != null && proxyUrl.isNotEmpty

        ? await _webFetchWithAuth(url, headers, proxyUrl: proxyUrl)

        : await http.get(Uri.parse(kIsWeb ? _webProxyUrl(url) : url), headers: headers);

    if (res.statusCode != 200) return null;

    final body = json.decode(res.body);

    if (body is! Map) return null;

    final code = body['code'];

    if (code != 0 && code != '0') return null;

    return body['data'] as List? ?? [];

  } catch (_) {

    return null;

  }

}

/// 取得指定週期的 OI 變動百分比（最近一期），失敗或資料不足回傳 null

Future<double?> _fetchOiChange(String symbol, String period, [String? proxyUrl]) async {

  try {

    final url = 'https://fapi.binance.com/futures/data/openInterestHist?symbol=$symbol&period=$period&limit=2';
    final http.Response res;
    if (kIsWeb && proxyUrl != null && proxyUrl.trim().isNotEmpty) {
      final proxy = proxyUrl.trim().replaceAll(RegExp(r'/$'), '');
      res = await http.post(Uri.parse(proxy), headers: {'Content-Type': 'application/json'}, body: json.encode({'url': url, 'headers': <String, String>{}}));
    } else {
      res = await http.get(Uri.parse(_webProxyUrl(url)));
    }
    if (res.statusCode != 200) return null;
    final list = json.decode(res.body);
    if (list is! List) return null;

    if (list.length < 2) return null;

    final oldOi = toD((list[0] as Map)['sumOpenInterest']);

    final newOi = toD((list[1] as Map)['sumOpenInterest']);

    if (oldOi == 0) return null;

    return (newOi - oldOi) / oldOi * 100;

  } catch (_) {

    return null;

  }

}

/// 取得合約 24h 成交量（quoteVolume）與 Funding rate（%）等簡易統計
Future<Map<String, dynamic>> _fetchSymbolStats(String symbol) async {
  double? vol24h;
  double? fundingRate;
  int? fundingTime;
  try {
    // 24h ticker
    final res24 = await http.get(Uri.parse(_webProxyUrl('https://fapi.binance.com/fapi/v1/ticker/24hr?symbol=$symbol')));
    if (res24.statusCode == 200) {
      final m = json.decode(res24.body) as Map;
      // 以 quoteVolume（USDT 金額）為主，比純張數直覺
      vol24h = toD(m['quoteVolume']);
    }
  } catch (_) {}
  try {
    // Funding 資訊
    final resFunding = await http.get(Uri.parse(_webProxyUrl('https://fapi.binance.com/fapi/v1/premiumIndex?symbol=$symbol')));
    if (resFunding.statusCode == 200) {
      final m = json.decode(resFunding.body) as Map;
      final last = m['lastFundingRate'];
      if (last != null) fundingRate = toD(last) * 100;
      final t = (m['time'] as num?) ?? (m['nextFundingTime'] as num?);
      if (t != null) fundingTime = t.toInt();
    }
  } catch (_) {}
  return {
    'vol24h': vol24h,
    'fundingRate': fundingRate,
    'fundingTime': fundingTime,
  };
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

  final DateTime x;

  final double low;

  final double high;

  final double open;

  final double close;

}

/// 參考線用單點（時間, 價格），兩點連成水平線
class _RefPoint {

  _RefPoint(this.x, this.y);

  final DateTime x;

  final double y;

}

const List<String> _klineIntervals = ['15m', '1h', '4h'];

/// K 線來源：Binance fapi。symbol 會自動去掉連字號與空白以符合 Binance 格式。
Future<List<Candle>> _fetchKlines(String symbol, [String interval = '15m', String? proxyUrl]) async {

  try {

    final binanceSymbol = symbol.toString().trim().replaceAll('-', '').replaceAll(' ', '').toUpperCase();
    if (binanceSymbol.isEmpty) return [];

    final url = 'https://fapi.binance.com/fapi/v1/klines?symbol=$binanceSymbol&interval=$interval&limit=40';

    final http.Response res;
    if (kIsWeb && proxyUrl != null && proxyUrl.trim().isNotEmpty) {
      final proxy = proxyUrl.trim().replaceAll(RegExp(r'/$'), '');
      res = await http.post(Uri.parse(proxy), headers: {'Content-Type': 'application/json'}, body: json.encode({'url': url, 'headers': <String, String>{}}));
    } else {
      res = await http.get(Uri.parse(_webProxyUrl(url)));
    }

    if (res.statusCode != 200) return [];

    dynamic raw = json.decode(res.body);
    // 自訂 Proxy 常見回傳格式：直接陣列 / { "data": [...] } / { "data": "[...]" } / { "body": "..." } / { "result": ... }
    if (raw is Map) {
      for (final key in ['data', 'body', 'result']) {
        final v = raw[key];
        if (v is List) { raw = v; break; }
        if (v is String) {
          try {
            final decoded = json.decode(v);
            if (decoded is List) { raw = decoded; break; }
          } catch (_) {}
        }
      }
    }
    if (raw is! List || raw.isEmpty) return [];

    final out = <Candle>[];
    for (final e in raw) {
      if (e is! List || e.length < 5) continue;
      final t = e[0] is num ? (e[0] as num).toInt() : int.tryParse(e[0].toString());
      if (t == null) continue;
      out.add(Candle(
        DateTime.fromMillisecondsSinceEpoch(t),
        toD(e[3]),
        toD(e[2]),
        toD(e[1]),
        toD(e[4]),
      ));
    }
    return out;

  } catch (_) {

    return [];

  }

}

List<dynamic> _serializeCandles(List<Candle> c) => c.map((e) => [e.x.millisecondsSinceEpoch, e.open, e.high, e.low, e.close]).toList();

List<Candle> _deserializeCandles(List<dynamic> raw) => raw.map((e) {

  final L = e as List;

  return Candle(DateTime.fromMillisecondsSinceEpoch(L[0] as int), toD(L[3]), toD(L[2]), toD(L[1]), toD(L[4]));

}).toList();

/// 1H: 每 8 小時一格；15m: 90 分鐘；4H: 1 天
DateTimeAxis _dateTimeAxisForInterval(String interval) {

  switch (interval) {

    case '1h':

      return DateTimeAxis(interval: 8.0, intervalType: DateTimeIntervalType.hours);

    case '15m':

      return DateTimeAxis(interval: 90.0, intervalType: DateTimeIntervalType.minutes);

    case '4h':

      return DateTimeAxis(interval: 1.0, intervalType: DateTimeIntervalType.days);

    default:

      return DateTimeAxis(interval: 8.0, intervalType: DateTimeIntervalType.hours);

  }

}

/// 從倉位的 entry/tp/sl 算出 Y 軸範圍，避免無 K 線時出現 0～5.5 的錯誤刻度
(double min, double max)? _yRangeFromPosition(Map<String, dynamic> pos) {

  final entry = toD(pos['entry']);

  final sl = toD(pos['sl']);

  final tp1 = toD(pos['tp1']);

  final tp2 = toD(pos['tp2']);

  final tp3 = toD(pos['tp3']);

  final values = <double>[entry, sl];

  if (tp1 > 0) values.add(tp1);

  if (tp2 > 0) values.add(tp2);

  if (tp3 > 0) values.add(tp3);

  final valid = values.where((v) => v > 0).toList();

  if (valid.isEmpty) return (0, 100000);

  final mn = valid.reduce((a, b) => a < b ? a : b);

  final mx = valid.reduce((a, b) => a > b ? a : b);

  final pad = (mx - mn).clamp(1.0, double.infinity) * 0.1;

  return (mn - pad, mx + pad);

}

/// 依 K 線與倉位 entry/tp/sl 計算圖表 Y 軸範圍（含 padding）
(double min, double max) _klineChartYRange(List<Candle> candles, Map<String, dynamic> pos) {

  double yMin = double.infinity;

  double yMax = -double.infinity;

  for (final c in candles) {

    if (c.low < yMin) yMin = c.low;

    if (c.high > yMax) yMax = c.high;

  }

  final entry = toD(pos['entry']);

  final sl = toD(pos['sl']);

  final tp1 = toD(pos['tp1']);

  final tp2 = toD(pos['tp2']);

  final tp3 = toD(pos['tp3']);

  for (final v in [entry, sl, tp1, tp2, tp3]) {

    if (v > 0) {

      if (v < yMin) yMin = v;

      if (v > yMax) yMax = v;

    }

  }

  if (yMin == double.infinity || yMax <= yMin) {

    final fallback = _yRangeFromPosition(pos);

    return fallback ?? (0.0, 100000.0);

  }

  final pad = (yMax - yMin).clamp(1.0, double.infinity) * 0.08;

  return (yMin - pad, yMax + pad);

}

/// 單一 K 線圖核心：蠟燭圖 + 進場/止損/止盈水平線，Y 軸依資料與倉位計算
Widget _buildKlineChartCore({required List<Candle> candles, required Map<String, dynamic> pos, required String interval}) {

  final yRange = _klineChartYRange(candles, pos);

  DateTime xStart;
  final entryTimeRaw = pos['entryTime'];
  if (entryTimeRaw != null) {
    final entryTimeMs = entryTimeRaw is num ? entryTimeRaw.toInt() : int.tryParse(entryTimeRaw.toString());
    if (entryTimeMs != null && entryTimeMs > 0) {
      xStart = DateTime.fromMillisecondsSinceEpoch(entryTimeMs);
    } else {
      xStart = candles.isNotEmpty ? candles.first.x : DateTime.now().subtract(const Duration(hours: 24));
    }
  } else {
    xStart = candles.isNotEmpty ? candles.first.x : DateTime.now().subtract(const Duration(hours: 24));
  }

  final xEnd = candles.isNotEmpty ? candles.last.x : DateTime.now();

  final entry = toD(pos['entry']);

  final sl = toD(pos['sl']);

  final tp1 = toD(pos['tp1']);

  final tp2 = toD(pos['tp2']);

  final tp3 = toD(pos['tp3']);

  final series = <CartesianSeries<dynamic, DateTime>>[];

  if (candles.isNotEmpty) {

    series.add(CandleSeries<Candle, DateTime>(

      dataSource: candles,

      xValueMapper: (c, _) => c.x,

      lowValueMapper: (c, _) => c.low,

      highValueMapper: (c, _) => c.high,

      openValueMapper: (c, _) => c.open,

      closeValueMapper: (c, _) => c.close,

    ));

  }

  void addRefLine(double price, Color color) {

    if (price <= 0) return;

    series.add(LineSeries<_RefPoint, DateTime>(

      dataSource: [_RefPoint(xStart, price), _RefPoint(xEnd, price)],

      xValueMapper: (p, _) => p.x,

      yValueMapper: (p, _) => p.y,

      color: color,

      width: 1.5,

    ));

  }

  addRefLine(entry, Colors.white);

  addRefLine(sl, Colors.red);

  addRefLine(tp1, Colors.green);

  addRefLine(tp2, Colors.green);

  addRefLine(tp3, Colors.green);

  return SfCartesianChart(

    primaryXAxis: _dateTimeAxisForInterval(interval),

    primaryYAxis: NumericAxis(minimum: yRange.$1, maximum: yRange.$2),

    series: series,

  );

}

Widget _chartBox(String l, String v) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(v)]);

Widget _chartOiChip(String period, double? change) {

  if (change == null) return Text("$period: --", style: const TextStyle(fontSize: 11, color: Colors.grey));

  final isUp = change >= 0;

  final sign = isUp ? '+' : '';

  return Text("$period: $sign${change.toStringAsFixed(2)}%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isUp ? Colors.green : Colors.red));

}

Widget _chartOiGrid(List<String> periods, Map<String, double?> oiChanges, {bool isPortrait = false}) {
  final rowSpacing = isPortrait ? 1.5 : 1.0;
  final aspectRatio = isPortrait ? 5.0 : 9.0;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text("OI 變動：", style: TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 4),
      SizedBox(
        width: double.infinity,
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: rowSpacing,
          crossAxisSpacing: 12,
          childAspectRatio: aspectRatio,
          children: periods
              .map((p) => Align(
                    alignment: Alignment.centerLeft,
                    child: _chartOiChip(p, oiChanges[p]),
                  ))
              .toList(),
        ),
      ),
    ],
  );
}

Widget _chartPositionSummary(Map<String, dynamic> pos, {bool isPortrait = false}) {
  // 手機網頁版可能為字串或不同 key，統一用 toD 並支援 uvalue 小寫
  final uValue = toD(pos['uValue'] ?? pos['uvalue'] ?? pos['margin'] ?? 0);
  final lev = pos['leverage'] ?? pos['lev'];
  final funding = pos['statsFundingRate'];
  final ft = pos['statsFundingTime'];

  String _fmtFunding(dynamic v) {
    if (v == null) return '--';
    final d = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (d == null) return '--';
    final sign = d >= 0 ? '+' : '';
    return '$sign${d.toStringAsFixed(4)}%';
  }

  String _fmtTimeMs(dynamic ms) {
    if (ms == null) return '--';
    final n = ms is num ? ms.toInt() : int.tryParse(ms.toString());
    if (n == null || n <= 0) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(n);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmtRoi() {
    final ent = toD(pos['entry']);
    final cur = toD(pos['current']);
    final levNum = (lev is num) ? lev.toInt() : int.tryParse(lev.toString()) ?? 1;
    final ratio = toD(pos['exitRatio']) > 0 ? toD(pos['exitRatio']) : 1.0;
    if (ent == 0) return '--';
    final isLong = (pos['side'] ?? '').toString().toUpperCase().contains('LONG');
    final priceDiff = isLong ? (cur - ent) : (ent - cur);
    return ((priceDiff / ent) * 100 * levNum * ratio).toStringAsFixed(2);
  }

  final levNum = (lev is num) ? lev.toInt() : int.tryParse(lev.toString().trim()) ?? 1;
  final totalValue = uValue * levNum;
  final pnl = _pnlAmount(pos);
  final roiStr = _fmtRoi();
  final roiVal = double.tryParse(roiStr);
  final fundingVal = funding is num ? funding.toDouble() : double.tryParse(funding.toString());

  /// 倉位價值顯示：有總價值則顯示，否則若有保證金則顯示保證金，避免手機網頁版讀不到
  String positionValueStr() {
    if (totalValue > 0) return '${totalValue.toStringAsFixed(2)}U';
    if (uValue > 0) return '${uValue.toStringAsFixed(2)}U (保證金)';
    return '--';
  }

  Widget _summaryChip(String label, String value, {bool? isPositive}) {
    final color = isPositive == null ? Colors.grey : (isPositive ? Colors.green : Colors.red);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  final aspectRatio = isPortrait ? 5.0 : 9.0;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 6),
      const Text("倉位摘要：", style: TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 4),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _summaryChip('倉位價值', positionValueStr())),
        ],
      ),
      const SizedBox(height: 2),
      SizedBox(
        width: double.infinity,
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: isPortrait ? 1.5 : 1.0,
          crossAxisSpacing: 12,
          childAspectRatio: aspectRatio,
          children: [
            _summaryChip('開倉點位', '${toD(pos['entry'])}'),
            _summaryChip('時間標記', _fmtTimeMs(ft)),
            _summaryChip('Funding', _fmtFunding(funding), isPositive: fundingVal != null ? fundingVal >= 0 : null),
            _summaryChip('PNL', '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}U', isPositive: pnl >= 0),
            _summaryChip('ROI', '${roiVal != null && roiVal >= 0 ? '+' : ''}$roiStr%', isPositive: roiVal != null ? roiVal >= 0 : null),
          ],
        ),
      ),
    ],
  );
}



class CryptoDashboard extends StatefulWidget {

  const CryptoDashboard({super.key});

  @override

  State<CryptoDashboard> createState() => _CryptoDashboardState();

}



class _CryptoDashboardState extends State<CryptoDashboard> {

  Timer? _timer;

  Timer? _syncTimer;

  List<dynamic> positions = [];

  bool isLoading = true;

  Map<String, dynamic>? _levelData;

  Map<String, dynamic>? _streakData;

  String _bgMode = 'default';

  String? _bgCustomPath;

  String? _bgCustomImageBase64;

  Color _bgDynamicColor = const Color(0xFF00e5ff);

  final _secureStorage = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  /// 連續幾次 API 同步未偵測到該倉位時，才判定為已關閉（避免 API 延遲或短暫未回傳造成誤判）
  final _apiMissingCount = <String, int>{};



  @override

  void initState() {

    super.initState();

    _initData();

  }



  Future<void> _initData() async {

    final prefs = await SharedPreferences.getInstance();

    // 讀取手續費率並設置全局緩存
    final rateStr = prefs.getString(_tradingFeeRateKey);
    if (rateStr != null) {
      final rate = double.tryParse(rateStr);
      if (rate != null && rate >= 0 && rate <= 0.01) {
        _cachedTradingFeeRate = rate;
      }
    }

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

    _backfillFromBingxPositionHistory().then((added) {

      if (mounted && added > 0) setState(() {});

    });

    _timer = Timer.periodic(const Duration(seconds: 5), (t) => _refresh());

    _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) {

      _syncPositionsFromApi().then((result) {

        final (_, added) = result;

        if (mounted && added > 0) setState(() {});

      });

    });

  }

  @override

  void dispose() {

    _timer?.cancel();

    _syncTimer?.cancel();

    super.dispose();

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

  Future<String?> _getApiProxyUrl() async {

    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_apiProxyUrlKey);

  }

  Future<void> _setApiCredentials(String exchange, String key, String secret) async {

    await _secureStorage.write(key: _apiExchangeKey, value: exchange);

    await _secureStorage.write(key: _apiKeyStorageKey, value: key);

    await _secureStorage.write(key: _apiSecretStorageKey, value: secret);

  }

  Future<void> _setApiProxyUrl(String url) async {

    final prefs = await SharedPreferences.getInstance();

    if (url.trim().isEmpty) {

      await prefs.remove(_apiProxyUrlKey);

    } else {

      await prefs.setString(_apiProxyUrlKey, url.trim());

    }

  }

  /// 讀取手續費率（從 SharedPreferences 或使用預設值）
  Future<double> _getTradingFeeRate() async {

    final prefs = await SharedPreferences.getInstance();

    final rateStr = prefs.getString(_tradingFeeRateKey);

    if (rateStr != null) {

      final rate = double.tryParse(rateStr);

      if (rate != null && rate >= 0 && rate <= 0.01) return rate; // 限制在 0-1% 之間

    }

    return _defaultTradingFeeRate;

  }

  /// 設定手續費率（0-1% 之間，例如 0.055% 輸入 0.00055）
  Future<void> _setTradingFeeRate(double rate) async {

    if (rate < 0 || rate > 0.01) return; // 限制在 0-1% 之間

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_tradingFeeRateKey, rate.toString());

    // 更新全局緩存的手續費率
    _cachedTradingFeeRate = rate;

  }

  Future<void> _clearApiCredentials() async {

    await _secureStorage.delete(key: _apiExchangeKey);

    await _secureStorage.delete(key: _apiKeyStorageKey);

    await _secureStorage.delete(key: _apiSecretStorageKey);

  }

  /// 從 BingX 倉位歷史補錄最近 1 天遺漏的已平倉紀錄；若無倉位歷史 API 則改以盈虧流水補
  Future<int> _backfillFromBingxPositionHistory() async {

    final exchange = await _getApiExchange();

    if (exchange != 'bingx') return 0;

    final apiKey = await _getApiKey();

    final apiSecret = await _getApiSecret();

    if (apiKey == null || apiSecret == null || apiKey.isEmpty || apiSecret.isEmpty) return 0;

    final now = DateTime.now();

    final endMs = now.millisecondsSinceEpoch;

    final startMs = endMs - 24 * 60 * 60 * 1000;

    final proxyUrl = kIsWeb ? await _getApiProxyUrl() : null;

    List<dynamic>? list = await _fetchBingxPositionHistory(apiKey, apiSecret, startMs, endMs, proxyUrl: proxyUrl);

    final bool fromIncome = list == null || list.isEmpty;

    if (fromIncome) list = await _fetchBingxIncome(apiKey, apiSecret, startMs, endMs, proxyUrl: proxyUrl);

    if (list == null || list.isEmpty) return 0;

    int added = 0;

    for (final raw in list) {

      final m = raw is Map ? raw : null;

      if (m == null) continue;

      String symbolRaw;

      double income;

      int? timeMs;

      if (fromIncome) {

        final incomeType = (m['incomeType'] ?? m['type'] ?? '').toString();

        if (incomeType != 'REALIZED_PNL' && incomeType != 'TRADE' && incomeType.isNotEmpty && incomeType != 'realized_pnl') continue;

        symbolRaw = (m['symbol'] ?? '').toString();

        income = toD(m['income'] ?? m['amount'] ?? 0);

        timeMs = m['time'] is num ? (m['time'] as num).toInt() : int.tryParse(m['time']?.toString() ?? '');

      } else {

        symbolRaw = (m['symbol'] ?? '').toString();

        income = toD(m['realizedPnl'] ?? m['realized_pnl'] ?? m['pnl'] ?? m['income'] ?? m['amount'] ?? 0);

        final ct = m['closeTime'] ?? m['time'];
        timeMs = ct is num ? ct.toInt() : int.tryParse(ct?.toString() ?? '');

      }

      if (symbolRaw.isEmpty) continue;

      final symbol = symbolRaw.replaceAll('-', '');

      if (timeMs == null || timeMs <= 0) continue;

      final int settledAtMs = timeMs;

      final existing = positions.where((p) {

        if (p is! Map) return false;

        if ((p['symbol'] ?? '').toString() != symbol) return false;

        final s = p['status']?.toString() ?? '';

        if (!s.contains('完全平倉') && !s.contains('部分平倉') && !s.contains('止盈') && !s.contains('止損') && !s.contains('手動出場')) return false;

        final settled = p['settledAt'];

        if (settled == null) return false;

        final settledMs = settled is num ? settled.toInt() : int.tryParse(settled.toString());

        if (settledMs == null) return false;

        return (settledMs - settledAtMs).abs() < 120000;

      }).isNotEmpty;

      if (existing) continue;

      // 讀取槓桿
      final leverage = (m['leverage'] is num) ? (m['leverage'] as num).toInt() : int.tryParse(m['leverage']?.toString() ?? '') ?? 20;
      final levNum = leverage < 1 ? 20 : leverage;

      // 讀取進場價格
      final entryPrice = toD(m['entryPrice'] ?? m['avgPrice'] ?? m['openPrice'] ?? m['entry_price'] ?? m['avgEntryPrice'] ?? 0);

      // 讀取平倉價格（如果有）
      final closePrice = toD(m['closePrice'] ?? m['close_price'] ?? m['exitPrice'] ?? m['exit_price'] ?? m['markPrice'] ?? m['mark_price'] ?? 0);

      // 讀取方向資訊
      final sideStr = (m['positionSide'] ?? m['position_side'] ?? m['side'] ?? m['direction'] ?? '').toString().toLowerCase();
      final amt = toD(m['positionAmt'] ?? m['position_amt'] ?? m['size'] ?? m['amount'] ?? m['quantity'] ?? 0);
      String side = 'long';
      if (sideStr == 'short' || sideStr == 'sell' || sideStr == '做空') {
        side = 'short';
      } else if (amt < 0) {
        side = 'short';
      } else if (sideStr == 'long' || sideStr == 'buy' || sideStr == '做多' || sideStr.isEmpty) {
        side = 'long';
      }

      // 讀取倉位價值（嘗試多種可能的欄位名稱）
      double notional = toD(m['notional'] ?? m['notionalValue'] ?? m['positionValue'] ?? m['position_value'] ?? m['notional_value'] ?? m['value'] ?? m['totalValue'] ?? 0);
      
      // 如果沒有直接的名義價值，嘗試從持倉數量和價格計算
      if (notional <= 0) {
        final positionAmt = toD(m['positionAmt'] ?? m['position_amt'] ?? m['size'] ?? m['amount'] ?? m['quantity'] ?? 0);
        if (positionAmt != 0) {
          // 優先使用進場價格，如果沒有則嘗試其他價格
          final price = entryPrice > 0 ? entryPrice : (closePrice > 0 ? closePrice : toD(m['markPrice'] ?? m['mark_price'] ?? m['lastPrice'] ?? 0));
          if (price > 0) {
            notional = positionAmt.abs() * price;
          }
        }
      }

      // 計算保證金（uValue）
      final uValue = notional > 0 ? notional / levNum : 0.0;

      positions.add({

        'symbol': symbol,

        'leverage': levNum,

        'uValue': uValue,

        'entry': entryPrice > 0 ? entryPrice : 0.0,

        'current': closePrice > 0 ? closePrice : 0.0,

        'entryTime': settledAtMs - 3600000,

        'settledAt': settledAtMs,

        'tp1': 0.0,

        'tp2': 0.0,

        'tp3': 0.0,

        'sl': 0.0,

        'status': '完全平倉',

        'side': side,

        'manualEntry': false,

        'realizedPnl': income,

        'source': 'api_backfill',

      });

      added++;

    }

    if (added > 0) await _persistPositions();

    return added;

  }

  /// 回傳 (錯誤訊息, 成功時加入的筆數)。無錯誤時 error 為 null。
  Future<(String?, int)> _syncPositionsFromApi() async {

    final exchange = await _getApiExchange();

    final apiKey = await _getApiKey();

    final apiSecret = await _getApiSecret();

    if (apiKey == null || apiSecret == null || apiKey.isEmpty || apiSecret.isEmpty) {

      return ('請先填寫並儲存 API Key 與 Secret', 0);

    }

    final proxyUrl = kIsWeb ? await _getApiProxyUrl() : null;

    List<dynamic>? list;

    if (exchange == 'binance') {

      list = await _fetchBinancePositionRisk(apiKey, apiSecret, proxyUrl: proxyUrl);

    } else if (exchange == 'bingx') {

      list = await _fetchBingxPositions(apiKey, apiSecret, proxyUrl: proxyUrl);

    } else if (exchange == 'bittap') {

      list = await _fetchBittapPositions(apiKey, apiSecret, proxyUrl: proxyUrl);

    } else {

      return ('此交易所尚未支援同步，敬請期待', 0);

    }

    if (list == null) {

      if (exchange == 'bittap') return ('無法取得 BitTap 倉位（請檢查 API 權限、網路或端點路徑）', 0);

      if (exchange == 'bingx') return ('無法取得 BingX 倉位（請檢查 API 權限、網路或端點路徑）', 0);

      return ('無法取得倉位（請檢查 API 權限與網路）', 0);

    }

    final apiOpenSymbols = <String>{};

    final apiPositionMap = <String, Map<String, dynamic>>{};

    for (final raw in list) {

      final m = raw is Map ? raw : null;

      if (m == null) continue;

      final amt = toD(m['positionAmt'] ?? m['position_amt'] ?? m['size'] ?? m['position'] ?? m['quantity'] ?? 0);

      if (amt == 0) continue;

      final sym = (m['symbol'] ?? m['symbolName'] ?? '').toString().replaceAll('-', '');

      if (sym.isEmpty) continue;

      apiOpenSymbols.add(sym);

      final entryPrice = toD(m['entryPrice'] ?? m['avgPrice'] ?? m['openPrice']);

      final markPrice = toD(m['markPrice'] ?? m['lastPrice'] ?? m['avgPrice'] ?? entryPrice);

      final leverage = (m['leverage'] is num) ? (m['leverage'] as num).toInt() : int.tryParse(m['leverage']?.toString() ?? '') ?? 1;

      final notional = (amt.abs() * entryPrice);

      final uValue = notional / (leverage < 1 ? 1 : leverage);

      final sideStr = (m['positionSide'] ?? m['position_side'] ?? m['side'] ?? '').toString().toLowerCase();

      num amtNum = amt;

      if (sideStr == 'short' && amtNum > 0) amtNum = -amtNum;

      apiPositionMap[sym] = {

        'entryPrice': entryPrice,

        'markPrice': markPrice,

        'leverage': leverage < 1 ? 1 : leverage,

        'uValue': uValue,

        'side': amtNum > 0 ? 'long' : 'short',

      };

    }

    int updatedCount = 0;

    final closedPositions = <Map<String, dynamic>>[];

    for (int i = 0; i < positions.length; i++) {

      final p = positions[i];

      if (p is! Map) continue;

      final status = p['status']?.toString() ?? '';

      if (!status.contains('監控中')) continue;

      if (p['manualEntry'] == true) continue;

      final symbol = (p['symbol'] ?? '').toString();

      if (symbol.isEmpty) continue;

      final apiData = apiPositionMap[symbol];

      if (apiData != null) {

        final oldU = toD(p['uValue']);

        final newU = toD(apiData['uValue']);

        if (newU < oldU && oldU > 0) {

          final closedRatio = 1 - (newU / oldU);

          final closedU = oldU * closedRatio;

          final closedPortion = Map<String, dynamic>.from(p);

          closedPortion['status'] = '部分平倉';

          closedPortion['settledAt'] = DateTime.now().millisecondsSinceEpoch;

          closedPortion['exitRatio'] = closedRatio;

          closedPortion['exitRatioDisplay'] = closedRatio;

          closedPortion['uValue'] = closedU;

          closedPortion['current'] = apiData['markPrice'];

          positions.add(closedPortion);

          closedPositions.add(closedPortion);

        }

        p['entry'] = apiData['entryPrice'];

        p['current'] = apiData['markPrice'];

        p['leverage'] = apiData['leverage'];

        p['uValue'] = apiData['uValue'];

        p['side'] = apiData['side'];

        updatedCount++;

        _apiMissingCount[symbol] = 0;

      } else {

        final missingCount = (_apiMissingCount[symbol] ?? 0) + 1;

        _apiMissingCount[symbol] = missingCount;

        if (missingCount < 4) continue;

        _apiMissingCount.remove(symbol);

        p['status'] = '完全平倉';

        p['settledAt'] = DateTime.now().millisecondsSinceEpoch;

        p['exitRatio'] = 1.0;

        closedPositions.add(Map<String, dynamic>.from(p));

      }

    }

    if (exchange == 'bingx' && closedPositions.isNotEmpty) {

      final endMs = DateTime.now().millisecondsSinceEpoch;

      final startMs = endMs - 24 * 60 * 60 * 1000;

      final incomeList = await _fetchBingxIncome(apiKey, apiSecret, startMs, endMs, proxyUrl: proxyUrl);

      if (incomeList != null && incomeList.isNotEmpty) {

        final bySymbol = <String, int>{};

        for (final raw in incomeList) {

          final m = raw is Map ? raw : null;

          if (m == null) continue;

          final incomeType = (m['incomeType'] ?? m['type'] ?? '').toString();

          if (incomeType != 'REALIZED_PNL' && incomeType != 'TRADE' && incomeType.isNotEmpty && incomeType != 'realized_pnl') continue;

          final symbolRaw = (m['symbol'] ?? '').toString();

          if (symbolRaw.isEmpty) continue;

          final symbol = symbolRaw.replaceAll('-', '');

          final timeMs = m['time'] is num ? (m['time'] as num).toInt() : int.tryParse(m['time']?.toString() ?? '');

          if (timeMs == null || timeMs <= 0) continue;

          final prev = bySymbol[symbol];

          if (prev == null || timeMs > prev) bySymbol[symbol] = timeMs;

        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;

        for (final p in positions) {

          if (p is! Map) continue;

          if ((p['status'] ?? '').toString() != '完全平倉') continue;

          final symbol = (p['symbol'] ?? '').toString();

          if (symbol.isEmpty) continue;

          final settled = p['settledAt'];

          if (settled == null) continue;

          final settledMs = settled is num ? settled.toInt() : int.tryParse(settled.toString());

          if (settledMs == null || nowMs - settledMs > 120000) continue;

          final incomeTime = bySymbol[symbol];

          if (incomeTime != null) p['settledAt'] = incomeTime;

        }

      }

    }

    if (closedPositions.isNotEmpty) {

      await _persistPositions();

      await _onHitManualExit(closedPositions);

    }

    if (updatedCount > 0) await _persistPositions();

    final watchingSymbols = positions.where((p) => p['status'].toString().contains('監控中')).map((p) => p['symbol'] as String).toSet();

    int added = 0;

    final now = DateTime.now();

    const reopenWindowMs = 120000;

    for (final raw in list) {

      final map = raw is Map ? raw : null;

      if (map == null) continue;

      final positionAmt = toD(map['positionAmt'] ?? map['position_amt'] ?? map['size'] ?? map['position'] ?? map['quantity'] ?? 0);

      if (positionAmt == 0) continue;

      final symbolRaw = (map['symbol'] ?? map['symbolName'] ?? '').toString();

      final symbol = symbolRaw.replaceAll('-', '');

      if (symbol.isEmpty) continue;

      if (watchingSymbols.contains(symbol)) continue;

      final entryPrice = toD(map['entryPrice'] ?? map['avgPrice'] ?? map['openPrice']);

      final markPrice = toD(map['markPrice'] ?? map['lastPrice'] ?? map['avgPrice'] ?? entryPrice);

      final leverage = (map['leverage'] is num) ? (map['leverage'] as num).toInt() : int.tryParse(map['leverage']?.toString() ?? '') ?? 1;

      final notional = (positionAmt.abs() * entryPrice);

      final uValue = notional / (leverage < 1 ? 1 : leverage);

      final side = positionAmt > 0 ? 'long' : 'short';

      Map<String, dynamic>? recentlyClosed;

      int? latestSettled;

      for (final p in positions) {

        if (p is! Map) continue;

        if ((p['symbol'] ?? '').toString() != symbol) continue;

        final status = p['status']?.toString() ?? '';

        if (!status.contains('完全平倉') && !status.contains('部分平倉')) continue;

        final settled = p['settledAt'];

        if (settled == null) continue;

        final settledMs = settled is num ? settled.toInt() : int.tryParse(settled.toString());

        if (settledMs == null || now.millisecondsSinceEpoch - settledMs > reopenWindowMs) continue;

        if (latestSettled == null || settledMs > latestSettled) {

          latestSettled = settledMs;

          recentlyClosed = p as Map<String, dynamic>;

        }

      }

      if (recentlyClosed != null) {

        recentlyClosed['status'] = '監控中';

        recentlyClosed['entry'] = entryPrice;

        recentlyClosed['current'] = markPrice;

        recentlyClosed['uValue'] = uValue;

        recentlyClosed['leverage'] = leverage < 1 ? 1 : leverage;

        recentlyClosed['side'] = side;

        recentlyClosed.remove('settledAt');

        recentlyClosed.remove('exitRatio');

        recentlyClosed.remove('exitRatioDisplay');

        _apiMissingCount[symbol] = 0;

        watchingSymbols.add(symbol);

        added++;

      } else {

        positions.add({

          'symbol': symbol,

          'leverage': leverage < 1 ? 1 : leverage,

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

          'manualEntry': false,

        });

        _apiMissingCount[symbol] = 0;

        watchingSymbols.add(symbol);

        added++;

      }

    }

    if (added > 0) await _persistPositions();

    return (null, closedPositions.length + updatedCount + added);

  }

  void _showBatchDelete() {

    final settledList = _settled;

    if (settledList.isEmpty) {

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚無已結算的紀錄可刪除'), behavior: SnackBarBehavior.floating));

      return;

    }

    final selected = <int>{};

    showModalBottomSheet(

      context: context,

      isScrollControlled: true,

      backgroundColor: const Color(0xFF1A1A1A),

      builder: (ctx) => StatefulBuilder(

        builder: (context, setModalState) {

          return DraggableScrollableSheet(

            initialChildSize: 0.6,

            minChildSize: 0.3,

            maxChildSize: 0.95,

            expand: false,

            builder: (context, scrollCtrl) => Padding(

              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),

              child: Column(

                mainAxisSize: MainAxisSize.min,

                children: [

                  Padding(

                    padding: const EdgeInsets.all(16),

                    child: Row(

                      mainAxisAlignment: MainAxisAlignment.spaceBetween,

                      children: [

                        Text('批量刪除紀錄 (${settledList.length} 筆)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFFC0CB))),

                        Row(

                          children: [

                            TextButton(onPressed: () { selected.addAll(List.generate(settledList.length, (i) => i)); setModalState(() {}); }, child: const Text('全選')),

                            TextButton(onPressed: () { selected.clear(); setModalState(() {}); }, child: const Text('取消全選')),

                          ],

                        ),

                      ],

                    ),

                  ),

                  const Divider(),

                  Expanded(

                    child: ListView.builder(

                      controller: scrollCtrl,

                      itemCount: settledList.length,

                      itemBuilder: (ctx, i) {

                        final pos = settledList[i];

                        if (pos is! Map) return const SizedBox.shrink();

                        final sym = (pos['symbol'] ?? '').toString();

                        final status = pos['status']?.toString() ?? '';

                        final pnl = _pnlAmount(Map<String, dynamic>.from(pos));

                        return CheckboxListTile(

                          value: selected.contains(i),

                          onChanged: (v) { if (v == true) selected.add(i); else selected.remove(i); setModalState(() {}); },

                          title: Text('$sym (${pos['leverage']}x) ${_sideLabel(Map<String, dynamic>.from(pos))}', style: const TextStyle(fontSize: 14)),

                          subtitle: Text('$status · ${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)} U', style: const TextStyle(fontSize: 11, color: Colors.grey)),

                          activeColor: const Color(0xFFFFC0CB),

                        );

                      },

                    ),

                  ),

                  Padding(

                    padding: const EdgeInsets.all(16),

                    child: SizedBox(

                      width: double.infinity,

                      child: FilledButton.icon(

                        icon: const Icon(Icons.delete_outline),

                        label: Text('刪除選中 (${selected.length})'),

                        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),

                        onPressed: selected.isEmpty ? null : () async {

                          final toRemove = selected.toList()..sort((a, b) => b.compareTo(a));

                          for (final i in toRemove) positions.remove(settledList[i]);

                          await _persistPositions();

                          if (!ctx.mounted) return;

                          Navigator.pop(ctx);

                          setState(() {});

                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已刪除 ${toRemove.length} 筆紀錄'), behavior: SnackBarBehavior.floating));

                        },

                      ),

                    ),

                  ),

                ],

              ),

            ),

          );

        },

      ),

    );

  }

  void _showApiSettings() async {

    final savedExchange = await _getApiExchange();

    final keyController = TextEditingController(text: await _getApiKey() ?? '');

    final secretController = TextEditingController(text: await _getApiSecret() ?? '');

    final proxyController = TextEditingController(text: await _getApiProxyUrl() ?? '');

    final feeRate = await _getTradingFeeRate();

    final feeRateController = TextEditingController(text: (feeRate * 10000).toStringAsFixed(2)); // 顯示為基點（0.055% = 5.5 基點）

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
                if (kIsWeb) Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('網頁版需設定自訂代理才能取得倉位（公開 API 如 K 線則不需）。', style: TextStyle(fontSize: 10, color: Colors.orangeAccent)),
                      const Text('請部署 cloudflare-worker/proxy.js 至 Cloudflare Workers，再將 Worker URL 填於下方。', style: TextStyle(fontSize: 9, color: Colors.grey)),
                    ],
                  ),
                ),

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

                if (kIsWeb) ...[

                  const SizedBox(height: 12),

                  TextField(

                    controller: proxyController,

                    decoration: const InputDecoration(labelText: 'Proxy URL（網頁版必填，如 https://xxx.workers.dev）', border: OutlineInputBorder(), hintText: 'Cloudflare Worker URL'),

                    keyboardType: TextInputType.url,

                  ),

                ],

                const SizedBox(height: 12),

                TextField(

                  controller: feeRateController,

                  decoration: const InputDecoration(

                    labelText: '手續費率（基點，例如 5.5 表示 0.055%）',

                    border: OutlineInputBorder(),

                    hintText: '預設：5.5（0.055%）',

                    helperText: '買賣皆為此費率，用於計算盈虧時扣除手續費',

                  ),

                  keyboardType: const TextInputType.numberWithOptions(decimal: true),

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

                          if (kIsWeb) await _setApiProxyUrl(proxyController.text.trim());

                          // 儲存手續費率（將基點轉換為小數，例如 5.5 -> 0.00055）
                          final feeRateBps = double.tryParse(feeRateController.text.trim());
                          if (feeRateBps != null && feeRateBps >= 0 && feeRateBps <= 100) {
                            await _setTradingFeeRate(feeRateBps / 10000);
                          }

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

                          if (kIsWeb) await _setApiProxyUrl(proxyController.text.trim());

                          // 儲存手續費率（將基點轉換為小數，例如 5.5 -> 0.00055）
                          final feeRateBps = double.tryParse(feeRateController.text.trim());
                          if (feeRateBps != null && feeRateBps >= 0 && feeRateBps <= 100) {
                            await _setTradingFeeRate(feeRateBps / 10000);
                          }

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

                const SizedBox(height: 12),

                OutlinedButton.icon(

                  icon: const Icon(Icons.link_off, size: 18),

                  label: const Text('取消 API 連接'),

                  style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade300),

                  onPressed: () async {

                    await _clearApiCredentials();

                    if (!ctx.mounted) return;

                    Navigator.pop(ctx);

                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已取消 API 連接'), behavior: SnackBarBehavior.floating));

                  },

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

      {'id': 'default', 'label': '預設', 'desc': '深色帶淡粉紫'},

      {'id': 'gradient_soft', 'label': '柔和', 'desc': '深藍灰'},

      {'id': 'gradient_midnight', 'label': '午夜藍', 'desc': '藍紫色系'},

      {'id': 'gradient_warm', 'label': '暖色', 'desc': '深褐紅'},

      {'id': 'dynamic', 'label': '動態背景', 'desc': '光球・線條・粒子'},

      {'id': 'custom', 'label': '自訂圖片', 'desc': kIsWeb ? '從本機選擇圖片' : '從相簿選擇'},

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

        final res = await http.get(Uri.parse(_webProxyUrl('https://fapi.binance.com/fapi/v1/ticker/price?symbol=${positions[i]['symbol']}')));

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

      if (sl > 0 && cur <= sl) pos['status'] = '止損出局 ⚡️';

      else if (targetTp > 0 && cur >= targetTp) pos['status'] = '止盈達標 ⭐️';

    } else {

      if (sl > 0 && cur >= sl) pos['status'] = '止損出局 ⚡️';

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

  /// 手動出場反饋：依盈虧給予與止盈止損一致的反饋（經驗、每日任務、SnackBar）
  Future<void> _onHitManualExit(List<Map<String, dynamic>> closedPositions) async {

    if (closedPositions.isEmpty) return;

    for (final p in closedPositions) {

      final exp = _calculateExp(p);

      if (exp > 0) await _addExp(exp, showNotification: false);

    }

    await _checkDailyTask('settle_task');

    final streaks = await _calculateStreaks(positions);

    final unlocked = await _getUnlocked();

    final profitDays = streaks['profitDays'] ?? 0;

    final lastPos = closedPositions.last;

    final pnl = _pnlAmount(lastPos);

    if (pnl > 0) {

      if (profitDays >= 3 && !unlocked.contains('profit_streak_3')) await _unlock('profit_streak_3');

      if (profitDays >= 7 && !unlocked.contains('profit_streak_7')) await _unlock('profit_streak_7');

    }

    final tasks = await _getDailyTasks();

    final completed = Set<String>.from((tasks['completed'] as Map? ?? {}).keys.cast<String>());

    if (completed.length == _dailyTasks.length && !unlocked.contains('daily_all')) await _unlock('daily_all');

    if (!mounted) return;

    final statusLabel = lastPos['status']?.toString().contains('完全平倉') == true ? '完全平倉' : (lastPos['status']?.toString().contains('部分平倉') == true ? '部分平倉' : '手動出場');

    ScaffoldMessenger.of(context).showSnackBar(

      SnackBar(

        content: Text(pnl > 0 ? "やった！$statusLabel盈餘 ⭐️ (+${pnl.toStringAsFixed(2)} U)" : "ちー…$statusLabel虧損 ⚡️ (${pnl.toStringAsFixed(2)} U)"),

        backgroundColor: pnl > 0 ? const Color(0xFF4CAF50) : const Color(0xFF757575),

        behavior: SnackBarBehavior.floating,

      ),

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

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(

                  SnackBar(

                    content: Text(pnl > 0 ? "やった！手動出場盈餘 ⭐️ (+${pnl.toStringAsFixed(2)} U)" : "ちー…手動出場虧損 ⚡️ (${pnl.toStringAsFixed(2)} U)"),

                    backgroundColor: pnl > 0 ? const Color(0xFF4CAF50) : const Color(0xFF757575),

                    behavior: SnackBarBehavior.floating,

                  ),

                );

              },

              child: const Text("確認出場"),

            ),

          ],

        ),

      ),

    );

  }

  List<dynamic> get _watching => positions.where((p) => p['status'].toString().contains('監控中')).toList();

  /// 監控中持倉的未結盈虧統計（合計與筆數）
  Widget _buildWatchingUnrealizedSummary() {
    final watching = _watching;
    if (watching.isEmpty) return const SizedBox.shrink();
    double totalPnl = 0;
    for (final p in watching) {
      if (p is Map<String, dynamic>) totalPnl += _pnlAmount(p);
    }
    final isPositive = totalPnl >= 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Card(
        color: const Color(0xFF1A1A1A),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('未結盈虧統計', style: TextStyle(fontSize: 14, color: Colors.grey.shade300)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${totalPnl >= 0 ? '+' : ''}${totalPnl.toStringAsFixed(2)} U', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isPositive ? Colors.green : Colors.red)),
                  const SizedBox(width: 12),
                  Text('${watching.length} 筆持倉', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<dynamic> get _settled => positions.where((p) {

    final s = p['status'].toString();

    return s.contains('止盈') || s.contains('止損') || s.contains('手動出場') || s.contains('完全平倉') || s.contains('部分平倉');

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

            IconButton(

              icon: const Icon(Icons.delete_sweep),

              tooltip: '批量刪除紀錄',

              onPressed: _showBatchDelete,

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

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildWatchingUnrealizedSummary(),
                          Expanded(child: _listForPositions(_watching, emptyLabel: '尚無監控中的任務', isSettled: false)),
                        ],
                      ),

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

      if (s.contains('止盈') || ((s.contains('手動出場') || s.contains('完全平倉') || s.contains('部分平倉')) && _pnlAmount(p) > 0)) winCount++;

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

            ? "盈利: ${_pnlAmount(pos) >= 0 ? '+' : ''}${_pnlAmount(pos).toStringAsFixed(2)} U | RR: ${_rrValue(pos) != null ? _rrValue(pos)!.toStringAsFixed(2) : '--'} | ROI: ${calculateROI(pos)}% |平倉: ${_fmtEntryTime(pos['settledAt'])} · 持倉 ${_fmtDuration(pos['entryTime'], pos['settledAt'])}${pos['status'].toString().contains('止盈') && pos['hitTp'] != null ? ' · ${_tpLabel(pos['hitTp'].toString(), pos)}' : ''} | ${_statusDisplay(pos['status'], pos)}"

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

    final isSettled = pos['status'].toString().contains('止盈') || pos['status'].toString().contains('止損') || pos['status'].toString().contains('手動出場') || pos['status'].toString().contains('完全平倉') || pos['status'].toString().contains('部分平倉');

    const oiPeriods = ['5m', '15m', '30m', '1h', '4h'];

    final proxyUrl = kIsWeb ? await _getApiProxyUrl() : null;

    // 先抓 symbol 統計資料（24h 成交量、Funding 等）
    final stats = await _fetchSymbolStats(symbol);
    pos['stats24hVol'] = stats['vol24h'];
    pos['statsFundingRate'] = stats['fundingRate'];
    pos['statsFundingTime'] = stats['fundingTime'];

    if (isSettled) {

      List<Candle> candles = [];

      if (pos['candles'] != null && (pos['candles'] as List).isNotEmpty) {

        candles = _deserializeCandles(pos['candles'] as List);

      } else {

        candles = await _fetchKlines(symbol, '15m', proxyUrl);

      }

      if (!mounted) return;

      _showChartDialog(pos: pos, symbol: symbol, candles: candles, oiChanges: <String, double?>{}, oiPeriods: oiPeriods, isSettled: true, proxyUrl: proxyUrl);

    } else {

      List<Candle> candles = await _fetchKlines(symbol, '15m', proxyUrl);

      final oiChanges = <String, double?>{};

      await Future.wait(oiPeriods.map((p) async => oiChanges[p] = await _fetchOiChange(symbol, p, proxyUrl)));

      if (!mounted) return;

      _showChartDialog(pos: pos, symbol: symbol, candles: candles, oiChanges: oiChanges, oiPeriods: oiPeriods, isSettled: false, proxyUrl: proxyUrl);

    }

  }

  void _showChartDialog({required Map<String, dynamic> pos, required String symbol, required List<Candle> candles, required Map<String, double?> oiChanges, required List<String> oiPeriods, required bool isSettled, String? proxyUrl}) {

    showDialog(context: context, builder: (ctx) {

      final size = MediaQuery.of(ctx).size;

      final isPortrait = MediaQuery.of(ctx).orientation == Orientation.portrait;

      final double dialogW = isPortrait ? size.width - 24 : 1100;

      final double dialogH = isPortrait ? (800.0 * 0.75) : 800.0;

      return AlertDialog(

        backgroundColor: const Color(0xFF111111),

        content: SizedBox(

          width: dialogW,

          height: dialogH,

          child: _ChartDialogContent(

            pos: pos,

            symbol: symbol,

            initialCandles: candles,

            oiChanges: oiChanges,

            oiPeriods: oiPeriods,

            isSettled: isSettled,

            proxyUrl: proxyUrl,

            buildContent: (bctx, interval, list, proxy) {

              final s = MediaQuery.of(bctx).size;

              final shrinkChart = s.height > s.width;

              return isSettled

                  ? _buildSettledDataContent(context: bctx, pos: pos, symbol: symbol)

                  : _DetailChartLive(pos: pos, symbol: symbol, initialCandles: list, initialOiChanges: Map.from(oiChanges), oiPeriods: oiPeriods, interval: interval, isPortrait: isPortrait, shrinkChartHeight: shrinkChart, proxyUrl: proxy);

            },

          ),

        ),

      );

    });

  }

  /// 結算頁：不顯示 K 線，只顯示紀錄的數據（基本／進場／出場／目標／盈虧／來源）
  Widget _buildSettledDataContent({required BuildContext context, required Map<String, dynamic> pos, required String symbol}) {

    final pnl = _pnlAmount(pos);
    final roi = calculateROI(pos);
    final rr = _rrValue(pos);
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final crossCount = isPortrait ? 2 : 3;

    // 方案二：區塊標題分色（淡藍／淡綠／淡橙／淡紫／盈虧綠紅／其他灰／筆記淡青）
    const Color _secBasic = Color(0xFF7EC8E3);   // 基本-淡藍
    const Color _secEntry = Color(0xFF98D8A8);  // 進場-淡綠
    const Color _secExit = Color(0xFFFFB366);   // 出場-淡橙
    const Color _secTarget = Color(0xFFDDA0DD); // 目標與結果-淡紫
    const Color _secPnlWin = Color(0xFF81C784); // 盈虧正-淡綠
    const Color _secPnlLoss = Color(0xFFE57373);// 盈虧負-淡紅
    const Color _secOther = Color(0xFFB0B0B0); // 其他-淡灰
    const Color _secNote = Color(0xFFB0C4DE);   // 筆記-淡青

    Widget sectionTitle(String t, Color color) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(t, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
    );

    // 內容字色：欄位名用區塊色，數值預設亮白；盈虧金額/率依正負綠紅
    const Color _valueDefault = Color(0xFFE8E8E8);
    Widget settledChartBox(String l, String v, Color labelColor, {Color? valueColor}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l, style: TextStyle(fontSize: 10, color: labelColor)),
        Text(v, style: TextStyle(fontSize: 13, color: valueColor ?? _valueDefault)),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('$symbol 結算紀錄', style: const TextStyle(color: Color(0xFFFFC0CB), fontSize: 20)),
          ),
          sectionTitle('基本', _secBasic),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 12,
            childAspectRatio: 2.8,
            children: [
              settledChartBox('交易對', symbol, _secBasic),
              settledChartBox('方向', _sideLabel(pos), _secBasic),
              settledChartBox('槓桿', '${pos['leverage'] ?? '--'}x', _secBasic),
              settledChartBox('保證金', '${pos['uValue'] ?? '--'} U', _secBasic),
            ],
          ),
          sectionTitle('進場', _secEntry),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 12,
            childAspectRatio: 2.8,
            children: [
              settledChartBox('進場時間', _fmtEntryTime(pos['entryTime']), _secEntry),
              settledChartBox('進場價', '${pos['entry'] ?? '--'}', _secEntry),
            ],
          ),
          sectionTitle('出場', _secExit),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 12,
            childAspectRatio: 2.8,
            children: [
              settledChartBox('平倉時間', _fmtEntryTime(pos['settledAt']), _secExit),
              settledChartBox(
                pos['status'].toString().contains('手動出場') ? '出場價格' : '平倉價',
                '${pos['current'] ?? '--'}',
                _secExit,
              ),
              settledChartBox('持倉時長', _fmtDuration(pos['entryTime'], pos['settledAt']), _secExit),
              if (pos['exitRatioDisplay'] != null || pos['exitRatio'] != null)
                settledChartBox('出場比例', '${((toD(pos['exitRatioDisplay'] ?? pos['exitRatio'] ?? 0)) * 100).toStringAsFixed(0)}%', _secExit),
            ],
          ),
          sectionTitle('目標與結果', _secTarget),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 12,
            childAspectRatio: 2.8,
            children: [
              settledChartBox('TP1', '${pos['tp1'] ?? '--'}', _secTarget),
              if (toD(pos['tp2']) > 0) settledChartBox('TP2', '${pos['tp2']}', _secTarget),
              if (toD(pos['tp3']) > 0) settledChartBox('TP3', '${pos['tp3']}', _secTarget),
              settledChartBox('止損', '${pos['sl'] ?? '--'}', _secTarget),
              settledChartBox('達標檔位', pos['status'].toString().contains('止盈') ? _tpLabel((pos['hitTp'] ?? '--').toString(), pos) : (pos['status'].toString().contains('止損') ? '止損' : (pos['status'] ?? '--').toString()), _secTarget),
              settledChartBox('結算類型', _statusDisplay(pos['status'], pos), _secTarget),
            ],
          ),
          sectionTitle('盈虧', Colors.grey),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 12,
            childAspectRatio: 2.8,
            children: [
              settledChartBox('盈虧金額', '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)} U', Colors.grey, valueColor: pnl >= 0 ? _secPnlWin : _secPnlLoss),
              settledChartBox('盈虧率', '$roi%', Colors.grey, valueColor: pnl >= 0 ? _secPnlWin : _secPnlLoss),
              settledChartBox('RR', rr != null ? rr.toStringAsFixed(2) : '--', Colors.grey),
            ],
          ),
          if (pos['source'] != null && pos['source'].toString().isNotEmpty) ...[
            sectionTitle('其他', _secOther),
            settledChartBox('來源', pos['source'].toString() == 'api_backfill' ? 'API 補錄' : pos['source'].toString(), _secOther),
          ],
          sectionTitle('筆記', _secNote),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Card(
              color: const Color(0xFF1A1A1A),
              child: InkWell(
                onTap: () => _showNoteEditor(pos),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          (pos['note'] ?? '').toString().isEmpty ? '點擊新增筆記...' : pos['note'].toString(),
                          style: TextStyle(
                            fontSize: 14,
                            color: (pos['note'] ?? '').toString().isEmpty ? Colors.grey : _secNote,
                            fontStyle: (pos['note'] ?? '').toString().isEmpty ? FontStyle.italic : FontStyle.normal,
                          ),
                          maxLines: 10,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
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

  void _showNoteEditor(Map<String, dynamic> pos) {
    final noteController = TextEditingController(text: (pos['note'] ?? '').toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text('筆記', style: TextStyle(color: Color(0xFFFFC0CB))),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            hintText: '記錄覆盤過程、心得、檢討...',
            border: OutlineInputBorder(),
          ),
          maxLines: 10,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final idx = positions.indexOf(pos);
              if (idx >= 0) {
                setState(() {
                  positions[idx]['note'] = noteController.text.trim();
                });
                _persistPositions();
              }
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFC0CB)),
            child: const Text('儲存', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  /// 監控中倉位詳情用（含 K 線）；結算頁已改為只顯示 _buildSettledDataContent，此方法保留供日後「查看 K 線」等用途。
  // ignore: unused_element
  Widget _buildChartContent({required BuildContext context, required Map<String, dynamic> pos, required String symbol, required List<Candle> candles, required Map<String, double?> oiChanges, required List<String> oiPeriods, String interval = '15m', bool shrinkChart = false}) {

    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    return Column(children: [

      Text("$symbol $interval K線${candles.isEmpty ? ' · K 線載入失敗，僅顯示進出場線' : ''}", style: const TextStyle(color: Color(0xFFFFC0CB), fontSize: 20)),

      Expanded(flex: shrinkChart ? 2 : 3, child: _buildKlineChartCore(candles: candles, pos: pos, interval: interval)),

      shrinkChart
          ? Expanded(
              flex: 2,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 200),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(),
                        if (oiChanges.isNotEmpty && oiChanges.values.any((v) => v != null))
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: _chartOiGrid(oiPeriods, oiChanges, isPortrait: isPortrait),
                          ),
                        _chartPositionSummary(pos, isPortrait: isPortrait),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : SizedBox(
              height: 180,
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(),
                      if (oiChanges.isNotEmpty && oiChanges.values.any((v) => v != null))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _chartOiGrid(oiPeriods, oiChanges, isPortrait: isPortrait),
                        ),
                      _chartPositionSummary(pos, isPortrait: isPortrait),
                    ],
                  ),
                ),
              ),
            ),

      const SizedBox(height: 8),

      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [

        _chartBox("槓桿", "${pos['leverage']}x"),

        _chartBox("保證金", "${pos['uValue']}U"),

        _chartBox("進場時間", _fmtEntryTime(pos['entryTime'])),

        _chartBox("TP1 (${_tp1RatioFrom(pos)})", "${pos['tp1']}"),

        if (toD(pos['tp2']) > 0) _chartBox("TP2 (${_tp2RatioFrom(pos)})", "${pos['tp2']}"),

        if (toD(pos['tp3']) > 0) _chartBox("TP3 (${_tp3RatioFrom(pos)})", "${pos['tp3']}"),

      ]),

      if (pos['settledAt'] != null) ...[

        const Divider(),

        const Text("Closing log", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),

        const SizedBox(height: 6),

        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [

          Column(children: [

            const Text("盈利金額", style: TextStyle(fontSize: 11, color: Colors.grey)),

            Text("${_pnlAmount(pos) >= 0 ? '+' : ''}${_pnlAmount(pos).toStringAsFixed(2)} U", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _pnlAmount(pos) >= 0 ? Colors.green : Colors.red)),

          ]),

          Column(children: [

            const Text("RR ", style: TextStyle(fontSize: 11, color: Colors.grey)),

            Text(_rrValue(pos) != null ? _rrValue(pos)!.toStringAsFixed(2) : '--', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _rrValue(pos) != null && _rrValue(pos)! >= 0 ? Colors.green : (_rrValue(pos) != null ? Colors.red : Colors.white))),

          ]),

        ]),

        const SizedBox(height: 8),

        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [

          _chartBox("平倉時間", _fmtEntryTime(pos['settledAt'])),

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

                Expanded(child: TextField(controller: cs['lev'], decoration: const InputDecoration(labelText: "槓桿"), keyboardType: const TextInputType.numberWithOptions(decimal: true))),

                const SizedBox(width: 10),

                Expanded(child: TextField(controller: cs['val'], decoration: const InputDecoration(labelText: "倉位 (U)"), keyboardType: const TextInputType.numberWithOptions(decimal: true))),

              ]),

              TextField(controller: cs['ent'], decoration: const InputDecoration(labelText: "進場價"), keyboardType: const TextInputType.numberWithOptions(decimal: true)),

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

              TextField(controller: cs['tp1'], decoration: const InputDecoration(labelText: "TP1（必填）出場 50%，僅設 TP1 時為全出 100%"), keyboardType: const TextInputType.numberWithOptions(decimal: true)),

              Row(children: [

                Expanded(child: TextField(controller: cs['tp2'], decoration: const InputDecoration(labelText: "TP2（選填）出場 25%，僅設 TP1+TP2 時為 50%"), keyboardType: const TextInputType.numberWithOptions(decimal: true))),

                const SizedBox(width: 8),

                Expanded(child: TextField(controller: cs['tp3'], decoration: const InputDecoration(labelText: "TP3（選填）出場 25%"), keyboardType: const TextInputType.numberWithOptions(decimal: true))),

              ]),

              TextField(controller: cs['sl'], decoration: const InputDecoration(labelText: "止損 SL"), keyboardType: const TextInputType.numberWithOptions(decimal: true)),

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

                    'side': isLong ? 'long' : 'short',

                    'manualEntry': true,

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

                child: const Text("開始監控", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))

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

    final isSettledEdit = pos['status'].toString().contains('止盈') || pos['status'].toString().contains('止損') || pos['status'].toString().contains('手動出場') || pos['status'].toString().contains('完全平倉') || pos['status'].toString().contains('部分平倉');

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

                Expanded(child: TextField(controller: cs['lev'], decoration: const InputDecoration(labelText: "槓桿"), keyboardType: const TextInputType.numberWithOptions(decimal: true))),

                const SizedBox(width: 10),

                Expanded(child: TextField(controller: cs['val'], decoration: const InputDecoration(labelText: "保證金"), keyboardType: const TextInputType.numberWithOptions(decimal: true))),

              ]),

              TextField(controller: cs['ent'], decoration: const InputDecoration(labelText: "進場價"), keyboardType: const TextInputType.numberWithOptions(decimal: true)),

              if (isSettledEdit) TextField(controller: cs['settledPrice'], decoration: const InputDecoration(labelText: "平倉價"), keyboardType: const TextInputType.numberWithOptions(decimal: true)),

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

              TextField(controller: cs['tp1'], decoration: const InputDecoration(labelText: "TP1（必填）出場 50%，僅設 TP1 時為全出 100%"), keyboardType: const TextInputType.numberWithOptions(decimal: true)),

              Row(children: [

                Expanded(child: TextField(controller: cs['tp2'], decoration: const InputDecoration(labelText: "TP2（選填）出場 25%，僅設 TP1+TP2 時為 50%"), keyboardType: const TextInputType.numberWithOptions(decimal: true))),

                const SizedBox(width: 8),

                Expanded(child: TextField(controller: cs['tp3'], decoration: const InputDecoration(labelText: "TP3（選填）出場 25%"), keyboardType: const TextInputType.numberWithOptions(decimal: true))),

              ]),

              TextField(controller: cs['sl'], decoration: const InputDecoration(labelText: "止損 SL"), keyboardType: const TextInputType.numberWithOptions(decimal: true)),

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

                    if (pos['exitRatioDisplay'] != null) updated['exitRatioDisplay'] = pos['exitRatioDisplay'];

                  }

                  if (pos['note'] != null) updated['note'] = pos['note'];

                  if (pos['realizedPnl'] != null) updated['realizedPnl'] = pos['realizedPnl'];

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

class _ChartDialogContent extends StatefulWidget {

  final Map<String, dynamic> pos;

  final String symbol;

  final List<Candle> initialCandles;

  final Map<String, double?> oiChanges;

  final List<String> oiPeriods;

  final bool isSettled;

  final String? proxyUrl;

  final Widget Function(BuildContext context, String interval, List<Candle> candles, String? proxyUrl) buildContent;

  const _ChartDialogContent({required this.pos, required this.symbol, required this.initialCandles, required this.oiChanges, required this.oiPeriods, required this.isSettled, this.proxyUrl, required this.buildContent});

  @override

  State<_ChartDialogContent> createState() => _ChartDialogContentState();

}

class _ChartDialogContentState extends State<_ChartDialogContent> {

  String _selectedInterval = '15m';

  late List<Candle> _candles;

  @override

  void initState() {

    super.initState();

    _candles = List.from(widget.initialCandles);

  }

  Future<void> _loadCandles(String interval) async {

    final c = await _fetchKlines(widget.symbol, interval, widget.proxyUrl);

    if (mounted) setState(() => _candles = c);

  }

  @override

  Widget build(BuildContext context) {

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      if (!widget.isSettled) Row(children: [

        const Text("週期：", style: TextStyle(color: Colors.grey, fontSize: 14)),

        const SizedBox(width: 8),

        ..._klineIntervals.map((iv) => Padding(

          padding: const EdgeInsets.only(right: 8),

          child: ChoiceChip(

            label: Text(iv),

            selected: _selectedInterval == iv,

            onSelected: (_) {

              setState(() => _selectedInterval = iv);

              if (widget.isSettled) _loadCandles(iv);

            },

          ),

        )),

      ]),

      const SizedBox(height: 8),

      Expanded(child: widget.buildContent(context, _selectedInterval, widget.isSettled ? _candles : widget.initialCandles, widget.proxyUrl)),

    ]);

  }

}

class _DetailChartLive extends StatefulWidget {

  final Map<String, dynamic> pos;

  final String symbol;

  final List<Candle> initialCandles;

  final Map<String, double?> initialOiChanges;

  final List<String> oiPeriods;

  final String interval;

  final bool isPortrait;

  final bool shrinkChartHeight;

  final String? proxyUrl;

  const _DetailChartLive({required this.pos, required this.symbol, required this.initialCandles, required this.initialOiChanges, required this.oiPeriods, required this.interval, this.isPortrait = false, this.shrinkChartHeight = false, this.proxyUrl});

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

  @override

  void didUpdateWidget(covariant _DetailChartLive oldWidget) {

    super.didUpdateWidget(oldWidget);

    if (oldWidget.interval != widget.interval) _refresh();

  }

  Future<void> _refresh() async {

    final c = await _fetchKlines(widget.symbol, widget.interval, widget.proxyUrl);

    final oi = <String, double?>{};

    await Future.wait(widget.oiPeriods.map((p) async => oi[p] = await _fetchOiChange(widget.symbol, p, widget.proxyUrl)));

    if (!mounted) return;

    setState(() { candles = c; oiChanges = oi; });

  }

  @override

  Widget build(BuildContext context) {

    final pos = widget.pos;

    return Column(children: [

      Row(children: [
        Flexible(child: Text("${widget.symbol} ${widget.interval} K線${candles.isEmpty ? ' · K 線載入失敗，僅顯示進出場線' : ''}", style: const TextStyle(color: Color(0xFFFFC0CB), fontSize: 20))),
        if (candles.isEmpty)
          TextButton(
            onPressed: () => _refresh(),
            child: const Text('重試', style: TextStyle(color: Color(0xFFFFC0CB), fontSize: 14)),
          ),
      ]),

      Expanded(flex: widget.shrinkChartHeight ? 2 : 3, child: _buildKlineChartCore(candles: candles, pos: pos, interval: widget.interval)),

      widget.shrinkChartHeight
          ? Expanded(
              flex: 2,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 200),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _chartOiGrid(widget.oiPeriods, oiChanges, isPortrait: widget.isPortrait),
                        ),
                        _chartPositionSummary(pos, isPortrait: widget.isPortrait),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : SizedBox(
              height: 180,
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _chartOiGrid(widget.oiPeriods, oiChanges, isPortrait: widget.isPortrait),
                        ),
                        _chartPositionSummary(pos, isPortrait: widget.isPortrait),
                    ],
                  ),
                ),
              ),
            ),

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