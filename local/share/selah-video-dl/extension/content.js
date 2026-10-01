// Selah Video Downloader - content script.
//
// Ctrl+D while a video is playing in this frame = "download this video".
// The keypress is swallowed so Chromium's bookmark dialog never appears.
// No video in the frame? Ctrl+D stays the normal bookmark shortcut, so
// bookmarking ordinary pages keeps working.
(() => {
  "use strict";

  function activeVideo() {
    const vids = Array.from(document.querySelectorAll("video"));
    for (const v of vids) {
      if (v.ended || v.readyState < 2) continue;
      if (!v.paused || v.currentTime > 0.5) return v;
    }
    return null;
  }

  document.addEventListener(
    "keydown",
    (e) => {
      if (!e.ctrlKey || e.shiftKey || e.altKey || e.metaKey) return;
      if (e.key !== "d" && e.key !== "D") return;
      if (!activeVideo()) return;
      e.preventDefault();
      e.stopPropagation();
      const msg = {
        url: location.href,
        title: (document.title || "video").replace(/\s+/g, " ").slice(0, 200),
      };
      try {
        chrome.runtime.sendMessage(msg);
      } catch (_) {
        /* extension context invalidated during reload - ignore */
      }
    },
    true // capture phase: beat the page's own key handlers
  );
})();
