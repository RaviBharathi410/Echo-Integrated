/**
 * ECHO Integrated Web Engine
 * Mirrors the domain algorithms from the Android repository:
 * - Modified Hughson-Westlake Staircase (down 10 / up 5, 2 ascending responses)
 * - Experimental Binary Search Refinement (bracket establishment + midpoint halving)
 * - Ambient noise disturbance contamination guard
 * - Web Audio API stereo-isolated pure-tone stimulus with 20ms Hann ramp
 * - Live Monitor DSP parameters, 6-band per-ear EQ, audiogram reference & A/B clarity log
 */

export const DEFAULT_4_FREQUENCIES = [500, 1000, 2000, 4000];
export const EXTENDED_6_FREQUENCIES = [250, 500, 1000, 2000, 4000, 8000];
export const EQ_CENTERS_HZ = [250, 500, 1000, 2000, 4000, 6000];

export const StrategyType = Object.freeze({
  MODIFIED_HUGHSON_WESTLAKE: 'MODIFIED_HUGHSON_WESTLAKE',
  BINARY_SEARCH_REFINEMENT: 'BINARY_SEARCH_REFINEMENT',
});

export const ScreeningState = Object.freeze({
  DEVICE_READINESS: 'DEVICE_READINESS',
  TEST_PREP: 'TEST_PREP',
  PRACTICE_PRESENTATION: 'PRACTICE_PRESENTATION',
  PRACTICE_FEEDBACK: 'PRACTICE_FEEDBACK',
  STIMULUS_PRESENTATION: 'STIMULUS_PRESENTATION',
  WAITING_FOR_RESPONSE: 'WAITING_FOR_RESPONSE',
  EAR_TRANSITION: 'EAR_TRANSITION',
  AUTOMATIC_PAUSE_NOISE: 'AUTOMATIC_PAUSE_NOISE',
  AUTOMATIC_PAUSE_DEVICE: 'AUTOMATIC_PAUSE_DEVICE',
  USER_PAUSED: 'USER_PAUSED',
  RESULTS: 'RESULTS',
  CANCELLED: 'CANCELLED',
});

export const NoiseAssessment = Object.freeze({
  VALID: 'VALID',
  SUSPECT: 'SUSPECT',
  INVALID: 'INVALID',
  UNAVAILABLE: 'UNAVAILABLE',
});

export function createBinarySearchSession({ frequenciesHz = DEFAULT_4_FREQUENCIES, ears = ['left', 'right'] } = {}) {
  return {
    strategy: StrategyType.BINARY_SEARCH_REFINEMENT,
    frequenciesHz: [...frequenciesHz],
    ears: [...ears],
    earIndex: 0,
    frequencyIndex: 0,
    startingLevelDb: 40,
    currentLevelDb: 40,
    bracketStepDb: 20,
    resolutionDb: 5,
    minLevelDb: 0,
    maxLevelDb: 80,
    maxTrialsPerTarget: 18,
    bracket: { lowerInaudibleDb: null, upperAudibleDb: null, established: false },
    targetValidTrials: 0,
    trials: [],
    results: [],
    contaminatedTrials: [],
    noisePauseCount: 0,
    devicePauseCount: 0,
    qualityFlags: ['UNCALIBRATED_HARDWARE', 'BINARY_SEARCH_EXPERIMENTAL'],
  };
}

export function createHughsonWestlakeSession({ frequenciesHz = DEFAULT_4_FREQUENCIES, ears = ['left', 'right'] } = {}) {
  return {
    strategy: StrategyType.MODIFIED_HUGHSON_WESTLAKE,
    frequenciesHz: [...frequenciesHz],
    ears: [...ears],
    earIndex: 0,
    frequencyIndex: 0,
    startingLevelDb: 40,
    currentLevelDb: 40,
    downStepDb: 10,
    upStepDb: 5,
    minLevelDb: 0,
    maxLevelDb: 80,
    requiredAscendingResponses: 2,
    maxTrialsPerTarget: 18,
    wasLastStepAscending: false,
    ascendingResponsesAtLevel: {},
    targetValidTrials: 0,
    trials: [],
    results: [],
    contaminatedTrials: [],
    noisePauseCount: 0,
    devicePauseCount: 0,
    qualityFlags: ['UNCALIBRATED_HARDWARE'],
  };
}

export function getCurrentTarget(engine) {
  return {
    ear: engine.ears[engine.earIndex] ?? engine.ears[engine.ears.length - 1],
    frequencyHz: engine.frequenciesHz[engine.frequencyIndex] ?? engine.frequenciesHz[engine.frequenciesHz.length - 1],
  };
}

