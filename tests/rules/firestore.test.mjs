import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, getDocs, updateDoc, deleteDoc, collection, writeBatch,
  query, where, orderBy, limit, Timestamp, serverTimestamp } from 'firebase/firestore';

// Paths and fields follow firestore.schema.json / docs/FIRESTORE.md.
let env;
const old = Timestamp.fromMillis(1000);
const future = Timestamp.fromMillis(4102444800000);
const db = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const ref = (store, path) => doc(store, path);

const membership = (uid, role, status = 'approved', groupId = 'g') => ({
  groupId, userId: uid, displayName: uid, role, status, createdAt: old, updatedAt: old });
// uid -> [role, status] in group g; `outsider` has no membership.
const members = {
  admin: ['admin', 'approved'],
  member: ['member', 'approved'],
  other: ['member', 'approved'],
  applicant: ['member', 'pending'],
  rejected: ['member', 'rejected'],
};

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
      setDoc(ref(s, 'users/member'), { displayName: 'member', createdAt: old, updatedAt: old }),
      setDoc(ref(s, 'groups/g'), { name: '메이커스', description: '시연', ownerId: 'admin',
        themeColor: 'mint', status: 'active', createdAt: old, updatedAt: old }),
      ...Object.entries(members).map(([uid, [role, status]]) =>
        setDoc(ref(s, `memberships/g_${uid}`), membership(uid, role, status))),
      setDoc(ref(s, 'invitations/hash'), { groupId: 'g', expiresAt: future, active: true, createdBy: 'admin', createdAt: old }),
      setDoc(ref(s, 'activities/a'), { groupId: 'g', title: '활동', description: '', createdBy: 'admin',
        themeColor: 'mint', capacity: 20, targetTeamSize: 4, deadlineAt: future, status: 'recruiting',
        createdAt: old, updatedAt: old }),
      setDoc(ref(s, 'activities/a/settings/matching'), { method: 'balanced' }),
      setDoc(ref(s, 'activities/a/questions/q1'), { type: 'role' }),
      setDoc(ref(s, 'activities/a/feedbackSummary/current'), { average: 4 }),
      setDoc(ref(s, 'registrations/a_member'), { activityId: 'a', groupId: 'g', userId: 'member',
        status: 'submitted', answers: {}, submittedAt: old, updatedAt: old }),
      setDoc(ref(s, 'registrations/a_other'), { activityId: 'a', groupId: 'g', userId: 'other',
        status: 'cancelled', answers: {}, submittedAt: old, updatedAt: old }),
      setDoc(ref(s, 'drafts/d'), { activityId: 'a', groupId: 'g', version: 1, teams: [], status: 'ready',
        createdAt: old, updatedAt: old }),
      setDoc(ref(s, 'publications/a_v1'), { activityId: 'a', groupId: 'g', version: 1, teams: [],
        publishedBy: 'admin', publishedAt: old }),
      setDoc(ref(s, 'teamViews/a_member'), { activityId: 'a', groupId: 'g', userId: 'member', version: 1,
        teamId: 't1', members: [], commonTimes: [], compositionChanged: false, publishedAt: old }),
      setDoc(ref(s, 'teamViews/a_other'), { activityId: 'a', groupId: 'g', userId: 'other', version: 1,
        teamId: 't1', members: [], commonTimes: [], compositionChanged: false, publishedAt: old }),
      setDoc(ref(s, 'feedback/a_member'), { activityId: 'a', groupId: 'g', userId: 'member', teamId: 't1',
        rating: 5, createdAt: old }),
      setDoc(ref(s, 'placementPreferences/g_member_other'), { groupId: 'g', userId: 'member',
        targetUserId: 'other', active: true, createdAt: old, updatedAt: old }),
      setDoc(ref(s, 'notifications/n'), { userId: 'member', type: 'joinApproved', groupId: 'g',
        createdAt: old, readAt: null }),
      setDoc(ref(s, 'appConfig/teamix'), { palette: ['mint', 'peach', 'lilac'] }),
      setDoc(ref(s, '_schema/users'), { path: 'users/{authUid}' }),
    ]);
  });
});
after(async () => { if (env) await env.cleanup(); });

