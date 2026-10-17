import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validCommand, shouldInclude, mediaSummary, inspectMedia } from '../edge/protocol.js';

test('only bounded commands are accepted', () => {
  const command = { version: 1, type: 'command', requestId: 'abc', tabId: 7, action: 'volume', value: 35 };
  assert.ok(validCommand(command));
  for (const value of [-1, 101, NaN, Infinity, '35']) assert.ok(!validCommand({ ...command, value }));
  assert.ok(!validCommand({ ...command, action: 'execute' }));
  assert.ok(!validCommand({ ...command, tabId: -1 }));
  assert.ok(validCommand({ ...command, action: 'mute', value: false }));
  assert.ok(!validCommand({ ...command, action: 'mute', value: 0 }));
});
test('muted and previously audible tabs remain recoverable', () => {
  assert.ok(shouldInclude({ id: 1, audible: true }, new Set()));
  assert.ok(shouldInclude({ id: 1, audible: false, mutedInfo: { muted: true } }, new Set()));
  assert.ok(shouldInclude({ id: 1, audible: false }, new Set([1])));
  assert.ok(!shouldInclude({ id: 2, audible: false }, new Set([1])));
});
test('media coverage and mixed volumes are reported honestly', () => {
  assert.equal(mediaSummary([]).canVolume, false);
  const summary = mediaSummary([{ result: { values: [0.2, 0.7] } }, { result: { values: [0.2] } }]);
  assert.equal(summary.mixed, true);
  assert.equal(summary.volume, 20);
  assert.equal(mediaSummary([{ result: { values: [0.4, 0.4] } }]).mixed, false);
});
test('volume operations do not pause or unmute media', () => {
  const media = { volume: 0.7, muted: true, paused: false, currentTime: 123 };
  globalThis.document = { querySelectorAll: selector => selector === 'audio,video' ? [media] : [], querySelector: () => null };
  inspectMedia(null);
  assert.equal(media.volume, 0.7);
  inspectMedia(25);
  assert.deepEqual(media, { volume: 0.25, muted: true, paused: false, currentTime: 123 });
  delete globalThis.document;
});
