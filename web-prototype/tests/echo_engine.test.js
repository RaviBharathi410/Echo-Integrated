import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFAULT_4_FREQUENCIES,
  EXTENDED_6_FREQUENCIES,
  EQ_CENTERS_HZ,
  StrategyType,
  createHughsonWestlakeSession,
  createBinarySearchSession,
  evaluateEngineTrial,
  computeScreeningOutcome,
  getCurrentTarget,
  defaultUserProfile,
  defaultMonitorState,
  extractBaselineSummary,
  applyResultsToMonitor,
} from '../src/echo_engine.js';

test('echo_engine exposes expected frequency sets and strategy constants', () => {
  assert.deepEqual(DEFAULT_4_FREQUENCIES, [500, 1000, 2000, 4000]);
  assert.deepEqual(EXTENDED_6_FREQUENCIES, [250, 500, 1000, 2000, 4000, 8000]);
  assert.deepEqual(EQ_CENTERS_HZ, [250, 500, 1000, 2000, 4000, 6000]);
  assert.equal(StrategyType.MODIFIED_HUGHSON_WESTLAKE, 'MODIFIED_HUGHSON_WESTLAKE');
  assert.equal(StrategyType.BINARY_SEARCH_REFINEMENT, 'BINARY_SEARCH_REFINEMENT');
});

test('Modified Hughson-Westlake requires 2 ascending HEARD responses at threshold level', () => {
  let engine = createHughsonWestlakeSession({ frequenciesHz: [1000], ears: ['left'] });
  assert.equal(engine.currentLevelDb, 40);

  // Heard at 40 -> down 10 to 30
  let step = evaluateEngineTrial(engine, 'HEARD');
  assert.equal(step.action, 'NEXT_TRIAL');
  assert.equal(step.engine.currentLevelDb, 30);

  // Heard at 30 -> down 10 to 20
  step = evaluateEngineTrial(step.engine, 'HEARD');
  assert.equal(step.engine.currentLevelDb, 20);

  // Not heard at 20 -> up 5 to 25 (ascending step)
  step = evaluateEngineTrial(step.engine, 'NOT_HEARD');
  assert.equal(step.engine.currentLevelDb, 25);

  // First ascending HEARD at 25 -> down 10 to 15 (asc count at 25 = 1)
  step = evaluateEngineTrial(step.engine, 'HEARD');
  assert.equal(step.action, 'NEXT_TRIAL');
  assert.equal(step.engine.currentLevelDb, 15);

  // Not heard at 15 -> up 5 to 20
  step = evaluateEngineTrial(step.engine, 'NOT_HEARD');
  assert.equal(step.engine.currentLevelDb, 20);

  // Not heard at 20 -> up 5 to 25
  step = evaluateEngineTrial(step.engine, 'NOT_HEARD');
  assert.equal(step.engine.currentLevelDb, 25);

  // Second ascending HEARD at 25 -> threshold confirmed, single target session complete
  step = evaluateEngineTrial(step.engine, 'HEARD');
  assert.equal(step.action, 'COMPLETE');
  assert.equal(step.result.thresholdDb, 25);
  assert.equal(step.result.method, 'MODIFIED_HUGHSON_WESTLAKE');
});

test('Contaminated or interrupted trials never mutate staircase or binary bracket state', () => {
  let hw = createHughsonWestlakeSession({ frequenciesHz: [1000], ears: ['left'] });
  const hwContam = evaluateEngineTrial(hw, 'CONTAMINATED_BY_NOISE', { ambientNoiseDbFs: -22 });
  assert.equal(hwContam.action, 'RETRY');
  assert.equal(hwContam.engine.currentLevelDb, 40);
  assert.equal(hwContam.engine.targetValidTrials, 0);
  assert.equal(hwContam.engine.trials.length, 1);
  assert.equal(hwContam.engine.contaminatedTrials.length, 1);

  let bs = createBinarySearchSession({ frequenciesHz: [1000], ears: ['left'] });
  const bsInt = evaluateEngineTrial(bs, 'INVALID_INTERRUPTED');
  assert.equal(bsInt.action, 'RETRY');
  assert.equal(bsInt.engine.currentLevelDb, 40);
  assert.equal(bsInt.engine.targetValidTrials, 0);
  assert.equal(bsInt.engine.bracket.established, false);
});

