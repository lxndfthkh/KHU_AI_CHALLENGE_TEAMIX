'use strict';
class ValidationError extends Error {}
function check(ok, message) { if (!ok) throw new ValidationError(message); }
function text(v, max = 120) { check(typeof v === 'string' && v.trim().length > 0 && v.length <= max, 'Invalid text'); return v.trim(); }
function id(v) { check(typeof v === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(v), 'Invalid ID'); return v; }
function settings(s) {
  check(s && typeof s === 'object', 'Settings required');
  const title = text(s.title); const type = s.type;
  check(['study','project','social','other'].includes(type), 'Invalid activity type');
  check(['balanced','similar'].includes(s.formationMode), 'Invalid formation mode');
  check(Array.isArray(s.teamIds) && s.teamIds.length > 0 && s.teamIds.length <= 100, 'Invalid teams');
  s.teamIds.forEach(id); check(new Set(s.teamIds).size === s.teamIds.length, 'Duplicate team ID');
  const criteria = s.criteria;
  check(Array.isArray(criteria) && criteria.length >= 1 && criteria.length <= 5, 'Invalid criteria');
  const keys = new Set(); const ranks = new Set();
  for (const c of criteria) {
    check(['time','role','experience','interest','size'].includes(c.key) && !keys.has(c.key), 'Invalid criterion');
    check(Number.isInteger(c.priority) && c.priority >= 1 && c.priority <= criteria.length && !ranks.has(c.priority), 'Invalid priority');
    keys.add(c.key); ranks.add(c.priority);
  }
  check(keys.has('size'), 'Size criterion required');
  const questions = s.questions;
  check(Array.isArray(questions) && questions.length <= 4, 'Invalid questions');
  const qkeys = new Set(); const qids = new Set();
  for (const q of questions) {
    id(q.id); check(!qids.has(q.id), 'Duplicate question ID'); qids.add(q.id);
    check(['role','time','experience','interest'].includes(q.key) && !qkeys.has(q.key), 'Invalid question'); qkeys.add(q.key);
    check(typeof q.multiSelect === 'boolean', 'Invalid multiSelect');
    check(Array.isArray(q.scale) && q.scale.length > 0 && q.scale.length <= 50 && new Set(q.scale).size === q.scale.length, 'Invalid scale');
    check(q.scale.every(v => (typeof v === 'string' && v.length > 0 && v.length <= 120) || (typeof v === 'number' && Number.isFinite(v))), 'Invalid options');
    check(q.key !== 'experience' || (!q.multiSelect && q.scale.every(v => Number.isInteger(v) && v >= 1 && v <= 5)), 'Invalid experience scale');
  }
  check([...keys].every(k => k === 'size' || qkeys.has(k)), 'Criterion needs selected question');
  const capacity = {};
  for (const t of s.teamIds) {
    const cap = s.capacity?.[t] ?? null;
    check(cap === null || (Number.isInteger(cap) && cap >= 1 && cap <= 10000), 'Invalid capacity'); capacity[t] = cap;
  }
  check(!s.capacity || Object.keys(s.capacity).every(k => s.teamIds.includes(k)), 'Unknown capacity team');
  // Extra engine constraints are deliberately not guessed in stages 1-2.
  check(!s.extraRequirements || (Array.isArray(s.extraRequirements) && s.extraRequirements.length === 0), 'Extra constraints require stage 3');
  return {title, type, formationMode:s.formationMode, teamIds:s.teamIds, capacity, criteria:criteria.map(c => ({key:c.key,priority:c.priority})), extraRequirements:[], questions:questions.map(q => ({id:q.id,key:q.key,scale:q.scale,multiSelect:q.multiSelect,required:true}))};
}
function answers(input, questions) {
  check(input && typeof input === 'object' && !Array.isArray(input), 'Answers required');
  check(Object.keys(input).length === questions.length && Object.keys(input).every(k => questions.some(q => q.id === k)), 'Answer only selected questions');
  const out = {};
  for (const q of questions) {
    const a = input[q.id]; check(a && a.questionVersion === q.questionVersion, 'Stale question version');
    if (q.multiSelect) {
      check(Array.isArray(a.value) && a.value.length > 0 && new Set(a.value).size === a.value.length && a.value.every(v => q.scale.includes(v)), 'Invalid multi-select answer');
    } else check(q.scale.includes(a.value), 'Invalid answer');
    out[q.id] = {questionVersion:q.questionVersion, value:a.value};
  }
  return out;
}
function canAddPreference(activeTargets, target) { check(activeTargets.includes(target) || activeTargets.length < 2, 'At most two active preferences'); }
module.exports = {ValidationError, check, text, id, settings, answers, canAddPreference};
