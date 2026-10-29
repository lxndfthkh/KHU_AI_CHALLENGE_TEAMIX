import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

const ink = Color(0xFF202438);
const coral = Color(0xFFF07868);
const mint = Color(0xFFE0F2E8);
const butter = Color(0xFFFFF0BF);
const lilac = Color(0xFFEDE6FA);

class TeamixApp extends StatelessWidget {
  const TeamixApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'TEAMIX',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFFFFEFA),
      colorScheme: ColorScheme.fromSeed(seedColor: coral).copyWith(primary: coral, onPrimary: ink),
      textTheme: const TextTheme(bodyMedium: TextStyle(color: ink, fontSize: 16), headlineMedium: TextStyle(color: ink, fontSize: 30, fontWeight: FontWeight.w800)),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.all(16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52), foregroundColor: ink, textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    ),
    home: const EntryScreen(),
  );
}

void open(BuildContext c, Widget screen) => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => screen));
void message(BuildContext c, String text) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(text)));

class Frame extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> children;
  const Frame({super.key, required this.title, required this.subtitle, required this.children});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('teamix.', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -1)), backgroundColor: Colors.transparent, actions: [if (FirebaseAuth.instance.currentUser != null) IconButton(tooltip: '로그아웃', icon: const Icon(Icons.logout), onPressed: () async { await FirebaseAuth.instance.signOut(); if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst); })]),
    body: SafeArea(top: false, child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: ListView(padding: const EdgeInsets.fromLTRB(24, 20, 24, 32), children: [Text(title, style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 12), Text(subtitle, style: const TextStyle(color: Color(0xFF687080), height: 1.6)), const SizedBox(height: 28), ...children])))),
  );
}
class Panel extends StatelessWidget {
  final Color color; final Widget child;
  const Panel({super.key, required this.color, required this.child});
  @override
  Widget build(BuildContext context) => Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(22)), child: child);
}
class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(stream: FirebaseAuth.instance.authStateChanges(), builder: (c, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (snapshot.data != null) return const InvitationScreen();
    return Frame(title: '우리 모임이,\n좋은 팀이 되는 곳.', subtitle: '초대받은 모임과 함께 시작해요.', children: [
      const Panel(color: mint, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.diversity_2_rounded, size: 72, color: ink), SizedBox(height: 30), Text('다른 우리가 만나\n하나의 팀으로.', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)), SizedBox(height: 12), Text('모임의 시작부터 활동까지, TEAMIX')])),
      FilledButton(onPressed: () => open(context, const AuthScreen(signup: true)), child: const Text('회원가입')),
      const SizedBox(height: 12), OutlinedButton(onPressed: () => open(context, const AuthScreen(signup: false)), child: const Padding(padding: EdgeInsets.all(14), child: Text('로그인'))),
    ]);
  });
}

class AuthScreen extends StatefulWidget {
  final bool signup;
  const AuthScreen({super.key, required this.signup});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}
class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(), email = TextEditingController(), password = TextEditingController(), repeat = TextEditingController();
  bool busy = false, hidden = true;
  @override
  void dispose() { name.dispose(); email.dispose(); password.dispose(); repeat.dispose(); super.dispose(); }
  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (widget.signup) { open(context, TermsScreen(email: email.text.trim(), password: password.text, nickname: name.text.trim())); return; }
    setState(() => busy = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseAuthException catch (_) { if (mounted) message(context, '로그인하지 못했어요. 이메일·비밀번호와 네트워크를 확인해 주세요.'); }
    catch (_) { if (mounted) message(context, '잠시 후 다시 시도해 주세요.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Frame(title: widget.signup ? '반가워요!\n어떻게 불러드릴까요?' : '다시 만나서\n반가워요!', subtitle: widget.signup ? '1 / 2 · 계정에 필요한 정보만 입력해요.\n활동 질문은 소모임 참가 시 응답해요.' : '이메일로 활동을 이어가세요.', children: [Form(key: form, child: Column(children: [
    if (widget.signup) ...[TextFormField(controller: name, decoration: const InputDecoration(labelText: '닉네임'), maxLength: 20, validator: (v) => (v ?? '').trim().isEmpty ? '닉네임을 입력해 주세요.' : null), const SizedBox(height: 16)],
    TextFormField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: '이메일'), validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((v ?? '').trim()) ? null : '이메일을 확인해 주세요.'),
    const SizedBox(height: 16), TextFormField(controller: password, obscureText: hidden, decoration: InputDecoration(labelText: '비밀번호', suffixIcon: IconButton(tooltip: hidden ? '비밀번호 표시' : '비밀번호 숨김', onPressed: () => setState(() => hidden = !hidden), icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined))), validator: (v) => (v ?? '').length < 6 ? '6자 이상 입력해 주세요.' : null),
    if (widget.signup) ...[const SizedBox(height: 16), TextFormField(controller: repeat, obscureText: true, decoration: const InputDecoration(labelText: '비밀번호 확인'), validator: (v) => v != password.text ? '비밀번호가 일치하지 않아요.' : null)],
    const SizedBox(height: 28), FilledButton(onPressed: busy ? null : submit, child: Text(busy ? '로그인 중…' : widget.signup ? '다음' : '로그인')),
    if (!widget.signup) TextButton(onPressed: () async { final address = email.text.trim(); if (!address.contains('@')) { message(context, '이메일을 먼저 입력해 주세요.'); return; } try { await FirebaseAuth.instance.sendPasswordResetEmail(email: address); if (mounted) message(this.context, '해당 계정이 있다면 재설정 메일이 발송됩니다.'); } catch (_) { if (mounted) message(this.context, '요청을 처리하지 못했어요. 이메일과 네트워크를 확인해 주세요.'); } }, child: const Text('비밀번호 재설정')),
  ]))]);
}

