import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, getDocs, updateDoc, deleteDoc, writeBatch,
  collectionGroup, query, where, orderBy, Timestamp, serverTimestamp } from 'firebase/firestore';

let env;
const old = Timestamp.fromMillis(1000);
const future = Timestamp.fromMillis(4102444800000);
const db = (uid) => env.authenticatedContext(uid).firestore();
const ref = (store, path) => doc(store, path);
const group = { name: '메이커스', description: '시연', ownerUid: 'owner', createdAt: old };
const membership = (uid, role = 'member') => ({ uid, groupId: 'g', nickname: uid, role, joinedAt: old });
const questions = { selected: ['role', 'time', 'experience', 'interest'],
  roleOptions: ['개발'], timeOptions: ['수 저녁'], interestOptions: ['앱'] };
const settings = { teamCount: 1, teamCapacities: [{ teamId: 'team_1', capacity: 20 }],
  method: 'balanced', priority: ['role', 'time', 'experience', 'interest', 'size'], requireCommonTime: false };
const activity = (extra = {}) => ({ groupId: 'g', title: '활동', description: '', goal: '',
  recruitmentCapacity: 20, applicationCount: 0, deadline: future, status: 'recruiting',
  questions, matchingSettings: settings, settingsVersion: 1, responseVersion: 0,
  currentPublicationId: null, publicationVersion: 0, createdBy: 'owner', createdAt: old, updatedAt: old, ...extra });
const application = (uid, extra = {}) => ({ uid, groupId: 'g', status: 'submitted',
  answers: { role: '개발', time: ['수 저녁'], experience: 3, interest: ['앱'] },
  nicknameSnapshot: uid, submittedAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra });
const request = (uid, extra = {}) => ({ uid, groupId: 'g', groupName: group.name, nickname: uid, status: 'pending',
  requestedAt: old, reviewedAt: null, reviewedBy: null, inviteId: 'i', ...extra });
const preference = (targets = [{ targetUid: 'other', confirmed: true }]) => ({
  authorUid: 'member', groupId: 'g', targets, updatedAt: serverTimestamp() });

before(async () => {
  // Never silently connect to a production project.
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Firestore 에뮬레이터에서 실행하세요.');
  env = await initializeTestEnvironment({ projectId: 'demo-teamix-rules',
    firestore: { rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
});
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const s = context.firestore();
    await Promise.all([
      setDoc(ref(s, 'groups/g'), group),
      ...['owner', 'admin', 'member', 'other'].map((uid) => setDoc(
        ref(s, `groups/g/memberships/${uid}`), membership(uid, uid === 'owner' ? 'owner' : uid === 'admin' ? 'admin' : 'member'))),
      setDoc(ref(s, 'activities/a'), activity()),
      setDoc(ref(s, 'groups/g/invites/i'), { code: 'TEAM24', enabled: true, expiresAt: future, createdAt: old }),
      setDoc(ref(s, 'inviteCodes/TEAM24'), { groupId: 'g', inviteId: 'i' }),
      setDoc(ref(s, 'groups/g/joinRequests/applicant'), request('applicant')),
      setDoc(ref(s, 'activities/a/drafts/d'), { createdBy: 'owner', createdAt: old,
        enginePublic: { status: 'FEASIBLE', teams: [] }, conditionsSnapshot: {}, editedTeams: null,
        sourceResponseVersion: 0, sourceSettingsVersion: 1, revision: 0 }),
      setDoc(ref(s, 'privatePreferences/member/groups/g'), { ...preference(), updatedAt: old }),
    ]);
  });
});
after(async () => { if (env) await env.cleanup(); });

async function seed(path, data) {
  await env.withSecurityRulesDisabled((context) => setDoc(ref(context.firestore(), path), data));
}
function submit(s, { count = 1, extra = {}, uid = 'member', answers } = {}) {
  const batch = writeBatch(s);
  batch.set(ref(s, `activities/a/applications/${uid}`), application(uid, answers ? { answers } : {}));
  batch.update(ref(s, 'activities/a'), { applicationCount: count, responseVersion: 1, ...extra });
  return batch.commit();
}

