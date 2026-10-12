// Вставте цей файл цілком у консоль браузера на сторінці уроку Kwiga.
// Скрипт лишається активним: щойно плеєр запросить нове відео,
// у консолі з'явиться рядок, який можна вставити в кінець download.sh:
//   download "https://media.kwigacdn.com/.../video_1080p.mp4.m3u8"
//
// 360p і 1080p одного уроку зливаються в одне найкраще посилання.
// Сегменти seg-*.ts самі по собі не друкуються, якщо є m3u8.
// Зупинити: __kwigaTrack.stop()
// Скопіювати всі рядки: copy(videoLinks.join("\n"))

(() => {
  if (window.__kwigaTrack && window.__kwigaTrack.stop) window.__kwigaTrack.stop();

  const DELAY = 1200;
  const groups = new Map();
  const timers = new Map();
  window.videoLinks = window.videoLinks || [];

  const origFetch = window.fetch;
  const origOpen = XMLHttpRequest.prototype.open;
  const origSend = XMLHttpRequest.prototype.send;
  let observer = null;
  let domObserver = null;

  function analyze(raw) {
    let url;
    try {
      url = new URL(raw, location.href);
    } catch {
      return null;
    }
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    if (/^ip\d+\.media\.kwigacdn\.com$/i.test(url.hostname)) return null;

    let path = url.pathname;
    try {
      path = decodeURIComponent(url.pathname);
    } catch (err) {}
    if (!/\.(m3u8|mp4|ts)$/i.test(path)) return null;
    const parts = path.split("/");
    const file = parts[parts.length - 1];
    const parent = parts[parts.length - 2] || "";

    let kind = "";
    let stem = "";
    if (/\/seg-[^/]+\.ts$/i.test(path)) {
      kind = "ts";
      stem = parent.replace(/\.mp4$/i, "");
    } else if (/index\.m3u8$/i.test(file)) {
      kind = "m3u8";
      stem = parent.replace(/\.mp4$/i, "");
    } else if (/\.m3u8$/i.test(file)) {
      kind = "m3u8";
      stem = file.replace(/\.m3u8$/i, "").replace(/\.mp4$/i, "");
    } else if (/\.mp4$/i.test(file)) {
      kind = "mp4";
      stem = file.replace(/\.mp4$/i, "");
    } else {
      return null;
    }

    if (/_TPL$/i.test(stem)) return null;

    const qualityMatch = stem.match(/_(\d{3,4})p$/i);
    const quality = qualityMatch ? Number(qualityMatch[1]) : 0;
    const base = stem.replace(/_(\d{3,4})p$/i, "");
    const folder = parts.slice(0, kind === "ts" || /index\.m3u8$/i.test(file) ? -2 : -1).join("/");
    const stableFolder = folder.replace(/\/key=[^/]+/i, "");

    return {
      href: url.href,
      kind,
      quality,
      group: stableFolder + "/" + base.toLowerCase(),
      score: quality * 10 + { m3u8: 3, mp4: 2, ts: 1 }[kind],
    };
  }

  function emit(item) {
    const line = "download " + JSON.stringify(item.href);
    if (window.videoLinks.includes(line)) return;
    item.emittedScore = item.score;
    window.videoLinks.push(line);
    console.log(line);
  }

  function flush(group) {
    const item = groups.get(group);
    if (!item) return;
    if (item.emittedScore != null && item.score <= item.emittedScore) return;
    emit(item);
  }

  function consider(raw) {
    const info = analyze(raw);
    if (!info) return;
    const prev = groups.get(info.group);
    if (!prev || info.score > prev.score) {
      groups.set(info.group, { ...prev, ...info, emittedScore: prev ? prev.emittedScore : null });
    }
    clearTimeout(timers.get(info.group));
    timers.set(info.group, setTimeout(() => flush(info.group), DELAY));
  }

  function scanDom() {
    document.querySelectorAll("video, audio, source").forEach((el) => {
      if (el.src) consider(el.src);
      if (el.currentSrc) consider(el.currentSrc);
    });
  }

  window.fetch = function (input, init) {
    try {
      consider(typeof input === "string" ? input : input && input.url);
    } catch (err) {}
    return origFetch.apply(this, arguments);
  };

  XMLHttpRequest.prototype.open = function (method, url) {
    this.__kwigaUrl = url;
    return origOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function () {
    if (this.__kwigaUrl) consider(this.__kwigaUrl);
    return origSend.apply(this, arguments);
  };

  if (typeof PerformanceObserver === "function") {
    observer = new PerformanceObserver((list) => {
      list.getEntries().forEach((entry) => consider(entry.name));
    });
    try {
      observer.observe({ type: "resource", buffered: true });
    } catch (err) {
      observer.observe({ type: "resource" });
      performance.getEntriesByType("resource").forEach((entry) => consider(entry.name));
    }
  } else if (performance && performance.getEntriesByType) {
    performance.getEntriesByType("resource").forEach((entry) => consider(entry.name));
  }

  if (typeof MutationObserver === "function") {
    domObserver = new MutationObserver(scanDom);
    domObserver.observe(document.documentElement, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["src"],
    });
  }
  scanDom();

  window.__kwigaTrack = {
    watch: consider,
    stop() {
      window.fetch = origFetch;
      XMLHttpRequest.prototype.open = origOpen;
      XMLHttpRequest.prototype.send = origSend;
      if (observer) observer.disconnect();
      if (domObserver) domObserver.disconnect();
      timers.forEach((timer) => clearTimeout(timer));
      console.log("трекер відео зупинено");
    },
  };

  console.log('Слідкую за відео. Нове посилання зʼявиться рядком download "...".');
})();