class TermsScreen extends StatefulWidget {
  final String email, password, nickname;
  const TermsScreen({super.key, required this.email, required this.password, required this.nickname});
  @override
  State<TermsScreen> createState() => _TermsScreenState();
}
class _TermsScreenState extends State<TermsScreen> {
  bool terms = false, privacy = false, busy = false;
  Future<void> signup() async {
    setState(() => busy = true);
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: widget.email, password: widget.password);
      try { await credential.user?.updateDisplayName(widget.nickname); } catch (_) { /* Account is created; nickname can be updated later. */ }
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseAuthException catch (e) { if (mounted) message(context, e.code == 'email-already-in-use' ? '이미 가입된 이메일이에요. 로그인해 주세요.' : '가입하지 못했어요. 입력 정보와 인증 설정을 확인해 주세요.'); }
    catch (_) { if (mounted) message(context, '가입 요청을 처리하지 못했어요.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  void detail(String title) => showDialog<void>(context: context, builder: (c) => AlertDialog(title: Text(title), content: const Text('개발용 임시 안내입니다. 실제 약관·개인정보 처리 내용 및 동의 이력 저장은 아직 연결되지 않았습니다. 실제 사용자 모집 전 반드시 교체해야 합니다.'), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('닫기'))]));
  @override
  Widget build(BuildContext context) => Frame(title: '시작하기 전,\n확인해 주세요.', subtitle: '2 / 2 · 개발용 가입 화면입니다. 실제 개인정보를 입력하지 마세요.', children: [
    Panel(color: butter, child: Column(children: [CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('필수 항목 모두 동의'), value: terms && privacy, onChanged: busy ? null : (v) => setState(() { terms = v ?? false; privacy = v ?? false; })), const Divider(), Row(children: [Expanded(child: CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('[필수] 이용약관'), value: terms, onChanged: busy ? null : (v) => setState(() => terms = v ?? false))), IconButton(onPressed: () => detail('이용약관 · 임시'), icon: const Icon(Icons.chevron_right))]), Row(children: [Expanded(child: CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('[필수] 개인정보 수집·이용'), value: privacy, onChanged: busy ? null : (v) => setState(() => privacy = v ?? false))), IconButton(onPressed: () => detail('개인정보 안내 · 임시'), icon: const Icon(Icons.chevron_right))])])),
    FilledButton(onPressed: terms && privacy && !busy ? signup : null, child: Text(busy ? '가입 중…' : '동의하고 가입하기')),
  ]);
}

