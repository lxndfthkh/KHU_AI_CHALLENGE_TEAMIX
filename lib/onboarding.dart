import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'data/activity_backend.dart';
import 'data/demo_group_repository.dart';
import 'data/formation_backend.dart';
import 'data/firestore_group_writer.dart';
import 'data/firestore_groups_source.dart';
import 'data/firestore_invitations.dart';
import 'data/group_admin.dart';
import 'data/group_repository.dart';
import 'data/user_profile.dart';
import 'models/group_summary.dart';
import 'screens/my_groups_home.dart';
import 'services/formation_api.dart';
import 'screens/onboarding/auth.dart';
import 'screens/onboarding/create_group.dart';
import 'screens/onboarding/group_preview.dart';
import 'screens/onboarding/invite.dart';
import 'screens/onboarding/share_invite.dart';
import 'screens/onboarding/terms.dart';
import 'screens/onboarding/welcome.dart';
import 'theme.dart';
import 'widgets/onboarding_widgets.dart';

export 'theme.dart' show ink, coral, mint, butter, lilac;

// Auth, the groups home, group creation, invite codes and join approval are
// real; subgroups and team formation still use demo data.
class TeamixApp extends StatelessWidget {
  const TeamixApp({
    super.key,
    this.demoMode = false,
    this.showEmpty = false,
  });

  final bool demoMode;
  final bool showEmpty;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TEAMIX',
    debugShowCheckedModeBanner: false,
    theme: buildTeamixTheme(),
    home: EntryScreen(
      demoMode: demoMode,
      showEmpty: showEmpty,
    ),
  );
}

class EntryScreen extends StatefulWidget {
  const EntryScreen({
    super.key,
    this.demoMode = false,
    this.showEmpty = false,
  });

  final bool demoMode;
  final bool showEmpty;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  String page = 'loading', invite = '', group = '', notice = '';

  late GroupRepository groupRepository;

  // Cached so rebuilds (e.g. busy toggles) don't resubscribe.
  Stream<List<GroupSummary>>? myGroups;
  String? myGroupsUid;

  final email = TextEditingController(),
      password = TextEditingController(),
      nickname = TextEditingController(),
      confirmation = TextEditingController(),
      code = TextEditingController(),
      name = TextEditingController(),
      intro = TextEditingController(),
      other = TextEditingController();

  bool terms = false, privacy = false, busy = false;

  // Firestore invite flow: the code being joined, and the group just created.
  InvitationPreview? invitation;
  String? createdGroupId, shareCode;

  final categories = <String>{};

  static const onboardingPages = {
    'loading',
    'welcome',
    'terms',
    'signup',
    'login',
    'invite',
    'preview',
    'notice',
    'create',
    'share',
  };

