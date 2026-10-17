// Runs in every permitted frame. It observes media without changing playback.
(() => {
  let timer;
  function notify() {
    clearTimeout(timer);
    timer = setTimeout(() => chrome.runtime.sendMessage({ type: 'mediaChanged' }).catch(() => {}), 150);
  }
  for (const event of ['play', 'pause', 'volumechange', 'loadedmetadata', 'emptied']) {
    document.addEventListener(event, notify, true);
  }
  new MutationObserver(records => {
    if (records.some(r => [...r.addedNodes].some(n => n.nodeType === 1 &&
      (n.matches('audio,video') || n.querySelector('audio,video'))))) notify();
  }).observe(document, { subtree: true, childList: true });
})();