test('Binary Search Refinement brackets and halves until resolution threshold is reached', () => {
  let engine = createBinarySearchSession({ frequenciesHz: [500, 1000], ears: ['left', 'right'] });
  // Target 1: left 500 Hz, starts at 40 dB
  // Heard at 40 -> down bracketStep 20 -> 20 dB
  let step = evaluateEngineTrial(engine, 'HEARD');
  assert.equal(step.action, 'NEXT_TRIAL');
  assert.equal(step.engine.currentLevelDb, 20);

  // Not heard at 20 -> bracket [20, 40], midpoint = 30
  step = evaluateEngineTrial(step.engine, 'NOT_HEARD');
  assert.equal(step.action, 'NEXT_TRIAL');
  assert.equal(step.engine.currentLevelDb, 30);

  // Heard at 30 -> bracket [20, 30], midpoint = 25
  step = evaluateEngineTrial(step.engine, 'HEARD');
  assert.equal(step.action, 'NEXT_TRIAL');
  assert.equal(step.engine.currentLevelDb, 25);

  // Not heard at 25 -> bracket [25, 30], width == 5 <= resolutionDb -> THRESHOLD_FOUND (30)
  step = evaluateEngineTrial(step.engine, 'NOT_HEARD');
  assert.equal(step.action, 'THRESHOLD_FOUND');
  assert.equal(step.result.thresholdDb, 30);
  assert.equal(step.result.method, 'BINARY_SEARCH_REFINEMENT');
  assert.deepEqual(getCurrentTarget(step.engine), { ear: 'left', frequencyHz: 1000 });
});

test('Ear transition is signaled when left ear completes and right ear begins', () => {
  let engine = createBinarySearchSession({ frequenciesHz: [1000], ears: ['left', 'right'] });
  let step = evaluateEngineTrial(engine, 'HEARD'); // 40 -> 20
  step = evaluateEngineTrial(step.engine, 'NOT_HEARD'); // [20,40] -> 30
  step = evaluateEngineTrial(step.engine, 'HEARD'); // [20,30] -> 25
  step = evaluateEngineTrial(step.engine, 'NOT_HEARD'); // [25,30] -> threshold 30

  assert.equal(step.action, 'THRESHOLD_FOUND');
  assert.equal(step.switchedEar, true);
  assert.deepEqual(getCurrentTarget(step.engine), { ear: 'right', frequencyHz: 1000 });
});

test('computeScreeningOutcome classifies PASS, REFER, and INCONCLUSIVE correctly', () => {
  const engine = {
    frequenciesHz: [500, 1000],
    results: [
      { ear: 'left', frequencyHz: 500, thresholdDb: 20 },
      { ear: 'left', frequencyHz: 1000, thresholdDb: 25 },
      { ear: 'right', frequencyHz: 500, thresholdDb: 20 },
      { ear: 'right', frequencyHz: 1000, thresholdDb: 35 },
    ],
  };
  const outcome = computeScreeningOutcome(engine);
  assert.equal(outcome.left.classification, 'PASS');
  assert.equal(outcome.right.classification, 'REFER');
  assert.equal(outcome.overall, 'REFER');

  const incomplete = computeScreeningOutcome({
    frequenciesHz: [500, 1000],
    results: [{ ear: 'left', frequencyHz: 500, thresholdDb: 15 }],
  });
  assert.equal(incomplete.overall, 'INCONCLUSIVE');
});

test('initial baseline helpers track completion flag, extract averages, and populate monitor reference', () => {
  const profile = defaultUserProfile();
  assert.equal(profile.initialScreeningCompleted, false);

  const results = [
    { ear: 'left', frequencyHz: 500, thresholdDb: 20 },
    { ear: 'left', frequencyHz: 1000, thresholdDb: 30 },
    { ear: 'right', frequencyHz: 500, thresholdDb: 15 },
    { ear: 'right', frequencyHz: 1000, thresholdDb: 25 },
  ];
  const summary = extractBaselineSummary(results);
  assert.equal(summary.leftAvgDb, 25);
  assert.equal(summary.rightAvgDb, 20);
  assert.equal(summary.count, 4);

  const monitor = applyResultsToMonitor(defaultMonitorState(), results);
  assert.equal(monitor.thresholds[0][1], '20');
  assert.equal(monitor.thresholds[0][2], '30');
  assert.equal(monitor.thresholds[1][1], '15');
  assert.equal(monitor.thresholds[1][2], '25');
  assert.match(monitor.importMessage, /Imported 4/);
});

