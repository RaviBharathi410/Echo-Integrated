import {
  DEFAULT_4_FREQUENCIES,
  EXTENDED_6_FREQUENCIES,
  EQ_CENTERS_HZ,
  StrategyType,
  ScreeningState,
  NoiseAssessment,
  createHughsonWestlakeSession,
  createBinarySearchSession,
  getCurrentTarget,
  evaluateEngineTrial,
  computeScreeningOutcome,
  WebToneGenerator,
  defaultMonitorState,
  defaultUserProfile,
  extractBaselineSummary,
  applyResultsToMonitor,
} from './echo_engine.js';

const STORAGE_KEY = 'echo_integrated_web_v1';
const toneGen = new WebToneGenerator();

function loadPersisted() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

const persisted = loadPersisted();
const hasExistingSessions = Boolean(persisted?.savedSessions?.length);
const initialProfile = { ...defaultUserProfile(), ...(persisted?.profile || {}) };
const needsInitialOnLoad = !initialProfile.initialScreeningCompleted && !hasExistingSessions;

const state = {
  profile: initialProfile,
  savedSessions: persisted?.savedSessions || [],
  monitor: { ...defaultMonitorState(), ...(persisted?.monitor || {}), running: false, status: 'Stopped' },
  onboardingStep: 'WELCOME', // WELCOME | ACCOUNT | PROFILE_SETUP | HEALTH_NOTICE | PERMISSIONS
  skipProfileSetup: false,
  initialTestPending: needsInitialOnLoad,
  justCompletedBaseline: false,
  accountMode: 'Sign In',
  consentChecked: false,
  tab: 'TEST', // TEST | HOME | MONITOR | REPORTS | PROFILE
  testSub: needsInitialOnLoad ? 'BRIEFING' : 'MAIN', // MAIN | BRIEFING | HISTORY | COMPARE | REMINDERS | RECORD_DETAIL
  monitorSub: 'MAIN', // MAIN | HISTORY | DETAILS | SETTINGS
  reportsSub: 'MAIN', // MAIN | WEEKLY | TRENDS | TIPS | HISTORICAL
  profileSub: 'MAIN', // MAIN | EDIT | DEVICES | NOTIFICATIONS | PRIVACY | EXPORT | ABOUT | FAQ
  selectedRecord: null,
  showSimDrawer: false,
  isSimulationMode: false,
  // Screening state
  screeningState: ScreeningState.DEVICE_READINESS,
  strategyType: StrategyType.MODIFIED_HUGHSON_WESTLAKE,
  headphoneConnected: true,
  routeName: 'Bluetooth Audio Active (Stereo)',
  noiseAssessment: NoiseAssessment.VALID,
  noiseDbFs: -55.0,
  pauseReason: null,
  recoverySeconds: 3,
  engine: createHughsonWestlakeSession({ frequenciesHz: persisted?.profile?.useSixFrequencies ? EXTENDED_6_FREQUENCIES : DEFAULT_4_FREQUENCIES }),
  isTonePlaying: false,
  isWaitingForResponse: false,
  practiceTonePlaying: false,
  practiceHeard: null,
  practiceMessage: 'Tap "I Hear It" when you hear the 1000 Hz demo tone.',
  outcome: null,
  accordion: { dsp: true, eq: false, audiogram: false, clarity: false },
  clarityCorrect: '',
  clarityTotal: '10',
  copiedJson: false,
};

let presentationTimer = null;
let responseTimer = null;
let recoveryInterval = null;
let monitorInterval = null;

function persist() {
  try {
    const monSave = { ...state.monitor, running: false, status: 'Stopped' };
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({
        profile: state.profile,
        savedSessions: state.savedSessions,
        monitor: monSave,
      })
    );
  } catch {}
}

function clearTimers() {
  if (presentationTimer) { clearTimeout(presentationTimer); presentationTimer = null; }
  if (responseTimer) { clearTimeout(responseTimer); responseTimer = null; }
  if (recoveryInterval) { clearInterval(recoveryInterval); recoveryInterval = null; }
  toneGen.stop();
}

function stopLiveMonitor(msg = 'Stopped') {
  if (monitorInterval) {
    clearInterval(monitorInterval);
    monitorInterval = null;
  }
  if (state.monitor.running) {
    state.monitor.running = false;
    state.monitor.status = msg;
    state.monitor.liveMicPeakPct = 0;
  }
}

