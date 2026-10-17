import { validCommand, shouldInclude, mediaSummary, inspectMedia } from './protocol.js';

const HOST = 'com.audiohub.edge';
let port;
let seen = new Set();
const generations = new Map();
let refreshTimer;
let refreshing = false;
let refreshAgain = false;
const ready = chrome.storage.session.get('seen').then(state => { seen = new Set(state.seen ?? []); });

function connect() {
  if (port) return;
  const connection = chrome.runtime.connectNative(HOST);
  port = connection;
  connection.onDisconnect.addListener(() => {
    void chrome.runtime.lastError;
    if (port === connection) port = null;
    chrome.action.setBadgeText({ text: '离线' });
  });
  connection.onMessage.addListener(message => execute(message, connection));
  chrome.action.setBadgeText({ text: '' });
  schedule();
}

function schedule() {
  clearTimeout(refreshTimer);
  refreshTimer = setTimeout(refresh, 180);
}

async function media(tabId, value = null) {
  return chrome.scripting.executeScript({ target: { tabId, allFrames: true }, func: inspectMedia, args: [value] });
}

async function refresh() {
  await ready;
  if (refreshing) { refreshAgain = true; return; }
  if (!port) return;
  refreshing = true;
  try {
    const all = await chrome.tabs.query({});
    const live = new Set(all.map(t => t.id));
    seen = new Set([...seen].filter(id => live.has(id)));
    const tabs = [];
    for (const tab of all.filter(t => shouldInclude(t, seen))) {
      seen.add(tab.id);
      if (!generations.has(tab.id)) generations.set(tab.id, crypto.randomUUID());
      const generation = generations.get(tab.id);
      let summary = { canVolume: false, volume: 0, mixed: false };
      let status = '仅支持标签页静音：未发现可控制的普通媒体';
      try {
        const frames = await media(tab.id);
        summary = mediaSummary(frames);
        if (summary.canVolume) {
          status = summary.mixed ? '多个媒体音量不同；拖动后统一设置' : '控制普通音视频音量；不包含纯 Web Audio';
          if (frames.some(f => f.result?.hasFrames)) status += '；嵌入页面覆盖需验证';
          if (frames.some(f => f.result?.elementMuted)) status += '；播放器自身已静音';
        }
      } catch { status = '仅支持标签页静音：页面权限不足或受浏览器限制'; }
      let domain = '';
      try { domain = new URL(tab.url).hostname; } catch { /* Restricted tab. */ }
      if (generation !== generations.get(tab.id)) { refreshAgain = true; continue; }
      tabs.push({ id: tab.id, generation, title: (tab.title || '网页').slice(0, 512), domain,
        favicon: tab.favIconUrl || '', muted: !!tab.mutedInfo?.muted, audible: !!tab.audible, ...summary, status });
    }
    await chrome.storage.session.set({ seen: [...seen] });
    port?.postMessage({ version: 1, type: 'snapshot', tabs });
  } catch { /* The connection or a tab may disappear during enumeration. */ }
  finally {
    refreshing = false;
    if (refreshAgain) { refreshAgain = false; schedule(); }
  }
}

// Serialize commands to prevent a slow earlier slider operation overtaking a newer one.
let commands = Promise.resolve();
function execute(message, connection) {
  if (!validCommand(message)) return;
  commands = commands.then(async () => {
    await ready;
    let ok = false;
    let error = '';
    try {
      if (!seen.has(message.tabId)) throw new Error('音源已关闭或尚未发现');
      if (message.generation !== generations.get(message.tabId)) throw new Error('网页已导航，请刷新状态后重试');
      if (message.action === 'mute') {
        const tab = await chrome.tabs.update(message.tabId, { muted: message.value });
        ok = tab.mutedInfo?.muted === message.value;
      } else {
        const result = mediaSummary(await media(message.tabId, message.value));
        ok = result.canVolume && !result.mixed && Math.abs(result.volume - message.value) < 0.1;
      }
      if (!ok) error = '页面未确认设置；可能没有普通媒体或播放器已覆盖音量';
    } catch { error = '设置失败：网页已关闭、无权限或媒体不支持'; }
    try { connection.postMessage({ version: 1, type: 'result', requestId: message.requestId,
      tabId: message.tabId, ok, error }); } catch { /* Host closed. */ }
    schedule();
  });
}

chrome.tabs.onUpdated.addListener((id, change) => {
  if (change.status === 'loading' || change.url) generations.set(id, crypto.randomUUID());
  schedule();
});
chrome.tabs.onRemoved.addListener(id => { generations.delete(id); seen.delete(id); schedule(); });
chrome.tabs.onReplaced.addListener(schedule);
chrome.runtime.onMessage.addListener((message, sender) => {
  if (message?.type === 'mediaChanged' && sender.tab) schedule();
});
chrome.action.onClicked.addListener(() => { connect(); schedule(); });
chrome.alarms.onAlarm.addListener(() => { connect(); schedule(); });
chrome.alarms.create('reconnect', { periodInMinutes: 0.5 });
connect();
