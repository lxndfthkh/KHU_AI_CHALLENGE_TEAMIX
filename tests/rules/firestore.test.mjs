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
      ...Object.entries({ ABCD2345: [true, future], EXPRD234: [true, old], QFFQ2345: [false, future] }).map(
        ([code, [active, expiresAt]]) => setDoc(ref(s, `invitations/${code}`), { groupId: 'g', groupName: '메이커스',
          description: '시연', active, expiresAt, createdBy: 'admin', createdAt: old })),
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

test('멤버십: 본인 것, 임원진은 전체, 회원은 승인된 회원만 읽는다', async () => {
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

test('모임 만들기: 모임과 본인 임원진 멤버십을 한 번에 만들면 허용된다', async () => {
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

test('모임 만들기: 이미 있는 모임의 임원진으로 자신을 넣을 수 없다', async () => {
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
  // A decision must also stamp updatedAt with the server time.
  await assertFails(updateDoc(ref(db('admin'), 'memberships/g_applicant'), { status: 'approved' }));
  await assertFails(deleteDoc(ref(db('member'), 'memberships/g_member')));
});

const decide = (uid, target, status, extra = {}) =>
  updateDoc(ref(db(uid), `memberships/g_${target}`), { status, updatedAt: serverTimestamp(), ...extra });

test('가입 승인: 임원진이 대기 요청을 승인하면 정식 회원이 된다', async () => {
  await assertFails(getDoc(ref(db('applicant'), 'groups/g')));
  await assertSucceeds(decide('admin', 'applicant', 'approved'));
  await assertSucceeds(getDoc(ref(db('applicant'), 'groups/g')));
  await assertSucceeds(getDoc(ref(db('applicant'), 'activities/a')));
});

test('가입 거절: 임원진이 거절하면 모임을 계속 볼 수 없다', async () => {
  await assertSucceeds(decide('admin', 'applicant', 'rejected'));
  await assertFails(getDoc(ref(db('applicant'), 'groups/g')));
  // Already decided: no second decision.
  await assertFails(decide('admin', 'applicant', 'approved'));
});

test('가입 결정: 임원진이 아니거나 대기가 아니거나 다른 값을 바꾸면 거절된다', async () => {
  await assertFails(decide('member', 'applicant', 'approved'));
  await assertFails(decide('applicant', 'applicant', 'approved'));
  await assertFails(decide('outsider', 'applicant', 'approved'));
  await assertFails(decide('admin', 'applicant', 'left'));
  await assertFails(decide('admin', 'applicant', 'approved', { role: 'admin' }));
  await assertFails(decide('admin', 'applicant', 'approved', { displayName: '바뀐 이름' }));
  await assertFails(decide('admin', 'applicant', 'approved', { updatedAt: old }));
  await assertFails(decide('admin', 'rejected', 'approved'));
  await assertFails(decide('admin', 'member', 'rejected'));
  // An admin of another group can't decide here.
  await env.withSecurityRulesDisabled((c) => setDoc(ref(c.firestore(), 'memberships/h_outsider'),
    membership('outsider', 'admin', 'approved', 'h')));
  await assertFails(decide('outsider', 'applicant', 'approved'));
});

test('가입 요청 목록: 임원진만 모임의 대기 요청을 조회한다', async () => {
  const pending = (uid) => query(collection(db(uid), 'memberships'), where('groupId', '==', 'g'),
    where('status', '==', 'pending'), orderBy('createdAt'));
  assert.equal((await assertSucceeds(getDocs(pending('admin')))).size, 1);
  await assertFails(getDocs(pending('member')));
  await assertFails(getDocs(pending('applicant')));
});

const inSixDays = () => Timestamp.fromMillis(Date.now() + 6 * 864e5);
const invitation = (extra = {}) => ({ groupId: 'g', groupName: '메이커스', description: '시연', active: true,
  expiresAt: inSixDays(), createdBy: 'admin', createdAt: serverTimestamp(), ...extra });

test('초대 코드: 임원진만 모임 정보 그대로 7일 이내로 발급한다', async () => {
  await assertSucceeds(setDoc(ref(db('admin'), 'invitations/NEWC2345'), invitation()));
  await assertFails(setDoc(ref(db('member'), 'invitations/NEWC2346'), invitation({ createdBy: 'member' })));
  await assertFails(setDoc(ref(db('outsider'), 'invitations/NEWC2347'), invitation({ createdBy: 'outsider' })));
  for (const extra of [{ groupName: '다른 이름' }, { description: '다른 소개' }, { active: false },
    { expiresAt: Timestamp.fromMillis(Date.now() + 8 * 864e5) }, { expiresAt: old }, { createdBy: 'member' },
    { memberCount: 3 }]) {
    await assertFails(setDoc(ref(db('admin'), 'invitations/NEWC2348'), invitation(extra)));
  }
  await assertFails(setDoc(ref(db('admin'), 'invitations/short1'), invitation()));
  // An existing code can't be overwritten.
  await assertFails(setDoc(ref(db('admin'), 'invitations/ABCD2345'), invitation()));
});

test('초대 코드: 아는 코드만 조회하고 목록은 못 본다', async () => {
  await assertSucceeds(getDoc(ref(db('outsider'), 'invitations/ABCD2345')));
  await assertFails(getDoc(ref(anon(), 'invitations/ABCD2345')));
  await assertFails(getDoc(ref(db('outsider'), 'invitations/EXPRD234')));
  await assertFails(getDoc(ref(db('outsider'), 'invitations/QFFQ2345')));
  await assertFails(getDocs(collection(db('admin'), 'invitations')));
  await assertFails(getDocs(query(collection(db('admin'), 'invitations'), where('groupId', '==', 'g'))));
  await assertFails(updateDoc(ref(db('member'), 'invitations/ABCD2345'), { active: false }));
  await assertFails(updateDoc(ref(db('admin'), 'invitations/ABCD2345'), { expiresAt: inSixDays() }));
  await assertSucceeds(updateDoc(ref(db('admin'), 'invitations/ABCD2345'), { active: false }));
  await assertFails(deleteDoc(ref(db('admin'), 'invitations/ABCD2345')));
});

const joinRequest = (uid, extra = {}) => ({ groupId: 'g', userId: uid, displayName: uid, role: 'member',
  status: 'pending', invitationId: 'ABCD2345', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra });

test('참여 요청: 유효한 코드로 본인 승인 대기만 만들 수 있다', async () => {
  await assertSucceeds(setDoc(ref(db('outsider'), 'memberships/g_outsider'), joinRequest('outsider')));
  await assertSucceeds(getDoc(ref(db('outsider'), 'memberships/g_outsider')));
  // Still pending: the group itself stays hidden.
  await assertFails(getDoc(ref(db('outsider'), 'groups/g')));
});

test('참여 요청: 잘못된 코드·남의 요청·역할 올리기·중복 요청은 거절된다', async () => {
  const s = db('newbie');
  for (const extra of [{ invitationId: 'EXPRD234' }, { invitationId: 'QFFQ2345' }, { invitationId: 'NONE2345' },
    { status: 'approved' }, { role: 'admin' }, { userId: 'other' }, { displayName: '' }, { note: 'x' }]) {
    await assertFails(setDoc(ref(s, 'memberships/g_newbie'), joinRequest('newbie', extra)));
  }
  await env.withSecurityRulesDisabled((c) => setDoc(ref(c.firestore(), 'groups/h'),
    { name: '다른 모임', description: '', ownerId: 'admin', createdAt: old, updatedAt: old }));
  await assertFails(setDoc(ref(s, 'memberships/h_newbie'), joinRequest('newbie', { groupId: 'h' })));
  await assertFails(setDoc(ref(s, 'memberships/g_other'), joinRequest('other')));
  // Existing members, pending or rejected users can't re-request over their document.
  for (const uid of ['member', 'applicant', 'rejected']) {
    await assertFails(setDoc(ref(db(uid), `memberships/g_${uid}`), joinRequest(uid)));
  }
});

test('참여 요청 확인: 본인 멤버십만 모임별로 조회할 수 있다', async () => {
  const mine = (uid, g = 'g') => query(collection(db(uid), 'memberships'), where('userId', '==', uid),
    where('groupId', '==', g));
  assert.equal((await assertSucceeds(getDocs(mine('applicant')))).size, 1);
  assert.equal((await assertSucceeds(getDocs(mine('outsider')))).size, 0);
});

test('소모임: 회원은 본문과 질문, 임원진만 편성 설정과 후기 집계를 읽는다', async () => {
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

test('참가 신청: 본인과 임원진만 읽고 클라이언트는 쓸 수 없다', async () => {
  await assertSucceeds(getDoc(ref(db('member'), 'registrations/a_member')));
  await assertSucceeds(getDoc(ref(db('admin'), 'registrations/a_member')));
  await assertFails(getDoc(ref(db('other'), 'registrations/a_member')));
  await assertFails(setDoc(ref(db('other'), 'registrations/a_other'), { activityId: 'a', groupId: 'g',
    userId: 'other', status: 'submitted', answers: {} }));
  await assertFails(updateDoc(ref(db('member'), 'registrations/a_member'), { status: 'cancelled' }));
});

test('편성안과 공개 이력은 임원진만 읽는다', async () => {
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

test('배치 선호는 작성자만 읽고 임원진도 볼 수 없다', async () => {
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

test('학습 활용 동의는 본인만 읽고 앱이 직접 쓰지 못한다', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(ref(context.firestore(), 'consents/member'), { learning: { agreed: true, version: 'l1', at: old }, updatedAt: old });
  });
  await assertSucceeds(getDoc(ref(db('member'), 'consents/member')));
  await assertFails(getDoc(ref(db('admin'), 'consents/member')));
  await assertFails(setDoc(ref(db('member'), 'consents/member'), { learning: { agreed: false } }));
  await assertFails(setDoc(ref(db('other'), 'consents/other'), { learning: { agreed: true } }));
});

test('학습 데이터·모델·실행 기록은 앱에서 읽을 수 없고, 적용 중인 모델 설정만 로그인 사용자가 읽는다', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const s = context.firestore();
    await setDoc(ref(s, 'trainingDatasets/fx1/rows/r'), { y_overall: 4 });
    await setDoc(ref(s, 'modelVersions/m1'), { status: 'active' });
    await setDoc(ref(s, 'trainingRuns/t1'), { status: 'candidate' });
    await setDoc(ref(s, 'appConfig/learning'), { activeModelId: 'm1' });
  });
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(ref(context.firestore(), 'learningMonitor/a'), { yOverallMean: 4 });
    await setDoc(ref(context.firestore(), 'learningReports/latest'), { status: 'waiting' });
  });
  for (const path of ['trainingDatasets/fx1/rows/r', 'modelVersions/m1', 'trainingRuns/t1', 'learningMonitor/a', 'learningReports/latest']) {
    await assertFails(getDoc(ref(db('admin'), path)));
  }
  await assertSucceeds(getDoc(ref(db('member'), 'appConfig/learning')));
  await assertFails(setDoc(ref(db('admin'), 'appConfig/learning'), { activeModelId: null }));
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
