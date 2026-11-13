// TEST PAGE — fake data only. Storage keys get a prefix so the real scan page's login is never touched.
(function () {
  var P = "TEST_", S = Storage.prototype, g = S.getItem, s = S.setItem, r = S.removeItem;
  S.getItem = function (k) { return g.call(this, P + k); };
  S.setItem = function (k, v) { return s.call(this, P + k, v); };
  S.removeItem = function (k) { return r.call(this, P + k); };
  S.clear = function () { var ks = []; for (var i = 0; i < this.length; i++) { var k = this.key(i); if (k && k.indexOf(P) === 0) ks.push(k); } for (var j = 0; j < ks.length; j++) r.call(this, ks[j]); };
})();
// SILENT — the test copy makes no sound on the laptop (the real page still beeps)

// LOCAL PREVIEW ONLY — fake data, fake server (no real customers, no network)
(function () {
  if (location.hash || !localStorage.getItem("nishiki_scan_token")) { try { localStorage.clear(); localStorage.setItem("nishiki_scan_d", "AKfycbMOCKxxxxxxxxxxxxxxxxxxxxx"); localStorage.setItem("nishiki_scan_token", "abcdef0123456789abcdef0123456789"); localStorage.setItem("nishiki_scan_user", "テスト"); localStorage.setItem("nishiki_scan_clients", JSON.stringify([{ number: "99", name: "サンプル冷凍" }, { number: "98", name: "テスト食品" }, { number: "27", name: "サンプル水産" }, { number: "55", name: "テスト冷蔵" }])); } catch (e) {} }   // DEMO_SEED
  var CL = [{ number: "99", name: "サンプル冷凍" }, { number: "98", name: "テスト食品" }, { number: "27", name: "サンプル水産" }, { number: "55", name: "テスト冷蔵" }];
  var DB = { "99": { "10000": ["冷凍えび 30尾 1kg", "5R'", "8", 0, "ケース", "2026/10/01", "20"], "10001": ["冷凍えび 30尾 1kg", "7A", "48", 0, "ケース", "2026/10/28", "60", "大"], "10002": ["いか リング 500g", "7A", "12", 0, "ケース", "2026/10/15", "40"],
                     "10003": ["さば フィレ 10kg", "85", "30", 8, "ボール", "2026/11/02", "30"] },
             "27": { "20001": ["えいひれ 10K", "7A", "120", 0, "ケース", "2026/09/01", "200"], "20002": ["えいひれ 10K", "5R'", "40", 0, "ケース", "2026/10/20", "40"], "20003": ["あたりめ 5K", "7A", "30", 0, "ケース", "2026/10/05", "30"],
                     "10005": ["いりこ 中羽 10kg", "5B", "14", 0, "ケース", "2026/11/03", "14"] },
             "55": { "30001": ["えだまめ 500g×20", "7C", "56", 0, "ケース", "2026/11/04", "56"] }, "98": { "20001": ["とり もも 2kg", "7A", "20", 0, "ケース", "2026/09/30", "20"] } };
  var ZERO = { "99": { "10009": ["ほたて 貝柱 1kg", "8-01", "0", 0, "ケース", "2026/08/01", "10"] } };
  function item(c, id, a) { return { number: id, name: a[0], location: a[1], stock: a[2], yoyakuQty: a[3], nishikata: a[4], nyukoDate: a[5], nyukoQty: a[6], note: a[7] || "" }; }
  window.MOCK = { calls: [], failNext: 0, stockBump: {}, picks: {}, offline: false };
  function mockPicks(day) { return window.MOCK.picks[day] || (window.MOCK.picks[day] = {}); }
  var real = window.fetch;
  window.fetch = function (url, opt) {
    var u = new URL(url, location.href);
    if (u.hostname !== "script.google.com") return real.apply(this, arguments);
    window.MOCK.calls.push((opt && opt.method) || "GET");
    var p = Object.fromEntries(u.searchParams.entries()), body;
    if (u.searchParams.has("c") || u.searchParams.has("sid")) return Promise.resolve(new Response("<!DOCTYPE html>400 Bad Request", { status: 400 }));   // like Google
    p.c = p.client;
    if (opt && opt.method === "POST") {
      var b = JSON.parse(opt.body);
      if (window.MOCK.offline) return Promise.reject(new TypeError("Load failed"));
      if (b.api === "pick") {
        var P = mockPicks(b.date), m = P[b.key] || (P[b.key] = {});
        if (b.on) m[b.id] = { at: Date.now(), by: "テスト", hand: !!b.hand }; else delete m[b.id];
        return new Promise(function (res) { setTimeout(function () { res(new Response(JSON.stringify({ ok: true, key: b.key, lines: m }), { status: 200 })); }, 300); });
      }
      body = (b.user === "test" && b.pass === "1234") ? { ok: true, user: "テスト", token: "abcdef0123456789abcdef0123456789" } : { ok: false, error: "名前 か パスワードが ちがいます" };
    } else if (p.t !== "abcdef0123456789abcdef0123456789") body = { ok: false, auth: false, error: "この 端末は 登録されていません" };
    else if (p.api === "clients") body = { ok: true, user: "テスト", clients: CL };
    else if (p.api === "list") body = { ok: true, c: p.c, at: Date.now(), items: Object.keys(DB[p.c] || {}).map(function (id) { return item(p.c, id, DB[p.c][id]); }) };
    else if (p.api === "item") {
      var a = (DB[p.c] || {})[p.id] || (ZERO[p.c] || {})[p.id];
      var it = a ? item(p.c, p.id, a) : null;
      if (it && window.MOCK.stockBump[p.id]) it.stock = String(Number(it.stock) - window.MOCK.stockBump[p.id]);
      body = { ok: true, c: p.c, id: p.id, item: it };
    }
    else if (p.api === "kiroku") {
      var a2 = (DB[p.c] || {})[p.id] || (ZERO[p.c] || {})[p.id];
      body = a2 ? { ok: true, kiroku: { entry: { date: a2[5], qty: a2[6] },
        out: [["2026/11/01", 12, String(Number(a2[6]) - 12), "ヤマト", "本店", "佐藤", "D-0912", "", "", "09:30", "S-1"],
              ["2026/11/03", 0, String(Number(a2[6]) - 12), "", "", "鈴木", "", "", "", "14:05", ""],
              ["2026/11/04", 5, String(Number(a2[6]) - 17), "西濃", "大阪支店", "佐藤", "D-0950", "x", "予約", "10:12", "S-2"]],
        edit: [["2026/11/02 08:40", "名前", "えび", a2[0], "菊池"]],
        loc: [{ datetime: "2026/11/05 16:20", kind: "部屋移動", oldLocation: "6-01", newLocation: a2[1], qty: "10", changedBy: "佐藤" },
              { datetime: "2026/10/28 11:00", kind: "", oldLocation: "", newLocation: "6-01", qty: "", changedBy: "鈴木" }] } }
        : { ok: true, kiroku: { entry: null, out: [], edit: [], loc: [] } };
    }
    else if (p.api === "picks") body = { ok: true, date: p.date, picks: mockPicks(p.date) };
    else if (p.api === "shukko") {
      var d = new Date(), today = d.getFullYear() + "/" + ("0" + (d.getMonth() + 1)).slice(-2) + "/" + ("0" + d.getDate()).slice(-2);
      var L = function (c, id, q) { var a3 = DB[c][id]; return { id: id, name: a3[0], qty: q, left: String(Number(a3[2]) - q), loc: a3[1], nyukoDate: a3[5], yoyaku: id === "10003", sid: "S" + id }; };
      body = { ok: true, date: p.date, picks: mockPicks(p.date), slips: p.date !== today ? [] : [
        { key: "27_a", c: "27", client: "27. サンプル水産", time: "09:00", unso: "ヤマト", hikitori: "東京店", tantou: "高部", slipId: "D-1", lines: [L("27", "20001", 24), L("27", "10005", 3)] },
        { key: "99_a", c: "99", client: "99. サンプル冷凍", time: "09:30", unso: "ヤマト", hikitori: "本店", tantou: "佐藤", slipId: "D-2", lines: [L("99", "10001", 12), L("99", "10002", 5), L("99", "10003", 3)] },
        { key: "27_b", c: "27", client: "27. サンプル水産", time: "10:00", unso: "西濃", hikitori: "大阪店", tantou: "三谷", slipId: "D-3", lines: [L("27", "20001", 30), L("27", "20003", 6)] },
        { key: "98_a", c: "98", client: "98. テスト食品", time: "10:15", unso: "西濃", hikitori: "大阪支店", tantou: "鈴木", slipId: "D-4", lines: [L("98", "20001", 4)] },
        { key: "27_c", c: "27", client: "27. サンプル水産", time: "11:00", unso: "ヤマト", hikitori: "東京店", tantou: "高部", slipId: "D-5", lines: [L("27", "20001", 12)] },
        { key: "99_b", c: "99", client: "99. サンプル冷凍", time: "13:00", unso: "自社便", hikitori: "直送", tantou: "三谷", slipId: "D-6", lines: [L("99", "10001", 20)] },
        { key: "27_d", c: "27", client: "27. サンプル水産", time: "13:30", unso: "福山", hikitori: "名古屋店", tantou: "西原", slipId: "D-7", lines: [L("27", "20003", 2)] },
        { key: "99_c", c: "99", client: "99. サンプル冷凍", time: "14:00", unso: "ヤマト", hikitori: "本店", tantou: "鈴木", slipId: "D-8", lines: [L("99", "10002", 2)] }] };
    }
    var html = window.MOCK.failNext > 0;
    if (html) window.MOCK.failNext--;
    var txt = html ? "<html>We're sorry, a server error occurred while reading from storage. Error code INTERNAL.</html>" : JSON.stringify(body);
    return new Promise(function (res) { setTimeout(function () { res(new Response(txt, { status: 200 })); }, p.api === "list" ? 900 : 500); });
  };
})();