class InvitationScreen extends StatefulWidget {
  const InvitationScreen({super.key});
  @override
  State<InvitationScreen> createState() => _InvitationScreenState();
}
class _InvitationScreenState extends State<InvitationScreen> {
  final code = TextEditingController();
  @override
  void dispose() { code.dispose(); super.dispose(); }
  void check() {
    if (code.text.trim().toUpperCase() != 'TEAM24') { message(context, '시연 코드는 TEAM24예요. 실제 코드 조회는 아직 연결되지 않았어요.'); return; }
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (c) => SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('경희 메이커스', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)), const SizedBox(height: 12), const Text('캠퍼스의 작은 불편을 함께 해결해요.\n시연용 모임 · 실제 가입은 처리되지 않습니다.'), const SizedBox(height: 24), FilledButton(onPressed: () { Navigator.pop(c); open(context, const ReadyScreen(name: '경희 메이커스', owner: false)); }, child: const Text('이 모임으로 진행 · 시연'))]))));
  }
  @override
  Widget build(BuildContext context) => Frame(title: '우리 모임에\n연결해보세요.', subtitle: '전달받은 초대 코드로 우리 모임에 들어가요.\n현재는 모임 연결 UI 시연 단계입니다.', children: [
    Panel(color: mint, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.confirmation_number_outlined, size: 42), const SizedBox(height: 20), const Text('초대받으셨나요?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), const SizedBox(height: 16), TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: '초대 코드', hintText: '시연 코드 TEAM24'), onSubmitted: (_) => check()), const SizedBox(height: 16), FilledButton(onPressed: check, child: const Text('모임 확인하기'))])),
    Panel(color: lilac, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('모임 대표자이신가요?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), const SizedBox(height: 8), const Text('우리 동아리만의 공간을 만들어보세요.'), const SizedBox(height: 16), OutlinedButton(onPressed: () => open(context, const CreateScreen()), child: const Text('새 모임 만들기'))])),
    const Text('초대 링크 자동 연결과 기존 소속 모임 조회는 후속 구현 예정입니다.', style: TextStyle(color: Colors.black54, fontSize: 13)),
  ]);
}

class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});
  @override
  State<CreateScreen> createState() => _CreateScreenState();
}
class _CreateScreenState extends State<CreateScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(), intro = TextEditingController(), other = TextEditingController();
  final selected = <String>{};
  bool approval = false; int iconIndex = 0;
  final icons = const [Icons.diversity_2_rounded, Icons.auto_awesome_rounded, Icons.local_florist_rounded];
  @override
  void dispose() { name.dispose(); intro.dispose(); other.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Frame(title: '함께할 사람들을\n모아보세요.', subtitle: '팀 편성은 소모임을 만든 뒤 진행해요.', children: [Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Center(child: Column(children: [IconButton.filledTonal(iconSize: 48, tooltip: '기본 모임 심볼 변경', onPressed: () => setState(() => iconIndex = (iconIndex + 1) % icons.length), icon: Icon(icons[iconIndex])), const Text('눌러서 기본 심볼 선택'), const Text('사진 업로드는 추후 지원', style: TextStyle(color: Colors.black54, fontSize: 12))])),
    const SizedBox(height: 24), TextFormField(controller: name, maxLength: 30, decoration: const InputDecoration(labelText: '모임 이름 *', hintText: '예: 경희 메이커스'), validator: (v) => (v ?? '').trim().isEmpty ? '모임 이름을 입력해 주세요.' : null),
    const SizedBox(height: 16), TextFormField(controller: intro, maxLength: 80, decoration: const InputDecoration(labelText: '한 줄 소개 *', hintText: '어떤 모임인지 소개해 주세요'), validator: (v) => (v ?? '').trim().isEmpty ? '소개를 입력해 주세요.' : null),
    const SizedBox(height: 20), const Text('관심 카테고리 · 선택', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), const Text('최대 2개까지 선택할 수 있어요.'), const SizedBox(height: 8),
    Wrap(spacing: 8, children: ['친목', '스터디', '프로젝트', '취미', '운동', '기타'].map((s) => FilterChip(label: Text(s), selected: selected.contains(s), selectedColor: mint, onSelected: (value) { if (value && selected.length >= 2) { message(context, '최대 2개까지 선택해 주세요.'); return; } setState(() { if (value) { selected.add(s); } else { selected.remove(s); } }); })).toList()),
    if (selected.contains('기타')) TextFormField(controller: other, maxLength: 20, decoration: const InputDecoration(labelText: '카테고리 직접 입력'), validator: (v) => selected.contains('기타') && (v ?? '').trim().isEmpty ? '카테고리를 입력해 주세요.' : null),
    const SizedBox(height: 24), const Text('가입 방식', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), const SizedBox(height: 12),
    SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('바로 가입')), ButtonSegment(value: true, label: Text('승인 후 가입'))], selected: {approval}, onSelectionChanged: (s) => setState(() => approval = s.first)),
    const SizedBox(height: 24), const Panel(color: butter, child: Text('모임을 만든 사람은 대표자로 설정되며 모든 운영 권한을 가집니다. 비공개 배치 선호 열람 권한은 포함하지 않습니다.')),
    const Text('개발용 화면: 입력 내용은 Firestore에 저장되지 않으며 실제 모임은 생성되지 않습니다.', style: TextStyle(fontSize: 13, color: Colors.black54)), const SizedBox(height: 16),
    FilledButton(onPressed: () { if (form.currentState!.validate()) open(context, ReadyScreen(name: name.text.trim(), owner: true)); }, child: const Text('모임 만들기 · 시연')),
  ]))]);
}

class ReadyScreen extends StatelessWidget {
  final String name; final bool owner;
  const ReadyScreen({super.key, required this.name, required this.owner});
  @override
  Widget build(BuildContext context) => Frame(title: owner ? '우리 모임의\n시작을 준비했어요!' : '우리 모임을\n확인했어요!', subtitle: '홈 진입 직전 화면 · UI 시연 완료', children: [Panel(color: mint, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.check_circle_outline, size: 56), const SizedBox(height: 20), Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)), const SizedBox(height: 12), Text(owner ? '대표자 화면으로 이어질 예정입니다.' : '부원 화면으로 이어질 예정입니다.'), const SizedBox(height: 12), const Text('실제 생성·가입·권한 부여·초대 공유는 아직 처리되지 않았습니다. 모임 홈은 다음 개발 범위입니다.') ])), FilledButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('초대·생성 화면으로 돌아가기'))]);
}
