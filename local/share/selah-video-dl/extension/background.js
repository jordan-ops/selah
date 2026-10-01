// Selah Video Downloader - service worker.
//
// Bridges Ctrl+D messages from content scripts to the native helper
// (selah_video_downloader), which runs yt-dlp and sends the start/complete
// notifications. If the helper can't be reached we fall back to a Chromium
// notification so failures are never silent.
"use strict";

const HOST = "selah_video_downloader";

function fallbackNotice(text) {
  try {
    chrome.notifications.create({
      type: "basic",
      iconUrl: "icon.png",
      title: "Video download",
      message: String(text).slice(0, 300),
    });
  } catch (_) {
    /* notifications unavailable - nothing else we can do */
  }
}

chrome.runtime.onMessage.addListener((msg) => {
  if (!msg || typeof msg.url !== "string") return;
  if (!/^https?:\/\//.test(msg.url)) return;

  let gotReply = false;
  let port;
  try {
    port = chrome.runtime.connectNative(HOST);
  } catch (e) {
    fallbackNotice("Helper could not start: " + (e && e.message ? e.message : e));
    return;
  }

  port.onMessage.addListener(() => {
    gotReply = true;
  });

  port.onDisconnect.addListener(() => {
    if (gotReply) return;
    const err = chrome.runtime.lastError;
    fallbackNotice(
      "Downloader helper not connected" +
        (err && err.message ? ": " + err.message : "")
    );
  });

  try {
    port.postMessage({
      url: msg.url,
      title: msg.title || "video",
    });
  } catch (e) {
    fallbackNotice("Helper message failed: " + (e && e.message ? e.message : e));
  }
});