test('부원은 본인 가입 요청을 승인할 수 없다', async () => {
  const s = db('applicant');
  const batch = writeBatch(s);
  batch.update(ref(s, 'groups/g/joinRequests/applicant'), { status: 'approved', reviewedAt: serverTimestamp(), reviewedBy: 'applicant' });
  batch.set(ref(s, 'groups/g/memberships/applicant'), { ...membership('applicant'), joinedAt: serverTimestamp() });
  await assertFails(batch.commit());
});
test('남의 기존 모임에 대표자 회원 문서를 만들 수 없다', async () => {
  const s = db('intruder');
  await assertFails(setDoc(ref(s, 'groups/g/memberships/intruder'), {
    ...membership('intruder', 'owner'), joinedAt: serverTimestamp() }));
});
test('새 모임과 본인 대표자 문서는 같은 배치에서만 생성된다', async () => {
  const s = db('founder');
  const batch = writeBatch(s);
  batch.set(ref(s, 'groups/new'), { ...group, ownerUid: 'founder', createdAt: serverTimestamp() });
  batch.set(ref(s, 'groups/new/memberships/founder'), {
    ...membership('founder', 'owner'), groupId: 'new', joinedAt: serverTimestamp() });
  await assertSucceeds(batch.commit());
});
test('운영자와 다른 회원은 비공개 선호를 읽지 못한다', async () => {
  for (const uid of ['owner', 'admin', 'other']) {
    await assertFails(getDoc(ref(db(uid), 'privatePreferences/member/groups/g')));
  }
  await assertSucceeds(getDoc(ref(db('member'), 'privatePreferences/member/groups/g')));
});
test('비공개 선호는 최대 두 명이며 중복과 자기 지정이 금지된다', async () => {
  const s = db('member');
  await assertFails(setDoc(ref(s, 'privatePreferences/member/groups/g'), preference([
    { targetUid: 'other', confirmed: true }, { targetUid: 'other', confirmed: true }])));
  await assertFails(setDoc(ref(s, 'privatePreferences/member/groups/g'), preference([{ targetUid: 'member', confirmed: true }])));
  await assertFails(setDoc(ref(s, 'privatePreferences/member/groups/g'), preference([
    { targetUid: 'other', confirmed: true }, { targetUid: 'owner', confirmed: true }, { targetUid: 'admin', confirmed: true }])));
  await assertSucceeds(setDoc(ref(s, 'privatePreferences/member/groups/g'), preference([])));
  await assertSucceeds(deleteDoc(ref(s, 'privatePreferences/member/groups/g')));
});
test('부원은 초안을 읽지 못하고 운영자는 읽을 수 있다', async () => {
  await assertFails(getDoc(ref(db('member'), 'activities/a/drafts/d')));
  await assertSucceeds(getDoc(ref(db('admin'), 'activities/a/drafts/d')));
});
test('마감 이후 설문 제출 실패', async () => {
  await seed('activities/a', activity({ deadline: old }));
  await assertFails(submit(db('member')));
});
test('정상 신청은 카운터와 함께 성공한다', async () => {
  await assertSucceeds(submit(db('member')));
});
test('신청 문서만 쓰거나 카운터만 쓰면 실패한다', async () => {
  const s = db('member');
  await assertFails(setDoc(ref(s, 'activities/a/applications/member'), application('member')));
  await assertFails(updateDoc(ref(s, 'activities/a'), { applicationCount: 1, responseVersion: 1 }));
});
test('부원은 신청 수를 +2 하거나 다른 필드를 바꿀 수 없다', async () => {
  await assertFails(submit(db('member'), { count: 2 }));
  await assertFails(submit(db('member'), { extra: { title: '변조' } }));
  await assertFails(submit(db('member'), { extra: { updatedAt: serverTimestamp() } }));
  await assertFails(submit(db('member'), { extra: { responseVersion: 2 } }));
});
test('본인이 아닌 신청 및 선택지 밖 응답은 거부된다', async () => {
  await assertFails(submit(db('member'), { uid: 'other' }));
  await assertFails(submit(db('member'), { answers: { role: '미지원', time: ['수 저녁'], experience: 3, interest: ['앱'] } }));
});
test('응답 수정은 인원 유지와 버전 +1, 취소는 인원 -1과 버전 +1', async () => {
  const s = db('member');
  await assertSucceeds(submit(s));
  let batch = writeBatch(s);
  batch.update(ref(s, 'activities/a/applications/member'), {
    'answers.experience': 4, updatedAt: serverTimestamp() });
  batch.update(ref(s, 'activities/a'), { responseVersion: 2 });
  await assertSucceeds(batch.commit());
  batch = writeBatch(s);
  batch.update(ref(s, 'activities/a/applications/member'), { status: 'withdrawn', updatedAt: serverTimestamp() });
  batch.update(ref(s, 'activities/a'), { applicationCount: 0, responseVersion: 3 });
  await assertSucceeds(batch.commit());
});
test('운영자 승인은 요청과 회원 생성이 함께 필요하다', async () => {
  const s = db('admin');
  await assertFails(updateDoc(ref(s, 'groups/g/joinRequests/applicant'), {
    status: 'approved', reviewedAt: serverTimestamp(), reviewedBy: 'admin' }));
  const batch = writeBatch(s);
  batch.update(ref(s, 'groups/g/joinRequests/applicant'), { status: 'approved', reviewedAt: serverTimestamp(), reviewedBy: 'admin' });
  batch.set(ref(s, 'groups/g/memberships/applicant'), { ...membership('applicant'), joinedAt: serverTimestamp() });
  await assertSucceeds(batch.commit());
});
test('거절된 사용자는 유효 초대로 재요청할 수 있다', async () => {
  await seed('groups/g/joinRequests/applicant', request('applicant', { status: 'rejected', reviewedAt: old, reviewedBy: 'owner' }));
  await assertSucceeds(setDoc(ref(db('applicant'), 'groups/g/joinRequests/applicant'),
    request('applicant', { requestedAt: serverTimestamp() })));
});
test('신청 후 질문 변경 및 대표자 승격은 거부된다', async () => {
  await seed('activities/a', activity({ applicationCount: 1 }));
  await assertFails(updateDoc(ref(db('owner'), 'activities/a'), {
    questions: { ...questions, selected: ['role'] }, matchingSettings: { ...settings, priority: ['role', 'size'] },
    settingsVersion: 2, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref(db('admin'), 'groups/g/memberships/member'), { role: 'owner' }));
});
test('공개는 스냅샷과 포인터를 원자적으로 생성하며 과거 회차는 차단된다', async () => {
  await seed('activities/a', activity({ status: 'closed' }));
  const s = db('owner');
  const pub = { version: 1, sourceDraftId: 'd', publishedBy: 'owner', publishedAt: serverTimestamp(),
    teams: [{ teamId: 'team_1', participants: ['member'] }], displayProfiles: { member: '가온' } };
  await assertFails(setDoc(ref(s, 'activities/a/publications/p1'), pub));
  let batch = writeBatch(s);
  batch.set(ref(s, 'activities/a/publications/p1'), pub);
  batch.update(ref(s, 'activities/a'), { currentPublicationId: 'p1', publicationVersion: 1, updatedAt: serverTimestamp() });
  await assertSucceeds(batch.commit());
  await assertFails(getDoc(ref(db('other'), 'activities/a/publications/p1')));
  await seed('activities/a/applications/member', application('member', { submittedAt: old, updatedAt: old }));
  await assertSucceeds(getDoc(ref(db('member'), 'activities/a/publications/p1')));
  await assertFails(updateDoc(ref(db('member'), 'activities/a/applications/member'), { status: 'withdrawn', updatedAt: serverTimestamp() }));
  batch = writeBatch(s);
  batch.set(ref(s, 'activities/a/publications/p2'), { ...pub, version: 2 });
  batch.update(ref(s, 'activities/a'), { currentPublicationId: 'p2', publicationVersion: 2, updatedAt: serverTimestamp() });
  await assertSucceeds(batch.commit());
  await assertFails(getDoc(ref(s, 'activities/a/publications/p1')));
  await assertSucceeds(getDoc(ref(s, 'activities/a/publications/p2')));
  await assertSucceeds(deleteDoc(ref(db('member'), 'groups/g/memberships/member')));
  await assertFails(getDoc(ref(db('member'), 'activities/a/publications/p2')));
});
test('collectionGroup 조회는 본인 uid 조건이 필요하다', async () => {
  const s = db('member');
  await assertSucceeds(getDocs(query(collectionGroup(s, 'memberships'), where('uid', '==', 'member'), orderBy('joinedAt', 'desc'))));
  await assertFails(getDocs(collectionGroup(s, 'memberships')));
  await assertSucceeds(getDocs(query(collectionGroup(db('applicant'), 'joinRequests'),
    where('uid', '==', 'applicant'), where('status', '==', 'pending'), orderBy('requestedAt', 'desc'))));
});

const manyQuestions = {
  ...questions,
  roleOptions: ['개발', ...Array.from({ length: 9 }, (_, i) => `역할${i}`)],
  timeOptions: ['수 저녁', ...Array.from({ length: 9 }, (_, i) => `시간${i}`)],
  interestOptions: ['앱', ...Array.from({ length: 9 }, (_, i) => `관심${i}`)],
};

test('각 질문 선택지가 10개인 소모임에서 정상 신청이 성공한다', async () => {
  await seed('activities/a', activity({ questions: manyQuestions }));
  await assertSucceeds(submit(db('member')));
  const snapshot = await getDoc(ref(db('member'), 'activities/a'));
  assert.equal(snapshot.data().applicationCount, 1);
  assert.equal(snapshot.data().responseVersion, 1);
});
test('운영자는 선택지가 많은 소모임 제목을 수정할 수 있다', async () => {
  await seed('activities/a', activity({ questions: manyQuestions }));
  await assertSucceeds(updateDoc(ref(db('owner'), 'activities/a'), {
    title: '수정된 제목', updatedAt: serverTimestamp(),
  }));
});
test('가입 대기 화면은 재요청 문서의 groupName을 읽는다', async () => {
  await seed('groups/g/joinRequests/applicant', request('applicant', {
    status: 'rejected', reviewedAt: old, reviewedBy: 'owner',
  }));
  const s = db('applicant');
  await assertSucceeds(setDoc(ref(s, 'groups/g/joinRequests/applicant'),
    request('applicant', { requestedAt: serverTimestamp() })));
  const snapshot = await assertSucceeds(getDoc(ref(s, 'groups/g/joinRequests/applicant')));
  assert.equal(snapshot.data().groupName, group.name);
  assert.equal(snapshot.data().status, 'pending');
  await assertFails(getDoc(ref(s, 'groups/g')));
});
test('가입 요청의 groupName은 필수이며 1~100자 문자열이다', async () => {
  const s = db('applicant');
  await seed('groups/g/joinRequests/applicant', request('applicant', { status: 'rejected' }));
  for (const value of [undefined, '', '가'.repeat(101), 123]) {
    const data = request('applicant', { requestedAt: serverTimestamp(), groupName: value });
    if (value === undefined) delete data.groupName;
    await assertFails(setDoc(ref(s, 'groups/g/joinRequests/applicant'), data));
  }
  await assertSucceeds(setDoc(ref(s, 'groups/g/joinRequests/applicant'),
    request('applicant', { requestedAt: serverTimestamp(), groupName: '가'.repeat(100) })));
});
test('강퇴된 사용자는 approved 요청에서 유효 초대로 재요청한다', async () => {
  await seed('groups/g/joinRequests/member', request('member', {
    status: 'approved', reviewedAt: old, reviewedBy: 'owner',
  }));
  await assertSucceeds(deleteDoc(ref(db('admin'), 'groups/g/memberships/member')));
  const s = db('member');
  await assertSucceeds(setDoc(ref(s, 'groups/g/joinRequests/member'),
    request('member', { requestedAt: serverTimestamp() })));
  const snapshot = await getDoc(ref(s, 'groups/g/joinRequests/member'));
  assert.equal(snapshot.data().status, 'pending');
  assert.equal(snapshot.data().reviewedAt, null);
  assert.equal(snapshot.data().reviewedBy, null);
});
test('현재 회원 또는 만료된 초대로는 approved 요청을 재요청하지 못한다', async () => {
  await seed('groups/g/joinRequests/member', request('member', { status: 'approved' }));
  await assertFails(setDoc(ref(db('member'), 'groups/g/joinRequests/member'),
    request('member', { requestedAt: serverTimestamp() })));
  await assertSucceeds(deleteDoc(ref(db('member'), 'groups/g/memberships/member')));
  await seed('groups/g/invites/i', { code: 'TEAM24', enabled: true, expiresAt: old, createdAt: old });
  await assertFails(setDoc(ref(db('member'), 'groups/g/joinRequests/member'),
    request('member', { requestedAt: serverTimestamp() })));
});

test('각 질문 선택지가 10개인 소모임도 정상 공개할 수 있다', async () => {
  await seed('activities/a', activity({ status: 'closed', questions: manyQuestions }));
  const s = db('owner');
  const batch = writeBatch(s);
  batch.set(ref(s, 'activities/a/publications/many-options'), {
    version: 1, sourceDraftId: 'd', publishedBy: 'owner', publishedAt: serverTimestamp(),
    teams: [{ teamId: 'team_1', participants: ['member'] }], displayProfiles: { member: '가온' },
  });
  batch.update(ref(s, 'activities/a'), {
    currentPublicationId: 'many-options', publicationVersion: 1, updatedAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
  const snapshot = await assertSucceeds(getDoc(ref(s, 'activities/a/publications/many-options')));
  assert.equal(snapshot.data().version, 1);
});