test('사용자는 본인 프로필만 읽고, 허용된 필드로만 만들고 고친다', async () => {
  await assertSucceeds(getDoc(ref(db('member'), 'users/member')));
  await assertFails(getDoc(ref(db('other'), 'users/member')));
  await assertSucceeds(setDoc(ref(db('other'), 'users/other'),
    { displayName: 'other', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  await assertFails(setDoc(ref(db('outsider'), 'users/outsider'),
    { displayName: 'x', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), role: 'admin' }));
  await assertFails(setDoc(ref(db('outsider'), 'users/other2'),
    { displayName: 'x', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(ref(db('member'), 'users/member'), { displayName: '새 이름', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref(db('member'), 'users/member'), { createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  await assertFails(deleteDoc(ref(db('member'), 'users/member')));
});

test('모임은 승인된 회원만 읽고 클라이언트는 쓸 수 없다', async () => {
  await assertSucceeds(getDoc(ref(db('member'), 'groups/g')));
  for (const uid of ['applicant', 'rejected', 'outsider']) {
    await assertFails(getDoc(ref(db(uid), 'groups/g')));
  }
  await assertFails(getDoc(ref(anon(), 'groups/g')));
  await assertFails(updateDoc(ref(db('admin'), 'groups/g'), { name: '변경' }));
  await assertFails(setDoc(ref(db('outsider'), 'groups/new'), { name: '새 모임' }));
});

test('멤버십: 본인 것, 운영진은 전체, 회원은 승인된 회원만 읽는다', async () => {
  await assertSucceeds(getDoc(ref(db('applicant'), 'memberships/g_applicant')));
  await assertSucceeds(getDoc(ref(db('admin'), 'memberships/g_applicant')));
  await assertSucceeds(getDoc(ref(db('member'), 'memberships/g_other')));
  await assertFails(getDoc(ref(db('member'), 'memberships/g_applicant')));
  await assertFails(getDoc(ref(db('applicant'), 'memberships/g_member')));
  await assertFails(getDoc(ref(db('outsider'), 'memberships/g_member')));
});

test('홈 화면 조회: 본인 멤버십만 status로 걸러 조회할 수 있다', async () => {
  const s = db('applicant');
  const mine = query(collection(s, 'memberships'), where('userId', '==', 'applicant'),
    where('status', 'in', ['approved', 'pending']));
  const result = await assertSucceeds(getDocs(mine));
  assert.equal(result.size, 1);
  await assertFails(getDocs(query(collection(s, 'memberships'), where('groupId', '==', 'g'))));
});

test('앱 홈 쿼리: lib/data/firestore_groups_source.dart와 같은 조건이 허용된다', async () => {
  const s = db('member');
  await assertSucceeds(getDocs(query(collection(s, 'memberships'), where('userId', '==', 'member'),
    where('status', 'in', ['approved', 'pending']), orderBy('updatedAt', 'desc'))));
  await assertSucceeds(getDoc(ref(s, 'groups/g')));
  const recruiting = (store) => query(collection(store, 'activities'), where('groupId', '==', 'g'),
    where('status', '==', 'recruiting'), orderBy('createdAt', 'desc'), limit(2));
  const result = await assertSucceeds(getDocs(recruiting(s)));
  assert.equal(result.size, 1);
  // Pending members get only their membership; the group query is refused.
  await assertFails(getDocs(recruiting(db('applicant'))));
  await assertFails(getDocs(query(collection(s, 'activities'), where('status', '==', 'recruiting'))));
});

const newGroup = (uid, extra = {}) => ({ name: '새 모임', description: '함께해요', categories: ['스터디'],
  ownerId: uid, themeColor: 'mint', status: 'active', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra });
const creatorMembership = (uid, groupId, extra = {}) => ({ groupId, userId: uid, displayName: uid, role: 'admin',
  status: 'approved', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra });
// Mirrors lib/data/firestore_group_writer.dart: both documents in one batch.
function createGroup(s, uid, { gid = 'n1', group = {}, member = {}, memberId } = {}) {
  const batch = writeBatch(s);
  batch.set(ref(s, `groups/${gid}`), newGroup(uid, group));
  batch.set(ref(s, `memberships/${memberId ?? `${gid}_${uid}`}`), creatorMembership(uid, gid, member));
  return batch.commit();
}

test('모임 만들기: 모임과 본인 운영진 멤버십을 한 번에 만들면 허용된다', async () => {
  const s = db('outsider');
  await assertSucceeds(createGroup(s, 'outsider'));
  await assertSucceeds(getDoc(ref(s, 'groups/n1')));
  await assertSucceeds(createGroup(s, 'outsider', { gid: 'n2', group: { categories: [], themeColor: 'lilac' } }));
});

test('모임 만들기: 한쪽 문서만 만들거나 남의 이름으로 만들 수 없다', async () => {
  const s = db('outsider');
  await assertFails(setDoc(ref(s, 'groups/n1'), newGroup('outsider')));
  await assertFails(setDoc(ref(s, 'memberships/n1_outsider'), creatorMembership('outsider', 'n1')));
  await assertFails(createGroup(s, 'outsider', { group: { ownerId: 'member' } }));
  await assertFails(createGroup(s, 'outsider', { member: { userId: 'member' } }));
  await assertFails(createGroup(s, 'outsider', { memberId: 'n1_member' }));
  await assertFails(createGroup(anon(), 'outsider'));
});

test('모임 만들기: 이미 있는 모임의 운영진으로 자신을 넣을 수 없다', async () => {
  const s = db('outsider');
  await assertFails(setDoc(ref(s, 'memberships/g_outsider'), creatorMembership('outsider', 'g')));
  await assertFails(createGroup(s, 'outsider', { gid: 'g' }));
  await assertFails(createGroup(s, 'outsider', { gid: 'a_b' }));
});

test('모임 만들기: 정해진 필드와 값만 허용한다', async () => {
  const s = db('outsider');
  for (const group of [
    { name: '' }, { name: '가'.repeat(41) }, { description: '' }, { categories: ['a', 'b', 'c'] },
    { categories: [1] }, { themeColor: 'blue' }, { status: 'archived' }, { createdAt: old }, { inviteCode: 'X' },
  ]) {
    await assertFails(createGroup(s, 'outsider', { group }));
  }
  for (const member of [{ role: 'member' }, { status: 'pending' }, { displayName: '' }, { invitationId: 'i' }]) {
    await assertFails(createGroup(s, 'outsider', { member }));
  }
});

test('멤버십은 클라이언트가 만들거나 역할을 올릴 수 없다', async () => {
  await assertFails(setDoc(ref(db('outsider'), 'memberships/g_outsider'), membership('outsider', 'member', 'pending')));
  await assertFails(updateDoc(ref(db('member'), 'memberships/g_member'), { role: 'admin' }));
  await assertFails(updateDoc(ref(db('admin'), 'memberships/g_applicant'), { status: 'approved' }));
  await assertFails(deleteDoc(ref(db('member'), 'memberships/g_member')));
});

test('초대 토큰은 누구도 직접 읽거나 쓸 수 없다', async () => {
  await assertFails(getDoc(ref(db('admin'), 'invitations/hash')));
  await assertFails(getDocs(collection(db('admin'), 'invitations')));
  await assertFails(setDoc(ref(db('admin'), 'invitations/new'), { groupId: 'g' }));
});

test('소모임: 회원은 본문과 질문, 운영진만 편성 설정과 후기 집계를 읽는다', async () => {
  await assertSucceeds(getDoc(ref(db('member'), 'activities/a')));
  await assertSucceeds(getDoc(ref(db('member'), 'activities/a/questions/q1')));
  await assertFails(getDoc(ref(db('member'), 'activities/a/settings/matching')));
  await assertFails(getDoc(ref(db('member'), 'activities/a/feedbackSummary/current')));
  await assertSucceeds(getDoc(ref(db('admin'), 'activities/a/settings/matching')));
  await assertSucceeds(getDoc(ref(db('admin'), 'activities/a/feedbackSummary/current')));
  await assertFails(getDoc(ref(db('applicant'), 'activities/a')));
  await assertFails(getDoc(ref(db('outsider'), 'activities/a/questions/q1')));
  await assertFails(updateDoc(ref(db('admin'), 'activities/a'), { capacity: 30 }));
  await assertFails(setDoc(ref(db('admin'), 'activities/a/questions/q2'), { type: 'time' }));
});

test('참가 신청: 본인과 운영진만 읽고 클라이언트는 쓸 수 없다', async () => {
  await assertSucceeds(getDoc(ref(db('member'), 'registrations/a_member')));
  await assertSucceeds(getDoc(ref(db('admin'), 'registrations/a_member')));
  await assertFails(getDoc(ref(db('other'), 'registrations/a_member')));
  await assertFails(setDoc(ref(db('other'), 'registrations/a_other'), { activityId: 'a', groupId: 'g',
    userId: 'other', status: 'submitted', answers: {} }));
  await assertFails(updateDoc(ref(db('member'), 'registrations/a_member'), { status: 'cancelled' }));
});

test('편성안과 공개 이력은 운영진만 읽는다', async () => {
  for (const path of ['drafts/d', 'publications/a_v1']) {
    await assertSucceeds(getDoc(ref(db('admin'), path)));
    await assertFails(getDoc(ref(db('member'), path)));
    await assertFails(setDoc(ref(db('admin'), path), { activityId: 'a', groupId: 'g' }));
  }
});

test('내 팀 뷰는 제출한 참가자 본인만 읽는다', async () => {
  await assertSucceeds(getDoc(ref(db('member'), 'teamViews/a_member')));
  await assertFails(getDoc(ref(db('admin'), 'teamViews/a_member')));
  // `other` cancelled the registration, so the old view stays hidden.
  await assertFails(getDoc(ref(db('other'), 'teamViews/a_other')));
  await assertFails(updateDoc(ref(db('member'), 'teamViews/a_member'), { teamId: 't2' }));
});

test('후기 원문은 작성자만 읽는다', async () => {
  await assertSucceeds(getDoc(ref(db('member'), 'feedback/a_member')));
  await assertFails(getDoc(ref(db('admin'), 'feedback/a_member')));
  await assertFails(setDoc(ref(db('other'), 'feedback/a_other'), { activityId: 'a', groupId: 'g',
    userId: 'other', rating: 5 }));
});

test('배치 선호는 작성자만 읽고 운영진도 볼 수 없다', async () => {
  await assertSucceeds(getDoc(ref(db('member'), 'placementPreferences/g_member_other')));
  await assertFails(getDoc(ref(db('admin'), 'placementPreferences/g_member_other')));
  await assertFails(getDoc(ref(db('other'), 'placementPreferences/g_member_other')));
  await assertFails(setDoc(ref(db('member'), 'placementPreferences/g_member_admin'), { groupId: 'g',
    userId: 'member', targetUserId: 'admin', active: true }));
});

test('알림은 본인이 읽고 readAt만 서버 시각으로 바꿀 수 있다', async () => {
  await assertSucceeds(getDoc(ref(db('member'), 'notifications/n')));
  await assertFails(getDoc(ref(db('other'), 'notifications/n')));
  await assertSucceeds(updateDoc(ref(db('member'), 'notifications/n'), { readAt: serverTimestamp() }));
  await assertFails(updateDoc(ref(db('member'), 'notifications/n'), { readAt: old }));
  await assertFails(updateDoc(ref(db('member'), 'notifications/n'), { type: 'teamPublished' }));
  await assertFails(updateDoc(ref(db('other'), 'notifications/n'), { readAt: serverTimestamp() }));
  await assertFails(setDoc(ref(db('member'), 'notifications/new'), { userId: 'member' }));
  await assertFails(deleteDoc(ref(db('member'), 'notifications/n')));
});

test('앱 설정은 로그인 사용자만 읽고, 스키마 설명과 그 밖의 경로는 막는다', async () => {
  await assertSucceeds(getDoc(ref(db('outsider'), 'appConfig/teamix')));
  await assertFails(getDoc(ref(anon(), 'appConfig/teamix')));
  await assertFails(setDoc(ref(db('admin'), 'appConfig/teamix'), { palette: [] }));
  await assertFails(getDoc(ref(db('admin'), '_schema/users')));
  // Old subcollection layout must stay closed.
  await assertFails(getDoc(ref(db('member'), 'groups/g/memberships/member')));
  await assertFails(setDoc(ref(db('member'), 'unknown/x'), { a: 1 }));
});