function advanceTarget(engine) {
  let nextFreq = engine.frequencyIndex + 1;
  let nextEar = engine.earIndex;
  let switchedEar = false;
  if (nextFreq >= engine.frequenciesHz.length) {
    nextFreq = 0;
    nextEar += 1;
    switchedEar = nextEar < engine.ears.length;
  }
  if (nextEar >= engine.ears.length) {
    return { done: true, switchedEar: false, engine: { ...engine, earIndex: nextEar, frequencyIndex: nextFreq } };
  }
  const resetFields =
    engine.strategy === StrategyType.BINARY_SEARCH_REFINEMENT
      ? { bracket: { lowerInaudibleDb: null, upperAudibleDb: null, established: false } }
      : { wasLastStepAscending: false, ascendingResponsesAtLevel: {} };
  return {
    done: false,
    switchedEar,
    engine: {
      ...engine,
      earIndex: nextEar,
      frequencyIndex: nextFreq,
      currentLevelDb: engine.startingLevelDb,
      targetValidTrials: 0,
      ...resetFields,
    },
  };
}

/**
 * Evaluate a trial outcome ('HEARD' | 'NOT_HEARD' | 'CONTAMINATED_BY_NOISE' | 'INVALID_INTERRUPTED').
 * Contaminated or invalid trials are recorded but NEVER mutate staircase or binary bracket state.
 */
export function evaluateEngineTrial(engine, outcome, { latencyMs = null, ambientNoiseDbFs = -55 } = {}) {
  const target = getCurrentTarget(engine);
  const record = {
    trialNumber: engine.trials.length + 1,
    ear: target.ear,
    frequencyHz: target.frequencyHz,
    levelDb: engine.currentLevelDb,
    outcome,
    latencyMs,
    ambientNoiseDbFs,
    at: new Date().toISOString(),
  };
  const trials = [...engine.trials, record];

  if (outcome === 'CONTAMINATED_BY_NOISE' || outcome === 'INVALID_INTERRUPTED') {
    const contaminatedTrials = outcome === 'CONTAMINATED_BY_NOISE' ? [...engine.contaminatedTrials, record] : engine.contaminatedTrials;
    return { action: 'RETRY', switchedEar: false, engine: { ...engine, trials, contaminatedTrials } };
  }

  const validCount = engine.targetValidTrials + 1;
  if (validCount >= engine.maxTrialsPerTarget) {
    const adv = advanceTarget({ ...engine, trials, targetValidTrials: validCount });
    return { action: adv.done ? 'COMPLETE' : 'MAX_TRIALS', switchedEar: adv.switchedEar, engine: adv.engine };
  }

  if (engine.strategy === StrategyType.BINARY_SEARCH_REFINEMENT) {
    return evaluateBinarySearch(engine, outcome, trials, validCount, target);
  }
  return evaluateHughsonWestlake(engine, outcome, trials, validCount, target);
}

function evaluateHughsonWestlake(engine, outcome, trials, validCount, target) {
  let level = engine.currentLevelDb;
  let wasLastStepAscending = engine.wasLastStepAscending;
  const asc = { ...engine.ascendingResponsesAtLevel };

  if (outcome === 'HEARD') {
    if (wasLastStepAscending) {
      const count = (asc[level] || 0) + 1;
      asc[level] = count;
      if (count >= engine.requiredAscendingResponses) {
        const result = {
          ear: target.ear,
          frequencyHz: target.frequencyHz,
          thresholdDb: level,
          validAscendingResponses: count,
          totalTrialsForTarget: validCount,
          method: 'MODIFIED_HUGHSON_WESTLAKE',
          confidence: 'UNVALIDATED_POC_ESTIMATE',
        };
        const adv = advanceTarget({
          ...engine,
          trials,
          results: [...engine.results, result],
        });
        return { action: adv.done ? 'COMPLETE' : 'THRESHOLD_FOUND', switchedEar: adv.switchedEar, result, engine: adv.engine };
      }
    }
    level = Math.max(engine.minLevelDb, level - engine.downStepDb);
    wasLastStepAscending = false;
  } else {
    level = Math.min(engine.maxLevelDb, level + engine.upStepDb);
    wasLastStepAscending = true;
  }

  return {
    action: 'NEXT_TRIAL',
    switchedEar: false,
    engine: {
      ...engine,
      trials,
      targetValidTrials: validCount,
      currentLevelDb: level,
      wasLastStepAscending,
      ascendingResponsesAtLevel: asc,
    },
  };
}

