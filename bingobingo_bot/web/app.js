/**
 * 賓果賓果「最容易出現的 3 個號碼」— 邏輯架構
 *
 * 【資料約定】
 * - 開獎資料：draws = [ 第0期, 第1期, ... ]，每期 = 長度 20 的陣列（1~80 不重複）
 * - 時間順序：draws[0] = 最新一期，draws[1] = 上一期，… 依此類推（新→舊）
 *
 * 【預測邏輯】
 * 1. 加權頻率：越近的期數權重越高（衰減 WEIGHT_DECAY^期距），凸顯近期熱號
 * 2. 馬可夫加分：若該號在「最新一期」有開，分數 +MARKOV_BONUS（延續性）
 * 3. 冷號加分：若該號在最近 COLD_GAP 期都沒開，分數 +COLD_BONUS（預設 0=關閉）
 * 4. 分數 = 加權頻率 + 馬可夫 + 冷號，取最高 3 個，由小到大輸出
 * 預設參數為學習結果（真實歷史回測達 7%+）：0.95, 0.3, 0, 5
 *
 * 【資料來源】
 * - 更新開獎：從 https://twlottery.in/lotteryBingo 抓 HTML，解析出多期，順序為頁面順（最新在前）
 * - 自訂資料：使用者貼上，每行一期，第一行視為最新一期
 * - 內建／JSON：無真實時間則僅供示範
 */

