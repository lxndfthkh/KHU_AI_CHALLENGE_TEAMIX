import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Pre-home prototype only: Auth is real; membership and invitation fixtures are not persisted.
const ink = Color(0xFF202438),
    coral = Color(0xFFF07868),
    mint = Color(0xFFE0F2E8),
    butter = Color(0xFFFFF0BF),
    lilac = Color(0xFFEDE6FA);

class TeamixApp extends StatelessWidget {
  const TeamixApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TEAMIX',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFFFFEFA),
      colorScheme: ColorScheme.fromSeed(seedColor: coral)
          .copyWith(primary: coral, onPrimary: ink),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
        ),
      ),
    ),
    home: const EntryScreen(),
  );
}

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});
  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  String page = 'loading', invite = '', group = '', notice = '';
  final memberships = <String, String>{};
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

  void toast(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
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
    final v = invite.trim().toUpperCase();
    group = '경희 메이커스';
    if (v != 'TEAM24') {
      notice = '초대가 만료되었거나 올바르지 않아요.';
    } else if (memberships[group] == 'pending') {
      notice = '이미 요청했어요. 운영진 승인을 기다려 주세요.';
    } else if (memberships.containsKey(group)) {
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
        final r = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
        try {
          await r.user?.updateDisplayName(nickname.text.trim());
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

  Widget button(String label, VoidCallback action) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: FilledButton(onPressed: busy ? null : action, child: Text(label)),
  );
  Widget title(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Text(
      s,
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: ink,
      ),
    ),
  );
  Widget panel(Color color, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    ),
  );
  Widget field(String label, TextEditingController c, {bool secret = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
          controller: c,
          obscureText: secret,
          keyboardType: c == email
              ? TextInputType.emailAddress
              : TextInputType.text,
          decoration: InputDecoration(labelText: label),
        ),
      );
  void termsDetail() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('개발용 임시 약관'),
      content: const Text(
        '실제 약관·처리방침 및 동의 이력 저장은 아직 구현되지 않았습니다. 테스트 계정만 사용하세요.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('닫기')),
      ],
    ),
  );
  List<Widget> body() {
    switch (page) {
      case 'loading':
        return [
          title('teamix.'),
          const Center(child: CircularProgressIndicator()),
        ];
      case 'welcome':
        return [
          title('우리 모임이,\n좋은 팀이 되는 곳.'),
          panel(mint, [
            const Icon(Icons.diversity_2, size: 72),
            const Text('초대받은 모임과 함께 시작해요.'),
          ]),
          if (invite.isNotEmpty) const Text('초대 정보를 유지하고 있어요.'),
          button('회원가입', () => go('terms')),
          button('로그인', () => go('login')),
        ];
      case 'terms':
        return [
          title('시작하기 전,\n확인해 주세요.'),
          const Text('1 / 2 · 약관 동의'),
          panel(butter, [
            CheckboxListTile(
              title: const Text('필수 항목 모두 동의'),
              value: terms && privacy,
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      terms = v ?? false;
                      privacy = v ?? false;
                    }),
            ),
            CheckboxListTile(
              title: const Text('[필수] 이용약관'),
              value: terms,
              onChanged: (v) => setState(() => terms = v ?? false),
            ),
            CheckboxListTile(
              title: const Text('[필수] 개인정보 수집·이용'),
              value: privacy,
              onChanged: (v) => setState(() => privacy = v ?? false),
            ),
            TextButton(
              onPressed: termsDetail,
              child: const Text('임시 약관 안내 보기'),
            ),
          ]),
          if (terms && privacy) button('동의하고 다음', () => go('signup')),
          button('뒤로', () => go('welcome')),
        ];
      case 'signup':
      case 'login':
        final signup = page == 'signup';
        return [
          title(signup ? '어떻게 불러드릴까요?' : '다시 만나서 반가워요!'),
          if (signup) ...[
            const Text('2 / 2 · 최소 계정 정보'),
            field('닉네임', nickname),
          ],
          field('이메일', email),
          field('비밀번호', password, secret: true),
          if (signup) field('비밀번호 확인', confirmation, secret: true),
          button(
            busy
                ? '처리 중…'
                : signup
                ? '가입하기'
                : '로그인',
            () => auth(signup),
          ),
          if (!signup)
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
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
                    },
              child: const Text('비밀번호 재설정'),
            ),
          button('뒤로', () => go(signup ? 'terms' : 'welcome')),
        ];
      case 'invite':
        return [
          title('초대 코드로\n모임에 참가해요.'),
          panel(mint, [
            field('초대 코드 · 시연 TEAM24', code),
            button('모임 확인하기', () {
              invite = code.text;
              checkInvite();
            }),
          ]),
          button('취소', () {
            clearInvite();
            go('boundary');
          }),
        ];
      case 'preview':
        return [
          title('초대받은 모임이에요.'),
          panel(mint, [
            title(group),
            const Text('캠퍼스의 작은 불편을 함께 해결해요.\n인원 20명 · 가상 데이터'),
          ]),
          const Text('참여 요청 후 운영진 승인이 필요해요.'),
          button('참여 요청 보내기 · 시연', () {
            memberships[group] = 'pending';
            clearInvite();
            notice = '참여 요청을 보냈어요. 승인 대기 중입니다.';
            go('notice');
          }),
          button('참여 취소', () {
            clearInvite();
            go('boundary');
          }),
        ];
      case 'notice':
        return [
          panel(butter, [title(notice)]),
          button('다음', () => go('boundary')),
        ];
      case 'create':
        return [
          title('함께할 사람들을\n모아보세요.'),
          const Text('팀 편성은 소모임을 만든 뒤 진행해요.'),
          panel(lilac, [
            const Icon(Icons.diversity_2, size: 48),
            const Text('기본 이미지 · 사진 업로드 추후 지원'),
          ]),
          field('모임 이름 *', name),
          field('한 줄 소개 *', intro),
          const Text('관심 카테고리 · 최대 2개'),
          Wrap(
            spacing: 8,
            children: ['친목', '스터디', '프로젝트', '취미', '운동', '기타']
                .map(
                  (s) => FilterChip(
                    label: Text(s),
                    selected: categories.contains(s),
                    onSelected: (v) {
                      if (v && categories.length >= 2) {
                        toast('최대 2개까지 선택해 주세요.');
                        return;
                      }
                      setState(() {
                        if (v) {
                          categories.add(s);
                        } else {
                          categories.remove(s);
                        }
                      });
                    },
                  ),
                )
                .toList(),
          ),
          if (categories.contains('기타')) field('카테고리 직접 입력', other),
          panel(butter, [
            const Text('생성자는 승인 없이 대표자가 됩니다. 비공개 배치 선호 열람 권한은 포함되지 않습니다.'),
          ]),
          button('모임 만들기 · 시연', () {
            if (name.text.trim().isEmpty ||
                intro.text.trim().isEmpty ||
                (categories.contains('기타') && other.text.trim().isEmpty)) {
              toast('필수 항목을 입력해 주세요.');
              return;
            }
            group = name.text.trim();
            if (memberships.containsKey(group)) {
              toast('시연에서는 중복 이름 대신 다른 이름을 입력해 주세요.');
              return;
            }
            memberships[group] = 'owner';
            go('share');
          }),
          button('취소', () => go('boundary')),
        ];
      case 'share':
        return [
          title('모임 생성 완료 · 시연'),
          panel(mint, [title(group), const Text('대표자 · 별도 승인 없음')]),
          const Text('초대 링크 / 코드 공유\n실제 모임 저장 및 초대 발급 전이므로 공유는 아직 사용할 수 없어요.'),
          button('건너뛰기', () => go('boundary')),
        ];
      default:
        return [
          title('홈 진입 준비 완료'),
          const Text('여기는 Mainhome 직전 연결 지점입니다. 홈 화면은 구현 범위에 포함하지 않았습니다.'),
          panel(memberships.isEmpty ? butter : mint, [
            Text(
              memberships.isEmpty
                  ? '소속·대기 모임 없음 → 빈 Mainhome으로 연결 예정'
                  : '소속·대기 모임 있음 → Mainhome 목록으로 연결 예정',
            ),
            ...memberships.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${e.key} · ${e.value == 'pending'
                      ? '승인 대기'
                      : e.value == 'owner'
                      ? '대표자'
                      : '정식 멤버'}',
                ),
              ),
            ),
          ]),
          button('모임 참가하기', () => go('invite')),
          button('모임 만들기', () => go('create')),
        ];
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop || busy) return;
      if (currentUser == null) {
        go(page == 'signup' ? 'terms' : 'welcome');
      } else {
        clearInvite();
        go('boundary');
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text(
          'teamix.',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (currentUser != null)
            IconButton(
              tooltip: '로그아웃',
              icon: const Icon(Icons.logout),
              onPressed: busy
                  ? null
                  : () async {
                      try {
                        await FirebaseAuth.instance.signOut();
                        memberships.clear();
                        password.clear();
                        confirmation.clear();
                        if (mounted) go('welcome');
                      } catch (_) {
                        if (mounted) toast('로그아웃하지 못했어요.');
                      }
                    },
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
                panel(lilac, [
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
    ),
  );
}
