'use strict';
// Mock closed feedback so the learning jobs (algorithm/learning) have enough data:
// train needs >= 30 team rows from >= 5 ended activities (train.py MIN_ROWS, MIN_ACTIVITIES).
// Writes one hidden demo group (no real memberships, so no one sees it in the app) with
// 6 ended activities x 6 teams, publications, feedback and summaries. Every ID starts with mock_.
//
//   node scripts/mock_learning_data.cjs --out mock.json            dry run: write the docs as JSON
//   node scripts/mock_learning_data.cjs --write  --project teamix-309c0
//   node scripts/mock_learning_data.cjs --delete --project teamix-309c0
// --write/--delete use Application Default Credentials (gcloud auth application-default login).
//
// Ratings follow a known rule so a model can find it: time and role losses hurt most, while each
// activity's priority ranks them low, so the trained model beats the default-weight baseline.

const GROUP = 'mock_learning_demo';
const ACTIVITIES = 6, TEAMS = 6;
const TYPES = ['project', 'study', 'social', 'other', 'project', 'study'];
const PRIORITIES = [
  ['interest', 'experience', 'role', 'time'],
  ['experience', 'interest', 'time', 'role'],
  ['interest', 'role', 'experience', 'time'],
  ['experience', 'time', 'interest', 'role'],
  ['interest', 'experience', 'time', 'role'],
  ['role', 'interest', 'experience', 'time'],
];
const EFFECT = {time: 1.8, role: 1.2, experience: 0.4, interest: 0.2};
const TYPE_EFFECT = {social: 0.2, study: -0.1, project: 0, other: 0};
const DAY = 86400000;

function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Pure: {path: data} with dates as Date. */
function generate(seed = 7, now = new Date('2026-10-01T00:00:00Z')) {
  const rand = rng(seed);
  const normal = () => Math.sqrt(-2 * Math.log(1 - rand())) * Math.cos(2 * Math.PI * rand());
  const star = x => Math.min(5, Math.max(1, Math.round(x)));
  const docs = {};
  docs[`groups/${GROUP}`] = {name: '[목데이터] 학습 데모', description: '후기 학습용 가짜 데이터', ownerId: 'mock_owner',
    themeColor: 'mint', mock: true, createdAt: now, updatedAt: now};
  let user = 0;
  for (let i = 0; i < ACTIVITIES; i++) {
    const a = `mock_act_${i + 1}`;
    const ended = new Date(now.getTime() - (ACTIVITIES - i) * 14 * DAY);
    const started = new Date(ended.getTime() - 21 * DAY);
    const priority = PRIORITIES[i];
    const method = i % 2 ? 'similar' : 'balanced';
    const teams = [], feedback = [];
    for (let t = 0; t < TEAMS; t++) {
      const teamId = `t${t + 1}`;
      const size = rand() < 0.5 ? 4 : 5;
      const members = Array.from({length: size}, () => {
        user++;
        return {uid: `mock_u${user}`, displayName: `목업 ${user}`};
      });
      const losses = Object.fromEntries(priority.map(q => [q, Math.round(rand() * 1000)]));
      losses.size = Math.round(rand() * 200);
      const mu = 4.5 + TYPE_EFFECT[TYPES[i]] - priority.reduce((s, q) => s + EFFECT[q] * losses[q] / 1000, 0);
      teams.push({teamId, members, losses, commonTimes: ['mon-19', 'wed-20'].slice(0, 1 + (t % 2))});
      // Who answers and consents; redraw until the team passes extract.py's inclusion rule.
      let flags;
      do {
        flags = members.map(() => ({answered: rand() < 0.85, consent: rand() < 0.85}));
      } while (flags.filter(f => f.answered && f.consent).length < Math.max(2, Math.ceil(size / 2)));
      members.forEach((m, k) => {
        if (!flags[k].answered) return;
        const overall = star(mu + 0.45 * normal());
        const scores = {
          overall,
          schedule: star(4.6 - 2.2 * losses.time / 1000 + 0.5 * normal()),
          roles: star(4.6 - 2.0 * losses.role / 1000 + 0.5 * normal()),
          rejoin: star(overall + 0.5 * normal()),
        };
        feedback.push({activityId: a, groupId: GROUP, userId: m.uid, teamId, rating: overall, scores,
          questionnaireVersion: 'r2', teamVersion: 1, membershipRatio: 1, learningConsent: flags[k].consent,
          mock: true, createdAt: ended, updatedAt: ended});
      });
    }
    const participants = teams.reduce((s, t) => s + t.members.length, 0);
    docs[`activities/${a}`] = {groupId: GROUP, title: `목업 소모임 ${i + 1}`, description: '학습용 가짜 소모임',
      type: TYPES[i], status: 'ended', capacity: participants, targetTeamSize: 5, participantCount: participants,
      deadlineAt: new Date(started.getTime() - 3 * DAY), startedAt: started, endedAt: ended,
      publishedVersion: 1, endedVersion: 1, feedbackClosedAt: new Date(ended.getTime() + 7 * DAY),
      mock: true, createdAt: new Date(started.getTime() - 10 * DAY), updatedAt: ended};
    docs[`activities/${a}/settings/matching`] = {priority, method, teamIds: teams.map(t => t.teamId), updatedAt: started};
    docs[`publications/${a}_v1`] = {activityId: a, groupId: GROUP, version: 1, teams, publishedBy: 'mock_owner',
      publishedAt: started, validFrom: started, validTo: null, sourceRunId: null, manuallyEdited: false, mock: true};
    const summary = {};
    for (const t of teams) {
      const rows = feedback.filter(f => f.teamId === t.teamId);
      if (rows.length < 3) continue;
      summary[t.teamId] = {respondents: rows.length, averages: Object.fromEntries(['overall', 'schedule', 'roles', 'rejoin']
        .map(k => [k, Math.round(rows.reduce((s, r) => s + r.scores[k], 0) / rows.length * 100) / 100]))};
    }
    docs[`activities/${a}/feedbackSummary/current`] = {questionnaireVersion: 'r2', minRespondents: 3, teams: summary,
      updatedAt: new Date(ended.getTime() + 7 * DAY)};
    for (const f of feedback) docs[`feedback/${a}_${f.userId}`] = f;
  }
  return docs;
}