// ── テスト スキャン — ラベルを 読んだ ことに する ボタン（mock だけ）──
window.addEventListener("load", function () {
  var CODES = [["27-20001", "えいひれ 10K（9/1 入庫・3枚の 伝票）"], ["27-20002", "えいひれ 10K（10/20 入庫 — 入庫日 ちがい）"], ["27-20003", "あたりめ 5K（2枚の 伝票）"], ["27-10005", "いりこ 3（10 より 少ない）"],
               ["99-10001", "冷凍えび（2枚の 伝票）"], ["99-10002", "いか リング（2枚の 伝票）"], ["99-10003", "さば 3"], ["98-20001", "とり もも 4"], ["55-30001", "伝票に ない 商品"]];
  var st = document.createElement("style");
  st.textContent = "#tsBtn{position:fixed;left:8px;bottom:8px;z-index:99999;background:#1d2422;color:#fff;border:0;border-radius:999px;padding:10px 14px;font:700 14px sans-serif;box-shadow:0 4px 14px rgba(0,0,0,.3)}" +
    "#tsBox{position:fixed;left:8px;bottom:56px;z-index:99999;background:#fff;border:2px solid #1d2422;border-radius:14px;padding:8px;width:290px;max-width:92vw;box-shadow:0 8px 24px rgba(0,0,0,.3);display:none}" +
    "#tsBox.on{display:block}#tsBox button{display:block;width:100%;text-align:left;border:1px solid #c8d3cf;background:#f7faf9;border-radius:10px;padding:8px 10px;margin-top:6px;font:500 13px sans-serif;color:#1f2a27}" +
    "#tsBox button b{font-size:15px;margin-right:6px}#tsBox .h{font:700 12px sans-serif;color:#6b7280}#tsBox .x{background:#fff;color:#b3261e;text-align:center}";
  document.head.appendChild(st);
  var btn = document.createElement("button"); btn.id = "tsBtn"; btn.type = "button"; btn.textContent = "🧪 テスト スキャン";
  var box = document.createElement("div"); box.id = "tsBox";
  box.innerHTML = '<div class="h">ラベルを 読んだ ことに する（にせの データ）</div>' + CODES.map(function (c) { return '<button type="button" data-c="' + c[0] + '"><b>' + c[0] + "</b>" + c[1] + "</button>"; }).join("") +
    '<button type="button" class="x" data-reset="1">↺ 全部 やり直す（テストを 最初から）</button>';
  document.body.appendChild(box); document.body.appendChild(btn);
  btn.addEventListener("click", function () { box.classList.toggle("on"); });
  box.addEventListener("click", function (e) {
    var b = e.target.closest("button"); if (!b) return;
    if (b.getAttribute("data-reset")) { try { localStorage.clear(); } catch (x) {} location.reload(); return; }
    box.classList.remove("on");
    var i = document.getElementById("scanIn"); i.value = b.getAttribute("data-c");
    i.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
  });
});
