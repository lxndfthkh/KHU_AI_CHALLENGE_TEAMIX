import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'data/demo_group_repository.dart';
import 'data/group_repository.dart';
import 'screens/my_groups_home.dart';
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

// Auth is real; membership and invitation fixtures are not persisted.
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

  final email = TextEditingController(),
      password = TextEditingController(),
      nickname = TextEditingController(),
      confirmation = TextEditingController(),
      code = TextEditingController(),
      name = TextEditingController(),
      intro = TextEditingController(),
      other = TextEditingController();

  bool terms = false, privacy = false, busy = false;

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

  void route() {
    if (invite.isNotEmpty) {
      checkInvite();
    } else {
      go('boundary');
    }
  }

  void clearInvite() {
    invite = '';
    code.clear();
  }

  void checkInvite() {
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

  void createGroup() {
    if (name.text.trim().isEmpty ||
        intro.text.trim().isEmpty ||
        (categories.contains('기타') && other.text.trim().isEmpty)) {
      toast('필수 항목을 입력해 주세요.');
      return;
    }

    group = name.text.trim();

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
        );
      case 'preview':
        return buildGroupPreviewContent(
          ui: ui,
          group: group,
          onRequest: () {
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
        );
      case 'share':
        return buildShareInviteContent(
          ui: ui,
          group: group,
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
      content = MyGroupsHome(
        repository: groupRepository,
        demoMode: widget.demoMode,
        busy: busy,
        onCreateGroup: () => go('create'),
        onJoinGroup: () => go('invite'),
        onSignOut: signOut,
        onToggleDemoGroups: toggleDemoGroups,
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
                      '개발용 · 인증만 실제 연결. 모임·초대·참여 요청은 메모리 시연이며 새로고침 시 초기화됩니다.',
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
