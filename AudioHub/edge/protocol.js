export function validCommand(message) {
  return message?.version === 1 && message.type === 'command' &&
    typeof message.requestId === 'string' && message.requestId.length <= 64 &&
    Number.isInteger(message.tabId) && message.tabId >= 0 &&
    ((message.action === 'mute' && typeof message.value === 'boolean') ||
     (message.action === 'volume' && Number.isFinite(message.value) && message.value >= 0 && message.value <= 100));
}

export function shouldInclude(tab, seen) {
  return !!(tab.audible || tab.mutedInfo?.muted || seen.has(tab.id));
}

export function mediaSummary(frames) {
  const values = frames.flatMap(frame => frame.result?.values ?? []);
  const mixed = values.length > 1 && values.some(v => Math.abs(v - values[0]) > 0.001);
  return { canVolume: values.length > 0, volume: values.length ? values[0] * 100 : 0, mixed };
}

// Serialized by scripting.executeScript: keep this function self-contained.
export function inspectMedia(value) {
  const elements = [];
  function collect(root) {
    elements.push(...root.querySelectorAll('audio,video'));
    for (const element of root.querySelectorAll('*')) {
      if (element.shadowRoot) collect(element.shadowRoot);
    }
  }
  collect(document);
  if (value !== null) for (const element of elements) element.volume = value / 100;
  return { values: elements.map(e => e.volume),
    elementMuted: elements.some(e => e.muted),
    hasFrames: !!document.querySelector('iframe,frame') };
}