  User? get currentUser {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null; // Firebase 미초기화(테스트 등)에서는 비로그인으로 취급
    }
  }

  @override
  void initState() {
    super.initState();

    groupRepository = DemoGroupRepository(
      seedExamples: widget.demoMode && !widget.showEmpty,
    );

    // 시연·홈 테스트는 Firebase 초기화나 인증을 기다리지 않는다.
    if (widget.demoMode) {
      page = 'boundary';
      return;
    }

    invite = Uri.base.queryParameters['invite'] ?? '';

    Future.microtask(() async {
      try {
        await FirebaseAuth.instance.authStateChanges().first;
        if (mounted) {
          currentUser == null ? go('welcome') : route();
        }
      } catch (_) {
        if (mounted) go('welcome');
      }
    });
  }

  @override
  void dispose() {
    for (final c in [
      email,
      password,
      nickname,
      confirmation,
      code,
      name,
      intro,
      other,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void go(String p) {
    if (mounted) setState(() => page = p);
  }

  void toast(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text)),
  );

  /// Signed-in user whose data lives in Firestore; null in demo mode.
  User? get firestoreUser => widget.demoMode ? null : currentUser;

  String profileName(User user) => nickname.text.trim().isNotEmpty
      ? nickname.text.trim()
      : user.displayName ?? user.email?.split('@').first ?? '';

  Future<void> syncProfile() async {
    final user = firestoreUser;
    if (user == null) return;
    try {
      await ensureUserProfile(
        FirebaseFirestore.instance,
        user.uid,
        profileName(user),
      );
    } catch (_) {
      // The home doesn't depend on the profile; retry on next sign-in.
    }
  }

  Stream<List<GroupSummary>> myGroupsFor(String uid) {
    if (myGroups == null || myGroupsUid != uid) {
      myGroupsUid = uid;
      myGroups = FirestoreGroupsSource(
        FirebaseFirestore.instance,
        uid,
      ).watchMyGroups();
    }
    return myGroups!;
  }

  void route() {
    syncProfile();
    if (invite.isNotEmpty) {
      checkInvite();
    } else {
      go('boundary');
    }
  }

  void clearInvite() {
    invite = '';
    invitation = null;
    code.clear();
  }

  ActivityBackend? activityBackend;
  String? activityBackendUid;

  /// One per signed-in user so its HTTP client is reused across rebuilds.
  ActivityBackend? backendFor(String uid) {
    if (activityBackend == null || activityBackendUid != uid) {
      activityBackendUid = uid;
      activityBackend = FirebaseActivityBackend(FirebaseFirestore.instance, uid);
    }
    return activityBackend;
  }

  /// algorithm/server_v3.py, e.g. its Cloud Run URL:
  /// `flutter run --dart-define=FORMATION_URL=https://.../`.
  static const formationUrl = String.fromEnvironment('FORMATION_URL');

  FormationBackend? formationBackend;

  FormationBackend? get formation {
    if (formationUrl.isEmpty) return null;
    final base = formationUrl.endsWith('/') ? formationUrl : '$formationUrl/';
    return formationBackend ??= ServerFormationBackend(
      FirebaseFirestore.instance,
      FormationApi(baseUrl: Uri.parse(base)),
    );
  }

  GroupAdmin? get groupAdmin {
    final user = firestoreUser;
    return user == null
        ? null
        : FirestoreGroupAdmin(FirebaseFirestore.instance, user.uid);
  }

  Future<void> issueShareCode() async {
    final groupId = createdGroupId;
    if (groupId == null || busy) return;
    setState(() => busy = true);
    try {
      final issued = await groupAdmin!.issueInvitation(groupId);
      if (mounted) setState(() => shareCode = issued);
    } catch (_) {
      if (mounted) toast('초대 코드를 만들지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> checkFirestoreInvite(User user) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final db = FirebaseFirestore.instance;
      final found = await findInvitation(db, invite);
      if (found == null) {
        notice = '초대가 만료되었거나 올바르지 않아요.';
      } else {
        group = found.groupName;
        final status = await myMembershipStatus(
          db,
          uid: user.uid,
          groupId: found.groupId,
        );
        if (status == null) {
          invitation = found;
          go('preview');
          return;
        }
        notice = switch (status) {
          'pending' => '이미 요청했어요. 운영진 승인을 기다려 주세요.',
          'approved' => '이미 가입한 모임이에요.',
          _ => '이전 요청이 처리된 모임이에요. 운영진에게 문의해 주세요.',
        };
      }
    } catch (_) {
      notice = '초대 코드를 확인하지 못했어요. 다시 시도해 주세요.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
    clearInvite();
    go('notice');
  }

  Future<void> sendJoinRequest(User user, InvitationPreview found) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await requestJoin(
        FirebaseFirestore.instance,
        uid: user.uid,
        displayName: profileName(user),
        invitation: found,
      );
      notice = '참여 요청을 보냈어요. 승인 대기 중입니다.';
    } catch (_) {
      notice = '참여 요청을 보내지 못했어요. 초대 코드가 만료됐을 수 있어요.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
    clearInvite();
    go('notice');
  }

  void checkInvite() {
    final user = firestoreUser;
    if (user != null) {
      checkFirestoreInvite(user);
      return;
    }
    final value = invite.trim().toUpperCase();
    group = groupRepository.invitedGroupName;

    if (!groupRepository.isValidInvite(value)) {
      notice = '초대가 만료되었거나 올바르지 않아요.';
    } else if (groupRepository.membershipStatus(group) == 'pending') {
      notice = '이미 요청했어요. 운영진 승인을 기다려 주세요.';
    } else if (groupRepository.containsGroup(group)) {
      notice = '이미 가입한 모임이에요.';
    } else {
      go('preview');
      return;
    }

    clearInvite();
    go('notice');
  }

  Future<void> auth(bool signup) async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim()) ||
        password.text.length < 6 ||
        (signup &&
            (nickname.text.trim().isEmpty ||
                password.text != confirmation.text))) {
      toast('이메일·닉네임·비밀번호(6자 이상)와 확인 입력을 확인해 주세요.');
      return;
    }

    if (signup && !(terms && privacy)) {
      go('terms');
      return;
    }

    setState(() => busy = true);

    try {
      if (signup) {
        final result =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );

        try {
          await result.user?.updateDisplayName(nickname.text.trim());
        } catch (_) {
          if (mounted) toast('계정은 생성됐지만 닉네임 저장에 실패했어요.');
        }
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }

      password.clear();
      confirmation.clear();
      if (mounted) route();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        toast(
          e.code == 'email-already-in-use'
              ? '이미 가입한 이메일이에요.'
              : '인증 실패: 계정 정보와 이메일 로그인 설정을 확인해 주세요.',
        );
      }
    } catch (_) {
      if (mounted) toast('연결에 실패했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    if (!email.text.contains('@')) {
      toast('이메일을 먼저 입력해 주세요.');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email.text.trim(),
      );
      if (mounted) toast('해당 계정이 있다면 재설정 메일이 발송됩니다.');
    } catch (_) {
      if (mounted) toast('재설정 요청을 처리하지 못했어요.');
    }
  }

  Future<void> signOut() async {
    if (busy) return;
    setState(() => busy = true);

    try {
      // 시연용 로그아웃은 실제 Firebase 계정에 영향을 주지 않는다.
      if (!widget.demoMode) {
        await FirebaseAuth.instance.signOut();
      }

      if (!mounted) return;

      groupRepository.clearMemberships();
      myGroups = null;
      myGroupsUid = null;
      activityBackend = null;
      activityBackendUid = null;
      formationBackend = null;
      clearInvite();
      password.clear();
      confirmation.clear();
      go('welcome');
    } catch (_) {
      if (mounted) toast('로그아웃하지 못했어요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void toggleDemoGroups() {
    if (!widget.demoMode || busy) return;

    setState(() {
      groupRepository = DemoGroupRepository(
        seedExamples: groupRepository.memberships.isEmpty,
      );
    });
  }

  void termsDetail() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('개발용 임시 약관'),
      content: const Text(
        '실제 약관·처리방침 및 동의 이력 저장은 아직 구현되지 않았습니다. 테스트 계정만 사용하세요.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('닫기'),
        ),
      ],
    ),
  );

  void selectCategory(String category, bool selected) {
    if (selected && categories.length >= 2) {
      toast('최대 2개까지 선택해 주세요.');
      return;
    }

    setState(() {
      if (selected) {
        categories.add(category);
      } else {
        categories.remove(category);
      }
    });
  }

  Future<void> createGroup() async {
    if (name.text.trim().isEmpty ||
        intro.text.trim().isEmpty ||
        (categories.contains('기타') && other.text.trim().isEmpty)) {
      toast('필수 항목을 입력해 주세요.');
      return;
    }

    if (name.text.trim().length > groupNameMaxLength ||
        intro.text.trim().length > groupDescriptionMaxLength ||
        other.text.trim().length > groupCategoryMaxLength) {
      toast(
        '모임 이름은 $groupNameMaxLength자, 소개는 $groupDescriptionMaxLength자, '
        '카테고리는 $groupCategoryMaxLength자까지 입력할 수 있어요.',
      );
      return;
    }

    group = name.text.trim();

    final user = firestoreUser;
    if (user != null) {
      if (busy) return;
      setState(() => busy = true);
      try {
        createdGroupId = await createGroupInFirestore(
          FirebaseFirestore.instance,
          uid: user.uid,
          displayName: profileName(user),
          name: group,
          description: intro.text,
          categories: [
            for (final category in categories)
              category == '기타' ? other.text.trim() : category,
          ],
        );
        name.clear();
        intro.clear();
        other.clear();
        categories.clear();
        shareCode = null;
        go('share');
      } catch (_) {
        if (mounted) toast('모임을 만들지 못했어요. 잠시 후 다시 시도해 주세요.');
      } finally {
        if (mounted) setState(() => busy = false);
      }
      return;
    }

    if (groupRepository.containsGroup(group)) {
      toast('시연에서는 중복 이름 대신 다른 이름을 입력해 주세요.');
      return;
    }

    groupRepository.createGroup(group);
    go('share');
  }

  List<Widget> body() {
    final ui = OnboardingWidgets(busy: busy);

    switch (page) {
      case 'loading':
        return [
          ui.title('teamix.'),
          const Center(child: CircularProgressIndicator()),
        ];
      case 'welcome':
        return buildWelcomeContent(
          ui: ui,
          hasInvite: invite.isNotEmpty,
          onSignup: () => go('terms'),
          onLogin: () => go('login'),
        );
      case 'terms':
        return buildTermsContent(
          ui: ui,
          terms: terms,
          privacy: privacy,
          onAllChanged: (value) => setState(() {
            terms = value ?? false;
            privacy = value ?? false;
          }),
          onTermsChanged: (value) =>
              setState(() => terms = value ?? false),
          onPrivacyChanged: (value) =>
              setState(() => privacy = value ?? false),
          onDetail: termsDetail,
          onNext: () => go('signup'),
          onBack: () => go('welcome'),
        );
      case 'signup':
      case 'login':
        final signup = page == 'signup';
        return buildAuthContent(
          ui: ui,
          signup: signup,
          nickname: nickname,
          email: email,
          password: password,
          confirmation: confirmation,
          onSubmit: () => auth(signup),
          onResetPassword: resetPassword,
          onBack: () => go(signup ? 'terms' : 'welcome'),
        );
      case 'invite':
        return buildInviteContent(
          ui: ui,
          code: code,
          invitationCode: groupRepository.invitationCode,
          onCheck: () {
            invite = code.text;
            checkInvite();
          },
          onCancel: () {
            clearInvite();
            go('boundary');
          },
          demo: firestoreUser == null,
        );
      case 'preview':
        final user = firestoreUser, found = invitation;
        return buildGroupPreviewContent(
          ui: ui,
          group: group,
          description: found?.description,
          demo: user == null,
          onRequest: () {
            if (user != null && found != null) {
              sendJoinRequest(user, found);
              return;
            }
            groupRepository.requestMembership(group);
            clearInvite();
            notice = '참여 요청을 보냈어요. 승인 대기 중입니다.';
            go('notice');
          },
          onCancel: () {
            clearInvite();
            go('boundary');
          },
        );
      case 'notice':
        return [
          ui.panel(butter, [ui.title(notice)]),
          ui.button('다음', () => go('boundary')),
        ];
      case 'create':
        return buildCreateGroupContent(
          ui: ui,
          name: name,
          intro: intro,
          other: other,
          categories: categories,
          onCategorySelected: selectCategory,
          onCreate: createGroup,
          onCancel: () => go('boundary'),
          demo: firestoreUser == null,
        );
      case 'share':
        return buildShareInviteContent(
          ui: ui,
          group: group,
          demo: firestoreUser == null,
          inviteCode: shareCode,
          onIssueInvite: createdGroupId == null ? null : issueShareCode,
          onSkip: () => go('boundary'),
        );
      default:
        // 홈은 build()에서 별도 Scaffold로 표시한다.
        return const <Widget>[];
    }
  }

  void handleBack(bool didPop, Object? result) {
    if (didPop || busy) return;

    if (widget.demoMode || currentUser != null) {
      // 시연 로그아웃 후 welcome에서는 홈으로 되돌리지 않는다.
      if (widget.demoMode &&
          {'welcome', 'terms', 'signup', 'login'}.contains(page)) {
        go(page == 'signup' ? 'terms' : 'welcome');
        return;
      }
      clearInvite();
      go('boundary');
    } else {
      go(page == 'signup' ? 'terms' : 'welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;

    if (!onboardingPages.contains(page)) {
      final uid = widget.demoMode ? null : currentUser?.uid;
      Widget home(List<GroupSummary>? groups, {bool loadFailed = false}) =>
          MyGroupsHome(
            groups: groups,
            loadFailed: loadFailed,
            demoMode: widget.demoMode,
            busy: busy,
            onCreateGroup: () => go('create'),
            onJoinGroup: () => go('invite'),
            onSignOut: signOut,
            onToggleDemoGroups: toggleDemoGroups,
            groupAdmin: uid == null ? null : groupAdmin,
            activityBackend: uid == null ? null : backendFor(uid),
            formationBackend: uid == null ? null : formation,
          );

      content = uid == null
          ? home(DemoGroupRepository.summariesOf(groupRepository))
          : StreamBuilder<List<GroupSummary>>(
              stream: myGroupsFor(uid),
              builder: (context, snapshot) => home(
                snapshot.data,
                loadFailed: snapshot.hasError,
              ),
            );
    } else {
      content = Scaffold(
        appBar: AppBar(
          title: const Text(
            'teamix.',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            if (!widget.demoMode && currentUser != null)
              IconButton(
                tooltip: '로그아웃',
                icon: const Icon(Icons.logout),
                onPressed: busy ? null : signOut,
              ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListView(
                key: ValueKey(page),
                padding: const EdgeInsets.all(24),
                children: [
                  OnboardingWidgets(busy: busy).panel(lilac, [
                    const Text(
                      '개발용 · 인증, 내 모임 목록, 모임 만들기, 초대 코드 참여, 가입 승인은 실제 연결. 소모임·팀 편성은 시연 데이터예요.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ]),
                  ...body(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: handleBack,
      child: content,
    );
  }
}