function evaluateBinarySearch(engine, outcome, trials, validCount, target) {
  const bracket = { ...engine.bracket };
  let level = engine.currentLevelDb;

  if (!bracket.established) {
    if (outcome === 'HEARD') {
      bracket.upperAudibleDb = bracket.upperAudibleDb === null ? level : Math.min(bracket.upperAudibleDb, level);
      if (bracket.lowerInaudibleDb !== null && bracket.lowerInaudibleDb < bracket.upperAudibleDb) {
        bracket.established = true;
      } else {
        const nextLevel = level - engine.bracketStepDb;
        if (level <= engine.minLevelDb || nextLevel < engine.minLevelDb) {
          const adv = advanceTarget({
            ...engine,
            trials,
            qualityFlags: [...new Set([...engine.qualityFlags, 'INCOMPLETE_TARGETS'])],
          });
          return { action: adv.done ? 'COMPLETE' : 'INCONCLUSIVE', switchedEar: adv.switchedEar, engine: adv.engine };
        }
        return {
          action: 'NEXT_TRIAL',
          switchedEar: false,
          engine: { ...engine, trials, targetValidTrials: validCount, bracket, currentLevelDb: Math.max(engine.minLevelDb, nextLevel) },
        };
      }
    } else {
      bracket.lowerInaudibleDb = bracket.lowerInaudibleDb === null ? level : Math.max(bracket.lowerInaudibleDb, level);
      if (bracket.upperAudibleDb !== null && bracket.lowerInaudibleDb < bracket.upperAudibleDb) {
        bracket.established = true;
      } else {
        const nextLevel = level + engine.bracketStepDb;
        if (level >= engine.maxLevelDb || nextLevel > engine.maxLevelDb) {
          const adv = advanceTarget({
            ...engine,
            trials,
            qualityFlags: [...new Set([...engine.qualityFlags, 'INCOMPLETE_TARGETS'])],
          });
          return { action: adv.done ? 'COMPLETE' : 'INCONCLUSIVE', switchedEar: adv.switchedEar, engine: adv.engine };
        }
        return {
          action: 'NEXT_TRIAL',
          switchedEar: false,
          engine: { ...engine, trials, targetValidTrials: validCount, bracket, currentLevelDb: Math.min(engine.maxLevelDb, nextLevel) },
        };
      }
    }
  } else {
    if (outcome === 'HEARD') {
      bracket.upperAudibleDb = level;
    } else {
      bracket.lowerInaudibleDb = level;
    }
  }

  const lower = bracket.lowerInaudibleDb;
  const upper = bracket.upperAudibleDb;
  if (lower !== null && upper !== null) {
    if (upper - lower <= engine.resolutionDb) {
      const result = {
        ear: target.ear,
        frequencyHz: target.frequencyHz,
        thresholdDb: upper,
        validAscendingResponses: 1,
        totalTrialsForTarget: validCount,
        method: 'BINARY_SEARCH_REFINEMENT',
        confidence: 'EXPERIMENTAL_BINARY_REFINED',
        bracketLowerDb: lower,
        bracketUpperDb: upper,
      };
      const adv = advanceTarget({ ...engine, trials, results: [...engine.results, result] });
      return { action: adv.done ? 'COMPLETE' : 'THRESHOLD_FOUND', switchedEar: adv.switchedEar, result, engine: adv.engine };
    }
    const mid = Math.ceil((lower + upper) / 2);
    if (mid <= lower || mid >= upper) {
      const result = {
        ear: target.ear,
        frequencyHz: target.frequencyHz,
        thresholdDb: upper,
        validAscendingResponses: 1,
        totalTrialsForTarget: validCount,
        method: 'BINARY_SEARCH_REFINEMENT',
        confidence: 'EXPERIMENTAL_BINARY_REFINED',
        bracketLowerDb: lower,
        bracketUpperDb: upper,
      };
      const adv = advanceTarget({ ...engine, trials, results: [...engine.results, result] });
      return { action: adv.done ? 'COMPLETE' : 'THRESHOLD_FOUND', switchedEar: adv.switchedEar, result, engine: adv.engine };
    }
    return {
      action: 'NEXT_TRIAL',
      switchedEar: false,
      engine: { ...engine, trials, targetValidTrials: validCount, bracket, currentLevelDb: mid },
    };
  }

  return { action: 'NEXT_TRIAL', switchedEar: false, engine: { ...engine, trials, targetValidTrials: validCount, bracket } };
}

export function computeScreeningOutcome(engine) {
  const targetCount = engine.frequenciesHz.length;
  const evalEar = (ear) => {
    const thresholds = engine.results.filter((r) => r.ear === ear);
    const complete = thresholds.length >= targetCount;
    const hasElevated = thresholds.some((t) => t.thresholdDb > 25);
    const classification = !complete ? 'INCONCLUSIVE' : hasElevated ? 'REFER' : 'PASS';
    return { ear, thresholds, complete, classification };
  };
  const left = evalEar('left');
  const right = evalEar('right');
  const overall =
    left.classification === 'REFER' || right.classification === 'REFER'
      ? 'REFER'
      : left.classification === 'INCONCLUSIVE' || right.classification === 'INCONCLUSIVE'
        ? 'INCONCLUSIVE'
        : 'PASS';
  return { overall, left, right };
}

