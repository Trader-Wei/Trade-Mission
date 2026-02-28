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
 * - 更新開獎：重新載入同目錄 recent_draws.json（請先本機執行 fetch_history 或 csv_to_recent_draws 產生）
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
  var currentDrawPeriods = [];
  var currentPredictedPeriod = null;

  function applyLearnedParams(p) {
    if (p && typeof p.weight_decay === "number") WEIGHT_DECAY = p.weight_decay;
    if (p && typeof p.markov_bonus === "number") MARKOV_BONUS = p.markov_bonus;
    if (p && typeof p.cold_bonus === "number") COLD_BONUS = p.cold_bonus;
    if (p && typeof p.cold_gap === "number") COLD_GAP = p.cold_gap;
  }

  // 若有後端 API（api_server.py），請設定為例如 "http://localhost:8000"
  var API_BASE = "http://localhost:8000";

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

  function showResult(numbers, fourStar) {
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
    var fourRow = document.getElementById("fourStarRow");
    if (fourRow) {
      if (fourStar && fourStar.length >= 4) {
        fourRow.textContent = "4星推薦：" + fourStar.join("、");
      } else {
        fourRow.textContent = "4星推薦：—";
      }
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

  function updateDrawsList() {
    var meta = document.getElementById("drawsListMeta");
    var list = document.getElementById("drawsList");
    if (!list) return;
    var n = currentDraws.length;
    if (meta) meta.textContent = "共 " + n + " 期（最新在上方）";
    list.innerHTML = "";
    for (var i = 0; i < n; i++) {
      var periodLabel = (currentDrawPeriods[i] != null) ? currentDrawPeriods[i] + " 期" : "第 " + (i + 1) + " 期";
      var row = document.createElement("div");
      row.className = "draw-row";
      var periodSpan = document.createElement("span");
      periodSpan.className = "draw-period";
      periodSpan.textContent = periodLabel;
      row.appendChild(periodSpan);
      var numsWrap = document.createElement("span");
      numsWrap.className = "draw-nums";
      for (var j = 0; j < currentDraws[i].length; j++) {
        var numSpan = document.createElement("span");
        numSpan.className = "draw-num";
        numSpan.textContent = currentDraws[i][j];
        numsWrap.appendChild(numSpan);
      }
      row.appendChild(numsWrap);
      list.appendChild(row);
    }
  }

  function runPrediction() {
    var top3 = computeTop3(currentDraws);
    showResult(top3, null);
    updatePeriodDisplay();
    updateDrawsList();
    return top3;
  }

  document.getElementById("btnPredict").addEventListener("click", function () {
    runPrediction();
  });

  document.getElementById("btnUpdate").addEventListener("click", function () {
    var btn = this;
    var origText = btn.textContent;
    btn.disabled = true;
    btn.textContent = "重新載入中…";
    setStatus("");
    var base = (document.querySelector("script[src='app.js']") || {}).src.replace(/\/?app\.js$/i, "") || ".";
    var jsonPath = base + "/recent_draws.json";
    function done() {
      btn.disabled = false;
      btn.textContent = origText;
    }
    if (API_BASE) {
      var apiUrl = API_BASE.replace(/\/$/, "") + "/api/update-history?max=500";
      fetch(apiUrl, { cache: "no-store" })
        .then(function (r) { return r.json(); })
        .then(function (res) {
          if (!res || !res.ok) throw new Error("api");
          var prediction = res.prediction || null;
          loadJson(jsonPath, function (err) {
            done();
            if (err) {
              setStatus("API 已更新，但讀取 recent_draws.json 失敗。", true);
              return;
            }
            currentDrawPeriods = [];
            if (prediction && prediction.predicted_period) {
              currentPredictedPeriod = prediction.predicted_period;
            } else {
              currentPredictedPeriod = null;
            }
            if (prediction && prediction.top3) {
              showResult(prediction.top3, prediction.top4 || null);
              updatePeriodDisplay();
              updateDrawsList();
            } else {
              runPrediction();
            }
            setStatus("已從官方更新 " + currentDraws.length + " 期開獎，並重新訓練與預測。");
          });
        })
        .catch(function () {
          done();
          setStatus("無法連線到 API。改為重新載入本機 recent_draws.json。", true);
          loadJson(jsonPath, function (err) {
            if (!err) {
              currentDrawPeriods = [];
              currentPredictedPeriod = null;
              runPrediction();
              setStatus("已載入本機 " + currentDraws.length + " 期開獎。");
            }
          });
        });
      return;
    }
    loadJson(jsonPath, function (err) {
      done();
      if (err) {
        setStatus("找不到 recent_draws.json。請在本機執行：python -m bingobingo_bot.fetch_history -o web/recent_draws.json --max 500", true);
        return;
      }
      currentDrawPeriods = [];
      currentPredictedPeriod = null;
      runPrediction();
      setStatus("已重新載入 " + currentDraws.length + " 期開獎，並重新計算預測。");
    });
  });

  document.getElementById("btnUseCustom").addEventListener("click", function () {
    var text = document.getElementById("customData").value;
    var draws = parseCustomInput(text);
    if (draws.length >= MIN_DRAWS) {
      currentDraws = draws;
      currentDrawPeriods = [];
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
          currentDrawPeriods = [];
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