function arg(name) {
  const i = process.argv.indexOf(name);
  return i < 0 ? null : process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[i + 1] : true;
}

async function main() {
  const docs = generate();
  const out = arg('--out');
  if (typeof out === 'string') {
    require('fs').writeFileSync(out, JSON.stringify(docs, null, 1));
    console.log(`${Object.keys(docs).length} docs -> ${out}`);
  }
  const remove = arg('--delete');
  if (!arg('--write') && !remove) return;
  const project = arg('--project');
  if (typeof project !== 'string') throw new Error('--project is required');
  const admin = require('../functions/node_modules/firebase-admin');
  admin.initializeApp({projectId: project});
  const db = admin.firestore();
  const paths = Object.keys(docs);
  if (remove) {
    // Rows and markers the extract job made from these activities go too.
    for (let i = 1; i <= ACTIVITIES; i++) {
      const rows = await db.collection('trainingDatasets/fx1/rows').where('activityId', '==', `mock_act_${i}`).get();
      paths.push(...rows.docs.map(r => r.ref.path), `trainingDatasets/fx1/activities/mock_act_${i}`);
    }
  }
  for (let i = 0; i < paths.length; i += 400) {
    const batch = db.batch();
    for (const p of paths.slice(i, i + 400)) remove ? batch.delete(db.doc(p)) : batch.set(db.doc(p), docs[p]);
    await batch.commit();
  }
  // A deletion makes the next training run due (train.py should_train).
  if (remove) await db.doc('trainingDatasets/fx1').set({dirty: true}, {merge: true});
  console.log(`${remove ? 'deleted' : 'wrote'} ${paths.length} docs in ${project}`);
}

module.exports = {generate};
if (require.main === module) main().catch(e => { console.error(e.message); process.exit(1); });