(function () {
  "use strict";

  var NUM_RANGE = 80;
  var NUM_PER_DRAW = 20;
  var TOP_N = 3;
  var MIN_DRAWS = 30;
  var WEIGHT_DECAY = 0.95;
  var MARKOV_BONUS = 0.3;
  var COLD_BONUS = 0;
  var COLD_GAP = 5;

  var currentDraws = [];
  var currentPredictedPeriod = null;

  function applyLearnedParams(p) {
    if (p && typeof p.weight_decay === "number") WEIGHT_DECAY = p.weight_decay;
    if (p && typeof p.markov_bonus === "number") MARKOV_BONUS = p.markov_bonus;
    if (p && typeof p.cold_bonus === "number") COLD_BONUS = p.cold_bonus;
    if (p && typeof p.cold_gap === "number") COLD_GAP = p.cold_gap;
  }

  var LOTTERY_URL = "https://twlottery.in/lotteryBingo";
  var CORS_RAW = "https://api.allorigins.win/raw?url=";
  var CORS_GET = "https://api.allorigins.win/get?url=";

  // ========== 資料來源 ==========

  /** 內建範例：50 期模擬開獎，draws[0]=最新… */
  function getDefaultDraws() {
    var draws = [];
    var seed = 42;
    function rand() {
      seed = (seed * 1103515245 + 12345) >>> 0;
      return seed / 4294967296;
    }
    for (var i = 0; i < 50; i++) {
      var arr = [];
      for (var n = 1; n <= NUM_RANGE; n++) arr.push(n);
      for (var k = NUM_RANGE - 1; k >= 0; k--) {
        var j = Math.floor(rand() * (k + 1));
        var t = arr[k]; arr[k] = arr[j]; arr[j] = t;
      }
      draws.push(arr.slice(0, NUM_PER_DRAW).sort(function (a, b) { return a - b; }));
    }
    return draws;
  }

  /** 從使用者貼文解析：每行一期、第一行=最新一期 */
  function parseCustomInput(text) {
    var lines = text.trim().split(/\n/).filter(Boolean);
    var draws = [];
    for (var i = 0; i < lines.length; i++) {
      var raw = lines[i].split(/[\s,，、]+/).map(Number).filter(function (n) { return n >= 1 && n <= NUM_RANGE; });
      var seen = {};
      var one = [];
      for (var j = 0; j < raw.length && one.length < NUM_PER_DRAW; j++) {
        if (!seen[raw[j]]) { seen[raw[j]] = true; one.push(raw[j]); }
      }
      if (one.length >= NUM_PER_DRAW) {
        draws.push(one.slice(0, NUM_PER_DRAW).sort(function (a, b) { return a - b; }));
      }
    }
    return draws;
  }

  /** 從 twlottery.in 頁面 HTML 解析：頁面順=新→舊，回傳 { draws, latestPeriod } */
  function parseDrawsFromHtml(html) {
    var draws = [];
    var latestPeriod = null;
    var numRe = /\b(?:[1-9]|[1-7]\d|80)\b/g;
    var blockRe = /(\d{8,})\s*期\s*([\s\S]*?)(?=\d{8,}\s*期|$)/gi;
    var m;
    while ((m = blockRe.exec(html)) !== null) {
      if (latestPeriod === null) latestPeriod = m[1];
      var block = m[2];
      var nums = [];
      var seen = {};
      numRe.lastIndex = 0;
      var numMatch;
      while ((numMatch = numRe.exec(block)) !== null && nums.length < NUM_PER_DRAW) {
        var n = parseInt(numMatch[0], 10);
        if (!seen[n]) { seen[n] = true; nums.push(n); }
      }
      if (nums.length === NUM_PER_DRAW) {
        draws.push(nums.sort(function (a, b) { return a - b; }));
      }
    }
    if (draws.length > 0) return { draws: draws, latestPeriod: latestPeriod };
    var periodRe = /\d{8,}/g;
    var positions = [];
    var pm;
    while ((pm = periodRe.exec(html)) !== null) positions.push({ i: pm.index, num: pm[0] });
    for (var k = 0; k < positions.length - 1; k++) {
      var start = positions[k].i + positions[k].num.length;
      var end = positions[k + 1].i;
      if (end - start < 50) continue;
      numRe.lastIndex = 0;
      var nums = [];
      var seen = {};
      var seg = html.slice(start, end);
      var numMatch;
      while ((numMatch = numRe.exec(seg)) !== null && nums.length < NUM_PER_DRAW) {
        var n = parseInt(numMatch[0], 10);
        if (!seen[n]) { seen[n] = true; nums.push(n); }
      }
      if (nums.length === NUM_PER_DRAW) {
        draws.push(nums.sort(function (a, b) { return a - b; }));
        if (latestPeriod === null) latestPeriod = positions[k].num;
      }
    }
    if (latestPeriod === null && positions.length > 0) latestPeriod = positions[0].num;
    return { draws: draws, latestPeriod: latestPeriod };
  }

  // ========== 預測：頻率 + 馬可夫加分 ==========

  /**
   * 輸入 draws（draws[0]=最新）。輸出 TOP_N 個號碼（由小到大）。
   * 加權頻率（近期權重高）+ 馬可夫加分 + 冷號加分
   */
  function computeTop3(draws) {
    if (!draws || draws.length < MIN_DRAWS) return null;
    var weighted = Array(NUM_RANGE + 1).fill(0);
    var newest = draws[0];
    var inNewest = {};
    for (var i = 0; i < newest.length; i++) inNewest[newest[i]] = true;
    for (var d = 0; d < draws.length; d++) {
      var w = Math.pow(WEIGHT_DECAY, d);
      for (var j = 0; j < draws[d].length; j++) {
        var n = draws[d][j];
        if (n >= 1 && n <= NUM_RANGE) weighted[n] += w;
      }
    }
    var list = [];
    for (var num = 1; num <= NUM_RANGE; num++) {
      var score = weighted[num];
      if (inNewest[num]) score += MARKOV_BONUS;
      var gap = 0;
      for (var d = 0; d < draws.length; d++) {
        var found = false;
        for (var j = 0; j < draws[d].length; j++) { if (draws[d][j] === num) { found = true; break; } }
        if (found) break;
        gap++;
      }
      if (gap > COLD_GAP) score += COLD_BONUS;
      list.push({ num: num, score: score });
    }
    list.sort(function (a, b) { return b.score - a.score; });
    return list.slice(0, TOP_N).map(function (x) { return x.num; }).sort(function (a, b) { return a - b; });
  }

  // ========== UI ==========

  function showResult(numbers) {
    var b1 = document.getElementById("b1");
    var b2 = document.getElementById("b2");
    var b3 = document.getElementById("b3");
    [b1, b2, b3].forEach(function (el) { el.textContent = "—"; el.classList.add("empty"); });
    if (numbers && numbers.length >= TOP_N) {
      b1.textContent = numbers[0];
      b2.textContent = numbers[1];
      b3.textContent = numbers[2];
      [b1, b2, b3].forEach(function (el) { el.classList.remove("empty"); });
    }
  }

  function updatePeriodDisplay() {
    var el = document.getElementById("predictedPeriod");
    if (el) el.textContent = currentPredictedPeriod != null ? String(currentPredictedPeriod) : "—";
  }

  function setStatus(msg, isError) {
    var el = document.getElementById("updateStatus");
    if (!el) return;
    el.textContent = msg || "";
    el.style.color = isError ? "#e94560" : "var(--text-muted)";
  }

  function runPrediction() {
    var top3 = computeTop3(currentDraws);
    showResult(top3);
    updatePeriodDisplay();
    return top3;
  }

  function fetchHtml(url, asJson) {
    return fetch(url).then(function (r) { return r.text(); }).then(function (body) {
      if (!asJson) return body;
      try {
        var data = JSON.parse(body);
        return (data && data.contents) ? data.contents : body;
      } catch (e) { return body; }
    });
  }

  document.getElementById("btnPredict").addEventListener("click", function () {
    runPrediction();
  });

  document.getElementById("btnUpdate").addEventListener("click", function () {
    var btn = this;
    var origText = btn.textContent;
    btn.disabled = true;
    btn.textContent = "擷取中…";
    setStatus("");
    var urlRaw = CORS_RAW + encodeURIComponent(LOTTERY_URL);
    var urlGet = CORS_GET + encodeURIComponent(LOTTERY_URL);
    function apply(html) {
      var parsed = parseDrawsFromHtml(html);
      var draws = parsed.draws;
      if (parsed.latestPeriod != null) currentPredictedPeriod = parseInt(parsed.latestPeriod, 10) + 1;
      if (draws.length >= MIN_DRAWS) {
        currentDraws = draws;
        runPrediction();
        setStatus("已從 twlottery.in 更新 " + draws.length + " 筆開獎，並重新計算預測。");
      } else {
        setStatus("無法解析足夠期數（目前 " + (draws.length || 0) + " 期）。請用 localhost／部署後再試或使用自訂資料。", true);
        if (draws.length > 0) { currentDraws = draws; runPrediction(); }
      }
      return draws.length;
    }
    fetchHtml(urlRaw, false)
      .then(function (html) {
        var n = apply(html);
        if (n === 0) return fetchHtml(urlGet, true).then(apply);
      })
      .catch(function () {
        setStatus("擷取失敗。請檢查網路或使用自訂資料。", true);
      })
      .then(function () {
        btn.disabled = false;
        btn.textContent = origText;
      });
  });

  document.getElementById("btnUseCustom").addEventListener("click", function () {
    var text = document.getElementById("customData").value;
    var draws = parseCustomInput(text);
    if (draws.length >= MIN_DRAWS) {
      currentDraws = draws;
      currentPredictedPeriod = null;
      runPrediction();
    } else {
      alert("請貼上至少 " + MIN_DRAWS + " 期開獎資料，每期 20 個不重複號碼（1～80）。");
    }
  });

  function loadJson(path, cb) {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", path, true);
    xhr.onload = function () {
      if (xhr.status !== 200) return cb(new Error("network"));
      try {
        var data = JSON.parse(xhr.responseText);
        if (Array.isArray(data) && data.length >= MIN_DRAWS) {
          currentDraws = data;
          return cb(null, data);
        }
      } catch (e) {}
      cb(new Error("invalid"));
    };
    xhr.onerror = function () { cb(new Error("network")); };
    xhr.send();
  }

  currentDraws = getDefaultDraws();
  var base = (document.querySelector("script[src='app.js']") || {}).src.replace(/\/?app\.js$/i, "") || ".";
  loadJson(base + "/best_params.json", function (err, data) {
    if (!err && data && data.params) applyLearnedParams(data.params);
    loadJson(base + "/recent_draws.json", function (err2) {
      if (err2) currentDraws = getDefaultDraws();
      runPrediction();
    });
  });
})();