/**
 * Web Audio pure-tone stimulus generator with strict L/R isolation and 20ms Hann envelope.
 * Safe no-op in non-browser/test environments.
 */
export class WebToneGenerator {
  constructor() {
    this.ctx = null;
    this.activeOsc = null;
    this.activeTimer = null;
  }

  playTone({ frequencyHz, levelDb, ear, durationMs = 1200, onEnded }) {
    this.stop();
    if (typeof window === 'undefined') return;
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) return;

    if (!this.ctx) this.ctx = new AudioCtx();
    if (this.ctx.state === 'suspended') this.ctx.resume().catch(() => {});

    const now = this.ctx.currentTime;
    const dur = durationMs / 1000;
    const ramp = 0.02;
    const attenuationDb = levelDb - 80;
    const amplitude = Math.min(0.45, Math.max(0.002, Math.pow(10, attenuationDb / 20)));

    const osc = this.ctx.createOscillator();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(frequencyHz, now);

    const gain = this.ctx.createGain();
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.linearRampToValueAtTime(amplitude, now + ramp);
    gain.gain.setValueAtTime(amplitude, Math.max(now + ramp, now + dur - ramp));
    gain.gain.linearRampToValueAtTime(0.0001, now + dur);

    const merger = this.ctx.createChannelMerger(2);
    osc.connect(gain);
    if (ear === 'left') {
      gain.connect(merger, 0, 0);
    } else {
      gain.connect(merger, 0, 1);
    }
    merger.connect(this.ctx.destination);

    osc.start(now);
    osc.stop(now + dur);
    this.activeOsc = osc;
    this.activeTimer = setTimeout(() => {
      this.activeOsc = null;
      if (onEnded) onEnded();
    }, durationMs);
  }

  stop() {
    if (this.activeTimer) {
      clearTimeout(this.activeTimer);
      this.activeTimer = null;
    }
    if (this.activeOsc) {
      try {
        this.activeOsc.stop();
      } catch {}
      this.activeOsc = null;
    }
  }
}

export function defaultMonitorState() {
  return {
    running: false,
    status: 'Stopped',
    inputDevice: 'Built-in Microphone · Phone mic',
    outputDevice: 'Bluetooth Audio (A2DP) · Earbuds',
    monitorLevel: 0.15,
    processed: true,
    gateEnabled: true,
    gateThresholdDb: -54,
    denoiserEnabled: false,
    denoiserStrengthDb: 9,
    compressionEnabled: true,
    compressionRatio: 2.0,
    gains: [
      [0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0],
    ],
    thresholds: [
      ['', '', '', '', '', ''],
      ['', '', '', '', '', ''],
    ],
    realEarVerified: false,
    realEarNotes: '',
    environment: 'Quiet',
    trials: [],
    importMessage: '',
    trialMessage: '',
    liveMicPeakPct: 0,
  };
}

export function defaultUserProfile() {
  return {
    onboardingCompleted: false,
    initialScreeningCompleted: false,
    accountMode: 'Guest',
    email: '',
    preferredName: 'Alex Parker',
    ageRange: '18–35',
    preferredLanguage: 'English',
    notificationsEnabled: true,
    bluetoothEnabled: true,
    reminderFrequency: 'Monthly',
    useSixFrequencies: false,
  };
}

/**
 * Computes left/right ear baseline averages from screening results.
 */
export function extractBaselineSummary(results = []) {
  const avg = (items) => (items.length ? Math.round(items.reduce((s, r) => s + r.thresholdDb, 0) / items.length) : null);
  const left = results.filter((r) => r.ear === 'left');
  const right = results.filter((r) => r.ear === 'right');
  return {
    leftAvgDb: avg(left),
    rightAvgDb: avg(right),
    count: results.length,
  };
}

/**
 * Applies screening threshold results into the monitor's 6-band per-ear audiogram reference table.
 */
export function applyResultsToMonitor(monitor, results = []) {
  const nextThresholds = monitor.thresholds.map((row) => [...row]);
  let applied = 0;
  results.forEach((r) => {
    const band = EQ_CENTERS_HZ.indexOf(r.frequencyHz);
    const earIdx = r.ear === 'left' ? 0 : 1;
    if (band >= 0) {
      nextThresholds[earIdx][band] = String(r.thresholdDb);
      applied += 1;
    }
  });
  return {
    ...monitor,
    thresholds: nextThresholds,
    importMessage:
      applied > 0
        ? `Imported ${applied} uncalibrated screening thresholds as initial baseline reference.`
        : monitor.importMessage,
  };
}

