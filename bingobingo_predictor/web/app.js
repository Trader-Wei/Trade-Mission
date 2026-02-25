(function () {
  "use strict";

  var NUM_RANGE = 80;
  var TOP_N = 3;
  var MIN_DRAWS = 30;
  var LOOKBACK = 50;

  // 內建範例資料：50 期模擬開獎（每期 20 個不重複 1~80）
  function defaultDraws() {
    var draws = [];
    var seed = 42;
    function mulberry32() {
      var t = (seed += 0x6d2b79f5);
      return (t - (t >>> 0)) / 4294967296;
    }
    for (var i = 0; i < 50; i++) {
      var arr = [];
      for (var n = 1; n <= NUM_RANGE; n++) arr.push(n);
      for (var k = NUM_RANGE - 1; k > 0; k--) {
        var j = Math.floor(mulberry32() * (k + 1));
        var tmp = arr[k];
        arr[k] = arr[j];
        arr[j] = tmp;
      }
      draws.push(arr.slice(0, 20).sort(function (a, b) { return a - b; }));
    }
    return draws;
  }

  function parseCustomInput(text) {
    var lines = text.trim().split(/\n/).filter(Boolean);
    var draws = [];
    for (var i = 0; i < lines.length; i++) {
      var nums = lines[i].split(/[\s,，、]+/).map(Number).filter(function (n) { return n >= 1 && n <= NUM_RANGE; });
      var seen = {};
      var uniq = [];
      for (var j = 0; j < nums.length; j++) {
        if (!seen[nums[j]]) {
          seen[nums[j]] = true;
          uniq.push(nums[j]);
        }
      }
      if (uniq.length >= 20) draws.push(uniq.slice(0, 20).sort(function (a, b) { return a - b; }));
    }
    return draws;
  }

  /** 依頻率 + 上期是否出現（簡易馬可夫）計算分數，回傳最容易出現的 3 個號碼 */
  function computeTop3(draws) {
    if (!draws || draws.length < MIN_DRAWS) return null;
    var use = draws.slice(-LOOKBACK);
    var freq = Array(NUM_RANGE + 1).fill(0);
    var lastDraw = use[use.length - 1];
    var lastSet = {};
    for (var i = 0; i < lastDraw.length; i++) lastSet[lastDraw[i]] = true;

    for (var d = 0; d < use.length; d++) {
      for (var k = 0; k < use[d].length; k++) {
        var n = use[d][k];
        if (n >= 1 && n <= NUM_RANGE) freq[n]++;
      }
    }

    var score = [];
    for (var num = 1; num <= NUM_RANGE; num++) {
      var s = freq[num];
      if (lastSet[num]) s += 0.5;
      score.push({ num: num, score: s });
    }
    score.sort(function (a, b) { return b.score - a.score; });
    return score.slice(0, TOP_N).map(function (x) { return x.num; }).sort(function (a, b) { return a - b; });
  }

  function showResult(numbers) {
    var b1 = document.getElementById("b1");
    var b2 = document.getElementById("b2");
    var b3 = document.getElementById("b3");
    [b1, b2, b3].forEach(function (el) {
      el.textContent = "—";
      el.classList.add("empty");
    });
    if (numbers && numbers.length >= TOP_N) {
      b1.textContent = numbers[0];
      b2.textContent = numbers[1];
      b3.textContent = numbers[2];
      [b1, b2, b3].forEach(function (el) { el.classList.remove("empty"); });
    }
  }

  function runPrediction(draws) {
    var top3 = computeTop3(draws);
    showResult(top3);
    updatePredictedPeriodDisplay();
    return top3;
  }

  var currentDraws = defaultDraws();

  var LOTTERY_URL = "https://twlottery.in/lotteryBingo";
  var CORS_RAW = "https://api.allorigins.win/raw?url=";
  var CORS_GET = "https://api.allorigins.win/get?url=";

  var numRe = /\b(?:[1-9]|[1-7]\d|80)\b/g;

  function extractTwentyFromBlock(block) {
    var nums = [];
    var seen = {};
    var numMatch;
    numRe.lastIndex = 0;
    while ((numMatch = numRe.exec(block)) !== null && nums.length < 20) {
      var n = parseInt(numMatch[0], 10);
      if (!seen[n]) {
        seen[n] = true;
        nums.push(n);
      }
    }
    return nums.length === 20 ? nums.slice(0, 20).sort(function (a, b) { return a - b; }) : null;
  }

  /** 從開獎頁 HTML 文字中解析出每期 20 個號碼（1~80）與最新期號 */
  function parseDrawsFromHtml(html) {
    var draws = [];
    var latestPeriod = null;
    var blockRe = /(\d{8,})\s*期\s*([\s\S]*?)(?=\d{8,}\s*期|$)/gi;
    var m;
    while ((m = blockRe.exec(html)) !== null) {
      if (latestPeriod === null) latestPeriod = m[1];
      var one = extractTwentyFromBlock(m[2]);
      if (one) draws.push(one);
    }
    if (draws.length > 0) {
      return { draws: draws, latestPeriod: latestPeriod };
    }
    var periodNumRe = /\d{8,}/g;
    var periodStarts = [];
    var pm;
    while ((pm = periodNumRe.exec(html)) !== null) {
      periodStarts.push({ index: pm.index, num: pm[0] });
    }
    for (var i = 0; i < periodStarts.length - 1; i++) {
      var start = periodStarts[i].index + periodStarts[i].num.length;
      var end = periodStarts[i + 1].index;
      if (end - start > 50) {
        var block = html.slice(start, end);
        var one = extractTwentyFromBlock(block);
        if (one) {
          draws.push(one);
          if (latestPeriod === null) latestPeriod = periodStarts[i].num;
        }
      }
    }
    if (draws.length > 0 && latestPeriod === null && periodStarts.length > 0) {
      latestPeriod = periodStarts[0].num;
    }
    return { draws: draws, latestPeriod: latestPeriod };
  }

  var currentPredictedPeriod = null;

  function updatePredictedPeriodDisplay() {
    var el = document.getElementById("predictedPeriod");
    if (el) el.textContent = currentPredictedPeriod != null ? String(currentPredictedPeriod) : "—";
  }

  function setUpdateStatus(msg, isError) {
    var el = document.getElementById("updateStatus");
    if (!el) return;
    el.textContent = msg || "";
    el.style.color = isError ? "#e94560" : "var(--text-muted)";
  }

  document.getElementById("btnUpdate").addEventListener("click", function () {
    var btn = this;
    var origText = btn.textContent;
    btn.disabled = true;
    btn.textContent = "擷取中…";
    setUpdateStatus("");

    function tryParse(html) {
      var parsed = parseDrawsFromHtml(html);
      var draws = parsed.draws;
      if (parsed.latestPeriod != null) {
        currentPredictedPeriod = parseInt(parsed.latestPeriod, 10) + 1;
      }
      if (draws.length >= MIN_DRAWS) {
        currentDraws = draws;
        runPrediction(currentDraws);
        setUpdateStatus("已更新 " + draws.length + " 期開獎，並重新計算預測。");
      } else {
        setUpdateStatus("無法解析足夠期數（目前 " + (draws.length || 0) + " 期）。若從本機檔案開啟，請用 localhost 或部署到網頁後再試；或使用自訂資料。", true);
        if (draws.length > 0) {
          currentDraws = draws;
          runPrediction(currentDraws);
        }
      }
      return draws.length;
    }

    function fetchHtml(url, useJson) {
      return fetch(url).then(function (res) { return res.text(); }).then(function (body) {
        if (useJson) {
          try {
            var data = JSON.parse(body);
            return (data && data.contents) ? data.contents : body;
          } catch (e) { return body; }
        }
        return body;
      });
    }

    var urlRaw = CORS_RAW + encodeURIComponent(LOTTERY_URL);
    var urlGet = CORS_GET + encodeURIComponent(LOTTERY_URL);
    fetchHtml(urlRaw, false)
      .then(function (html) {
        var count = tryParse(html);
        if (count === 0) {
          return fetchHtml(urlGet, true).then(function (html2) { tryParse(html2); });
        }
      })
      .catch(function (err) {
        setUpdateStatus("擷取失敗（若從檔案直接開啟，請改由 localhost 或部署後使用）。請檢查網路或使用自訂資料。", true);
      })
      .then(function () {
        btn.disabled = false;
        btn.textContent = origText;
      });
  });

  function loadJson(path, cb) {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", path, true);
    xhr.onload = function () {
      if (xhr.status === 200) {
        try {
          var data = JSON.parse(xhr.responseText);
          if (Array.isArray(data) && data.length >= MIN_DRAWS) {
            currentDraws = data;
            cb(null, data);
            return;
          }
        } catch (e) {}
      }
      cb(new Error("invalid"));
    };
    xhr.onerror = function () { cb(new Error("network")); };
    xhr.send();
  }

  document.getElementById("btnPredict").addEventListener("click", function () {
    runPrediction(currentDraws);
  });

  document.getElementById("btnUseCustom").addEventListener("click", function () {
    var text = document.getElementById("customData").value;
    var draws = parseCustomInput(text);
    if (draws.length >= MIN_DRAWS) {
      currentDraws = draws;
      currentPredictedPeriod = null;
      runPrediction(currentDraws);
    } else {
      alert("請貼上至少 " + MIN_DRAWS + " 期開獎資料，每期 20 個不重複號碼（1～80）。");
    }
  });

  // 嘗試載入 recent_draws.json（同目錄），失敗則用內建
  var base = document.querySelector("script[src='app.js']").src.replace(/\/?app\.js$/, "") || ".";
  loadJson(base + "/recent_draws.json", function (err) {
    if (err) currentDraws = defaultDraws();
    runPrediction(currentDraws);
  });
})();