function esc(str) {
  return String(str ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// Inline SVG Icons (clean Material-style)
const icons = {
  back: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="m12 19-7-7 7-7"/></svg>`,
  forward: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>`,
  info: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>`,
  check: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>`,
  wave: `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M4 10v4"/><path d="M8 7v10"/><path d="M12 4v16"/><path d="M16 7v10"/><path d="M20 10v4"/></svg>`,
  ear: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 8.5a6.5 6.5 0 1 1 13 0c0 6-6 6-6 10a3.5 3.5 0 1 1-7 0"/><path d="M15 8.5a2.5 2.5 0 0 0-5 0v1a2 2 0 1 1 0 4"/></svg>`,
  headphones: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 18v-6a9 9 0 0 1 18 0v6"/><path d="M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3zM3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3z"/></svg>`,
  sliders: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="4" y1="21" x2="4" y2="14"/><line x1="4" y1="10" x2="4" y2="3"/><line x1="12" y1="21" x2="12" y2="12"/><line x1="12" y1="8" x2="12" y2="3"/><line x1="20" y1="21" x2="20" y2="16"/><line x1="20" y1="12" x2="20" y2="3"/><line x1="1" y1="14" x2="7" y2="14"/><line x1="9" y1="8" x2="15" y2="8"/><line x1="17" y1="16" x2="23" y2="16"/></svg>`,
  mic: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="22"/></svg>`,
  bell: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/></svg>`,
  bluetooth: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m7 7 10 10-5 5V2l5 5L7 17"/></svg>`,
  grid: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/></svg>`,
  chart: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M8 17v-5"/><path d="M12 17V7"/><path d="M16 17v-3"/></svg>`,
  person: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`,
  history: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l4 2"/></svg>`,
  pause: `<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/></svg>`,
  play: `<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><polygon points="6 4 20 12 6 20 6 4"/></svg>`,
  volOn: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/></svg>`,
  volOff: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><line x1="22" y1="9" x2="16" y2="15"/><line x1="16" y1="9" x2="22" y2="15"/></svg>`,
  lock: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`,
  download: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>`,
  bulb: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5"/><path d="M9 18h6"/><path d="M10 22h4"/></svg>`,
  trend: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/></svg>`,
  help: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>`,
  doc: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>`,
  compare: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="16 3 21 3 21 8"/><line x1="4" y1="20" x2="21" y2="3"/><polyline points="21 16 21 21 16 21"/><line x1="15" y1="15" x2="21" y2="21"/></svg>`,
  settings: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1Z"/></svg>`,
  refresh: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>`,
};

function topbar(title, { backAction = null, actionsHtml = '' } = {}) {
  return `
    <header class="topbar">
      <div class="topbar-left">
        ${backAction ? `<button class="icon-btn" data-action="${backAction}" aria-label="Back">${icons.back}</button>` : ''}
        <h1 class="topbar-title">${esc(title)}</h1>
      </div>
      <div class="topbar-actions">${actionsHtml}</div>
    </header>
  `;
}

function renderAudiogramSvg(results) {
  const freqs = [250, 500, 1000, 2000, 4000, 8000];
  const w = 360, h = 220;
  const padL = 36, padR = 16, padT = 18, padB = 26;
  const cw = w - padL - padR, ch = h - padT - padB;
  const minLog = Math.log2(freqs[0]), maxLog = Math.log2(freqs[freqs.length - 1]);
  const fx = (f) => padL + ((Math.log2(f) - minLog) / (maxLog - minLog)) * cw;
  const ly = (db) => padT + (Math.max(0, Math.min(80, db)) / 80) * ch;

  const left = results.filter((r) => r.ear === 'left').sort((a, b) => a.frequencyHz - b.frequencyHz);
  const right = results.filter((r) => r.ear === 'right').sort((a, b) => a.frequencyHz - b.frequencyHz);

  const rightLine = right.map((r, i) => `${i === 0 ? 'M' : 'L'}${fx(r.frequencyHz).toFixed(1)},${ly(r.thresholdDb).toFixed(1)}`).join(' ');
  const leftLine = left.map((r, i) => `${i === 0 ? 'M' : 'L'}${fx(r.frequencyHz).toFixed(1)},${ly(r.thresholdDb).toFixed(1)}`).join(' ');

  return `
    <div class="card">
      <div class="row-between" style="margin-bottom:10px">
        <div>
          <div style="font-size:11px;font-weight:800;letter-spacing:.08em;color:var(--navy)">AUDIOGRAM SCREENING PROFILE</div>
          <div class="small-note">Digital Attenuation (dBFS)</div>
        </div>
        <div class="row-gap" style="gap:10px;font-size:12px;font-weight:700">
          <span style="color:#dc2626">◯ Right (O)</span>
          <span style="color:#1565c0">✕ Left (X)</span>
        </div>
      </div>
      <svg class="audiogram-svg" viewBox="0 0 ${w} ${h}">
        <rect x="${padL}" y="${padT}" width="${cw}" height="${(ly(25) - padT).toFixed(1)}" fill="rgba(16,185,129,0.10)" />
        ${[0, 20, 40, 60, 80].map((lv) => `
          <line x1="${padL}" y1="${ly(lv)}" x2="${padL + cw}" y2="${ly(lv)}" stroke="#dce7f5" stroke-width="${lv === 0 ? 1.5 : 1}" />
          <text x="${padL - 6}" y="${ly(lv) + 4}" text-anchor="end" font-size="10" fill="#5b7083">${lv}</text>
        `).join('')}
        <line x1="${padL}" y1="${ly(25)}" x2="${padL + cw}" y2="${ly(25)}" stroke="rgba(16,185,129,0.5)" stroke-dasharray="4 4" />
        ${freqs.map((f) => `
          <line x1="${fx(f)}" y1="${padT}" x2="${fx(f)}" y2="${padT + ch}" stroke="#dce7f5" />
          <text x="${fx(f)}" y="${h - 6}" text-anchor="middle" font-size="10" fill="#5b7083">${f >= 1000 ? `${f / 1000}k` : f}</text>
        `).join('')}
        ${right.length ? `<path d="${rightLine}" fill="none" stroke="#dc2626" stroke-width="2.2" />` : ''}
        ${right.map((r) => `<circle cx="${fx(r.frequencyHz)}" cy="${ly(r.thresholdDb)}" r="4.5" fill="#fff" stroke="#dc2626" stroke-width="2" />`).join('')}
        ${left.length ? `<path d="${leftLine}" fill="none" stroke="#1565c0" stroke-width="2.2" stroke-dasharray="6 4" />` : ''}
        ${left.map((r) => {
          const x = fx(r.frequencyHz), y = ly(r.thresholdDb), d = 4.2;
          return `<circle cx="${x}" cy="${y}" r="6" fill="#fff" />
            <line x1="${x - d}" y1="${y - d}" x2="${x + d}" y2="${y + d}" stroke="#1565c0" stroke-width="2.2" />
            <line x1="${x - d}" y1="${y + d}" x2="${x + d}" y2="${y - d}" stroke="#1565c0" stroke-width="2.2" />`;
        }).join('')}
      </svg>
      <div class="small-note" style="margin-top:6px">Shaded: ≤ 25 dBFS provisional screening zone (uncalibrated).</div>
    </div>
  `;
}

// ---- ONBOARDING SCREENS ----

function renderOnboarding() {
  switch (state.onboardingStep) {
    case 'WELCOME':
      return `
        ${topbar('ECHO')}
        <div class="screen-body" style="align-items:center;text-align:center">
          <div class="icon-badge circle-lg">${icons.wave}</div>
          <h2 class="hero-title">Welcome to ECHO</h2>
          <p class="subtitle">Personalized hearing clarity and daily listening monitoring.</p>
          <div class="card" style="text-align:left">
            <div class="row-gap">
              <div class="icon-badge">${icons.ear}</div>
              <div>
                <div class="card-title" style="font-size:15px">Preliminary Sound Screening</div>
                <p class="small-note">Fast, non-clinical tone response checks across key speech frequencies.</p>
              </div>
            </div>
          </div>
          <div class="card" style="text-align:left">
            <div class="row-gap">
              <div class="icon-badge">${icons.headphones}</div>
              <div>
                <div class="card-title" style="font-size:15px">Acoustic Monitoring</div>
                <p class="small-note">Live DSP monitoring, ambient noise checks, and exposure tracking.</p>
              </div>
            </div>
          </div>
          <div class="card" style="text-align:left">
            <div class="row-gap">
              <div class="icon-badge">${icons.sliders}</div>
              <div>
                <div class="card-title" style="font-size:15px">Sound Personalization</div>
                <p class="small-note">Customizable multi-band equalization and speech clarity tools.</p>
              </div>
            </div>
          </div>
          <div style="flex:1"></div>
          <button class="btn-primary" data-action="onb-start">${icons.forward} Get Started</button>
          <button class="btn-pill" data-action="onb-account">I Already Have an Account</button>
        </div>
      `;

    case 'ACCOUNT':
      return `
        ${topbar('Account', { backAction: 'onb-welcome' })}
        <div class="screen-body">
          <div>
            <h2 class="section-title">${state.accountMode === 'Sign In' ? 'Welcome Back' : 'Create Local Profile'}</h2>
            <p class="subtitle">Sign in to access your saved screening history.</p>
          </div>
          <div class="grid-2">
            <button class="${state.accountMode === 'Sign In' ? 'btn-primary' : 'btn-pill'}" data-action="acc-mode" data-val="Sign In">Sign In</button>
            <button class="${state.accountMode === 'Register' ? 'btn-primary' : 'btn-pill'}" data-action="acc-mode" data-val="Register">Register</button>
          </div>
          <div class="field-group">
            <label class="field-label">Email Address</label>
            <input class="input-box" id="accEmail" value="${esc(state.profile.email || 'alex@example.com')}" />
          </div>
          <div class="field-group">
            <label class="field-label">Password</label>
            <input class="input-box" type="password" value="password123" />
          </div>
          <button class="btn-primary" data-action="acc-submit">${icons.check} ${esc(state.accountMode)}</button>
          <button class="btn-pill" data-action="acc-guest">${icons.person} Continue as Guest</button>
          <p class="small-note" style="text-align:center">Local authentication simulation for UI demonstration. No real credentials are transmitted.</p>
        </div>
      `;

    case 'PROFILE_SETUP': {
      const ages = ['18–35', '36–50', '51–65', '65+'];
      const langs = ['English', 'Spanish', 'French', 'German'];
      return `
        ${topbar('Profile Setup', { backAction: 'onb-welcome' })}
        <div class="screen-body">
          <div>
            <h2 class="section-title">Your Profile</h2>
            <p class="subtitle">Configure baseline details to personalize your audio experience.</p>
          </div>
          <div class="field-group">
            <label class="field-label">Preferred Name</label>
            <input class="input-box" id="profName" value="${esc(state.profile.preferredName)}" />
          </div>
          <div class="field-group">
            <label class="field-label">Age Range</label>
            <p class="small-note">Used for non-clinical demographic baseline context.</p>
            <div class="chip-row">
              ${ages.map((a) => `<button class="chip ${state.profile.ageRange === a ? 'selected' : ''}" data-action="set-age" data-val="${a}">${state.profile.ageRange === a ? icons.check : ''} ${a}</button>`).join('')}
            </div>
          </div>
          <div class="field-group">
            <label class="field-label">Preferred Language</label>
            <p class="small-note">Interface language for audio instructions and screening prompts.</p>
            <div class="chip-row">
              ${langs.map((l) => `<button class="chip ${state.profile.preferredLanguage === l ? 'selected' : ''}" data-action="set-lang" data-val="${l}">${state.profile.preferredLanguage === l ? icons.check : ''} ${l}</button>`).join('')}
            </div>
          </div>
          <div style="flex:1"></div>
          <button class="btn-primary" data-action="onb-to-notice">${icons.forward} Continue to Disclaimer</button>
        </div>
      `;
    }

    case 'HEALTH_NOTICE':
      return `
        ${topbar('Health Notice', { backAction: state.skipProfileSetup ? 'onb-account' : 'onb-profile' })}
        <div class="screen-body">
          <div class="card">
            <div class="row-gap" style="margin-bottom:10px">
              <span style="color:var(--primary)">${icons.info}</span>
              <h3 class="card-title">Important Health Notice</h3>
            </div>
            <p style="font-size:14.5px;line-height:1.5;margin:0 0 10px">ECHO provides a preliminary screening, not a substitute for professional audiological assessment.</p>
            <p class="subtitle" style="font-size:13.5px;margin-bottom:10px">This software application does not perform calibrated medical diagnosis or clinical audiometry. Sound response indicators use digital attenuation (dBFS), not clinical dB HL.</p>
            <p class="subtitle" style="font-size:13.5px">If you experience persistent ear discomfort, tinnitus, or sudden changes in hearing ability, consult a certified audiologist or physician.</p>
          </div>
          <label class="row-gap" style="cursor:pointer;align-items:flex-start">
            <input type="checkbox" id="consentBox" ${state.consentChecked ? 'checked' : ''} data-action="toggle-consent" style="margin-top:3px;width:18px;height:18px;accent-color:var(--primary)" />
            <span style="font-size:13.5px;line-height:1.45">I understand that ECHO provides a preliminary screening, not a substitute for professional audiological assessment.</span>
          </label>
          <div style="flex:1"></div>
          <button class="btn-primary" ${state.consentChecked ? '' : 'disabled'} data-action="onb-accept-notice">${icons.check} Accept &amp; Continue</button>
        </div>
      `;

    case 'PERMISSIONS': {
      const needsInitial = !state.profile.initialScreeningCompleted && !state.savedSessions.length;
      return `
        ${topbar('Permissions', { backAction: 'onb-notice' })}
        <div class="screen-body">
          <div>
            <h2 class="section-title">System Permissions</h2>
            <p class="subtitle">Simulated permissions for UI demonstration and optional browser audio synthesis.</p>
          </div>
          ${permRow('Microphone Permission', 'Simulated ambient sound level estimation & noise gate.', icons.mic, true, 'perm-mic')}
          ${permRow('Notifications Permission', 'Simulated daily listening reminders and summary alerts.', icons.bell, state.profile.notificationsEnabled, 'perm-notif')}
          ${permRow('Bluetooth Permission', 'Simulated wireless headphone connection and status detection.', icons.bluetooth, state.profile.bluetoothEnabled, 'perm-bt')}
          ${needsInitial ? `
            <div class="card" style="background:var(--surface-alt);border-color:var(--pill-border)">
              <div class="row-gap" style="align-items:flex-start">
                <span style="color:var(--primary)">${icons.ear}</span>
                <div>
                  <div style="font-weight:700;font-size:14px">Up Next: Initial Hearing Baseline Test</div>
                  <div class="small-note">Right after permissions, ECHO runs an initial pure-tone check to identify your baseline hearing input.</div>
                </div>
              </div>
            </div>
          ` : ''}
          <div style="flex:1"></div>
          <button class="btn-primary" data-action="onb-complete">${icons.forward} ${needsInitial ? 'Continue to Initial Hearing Test' : 'Continue to Device Setup'}</button>
        </div>
      `;
    }
  }
}

function permRow(title, desc, icon, checked, action) {
  return `
    <div class="card">
      <div class="toggle-row">
        <div class="row-gap">
          <div class="icon-badge">${icon}</div>
          <div>
            <div style="font-weight:700;font-size:14.5px">${esc(title)}</div>
            <div class="small-note">${esc(desc)}</div>
          </div>
        </div>
        <label class="switch">
          <input type="checkbox" ${checked ? 'checked' : ''} data-action="${action}" />
          <span class="slider-track"></span>
        </label>
      </div>
    </div>
  `;
}

// ---- TEST TAB SCREENS ----

function renderTestTab() {
  if (state.testSub === 'HISTORY') {
    return `
      ${topbar('Screening History', {
        backAction: 'test-main',
        actionsHtml: `<span class="pill">${icons.info} ${state.savedSessions.length ? `${state.savedSessions.length} saved` : 'Sample data'}</span>`,
      })}
      <div class="screen-body">
        <div class="card">
          <div class="card-header">
            <h3 class="card-title">Previous Screenings</h3>
            <span class="pill">${icons.info} ${state.savedSessions.length ? 'Local' : 'Sample data'}</span>
          </div>
          <p class="subtitle">Track preliminary tone response estimates over time.</p>
        </div>
        <button class="btn-pill" data-action="test-compare">${icons.compare} Compare Screenings</button>
        <button class="btn-pill" data-action="test-reminders">${icons.bell} Screening Reminders</button>
        <button class="btn-pill" data-action="test-latest">${icons.doc} ${state.savedSessions.length ? 'View Latest Record' : 'View Latest Record (Sample #1)'}</button>
        ${state.savedSessions.map((rec, i) => `
          <div class="card clickable" data-action="open-record" data-idx="${i}">
            <div class="row-between">
              <div>
                <div style="font-weight:700">${esc(rec.overall)} · ${esc(rec.strategyLabel)}</div>
                <div class="small-note">${new Date(rec.at).toLocaleString()} · ${rec.results.length} thresholds</div>
              </div>
              <button class="text-action-btn" data-action="del-record" data-idx="${i}" style="color:var(--rose)">Delete</button>
            </div>
          </div>
        `).join('')}
      </div>
    `;
  }

  if (state.testSub === 'COMPARE') {
    const s1 = state.savedSessions[0];
    const s2 = state.savedSessions[1];
    return `
      ${topbar('Compare Screenings', { backAction: 'test-history', actionsHtml: !s2 ? `<span class="pill">${icons.info} Sample data</span>` : '' })}
      <div class="screen-body">
        <div class="card">
          <h3 class="card-title">${s2 ? 'Latest vs Previous Screening' : 'Sample Comparison'}</h3>
          <p class="subtitle" style="margin-bottom:10px">${s2 ? 'Threshold delta (dBFS)' : 'Complete 2 screenings to compare real records. Showing sample baseline:'}</p>
          ${(s1 && s2 ? s1.results : DEFAULT_4_FREQUENCIES.map((f) => ({ ear: 'left', frequencyHz: f, thresholdDb: 20 }))).map((r) => {
            const prev = s2 ? s2.results.find((p) => p.ear === r.ear && p.frequencyHz === r.frequencyHz)?.thresholdDb : 20;
            const delta = prev !== undefined ? r.thresholdDb - prev : null;
            return `<div class="row-between" style="padding:5px 0;border-bottom:1px solid var(--border);font-size:13.5px">
              <span>${r.ear.toUpperCase()} ${r.frequencyHz} Hz</span>
              <strong style="color:var(--primary)">${prev ?? '—'} → ${r.thresholdDb} dBFS ${delta !== null ? `(${delta >= 0 ? '+' + delta : delta})` : ''}</strong>
            </div>`;
          }).join('')}
        </div>
      </div>
    `;
  }

  if (state.testSub === 'REMINDERS') {
    const opts = ['Weekly', 'Monthly', 'Quarterly', 'Off'];
    return `
      ${topbar('Screening Reminders', { backAction: 'test-history' })}
      <div class="screen-body">
        <div class="card">
          <h3 class="card-title">Reminder Cadence</h3>
          <p class="subtitle" style="margin-bottom:12px">Choose how often ECHO reminds you to take a routine sound check.</p>
          <div class="chip-row">
            ${opts.map((o) => `<button class="chip ${state.profile.reminderFrequency === o ? 'selected' : ''}" data-action="set-reminder" data-val="${o}">${o}</button>`).join('')}
          </div>
        </div>
      </div>
    `;
  }

  if (state.testSub === 'RECORD_DETAIL') {
    const rec = state.selectedRecord || state.savedSessions[0];
    const sampleResults = [
      { ear: 'left', frequencyHz: 500, thresholdDb: 20 },
      { ear: 'left', frequencyHz: 1000, thresholdDb: 15 },
      { ear: 'left', frequencyHz: 2000, thresholdDb: 20 },
      { ear: 'left', frequencyHz: 4000, thresholdDb: 25 },
      { ear: 'right', frequencyHz: 500, thresholdDb: 20 },
      { ear: 'right', frequencyHz: 1000, thresholdDb: 20 },
      { ear: 'right', frequencyHz: 2000, thresholdDb: 25 },
      { ear: 'right', frequencyHz: 4000, thresholdDb: 25 },
    ];
    const results = rec ? rec.results : sampleResults;
    return `
      ${topbar(rec ? 'Screening Record' : 'Sample Record #1', { backAction: 'test-history', actionsHtml: !rec ? `<span class="pill">${icons.info} Sample data</span>` : '' })}
      <div class="screen-body">
        ${renderAudiogramSvg(results)}
        <div class="card">
          <h3 class="card-title">${rec ? `${rec.overall} (${rec.strategyLabel})` : 'Sample Threshold Summary'}</h3>
          ${results.map((r) => `<div class="small-note" style="margin-top:4px">${r.ear.toUpperCase()} · ${r.frequencyHz} Hz: ${r.thresholdDb} dBFS</div>`).join('')}
        </div>
      </div>
    `;
  }

  if (state.testSub === 'BRIEFING') {
    const freqs = state.profile.useSixFrequencies ? '6 test frequencies (250, 500, 1000, 2000, 4000, 8000 Hz)' : '4 core frequencies (500, 1000, 2000, 4000 Hz)';
    const isInitial = state.initialTestPending || (!state.profile.initialScreeningCompleted && !state.savedSessions.length);
    const ready = state.headphoneConnected && state.noiseAssessment === NoiseAssessment.VALID;
    return `
      ${topbar('Initial Screening Briefing', {
        backAction: 'test-main',
        actionsHtml: `
          <button class="pill clickable ${state.showSimDrawer || state.isSimulationMode ? 'amber' : ''}" data-action="toggle-sim">DEV SIM</button>
          <span class="pill">${isInitial ? 'Initial Input' : state.strategyType === StrategyType.MODIFIED_HUGHSON_WESTLAKE ? 'H-W' : 'Binary'}</span>
        `,
      })}
      <div class="screen-body">
        ${isInitial ? `
          <div class="card" style="background:var(--surface-alt);border-color:var(--pill-border)">
            <div class="row-gap" style="margin-bottom:6px">
              <span style="color:var(--primary)">${icons.person}</span>
              <h3 class="card-title" style="font-size:16px">Welcome, ${esc(state.profile.preferredName)}</h3>
            </div>
            <p class="subtitle" style="font-size:13.5px;margin-bottom:8px">Complete this initial tone test to identify your baseline hearing input and automatically calibrate ECHO's Sound Monitor &amp; EQ.</p>
            <div class="chip-row">
              <span class="pill ${state.headphoneConnected ? 'emerald' : 'rose'}">${state.headphoneConnected ? 'Headphones Ready' : 'Headphones Needed'}</span>
              <span class="pill ${state.noiseAssessment === NoiseAssessment.VALID ? 'emerald' : 'amber'}">${state.noiseAssessment === NoiseAssessment.VALID ? 'Room Quiet' : 'Check Noise'}</span>
            </div>
          </div>
        ` : ''}
        <div class="card">
          <div class="row-gap" style="margin-bottom:10px">
            <span style="color:var(--primary)">${icons.ear}</span>
            <h3 class="card-title">Preliminary Tone Screening</h3>
          </div>
          <p style="font-size:14.5px;line-height:1.5;margin:0 0 10px">This sound check presents a sequence of ${freqs}, beginning at reference 1000 Hz, to evaluate relative auditory response.</p>
          <p class="subtitle" style="font-size:13.5px;margin-bottom:10px">Whenever you hear a tone pulse, tap "I Hear It". If you do not hear it after several pulses, tap "Can't Hear It" to test the next relative level.</p>
          <div class="toggle-row">
            <span style="font-size:13px;font-weight:600">Use full 6 frequencies (250–8000 Hz)</span>
            <label class="switch">
              <input type="checkbox" ${state.profile.useSixFrequencies ? 'checked' : ''} data-action="toggle-six-freq" />
              <span class="slider-track"></span>
            </label>
          </div>
        </div>
        <div class="card">
          <h3 class="card-title" style="margin-bottom:8px">Screening Protocol</h3>
          <p style="font-size:13.5px;line-height:1.65;margin:0">
            • Left Ear tested first across all test frequencies.<br/>
            • Button-driven interstitial transition.<br/>
            • Right Ear tested second.<br/>
            • Automatic ambient noise gating pauses on disturbance.<br/>
            • Initial audiogram &amp; Monitor DSP reference saved upon completion.
          </p>
        </div>
        <div style="flex:1"></div>
        ${ready ? `<button class="btn-pill" data-action="start-practice">${icons.play} Try Practice Tone (1000 Hz)</button>` : ''}
        <button class="btn-primary" data-action="begin-screening">${icons.play} ${ready ? 'Begin Initial Screening' : 'Check Headphones &amp; Noise Setup'}</button>
        ${isInitial ? `<button class="text-action-btn" style="align-self:center;color:var(--muted)" data-action="skip-initial">Skip baseline for now</button>` : ''}
      </div>
    `;
  }

  // MAIN SCREENING FLOW
  if (state.screeningState === ScreeningState.DEVICE_READINESS || state.screeningState === ScreeningState.TEST_PREP) {
    const noiseCls = state.noiseAssessment === NoiseAssessment.VALID ? 'emerald'
      : state.noiseAssessment === NoiseAssessment.SUSPECT ? 'amber'
        : state.noiseAssessment === NoiseAssessment.INVALID ? 'rose' : '';
    const noiseTxt = state.noiseAssessment === NoiseAssessment.VALID ? 'Quiet · Ready'
      : state.noiseAssessment === NoiseAssessment.SUSPECT ? 'Moderate Noise'
        : state.noiseAssessment === NoiseAssessment.INVALID ? 'Too Loud' : 'Mic Unavailable';

    return `
      ${topbar('Device Setup', {
        actionsHtml: `
          <button class="pill clickable ${state.showSimDrawer || state.isSimulationMode ? 'amber' : ''}" data-action="toggle-sim">DEV SIM</button>
          <button class="pill clickable" data-action="test-history">${icons.history} History</button>
        `,
      })}
      <div class="screen-body">
        <div>
          <h2 class="section-title">Headphone Check</h2>
          <p class="subtitle">Verify your headphones before proceeding to preliminary screening.</p>
        </div>
        ${state.initialTestPending ? `
          <div class="card" style="background:var(--surface-alt);border-color:var(--pill-border)">
            <div style="font-weight:700;font-size:14px;color:var(--navy)">Initial Hearing Test Pending</div>
            <div class="small-note">Connect headphones in a quiet room to begin your post-login initial hearing input check.</div>
          </div>
        ` : ''}
        <div class="chip-row">
          <button class="chip ${state.headphoneConnected ? 'selected' : ''}" data-action="set-hp" data-val="1">${state.headphoneConnected ? icons.check : ''} Connected</button>
          <button class="chip ${!state.headphoneConnected ? 'selected' : ''}" data-action="set-hp" data-val="0">Disconnected</button>
          ${state.noiseAssessment === NoiseAssessment.UNAVAILABLE ? `<span class="chip selected">Permission Denied</span>` : ''}
        </div>
        ${state.pauseReason ? `<div class="card rose"><div class="small-note" style="color:var(--rose);font-weight:600">${esc(state.pauseReason)}</div></div>` : ''}
        <div class="card">
          <div class="row-between">
            <div class="row-gap">
              <span style="color:${state.headphoneConnected ? 'var(--primary)' : 'var(--rose)'}">${icons.bluetooth}</span>
              <div>
                <div class="row-gap" style="gap:8px">
                  <strong style="font-size:15px">${state.headphoneConnected ? 'Headphones Connected' : 'Speaker Active'}</strong>
                  <span class="pill">${icons.info} ${state.isSimulationMode ? 'Simulated' : 'Sample data'}</span>
                </div>
                <div class="small-note" style="color:${state.headphoneConnected ? 'var(--muted)' : 'var(--rose)'}">${esc(state.routeName)}</div>
              </div>
            </div>
          </div>
        </div>

        <div class="card">
          <div class="row-between" style="margin-bottom:6px">
            <strong style="font-size:15px">Ambient Noise Monitor</strong>
            <span class="pill ${noiseCls}">${noiseTxt}</span>
          </div>
          <div class="small-note">${state.noiseAssessment === NoiseAssessment.UNAVAILABLE ? 'Noise Level: Unavailable (Permission denied)' : `Noise Level: ${state.noiseDbFs.toFixed(1)} dBFS (RMS)`}</div>
        </div>

        <div class="card">
          <strong style="font-size:15px;display:block;margin-bottom:8px">Threshold Estimation Algorithm</strong>
          <div class="grid-2">
            <button class="chip ${state.strategyType === StrategyType.MODIFIED_HUGHSON_WESTLAKE ? 'selected' : ''}" style="justify-content:center" data-action="set-strategy" data-val="${StrategyType.MODIFIED_HUGHSON_WESTLAKE}">Hughson–Westlake</button>
            <button class="chip ${state.strategyType === StrategyType.BINARY_SEARCH_REFINEMENT ? 'selected' : ''}" style="justify-content:center" data-action="set-strategy" data-val="${StrategyType.BINARY_SEARCH_REFINEMENT}">Binary Search (Exp)</button>
          </div>
          <p class="small-note" style="margin-top:8px">
            ${state.strategyType === StrategyType.MODIFIED_HUGHSON_WESTLAKE
              ? 'Modified Hughson–Westlake: Down-10 / Up-5 staircase requiring 2 ascending responses.'
              : 'Binary Search Refinement: Bracket interval halving with deterministic midpoint convergence.'}
          </p>
        </div>

        <div class="card">
          <h3 class="card-title" style="margin-bottom:10px">Screening Checklist</h3>
          <div class="row-gap" style="align-items:flex-start;margin-bottom:8px"><span class="step-num">1</span><div><strong style="font-size:14px">Secure Fit</strong><div class="small-note">Ensure both left and right earcups fit comfortably.</div></div></div>
          <div class="row-gap" style="align-items:flex-start;margin-bottom:8px"><span class="step-num">2</span><div><strong style="font-size:14px">Quiet Environment</strong><div class="small-note">Minimize background noise and conversations around you.</div></div></div>
          <div class="row-gap" style="align-items:flex-start"><span class="step-num">3</span><div><strong style="font-size:14px">Moderate Volume</strong><div class="small-note">Set your device volume to a comfortable, moderate level.</div></div></div>
        </div>

        <button class="btn-pill" data-action="start-practice">${icons.play} Try Practice Tone (1000 Hz)</button>
        <button class="btn-primary" data-action="to-briefing">${icons.forward} Continue to Screening Briefing</button>
      </div>
    `;
  }

  if (state.screeningState === ScreeningState.PRACTICE_PRESENTATION || state.screeningState === ScreeningState.PRACTICE_FEEDBACK) {
    return `
      ${topbar('Practice Trial', { backAction: 'back-setup' })}
      <div class="screen-body centered">
        <div class="card">
          <div style="display:flex;flex-direction:column;align-items:center;gap:12px">
            <div class="icon-badge circle-lg ${state.practiceTonePlaying ? 'pulse' : ''}">${icons.wave}</div>
            <h3 class="card-title" style="font-size:20px">1000 Hz Demo Tone (Left Ear)</h3>
            <p class="subtitle">${esc(state.practiceMessage)}</p>
            ${state.screeningState === ScreeningState.PRACTICE_PRESENTATION ? `
              <button class="btn-primary" data-action="practice-heard">${icons.volOn} I Hear It</button>
              <button class="btn-pill" data-action="practice-not-heard">${icons.volOff} Can't Hear It</button>
            ` : `
              <button class="btn-pill" data-action="start-practice">Try Again</button>
              <button class="btn-primary" ${state.practiceHeard ? '' : 'disabled'} data-action="begin-screening">Start Formal Screening</button>
            `}
          </div>
        </div>
      </div>
    `;
  }

  if (state.screeningState === ScreeningState.EAR_TRANSITION) {
    return `
      ${topbar('Hearing Screening', {
        actionsHtml: `<button class="text-action-btn" data-action="pause-test">${icons.pause} Pause test</button>`,
      })}
      <div class="screen-body centered" style="padding:28px">
        <div style="color:var(--primary);transform:scale(2);margin-bottom:18px">${icons.headphones}</div>
        <h2 class="section-title">Left Ear Screening Complete</h2>
        <p class="subtitle" style="max-width:300px">Please reposition your headphones or adjust fit to ensure a comfortable seal for your right ear.</p>
        <button class="btn-primary" style="margin-top:14px" data-action="continue-right-ear">${icons.forward} Continue to Right Ear</button>
      </div>
    `;
  }

  if (state.screeningState === ScreeningState.RESULTS) {
    const out = state.outcome || computeScreeningOutcome(state.engine);
    const cls = out.overall === 'PASS' ? 'emerald' : out.overall === 'REFER' ? 'amber' : '';
    const title = out.overall === 'PASS' ? 'PRELIMINARY SCREENING PASS' : out.overall === 'REFER' ? 'REFERRAL RECOMMENDED' : 'SCREENING INCONCLUSIVE';
    const desc = out.overall === 'PASS'
      ? 'Responses recorded within provisional screening levels across tested frequencies in both ears.'
      : out.overall === 'REFER'
        ? 'Elevated response levels or non-responses detected. Formal diagnostic audiometry recommended.'
        : 'Incomplete target completion or interruptions occurred during screening.';

    return `
      ${topbar('Screening Results', { actionsHtml: `<button class="pill clickable" data-action="test-history">${icons.history} History</button>` })}
      <div class="screen-body">
        <div class="card ${cls}">
          <div style="font-weight:800;font-size:14px;margin-bottom:4px">${title}</div>
          <p class="subtitle" style="color:var(--navy);font-size:13.5px">${desc}</p>
          <div class="small-note" style="margin-top:6px">Algorithm: ${state.strategyType === StrategyType.MODIFIED_HUGHSON_WESTLAKE ? 'Modified Hughson–Westlake' : 'Binary Search Refinement'}</div>
        </div>
        ${state.justCompletedBaseline ? `
          <div class="card" style="background:var(--surface-alt);border-color:var(--pill-border)">
            <div style="font-weight:700;font-size:14px;color:var(--primary);margin-bottom:4px">Initial Hearing Input Captured</div>
            <div class="small-note" style="color:var(--navy)">Your baseline thresholds have been saved and automatically applied to Live Monitor's Audiogram Reference.</div>
          </div>
        ` : ''}
        ${renderAudiogramSvg(state.engine.results)}
        <div class="grid-2">
          <div class="card">
            <div style="color:var(--primary);font-weight:800;font-size:12px">LEFT EAR (AS)</div>
            <div style="font-weight:700;font-size:13px;margin:4px 0">${out.left.classification}</div>
            ${out.left.thresholds.map((t) => `<div class="small-note">${t.frequencyHz}Hz: ${t.thresholdDb} dBFS</div>`).join('')}
          </div>
          <div class="card">
            <div style="color:var(--rose);font-weight:800;font-size:12px">RIGHT EAR (AD)</div>
            <div style="font-weight:700;font-size:13px;margin:4px 0">${out.right.classification}</div>
            ${out.right.thresholds.map((t) => `<div class="small-note">${t.frequencyHz}Hz: ${t.thresholdDb} dBFS</div>`).join('')}
          </div>
        </div>
        <div class="card">
          <strong style="font-size:14px">Quality &amp; Reliability Metrics</strong>
          <div class="small-note" style="margin-top:6px">
            Total trials: ${state.engine.trials.length} · Contaminated retried: ${state.engine.contaminatedTrials.length} · Noise pauses: ${state.engine.noisePauseCount}<br/>
            Flags: ${state.engine.qualityFlags.join(', ')}
          </div>
        </div>
        <button class="btn-pill" data-action="import-to-monitor">${icons.download} Import to Monitor Reference</button>
        ${state.justCompletedBaseline ? `<button class="btn-primary" data-action="nav-tab" data-val="HOME">${icons.check} Done · Open Home Dashboard</button>` : ''}
        <button class="${state.justCompletedBaseline ? 'btn-pill' : 'btn-primary'}" data-action="restart-screening">${icons.refresh} ${state.justCompletedBaseline ? 'Retake Screening' : 'Restart Screening'}</button>
      </div>
    `;
  }

  // ACTIVE SCREENING / PAUSED
  const totalTargets = state.engine.ears.length * state.engine.frequenciesHz.length;
  const completed = state.engine.results.length;
  const pct = Math.round((completed / Math.max(1, totalTargets)) * 100);
  const target = getCurrentTarget(state.engine);
  const isPaused = [ScreeningState.AUTOMATIC_PAUSE_NOISE, ScreeningState.AUTOMATIC_PAUSE_DEVICE, ScreeningState.USER_PAUSED].includes(state.screeningState);
  const dotCls = state.noiseAssessment === NoiseAssessment.VALID ? 'valid' : state.noiseAssessment === NoiseAssessment.SUSPECT ? 'suspect' : 'invalid';

  return `
    ${topbar('Hearing Screening', {
      actionsHtml: `<button class="text-action-btn" data-action="${isPaused ? 'resume-test' : 'pause-test'}">${isPaused ? icons.play + ' Resume' : icons.pause + ' Pause test'}</button>`,
    })}
    <div class="screen-body">
      <div class="row-between">
        <div class="chip-row">
          <span class="pill">${icons.ear} ${target.ear === 'left' ? 'Left Ear' : 'Right Ear'}</span>
          <span class="pill">${icons.info} ${state.strategyType === StrategyType.MODIFIED_HUGHSON_WESTLAKE ? 'Hughson–Westlake' : 'Binary Search'}</span>
        </div>
        <button class="pill clickable ${state.showSimDrawer || state.isSimulationMode ? 'amber' : ''}" data-action="toggle-sim">DEV SIM</button>
      </div>

      <div>
        <div class="progress-track"><div class="progress-fill" style="width:${pct}%"></div></div>
        <div class="progress-meta">
          <span>Target ${Math.min(completed + 1, totalTargets)} of ${totalTargets}</span>
          <span>Progress: ${pct}%</span>
        </div>
      </div>

      ${isPaused ? `
        <div class="card amber" style="text-align:center;padding:24px">
          <h3 class="card-title" style="color:var(--amber);margin-bottom:6px">Screening Paused</h3>
          <p class="subtitle" style="margin-bottom:10px">${esc(state.pauseReason || 'Environmental disturbance detected.')}</p>
          ${state.screeningState === ScreeningState.AUTOMATIC_PAUSE_NOISE
            ? `<div style="color:var(--amber);font-weight:700;font-size:13px">Auto-resuming in ${state.recoverySeconds}s of quiet...</div>`
            : `<button class="btn-primary" data-action="resume-test">Resume Screening</button>`}
        </div>
      ` : `
        <div class="card" style="text-align:center;padding:26px 18px">
          <div style="display:flex;flex-direction:column;align-items:center;gap:10px">
            <div class="icon-badge circle-lg ${state.isTonePlaying ? 'pulse' : ''}">${icons.wave}</div>
            <div style="font-size:32px;font-weight:800;color:var(--navy)">${target.frequencyHz} Hz</div>
            <div class="subtitle" style="font-size:15px">Digital Level ${state.engine.currentLevelDb} dBFS · Trial ${state.engine.trials.length + 1}</div>
            <div style="font-size:12.5px;font-weight:700;color:var(--primary)">
              ${state.isTonePlaying ? 'Presenting tone stimulus...' : state.isWaitingForResponse ? 'Did you hear the tone?' : 'Preparing next presentation...'}
            </div>
          </div>
        </div>
        <button class="btn-primary" ${state.isWaitingForResponse ? '' : 'disabled'} data-action="resp-heard">${icons.volOn} I Hear It</button>
        <button class="btn-pill" ${state.isWaitingForResponse ? '' : 'disabled'} data-action="resp-not-heard">${icons.volOff} Can't Hear It</button>
      `}

      <div style="flex:1"></div>
      <div class="card">
        <div class="row-between">
          <div class="row-gap" style="gap:8px">
            <span class="dot ${dotCls}"></span>
            <span class="small-note">Ambient: ${state.noiseDbFs.toFixed(1)} dBFS (${state.noiseAssessment})</span>
          </div>
          <button class="text-action-btn" style="color:var(--rose)" data-action="cancel-test">Cancel</button>
        </div>
      </div>
    </div>
  `;
}

// ---- HOME TAB ----

function renderHomeTab() {
  const latest = state.savedSessions[0];
  const needsInitial = state.initialTestPending || (!state.profile.initialScreeningCompleted && !latest);
  const baseline = latest ? extractBaselineSummary(latest.results) : null;
  return `
    ${topbar('ECHO', {
      actionsHtml: `<span class="pill ${state.monitor.running ? 'emerald' : ''}">${state.monitor.running ? 'Monitor Live' : 'Ready'}</span>`,
    })}
    <div class="screen-body">
      <div>
        <h2 class="section-title">Welcome back, ${esc(state.profile.preferredName)}</h2>
        <p class="subtitle">Personalized hearing clarity and daily listening monitoring.</p>
      </div>
      ${needsInitial ? `
        <div class="card" style="background:var(--surface-alt);border-color:var(--pill-border)">
          <div style="font-weight:700;font-size:15.5px;color:var(--primary);margin-bottom:4px">Initial Hearing Input Pending</div>
          <p class="subtitle" style="color:var(--navy);font-size:13.5px;margin-bottom:10px">Take your initial pure-tone screening to capture your baseline hearing input and calibrate ECHO.</p>
          <button class="btn-primary" data-action="start-initial-test">${icons.ear} Start Initial Hearing Test</button>
        </div>
      ` : ''}
      <div class="card">
        <div class="card-header">
          <h3 class="card-title">System Status</h3>
          <span class="pill">${state.headphoneConnected ? 'Headphones Ready' : 'Check Headphones'}</span>
        </div>
        <p class="subtitle" style="font-size:13.5px;margin-bottom:6px">
          ${latest ? `Baseline &amp; latest (${latest.overall}): L avg ${baseline?.leftAvgDb ?? '—'} dBFS · R avg ${baseline?.rightAvgDb ?? '—'} dBFS` : 'No screening saved yet. Run a preliminary pure-tone check to establish your baseline.'}
        </p>
        <div class="small-note" style="color:${state.monitor.running ? 'var(--emerald)' : 'var(--muted)'};font-weight:600">
          Live Audio Monitor: ${state.monitor.running ? `Active · ${state.monitor.processed ? 'ECHO DSP On' : 'Baseline'}` : 'Stopped'}
        </div>
      </div>
      <div class="card">
        <div class="row-gap" style="margin-bottom:12px">
          <div class="icon-badge">${icons.ear}</div>
          <div><div class="card-title" style="font-size:15.5px">Preliminary Sound Screening</div><div class="small-note">Hughson–Westlake or Binary Search screening with ambient noise gating.</div></div>
        </div>
        <button class="btn-primary" data-action="nav-tab" data-val="TEST">Open Screening</button>
      </div>
      <div class="card">
        <div class="row-gap" style="margin-bottom:12px">
          <div class="icon-badge">${icons.wave}</div>
          <div><div class="card-title" style="font-size:15.5px">Live Audio Monitor &amp; DSP</div><div class="small-note">Noise gate, adaptive denoiser, 4-band compression &amp; 6-band per-ear EQ.</div></div>
        </div>
        <button class="btn-primary" data-action="nav-tab" data-val="MONITOR">Open Sound Monitor</button>
      </div>
      <button class="btn-pill" data-action="open-history-from-home">${icons.history} View Screening History (${state.savedSessions.length})</button>
    </div>
  `;
}

// ---- MONITOR TAB (Image 4 + Full DSP Settings) ----

function renderMonitorTab() {
  const m = state.monitor;

  if (state.monitorSub === 'HISTORY') {
    return `
      ${topbar('Exposure History', { backAction: 'mon-main', actionsHtml: `<span class="pill">${icons.info} ${m.trials.length ? `${m.trials.length} logs` : 'Sample data'}</span>` })}
      <div class="screen-body">
        <div class="card">
          <h3 class="card-title">Recent Ambient Exposure (Sample)</h3>
          <p class="subtitle" style="margin-top:6px">• Today · 09:30 AM · Quiet Room · Comfortable<br/>• Today · 11:15 AM · Commute · Moderate Level<br/>• Yesterday · 06:00 PM · Cafe · Moderate Level</p>
        </div>
        <div class="card">
          <h3 class="card-title">Speech Clarity A/B Logs</h3>
          ${m.trials.length ? m.trials.map((t) => `<div class="small-note" style="margin-top:6px">• ${esc(t)}</div>`).join('') : '<p class="small-note" style="margin-top:6px">No clarity trials logged yet.</p>'}
        </div>
      </div>
    `;
  }

  if (state.monitorSub === 'DETAILS') {
    return `
      ${topbar('Exposure Details', { backAction: 'mon-main', actionsHtml: `<span class="pill">${m.running ? 'Live' : 'Sample data'}</span>` })}
      <div class="screen-body">
        <div class="card">
          <h3 class="card-title" style="margin-bottom:8px">Audio Stream &amp; DSP Pipeline</h3>
          ${detailRow('Monitor State', m.running ? 'Running' : 'Stopped')}
          ${detailRow('Processing Mode', m.processed ? 'Processed (4-band LR4 + EQ)' : 'Baseline (Bypass)')}
          ${detailRow('Volume Trim', `${Math.round(m.monitorLevel * 100)}% (max 50%)`)}
          ${detailRow('Noise Gate', m.gateEnabled ? `On (${m.gateThresholdDb} dBFS)` : 'Off')}
          ${detailRow('Adaptive Denoiser', m.denoiserEnabled ? `On (${m.denoiserStrengthDb} dB)` : 'Off')}
          ${detailRow('Speech Compression', m.compressionEnabled ? `On (${m.compressionRatio.toFixed(1)}:1)` : 'Off')}
        </div>
      </div>
    `;
  }

  if (state.monitorSub === 'SETTINGS') {
    return `
      ${topbar('Monitoring Settings', { backAction: 'mon-main' })}
      <div class="screen-body">
        ${accordion('dsp', 'Noise and speech processing', `
          ${switchRow('Noise gate (quiet-period hiss)', m.gateEnabled, 'mon-gate-toggle')}
          ${m.gateEnabled ? `<label class="small-note">Threshold: <strong id="lblGate">${m.gateThresholdDb}</strong> dBFS</label><input type="range" min="-72" max="-36" step="1" value="${m.gateThresholdDb}" data-range="gateThresholdDb" data-lbl="lblGate" />` : ''}
          ${switchRow('Adaptive noise reduction (experimental)', m.denoiserEnabled, 'mon-den-toggle')}
          ${m.denoiserEnabled ? `<label class="small-note">Max attenuation: <strong id="lblDen">${m.denoiserStrengthDb}</strong> dB</label><input type="range" min="0" max="18" step="1" value="${m.denoiserStrengthDb}" data-range="denoiserStrengthDb" data-lbl="lblDen" />` : ''}
          ${switchRow('Speech compression (4-band)', m.compressionEnabled, 'mon-comp-toggle')}
          ${m.compressionEnabled ? `<label class="small-note">Ratio: <strong id="lblComp">${m.compressionRatio.toFixed(1)}</strong>:1</label><input type="range" min="1" max="3" step="0.1" value="${m.compressionRatio}" data-range="compressionRatio" data-lbl="lblComp" />` : ''}
        `)}

        ${accordion('eq', 'Hearing profile (6-band per-ear EQ)', `
          <p class="small-note">Fitting gain offsets, ±6 dB per band. Use only gains from an audiogram-based fitting.</p>
          ${['Left ear', 'Right ear'].map((earName, earIdx) => `
            <div style="font-weight:700;color:var(--primary);font-size:13.5px;margin-top:6px">${earName}</div>
            ${EQ_CENTERS_HZ.map((hz, bandIdx) => `
              <div>
                <div class="small-note">${hz >= 1000 ? `${hz / 1000} kHz` : `${hz} Hz`}: <strong id="eq_${earIdx}_${bandIdx}">${m.gains[earIdx][bandIdx] >= 0 ? '+' : ''}${m.gains[earIdx][bandIdx].toFixed(1)}</strong> dB</div>
                <input type="range" min="-6" max="6" step="0.5" value="${m.gains[earIdx][bandIdx]}" data-eq="${earIdx},${bandIdx}" />
              </div>
            `).join('')}
          `).join('')}
        `)}

        ${accordion('audiogram', 'Audiogram and verification record', `
          <p class="small-note">Reference only: thresholds do not change any gain. Import latest ECHO screening or enter dB HL.</p>
          <button class="btn-pill" data-action="mon-import">${icons.download} Import latest screening</button>
          ${m.importMessage ? `<div class="small-note" style="color:var(--primary)">${esc(m.importMessage)}</div>` : ''}
          ${['Left ear (dB HL)', 'Right ear (dB HL)'].map((earName, earIdx) => `
            <div style="font-weight:700;color:var(--primary);font-size:13px">${earName}</div>
            <div class="grid-3">
              ${EQ_CENTERS_HZ.map((hz, b) => `<input class="input-box" style="height:38px;font-size:12.5px" placeholder="${hz >= 1000 ? hz / 1000 + 'k' : hz}" value="${esc(m.thresholds[earIdx][b])}" data-thresh="${earIdx},${b}" />`).join('')}
            </div>
          `).join('')}
          <label class="row-gap" style="font-size:13px">
            <input type="checkbox" ${m.realEarVerified ? 'checked' : ''} data-action="mon-real-ear" /> External real-ear measurement reviewed
          </label>
          <textarea class="input-box" placeholder="Date, equipment, target, measured dB SPL" data-input="realEarNotes">${esc(m.realEarNotes)}</textarea>
        `)}

        ${accordion('clarity', 'Speech clarity A/B log', `
          <p class="small-note">Read the same unseen word list in Processed and Baseline mode, then log understood words.</p>
          <div class="chip-row">
            ${['Quiet', 'Background noise'].map((env) => `<button class="chip ${m.environment === env ? 'selected' : ''}" data-action="mon-env" data-val="${env}">${env}</button>`).join('')}
          </div>
          <div class="grid-2">
            <input class="input-box" id="clarityCorrect" placeholder="Correct" value="${esc(state.clarityCorrect)}" />
            <input class="input-box" id="clarityTotal" placeholder="List size" value="${esc(state.clarityTotal)}" />
          </div>
          <button class="btn-primary" data-action="mon-save-trial">Save ${m.processed ? 'processed' : 'baseline'} score</button>
          ${m.trialMessage ? `<div class="small-note" style="color:var(--amber)">${esc(m.trialMessage)}</div>` : ''}
          ${m.trials.slice(0, 10).map((t) => `<div class="small-note">• ${esc(t)}</div>`).join('')}
        `)}

        <button class="text-action-btn" style="justify-content:center" data-action="mon-reset">Reset to cautious defaults</button>
      </div>
    `;
  }

  return `
    ${topbar('Sound Monitoring', {
      actionsHtml: `<span class="pill ${m.running ? 'emerald' : ''}">${m.running ? icons.wave + ' Live DSP' : icons.info + ' Sample data'}</span>`,
    })}
    <div class="screen-body">
      <div class="card">
        <div class="card-header">
          <h3 class="card-title">Live Sound Monitor</h3>
          <span class="pill">${icons.info} ${m.running ? 'Live' : 'Sample data'}</span>
        </div>
        <div class="row-gap" style="margin:8px 0 14px">
          <span style="color:${m.running ? 'var(--emerald)' : 'var(--primary)'}">${icons.mic}</span>
          <div>
            <div style="font-size:23px;font-weight:800;color:${m.running ? 'var(--emerald)' : 'var(--primary)'}">${m.running ? 'Monitoring Active' : 'Moderate Level'}</div>
            <div class="subtitle" style="font-size:13.5px">${m.running ? esc(m.status) : 'Comfortable ambient environment'}</div>
          </div>
        </div>
        <hr style="border:none;border-top:1px solid var(--border);margin:10px 0" />
        <div class="field-group" style="margin-bottom:10px">
          <label class="small-note">Microphone</label>
          <select class="input-box" style="height:42px" ${m.running ? 'disabled' : ''} data-select="inputDevice">
            <option ${m.inputDevice.includes('Built-in') ? 'selected' : ''}>Built-in Microphone · Phone mic</option>
            <option ${m.inputDevice.includes('Headset') ? 'selected' : ''}>Wired Headset Mic</option>
          </select>
        </div>
        <div class="field-group" style="margin-bottom:10px">
          <label class="small-note">Output (earbuds)</label>
          <select class="input-box" style="height:42px" ${m.running ? 'disabled' : ''} data-select="outputDevice">
            <option ${m.outputDevice.includes('Bluetooth') ? 'selected' : ''}>Bluetooth Audio (A2DP) · Earbuds</option>
            <option ${m.outputDevice.includes('Wired') ? 'selected' : ''}>Wired Headphones (3.5mm / USB-C)</option>
          </select>
        </div>
        <div style="margin-bottom:10px">
          <div class="small-note">Volume trim: <strong id="lblVol">${Math.round(m.monitorLevel * 100)}</strong>% (max 50%)</div>
          <input type="range" min="0" max="0.5" step="0.01" value="${m.monitorLevel}" data-range="monitorLevel" data-lbl="lblVol" />
        </div>
        ${switchRow('Processed Mode (A/B) — ' + (m.processed ? 'ECHO DSP on' : 'Baseline bypass'), m.processed, 'mon-processed-toggle')}
        <div style="margin-top:12px">
          ${m.running
            ? `<button class="btn-primary danger" data-action="mon-stop">Stop Monitor</button>`
            : `<button class="btn-primary" data-action="mon-start">${icons.play} Start Live Monitor</button>`}
        </div>
        <p class="small-note" style="color:var(--amber);margin-top:8px">Start with low phone and earbud volume. Prototype only; not a hearing aid.</p>
      </div>

      <button class="btn-pill" data-action="mon-history">${icons.history} View Exposure History</button>
      <button class="btn-pill" data-action="mon-details">${icons.chart} Exposure Details</button>
      <button class="btn-pill" data-action="mon-settings">${icons.settings} Monitoring Settings</button>
    </div>
  `;
}

function detailRow(k, v) {
  return `<div class="row-between" style="padding:5px 0;border-bottom:1px solid var(--border);font-size:13.5px"><span style="color:var(--muted)">${esc(k)}</span><strong>${esc(v)}</strong></div>`;
}

function switchRow(label, checked, action) {
  return `<div class="toggle-row" style="margin:4px 0"><span style="font-size:13.5px;font-weight:600">${esc(label)}</span><label class="switch"><input type="checkbox" ${checked ? 'checked' : ''} data-action="${action}" /><span class="slider-track"></span></label></div>`;
}

function accordion(key, title, bodyHtml) {
  const open = state.accordion[key];
  return `
    <div class="card">
      <div class="accordion-head" data-action="toggle-acc" data-val="${key}">
        <strong style="font-size:15px">${esc(title)}</strong>
        <span style="color:var(--primary);font-size:20px;font-weight:700">${open ? '−' : '+'}</span>
      </div>
      ${open ? `<div class="accordion-body">${bodyHtml}</div>` : ''}
    </div>
  `;
}

// ---- REPORTS TAB (Image 1) ----

function renderReportsTab() {
  if (state.reportsSub === 'WEEKLY') {
    const days = [['Mon', 35], ['Tue', 50], ['Wed', 42], ['Thu', 60], ['Fri', 48], ['Sat', 30], ['Sun', 25]];
    return `
      ${topbar('Weekly Report', { backAction: 'rep-main', actionsHtml: `<span class="pill">${icons.info} Sample data</span>` })}
      <div class="screen-body">
        <div class="card">
          <h3 class="card-title" style="margin-bottom:12px">Weekly Safe Listening Budget (Sample)</h3>
          <div style="display:flex;align-items:flex-end;justify-content:space-around;height:120px;padding-top:10px">
            ${days.map(([d, h]) => `<div style="display:flex;flex-direction:column;align-items:center;gap:6px"><div style="width:22px;height:${h * 1.4}px;background:var(--primary);border-radius:6px 6px 0 0"></div><span class="small-note">${d}</span></div>`).join('')}
          </div>
        </div>
        <div class="card">
          <h3 class="card-title">Recorded Device Activity</h3>
          <p class="subtitle" style="margin-top:6px">• Saved screenings: ${state.savedSessions.length}<br/>• Logged Speech Clarity A/B trials: ${state.monitor.trials.length}</p>
        </div>
      </div>
    `;
  }
  if (state.reportsSub === 'TRENDS') {
    return `
      ${topbar('Exposure Trends', { backAction: 'rep-main', actionsHtml: `<span class="pill">${icons.info} Sample data</span>` })}
      <div class="screen-body">
        <div class="card">
          <h3 class="card-title" style="margin-bottom:10px">Ambient Level Distribution (Sample)</h3>
          ${trendBar('Quiet (< -45 dBFS)', 65, 'var(--emerald)')}
          ${trendBar('Moderate (-45 to -32 dBFS)', 28, 'var(--primary)')}
          ${trendBar('Elevated (> -32 dBFS)', 7, 'var(--amber)')}
        </div>
      </div>
    `;
  }
  if (state.reportsSub === 'TIPS') {
    return `
      ${topbar('Insights & Tips', { backAction: 'rep-main' })}
      <div class="screen-body">
        <div class="card"><h3 class="card-title">Quiet Screening Room</h3><p class="subtitle">Run preliminary tone checks in a room below -45 dBFS so the noise gate remains green.</p></div>
        <div class="card"><h3 class="card-title">Conservative Monitor Trim</h3><p class="subtitle">Start Live Monitor volume trim near 15% and never exceed comfortable listening levels.</p></div>
        <div class="card"><h3 class="card-title">Matched A/B Word Lists</h3><p class="subtitle">Use unseen word lists of equal size when comparing Processed vs Baseline speech clarity.</p></div>
      </div>
    `;
  }
  if (state.reportsSub === 'HISTORICAL') {
    return `
      ${topbar('Historical Data', { backAction: 'rep-main' })}
      <div class="screen-body">
        <div class="card">
          <h3 class="card-title">Screening Sessions (${state.savedSessions.length})</h3>
          <p class="small-note" style="margin:6px 0 10px">${state.savedSessions.length ? state.savedSessions.map((s) => `• ${new Date(s.at).toLocaleString()} — ${s.overall}`).join('<br/>') : 'No saved screenings yet.'}</p>
          <button class="btn-pill" data-action="open-history-from-home">Open Full Screening History</button>
        </div>
        <div class="card">
          <h3 class="card-title">Speech Clarity A/B Trials (${state.monitor.trials.length})</h3>
          <p class="small-note" style="margin-top:6px">${state.monitor.trials.length ? state.monitor.trials.map((t) => `• ${esc(t)}`).join('<br/>') : 'No speech clarity logs recorded yet.'}</p>
        </div>
      </div>
    `;
  }

  return `
    ${topbar('Listening Reports', { actionsHtml: `<span class="pill">${icons.info} Sample data</span>` })}
    <div class="screen-body">
      <div class="card">
        <div class="card-header">
          <h3 class="card-title" style="font-size:20px">Weekly Summary</h3>
          <span class="pill">${icons.info} Sample data</span>
        </div>
        <p class="subtitle">Your listening habits remained 100% within recommended sound limits this week.</p>
      </div>
      <button class="btn-pill" data-action="rep-sub" data-val="WEEKLY">${icons.chart} Weekly Report</button>
      <button class="btn-pill" data-action="rep-sub" data-val="TRENDS">${icons.trend} Exposure Trends</button>
      <button class="btn-pill" data-action="rep-sub" data-val="TIPS">${icons.bulb} Insights &amp; Tips</button>
      <button class="btn-pill" data-action="rep-sub" data-val="HISTORICAL">${icons.history} Historical Data</button>
    </div>
  `;
}

function trendBar(label, pct, color) {
  return `<div style="margin-bottom:10px"><div class="row-between" style="font-size:13px;margin-bottom:4px"><span>${label}</span><strong style="color:${color}">${pct}%</strong></div><div class="progress-track"><div class="progress-fill" style="width:${pct}%;background:${color}"></div></div></div>`;
}

// ---- PROFILE TAB (Image 10) ----

function renderProfileTab() {
  if (state.profileSub === 'EDIT') {
    const ages = ['18–35', '36–50', '51–65', '65+'];
    const langs = ['English', 'Spanish', 'French', 'German'];
    return `
      ${topbar('Edit Profile', { backAction: 'prof-main' })}
      <div class="screen-body">
        <div class="field-group"><label class="field-label">Preferred Name</label><input class="input-box" id="editName" value="${esc(state.profile.preferredName)}" /></div>
        <div class="field-group"><label class="field-label">Age Range</label><div class="chip-row">${ages.map((a) => `<button class="chip ${state.profile.ageRange === a ? 'selected' : ''}" data-action="set-age" data-val="${a}">${a}</button>`).join('')}</div></div>
        <div class="field-group"><label class="field-label">Preferred Language</label><div class="chip-row">${langs.map((l) => `<button class="chip ${state.profile.preferredLanguage === l ? 'selected' : ''}" data-action="set-lang" data-val="${l}">${l}</button>`).join('')}</div></div>
        <div style="flex:1"></div>
        <button class="btn-primary" data-action="save-edit-profile">Save Profile</button>
      </div>
    `;
  }
  if (state.profileSub === 'DEVICES') {
    return `
      ${topbar('Connected Devices', { backAction: 'prof-main' })}
      <div class="screen-body">
        <div class="card">
          <h3 class="card-title">Active Audio Route</h3>
          <p class="subtitle" style="margin-top:6px">${esc(state.routeName)} (${state.headphoneConnected ? 'Headphones connected' : 'Speaker active'})</p>
        </div>
      </div>
    `;
  }
  if (state.profileSub === 'NOTIFICATIONS') {
    return `
      ${topbar('Notifications', { backAction: 'prof-main' })}
      <div class="screen-body">
        <div class="card">${switchRow('Screening & Listening Alerts', state.profile.notificationsEnabled, 'perm-notif')}<p class="small-note">Reminder cadence: ${esc(state.profile.reminderFrequency)}</p></div>
      </div>
    `;
  }
  if (state.profileSub === 'PRIVACY') {
    return `
      ${topbar('Privacy & Data', { backAction: 'prof-main' })}
      <div class="screen-body">
        <div class="card">
          <h3 class="card-title">Offline-First Privacy Guarantee</h3>
          <p class="subtitle" style="margin-top:6px">• Audio is analyzed transiently in RAM only.<br/>• Zero raw audio is saved or transmitted.<br/>• Screening history and EQ profiles persist locally.</p>
        </div>
        <button class="btn-pill" data-action="restart-onboarding">Re-open Welcome &amp; Health Notice</button>
      </div>
    `;
  }
  if (state.profileSub === 'EXPORT') {
    const json = JSON.stringify({ profile: state.profile, screeningSessions: state.savedSessions, speechClarityTrials: state.monitor.trials }, null, 2);
    return `
      ${topbar('Export Data', { backAction: 'prof-main' })}
      <div class="screen-body">
        <button class="btn-primary" data-action="copy-json">${state.copiedJson ? 'Copied JSON to Clipboard' : 'Copy Export JSON'}</button>
        <div class="card"><h3 class="card-title" style="margin-bottom:8px">JSON Export Preview</h3><pre class="json-preview">${esc(json)}</pre></div>
      </div>
    `;
  }
  if (state.profileSub === 'ABOUT') {
    return `
      ${topbar('About ECHO', { backAction: 'prof-main' })}
      <div class="screen-body">
        <div class="card"><h3 class="card-title">ECHO Integrated POC</h3><p class="subtitle" style="margin-top:6px">Combines pure-tone screening (Modified Hughson–Westlake &amp; Experimental Binary Search Refinement with ambient noise gating) and live audio DSP controls (4-band LR4 crossover, noise gate, adaptive denoiser, downward compression, and 6-band per-ear EQ). Engineering prototype only.</p></div>
      </div>
    `;
  }
  if (state.profileSub === 'FAQ') {
    return `
      ${topbar('Help & FAQ', { backAction: 'prof-main' })}
      <div class="screen-body">
        <div class="card"><h3 class="card-title">Why dBFS instead of dB HL?</h3><p class="subtitle" style="margin-top:4px">Consumer hardware lacks artificial-ear calibration, so ECHO honestly reports digital attenuation (dBFS).</p></div>
        <div class="card"><h3 class="card-title">Why does Monitor stop when switching tabs?</h3><p class="subtitle" style="margin-top:4px">Screening and Live Monitor share the microphone and output route, so leaving Monitor safely stops the live stream.</p></div>
      </div>
    `;
  }

  return `
    ${topbar('Profile & Settings')}
    <div class="screen-body">
      <div class="card clickable" data-action="prof-sub" data-val="EDIT">
        <div class="row-gap">
          <div class="icon-badge circle-lg" style="width:56px;height:56px">${icons.person}</div>
          <div style="flex:1">
            <div class="card-title" style="font-size:19px">${esc(state.profile.preferredName)}</div>
            <div class="subtitle" style="font-size:13.5px">Standard Listening Profile</div>
            <div class="small-note">${esc(state.profile.ageRange)} · ${esc(state.profile.preferredLanguage)} · ${esc(state.profile.accountMode)}</div>
          </div>
        </div>
      </div>
      <button class="btn-pill" data-action="prof-sub" data-val="DEVICES">${icons.headphones} Connected Devices</button>
      <button class="btn-pill" data-action="prof-sub" data-val="NOTIFICATIONS">${icons.bell} Notifications</button>
      <button class="btn-pill" data-action="prof-sub" data-val="PRIVACY">${icons.lock} Privacy &amp; Data</button>
      <button class="btn-pill" data-action="prof-sub" data-val="EXPORT">${icons.download} Export Data</button>
      <button class="btn-pill" data-action="prof-sub" data-val="ABOUT">${icons.info} About ECHO</button>
      <button class="btn-pill" data-action="prof-sub" data-val="FAQ">${icons.help} Help &amp; FAQ</button>
      <button class="btn-pill" data-action="sign-out">${icons.back} Sign Out / Switch Account</button>
    </div>
  `;
}

// ---- BOTTOM NAV + SIM DRAWER ----

function renderBottomNav() {
  const items = [
    ['TEST', 'Test', icons.ear],
    ['HOME', 'Home', icons.grid],
    ['MONITOR', 'Monitor', icons.wave],
    ['REPORTS', 'Reports', icons.chart],
    ['PROFILE', 'Profile', icons.person],
  ];
  return `
    <nav class="bottom-nav">
      ${items.map(([id, label, icon]) => `
        <button class="nav-item ${state.tab === id ? 'active' : ''}" data-action="nav-tab" data-val="${id}">
          <span class="nav-pill">${icon}</span>
          <span>${label}</span>
        </button>
      `).join('')}
    </nav>
  `;
}

function renderSimDrawer() {
  if (!state.showSimDrawer) return '';
  return `
    <div class="sim-drawer">
      <div class="row-between" style="margin-bottom:8px">
        <strong style="color:${state.isSimulationMode ? 'var(--amber)' : 'var(--navy)'};font-size:14px">Developer Test Harness ${state.isSimulationMode ? '[ACTIVE]' : '[OFF]'}</strong>
        <button class="text-action-btn" data-action="toggle-sim">Close</button>
      </div>
      ${switchRow('Override Hardware with Synthetic Data', state.isSimulationMode, 'sim-mode-toggle')}
      <div class="grid-3" style="margin-top:10px">
        <button class="btn-primary danger" style="min-height:38px;font-size:12px" ${state.isSimulationMode ? '' : 'disabled'} data-action="sim-noise">Inject Noise</button>
        <button class="btn-primary" style="min-height:38px;font-size:12px;background:var(--emerald)" ${state.isSimulationMode ? '' : 'disabled'} data-action="sim-quiet">Clear Noise</button>
        <button class="btn-primary" style="min-height:38px;font-size:12px" ${state.isSimulationMode ? '' : 'disabled'} data-action="sim-unplug">Unplug</button>
      </div>
    </div>
  `;
}

function render() {
  const root = document.getElementById('app');
  if (!state.profile.onboardingCompleted) {
    root.innerHTML = renderOnboarding();
    return;
  }
  let content = '';
  if (state.tab === 'TEST') content = renderTestTab();
  else if (state.tab === 'HOME') content = renderHomeTab();
  else if (state.tab === 'MONITOR') content = renderMonitorTab();
  else if (state.tab === 'REPORTS') content = renderReportsTab();
  else content = renderProfileTab();

  root.innerHTML = `${content}${renderSimDrawer()}${renderBottomNav()}`;
}

// ---- SCREENING FLOW HELPERS ----

function createEngine() {
  const freqs = state.profile.useSixFrequencies ? EXTENDED_6_FREQUENCIES : DEFAULT_4_FREQUENCIES;
  return state.strategyType === StrategyType.BINARY_SEARCH_REFINEMENT
    ? createBinarySearchSession({ frequenciesHz: freqs })
    : createHughsonWestlakeSession({ frequenciesHz: freqs });
}

function startStimulusTrial() {
  clearTimers();
  state.screeningState = ScreeningState.STIMULUS_PRESENTATION;
  state.isTonePlaying = false;
  state.isWaitingForResponse = false;
  render();

  const jitter = 400 + Math.random() * 400;
  presentationTimer = setTimeout(() => {
    if (state.screeningState !== ScreeningState.STIMULUS_PRESENTATION) return;
    const target = getCurrentTarget(state.engine);
    state.isTonePlaying = true;
    state.isWaitingForResponse = true;
    render();

    toneGen.playTone({
      frequencyHz: target.frequencyHz,
      levelDb: state.engine.currentLevelDb,
      ear: target.ear,
      durationMs: 1200,
      onEnded: () => {
        state.isTonePlaying = false;
        if (state.screeningState === ScreeningState.STIMULUS_PRESENTATION) {
          state.screeningState = ScreeningState.WAITING_FOR_RESPONSE;
          render();
        }
      },
    });

    responseTimer = setTimeout(() => {
      if (state.isWaitingForResponse) {
        submitTrialResponse('NOT_HEARD');
      }
    }, 3500);
  }, jitter);
}

function submitTrialResponse(outcome) {
  clearTimers();
  state.isTonePlaying = false;
  state.isWaitingForResponse = false;
  const res = evaluateEngineTrial(state.engine, outcome, { ambientNoiseDbFs: state.noiseDbFs });
  state.engine = res.engine;

  if (res.action === 'COMPLETE') {
    finishScreeningSession();
    return;
  }
  if (res.switchedEar) {
    state.screeningState = ScreeningState.EAR_TRANSITION;
    render();
    return;
  }
  startStimulusTrial();
}

function finishScreeningSession() {
  clearTimers();
  state.outcome = computeScreeningOutcome(state.engine);
  state.screeningState = ScreeningState.RESULTS;
  const wasInitialPending = !state.profile.initialScreeningCompleted;
  state.savedSessions.unshift({
    id: `sess-${Date.now()}`,
    at: new Date().toISOString(),
    strategyLabel: state.strategyType === StrategyType.MODIFIED_HUGHSON_WESTLAKE ? 'Hughson–Westlake' : 'Binary Search',
    overall: state.outcome.overall,
    results: state.engine.results,
  });
  if (wasInitialPending) {
    state.profile.initialScreeningCompleted = true;
    state.initialTestPending = false;
    state.justCompletedBaseline = true;
    state.monitor = applyResultsToMonitor(state.monitor, state.engine.results);
  } else {
    state.justCompletedBaseline = false;
  }
  persist();
  render();
}

// ---- GLOBAL EVENT DELEGATION ----

document.getElementById('app').addEventListener('click', (e) => {
  const el = e.target.closest('[data-action]');
  if (!el) return;
  const action = el.dataset.action;
  const val = el.dataset.val;

  switch (action) {
    case 'onb-start': state.skipProfileSetup = false; state.onboardingStep = 'PROFILE_SETUP'; render(); break;
    case 'onb-account': state.onboardingStep = 'ACCOUNT'; render(); break;
    case 'onb-welcome': state.onboardingStep = 'WELCOME'; render(); break;
    case 'onb-profile': state.onboardingStep = 'PROFILE_SETUP'; render(); break;
    case 'onb-notice': state.onboardingStep = 'HEALTH_NOTICE'; render(); break;
    case 'acc-mode': state.accountMode = val; render(); break;
    case 'acc-submit': {
      state.profile.accountMode = state.accountMode;
      const em = document.getElementById('accEmail')?.value.trim() || 'alex@example.com';
      state.profile.email = em;
      if (!state.profile.preferredName || state.profile.preferredName === 'Alex Parker') {
        const local = em.split('@')[0];
        if (local) state.profile.preferredName = local.charAt(0).toUpperCase() + local.slice(1);
      }
      persist();
      if (state.accountMode === 'Sign In') {
        state.skipProfileSetup = true;
        state.onboardingStep = 'HEALTH_NOTICE';
      } else {
        state.skipProfileSetup = false;
        state.onboardingStep = 'PROFILE_SETUP';
      }
      render();
      break;
    }
    case 'acc-guest':
      state.profile.accountMode = 'Guest';
      state.skipProfileSetup = false;
      persist();
      state.onboardingStep = 'PROFILE_SETUP';
      render();
      break;
    case 'set-age': state.profile.ageRange = val; persist(); render(); break;
    case 'set-lang': state.profile.preferredLanguage = val; persist(); render(); break;
    case 'onb-to-notice':
      state.profile.preferredName = document.getElementById('profName')?.value.trim() || 'Alex Parker';
      persist();
      state.onboardingStep = 'HEALTH_NOTICE';
      render();
      break;
    case 'onb-accept-notice': state.onboardingStep = 'PERMISSIONS'; render(); break;
    case 'onb-complete': {
      const shouldRunInitial = !state.profile.initialScreeningCompleted && !state.savedSessions.length;
      state.profile.onboardingCompleted = true;
      if (shouldRunInitial) {
        state.profile.useSixFrequencies = true;
        state.initialTestPending = true;
        state.engine = createEngine();
        state.testSub = 'BRIEFING';
      } else {
        state.testSub = 'MAIN';
      }
      persist();
      state.tab = 'TEST';
      render();
      break;
    }
    case 'skip-initial':
      state.initialTestPending = false;
      state.testSub = 'MAIN';
      state.tab = 'HOME';
      render();
      break;
    case 'start-initial-test':
      state.tab = 'TEST';
      state.testSub = 'BRIEFING';
      render();
      break;

    case 'nav-tab':
      if (val !== 'MONITOR') stopLiveMonitor('Stopped');
      state.tab = val;
      render();
      break;

    case 'open-history-from-home':
      state.tab = 'TEST';
      state.testSub = 'HISTORY';
      render();
      break;

    case 'test-main': state.testSub = 'MAIN'; render(); break;
    case 'test-history': state.testSub = 'HISTORY'; render(); break;
    case 'test-compare': state.testSub = 'COMPARE'; render(); break;
    case 'test-reminders': state.testSub = 'REMINDERS'; render(); break;
    case 'test-latest': state.selectedRecord = state.savedSessions[0] || null; state.testSub = 'RECORD_DETAIL'; render(); break;
    case 'open-record': state.selectedRecord = state.savedSessions[Number(el.dataset.idx)]; state.testSub = 'RECORD_DETAIL'; render(); break;
    case 'del-record':
      e.stopPropagation();
      state.savedSessions.splice(Number(el.dataset.idx), 1);
      persist();
      render();
      break;
    case 'set-reminder': state.profile.reminderFrequency = val; persist(); render(); break;

    case 'set-hp':
      state.headphoneConnected = val === '1';
      state.routeName = state.headphoneConnected ? 'Bluetooth Audio Active (Stereo)' : 'Internal Device Speaker';
      state.pauseReason = null;
      render();
      break;
    case 'set-strategy':
      state.strategyType = val;
      state.engine = createEngine();
      render();
      break;
    case 'to-briefing':
      if (!state.headphoneConnected) {
        state.pauseReason = 'Headphones required. Built-in speaker cannot isolate left and right ears.';
        render();
        break;
      }
      if (state.noiseAssessment !== NoiseAssessment.VALID) {
        state.pauseReason = 'Quiet ambient environment required before starting screening.';
        render();
        break;
      }
      state.pauseReason = null;
      state.testSub = 'BRIEFING';
      render();
      break;
    case 'start-practice':
      clearTimers();
      state.screeningState = ScreeningState.PRACTICE_PRESENTATION;
      state.practiceTonePlaying = true;
      state.practiceHeard = null;
      state.practiceMessage = 'Playing 1000 Hz demo tone to Left Ear. Tap "I Hear It".';
      render();
      toneGen.playTone({
        frequencyHz: 1000,
        levelDb: 50,
        ear: 'left',
        durationMs: 1500,
        onEnded: () => { state.practiceTonePlaying = false; render(); },
      });
      break;
    case 'back-setup': clearTimers(); state.screeningState = ScreeningState.DEVICE_READINESS; render(); break;
    case 'practice-heard':
      clearTimers();
      state.practiceTonePlaying = false;
      state.practiceHeard = true;
      state.practiceMessage = 'Demo tone heard! You can try again or start formal screening.';
      state.screeningState = ScreeningState.PRACTICE_FEEDBACK;
      render();
      break;
    case 'practice-not-heard':
      clearTimers();
      state.practiceTonePlaying = false;
      state.practiceHeard = false;
      state.practiceMessage = 'Demo tone reported not heard. Increase headphone volume and tap "Try Again".';
      state.screeningState = ScreeningState.PRACTICE_FEEDBACK;
      render();
      break;
    case 'begin-screening':
      if (!state.headphoneConnected) {
        state.pauseReason = 'Headphones required. Built-in speaker cannot isolate left and right ears.';
        state.testSub = 'MAIN';
        render();
        break;
      }
      if (state.noiseAssessment !== NoiseAssessment.VALID) {
        state.pauseReason = 'Quiet ambient environment required before starting screening.';
        state.testSub = 'MAIN';
        render();
        break;
      }
      state.pauseReason = null;
      state.testSub = 'MAIN';
      state.engine = createEngine();
      state.outcome = null;
      startStimulusTrial();
      break;
    case 'resp-heard': if (state.isWaitingForResponse) submitTrialResponse('HEARD'); break;
    case 'resp-not-heard': if (state.isWaitingForResponse) submitTrialResponse('NOT_HEARD'); break;
    case 'continue-right-ear': startStimulusTrial(); break;
    case 'pause-test':
      clearTimers();
      state.screeningState = ScreeningState.USER_PAUSED;
      state.pauseReason = 'Testing paused by user.';
      render();
      break;
    case 'resume-test':
      state.pauseReason = null;
      startStimulusTrial();
      break;
    case 'cancel-test':
      clearTimers();
      state.screeningState = ScreeningState.DEVICE_READINESS;
      state.engine = createEngine();
      render();
      break;
    case 'restart-screening':
      clearTimers();
      state.screeningState = ScreeningState.DEVICE_READINESS;
      state.engine = createEngine();
      state.outcome = null;
      render();
      break;
    case 'import-to-monitor': {
      const latest = state.savedSessions[0];
      if (latest) {
        latest.results.forEach((r) => {
          const band = EQ_CENTERS_HZ.indexOf(r.frequencyHz);
          const earIdx = r.ear === 'left' ? 0 : 1;
          if (band >= 0) state.monitor.thresholds[earIdx][band] = String(r.thresholdDb);
        });
        state.monitor.importMessage = `Imported ${latest.results.length} uncalibrated screening thresholds (reference only).`;
        persist();
      }
      state.tab = 'MONITOR';
      state.monitorSub = 'SETTINGS';
      state.accordion.audiogram = true;
      render();
      break;
    }

    // DEV SIM
    case 'toggle-sim': state.showSimDrawer = !state.showSimDrawer; render(); break;
    case 'sim-noise':
      state.noiseAssessment = NoiseAssessment.INVALID;
      state.noiseDbFs = -25.0;
      if ([ScreeningState.STIMULUS_PRESENTATION, ScreeningState.WAITING_FOR_RESPONSE].includes(state.screeningState)) {
        clearTimers();
        state.engine = evaluateEngineTrial(state.engine, 'CONTAMINATED_BY_NOISE', { ambientNoiseDbFs: -25.0 }).engine;
        state.engine.noisePauseCount += 1;
        state.screeningState = ScreeningState.AUTOMATIC_PAUSE_NOISE;
        state.pauseReason = 'Environmental noise detected (-25.0 dBFS). Trial contaminated and paused.';
        state.recoverySeconds = 3;
      }
      render();
      break;
    case 'sim-quiet':
      state.noiseAssessment = NoiseAssessment.VALID;
      state.noiseDbFs = -55.0;
      state.pauseReason = null;
      if (state.screeningState === ScreeningState.AUTOMATIC_PAUSE_NOISE) {
        state.recoverySeconds = 3;
        recoveryInterval = setInterval(() => {
          state.recoverySeconds -= 1;
          if (state.recoverySeconds <= 0) {
            clearInterval(recoveryInterval);
            recoveryInterval = null;
            startStimulusTrial();
          } else {
            render();
          }
        }, 700);
      }
      render();
      break;
    case 'sim-unplug':
      state.headphoneConnected = false;
      state.routeName = 'Internal Phone Speaker (Simulated)';
      if ([ScreeningState.STIMULUS_PRESENTATION, ScreeningState.WAITING_FOR_RESPONSE].includes(state.screeningState)) {
        clearTimers();
        state.screeningState = ScreeningState.AUTOMATIC_PAUSE_DEVICE;
        state.pauseReason = 'Headphones disconnected. Please reconnect headphones.';
      }
      render();
      break;

    // MONITOR
    case 'mon-main': state.monitorSub = 'MAIN'; render(); break;
    case 'mon-history': state.monitorSub = 'HISTORY'; render(); break;
    case 'mon-details': state.monitorSub = 'DETAILS'; render(); break;
    case 'mon-settings': state.monitorSub = 'SETTINGS'; render(); break;
    case 'mon-start':
      state.monitor.running = true;
      state.monitor.status = 'Monitoring · Browser DSP preview active';
      monitorInterval = setInterval(() => {
        state.monitor.liveMicPeakPct = Math.round(12 + Math.random() * 26);
        state.monitor.status = `Monitoring · mic peak ${state.monitor.liveMicPeakPct}% · ${state.monitor.processed ? 'Processed' : 'Baseline'}`;
        render();
      }, 1200);
      render();
      break;
    case 'mon-stop': stopLiveMonitor('Stopped'); render(); break;
    case 'toggle-acc': state.accordion[val] = !state.accordion[val]; render(); break;
    case 'mon-env': state.monitor.environment = val; persist(); render(); break;
    case 'mon-import': {
      const latest = state.savedSessions[0];
      if (!latest) {
        state.monitor.importMessage = 'No screening results saved yet. Run a screening first.';
      } else {
        latest.results.forEach((r) => {
          const band = EQ_CENTERS_HZ.indexOf(r.frequencyHz);
          const earIdx = r.ear === 'left' ? 0 : 1;
          if (band >= 0) state.monitor.thresholds[earIdx][band] = String(r.thresholdDb);
        });
        state.monitor.importMessage = `Imported ${latest.results.length} uncalibrated thresholds (reference only).`;
        persist();
      }
      render();
      break;
    }
    case 'mon-save-trial': {
      const c = Number(document.getElementById('clarityCorrect')?.value);
      const t = Number(document.getElementById('clarityTotal')?.value);
      if (!Number.isInteger(t) || t < 1 || t > 200 || !Number.isInteger(c) || c < 0 || c > t) {
        state.monitor.trialMessage = 'Enter a correct count from 0 to list size (1–200).';
      } else {
        const mode = state.monitor.processed ? 'Processed' : 'Baseline';
        const pct = Math.round((c * 100) / t);
        state.monitor.trials.unshift(`${state.monitor.environment} · ${mode} · ${c}/${t} (${pct}%) · ${new Date().toLocaleTimeString()}`);
        state.monitor.trialMessage = '';
        state.clarityCorrect = '';
        persist();
      }
      render();
      break;
    }
    case 'mon-reset':
      state.monitor = { ...defaultMonitorState(), trials: state.monitor.trials, thresholds: state.monitor.thresholds };
      persist();
      render();
      break;

    // REPORTS & PROFILE
    case 'rep-main': state.reportsSub = 'MAIN'; render(); break;
    case 'rep-sub': state.reportsSub = val; render(); break;
    case 'prof-main': state.profileSub = 'MAIN'; render(); break;
    case 'prof-sub': state.profileSub = val; state.copiedJson = false; render(); break;
    case 'save-edit-profile':
      state.profile.preferredName = document.getElementById('editName')?.value.trim() || 'Alex Parker';
      persist();
      state.profileSub = 'MAIN';
      render();
      break;
    case 'restart-onboarding':
      stopLiveMonitor('Stopped');
      state.profile.onboardingCompleted = false;
      state.onboardingStep = 'WELCOME';
      persist();
      render();
      break;
    case 'sign-out':
      stopLiveMonitor('Stopped');
      clearTimers();
      state.profile.onboardingCompleted = false;
      state.profile.initialScreeningCompleted = false;
      state.profile.accountMode = 'Guest';
      state.consentChecked = false;
      state.initialTestPending = true;
      state.justCompletedBaseline = false;
      state.onboardingStep = 'ACCOUNT';
      state.profileSub = 'MAIN';
      persist();
      render();
      break;
    case 'copy-json': {
      const json = JSON.stringify({ profile: state.profile, screeningSessions: state.savedSessions, speechClarityTrials: state.monitor.trials }, null, 2);
      navigator.clipboard?.writeText(json).catch(() => {});
      state.copiedJson = true;
      render();
      break;
    }
  }
});

document.getElementById('app').addEventListener('change', (e) => {
  const t = e.target;
  const action = t.dataset.action;
  if (action === 'toggle-consent') { state.consentChecked = t.checked; render(); }
  else if (action === 'perm-notif') { state.profile.notificationsEnabled = t.checked; persist(); }
  else if (action === 'perm-bt') { state.profile.bluetoothEnabled = t.checked; persist(); }
  else if (action === 'toggle-six-freq') {
    state.profile.useSixFrequencies = t.checked;
    state.engine = createEngine();
    persist();
    render();
  }
  else if (action === 'sim-mode-toggle') { state.isSimulationMode = t.checked; render(); }
  else if (action === 'mon-processed-toggle') { state.monitor.processed = t.checked; persist(); render(); }
  else if (action === 'mon-gate-toggle') { state.monitor.gateEnabled = t.checked; persist(); render(); }
  else if (action === 'mon-den-toggle') { state.monitor.denoiserEnabled = t.checked; persist(); render(); }
  else if (action === 'mon-comp-toggle') { state.monitor.compressionEnabled = t.checked; persist(); render(); }
  else if (action === 'mon-real-ear') { state.monitor.realEarVerified = t.checked; persist(); }

  if (t.dataset.select) {
    state.monitor[t.dataset.select] = t.value;
    persist();
  }
  if (t.dataset.thresh) {
    const [earIdx, bandIdx] = t.dataset.thresh.split(',').map(Number);
    state.monitor.thresholds[earIdx][bandIdx] = t.value;
    persist();
  }
  if (t.dataset.input === 'realEarNotes') {
    state.monitor.realEarNotes = t.value;
    persist();
  }
});

document.getElementById('app').addEventListener('input', (e) => {
  const t = e.target;
  if (t.dataset.range) {
    const k = t.dataset.range;
    const v = Number(t.value);
    state.monitor[k] = v;
    const lbl = document.getElementById(t.dataset.lbl);
    if (lbl) {
      lbl.textContent = k === 'monitorLevel' ? Math.round(v * 100) : k === 'compressionRatio' ? v.toFixed(1) : v;
    }
    persist();
  } else if (t.dataset.eq) {
    const [earIdx, bandIdx] = t.dataset.eq.split(',').map(Number);
    const v = Number(t.value);
    state.monitor.gains[earIdx][bandIdx] = v;
    const lbl = document.getElementById(`eq_${earIdx}_${bandIdx}`);
    if (lbl) lbl.textContent = `${v >= 0 ? '+' : ''}${v.toFixed(1)}`;
    persist();
  }
});

render();
