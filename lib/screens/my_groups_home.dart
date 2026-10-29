import 'package:flutter/material.dart';
import 'group_home.dart';

const _ink = Color(0xFF20283F);
class MyGroupsHome extends StatefulWidget {
  const MyGroupsHome({super.key, this.initiallyEmpty = false});
  final bool initiallyEmpty;
  @override
  State<MyGroupsHome> createState() => _MyGroupsHomeState();
}
class _MyGroupsHomeState extends State<MyGroupsHome> {
  late bool _empty;
  @override
  void initState() { super.initState(); _empty = widget.initiallyEmpty; }
  void _notice(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  void _add() => showModalBottomSheet<void>(context: context, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(27))), builder: (sheet) => SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('새로운 모임과 함께해요', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
    ListTile(leading: const Icon(Icons.add), title: const Text('모임 만들기'), subtitle: const Text('우리 동아리의 새로운 공간을 만들어요.'), onTap: () { Navigator.pop(sheet); _notice('모임 만들기는 아직 연결되지 않은 시연 화면이에요.'); }),
    ListTile(leading: const Icon(Icons.login_outlined), title: const Text('모임 참가하기'), subtitle: const Text('초대 코드로 참여를 요청해요.'), onTap: () { Navigator.pop(sheet); _notice('초대 코드 참여는 아직 연결되지 않은 시연 화면이에요.'); }),
  ]))));
  void _account() => showModalBottomSheet<void>(context: context, backgroundColor: Colors.white, builder: (sheet) => SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('계정 정보', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
    const SizedBox(height: 12), const Text('디자인 시연 모드 · 실제 계정에 연결되지 않았어요.', style: TextStyle(color: Colors.grey)),
    ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.swap_horiz), title: Text(_empty ? '예시 모임 3개 보기' : '빈 화면 보기'), onTap: () { Navigator.pop(sheet); setState(() => _empty = !_empty); }),
  ]))));
  Widget _circle(IconData icon, String label, Color bg, Color fg, VoidCallback tap) => SizedBox.square(dimension: 36, child: Material(color: bg, shape: const CircleBorder(), child: InkWell(customBorder: const CircleBorder(), onTap: tap, child: Tooltip(message: label, child: Icon(icon, size: 23, color: fg)))));
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
    Row(children: [const Text.rich(TextSpan(children: [TextSpan(text: 'teamix', style: TextStyle(color: _ink)), TextSpan(text: '.', style: TextStyle(color: Color(0xFFFF5949)))]), style: TextStyle(fontFamily: 'Pretendard', fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -1)), const Spacer(),
      _circle(Icons.add, '모임 추가', const Color(0xFFFFF0ED), const Color(0xFFEC7569), _add), const SizedBox(width: 12), _circle(Icons.person_outline, '계정 정보', const Color(0xFFEAF4ED), const Color(0xFF739680), _account)]),
    const SizedBox(height: 12), const Text('내 모임', style: TextStyle(fontSize: 27, height: 1.23, fontWeight: FontWeight.w800, letterSpacing: -1, color: _ink)), const SizedBox(height: 12),
    if (_empty) const _EmptyGroups() else ...[
      _GroupCard(name: '경희 메이커스', color: const Color(0xFFEFF7F1), accent: const Color(0xFF739680), activities: const ['작은 아이디어, 함께 만들기', '메이커스 미니 프로젝트'], onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GroupHome()))),
      const SizedBox(height: 8),
      _GroupCard(name: '주말 산책 모임', color: const Color(0xFFFFF4E8), accent: const Color(0xFFAD886A), activities: const ['느긋하게 걷는 주말', '노을 따라 저녁 산책'], onTap: () => _notice('모임 상세는 아직 연결되지 않은 시연 화면이에요.')),
      const SizedBox(height: 8),
      const _GroupCard(name: '참여 요청한 모임', color: Color(0xFFF4F1FA), accent: Color(0xFF897B9A), activities: ['함께 시작하는 첫 프로젝트', '아이디어 나누는 저녁'], pending: true),
    ],
  ])))));
}
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.name, required this.color, required this.accent, required this.activities, this.pending = false, this.onTap});
  final String name;
  final Color color, accent;
  final List<String> activities;
  final bool pending;
  final VoidCallback? onTap;
  Widget _badge(String text) => Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: Colors.white.withAlpha(200), borderRadius: BorderRadius.circular(12)), child: Text(text, style: TextStyle(fontSize: 10, color: accent)));
  @override
  Widget build(BuildContext context) => Material(color: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Color(0xFFEFF0F3))), clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.fromLTRB(17, 11, 17, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Container(width: 31, height: 31, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: Icon(pending ? Icons.schedule : Icons.filter_vintage_outlined, color: accent, size: 21)), const SizedBox(width: 12), Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink))), const SizedBox(width: 7), _badge(pending ? '승인 대기' : '부원')]),
    const SizedBox(height: 8),
    Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: Colors.white.withAlpha(170), borderRadius: BorderRadius.circular(13)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(pending ? '승인 기다리는 소모임' : '진행 중인 소모임', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accent)), const SizedBox(height: 3),
      for (final activity in activities.take(2)) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Expanded(child: Text(activity, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _ink))), const SizedBox(width: 8), _badge(pending ? '승인 대기' : '참가 모집 중')])),
    ])),
    const SizedBox(height: 7), Align(alignment: Alignment.centerRight, child: Text(pending ? '승인을 기다리는 중' : '모임 들어가기 ↗', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accent))),
  ]))));
}
class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();
  @override
  Widget build(BuildContext context) => Container(width: double.infinity, margin: const EdgeInsets.only(top: 18), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28), decoration: BoxDecoration(color: const Color(0xFFF4F8F4), border: Border.all(color: const Color(0xFFDFE6E0)), borderRadius: BorderRadius.circular(24)), child: Column(children: [
    Container(width: 60, height: 60, decoration: BoxDecoration(color: const Color(0xFFE6F0E7), borderRadius: BorderRadius.circular(21)), child: const Icon(Icons.filter_vintage_outlined, color: Color(0xFF87A28B), size: 32)), const SizedBox(height: 16),
    const Text('아직 함께하는 모임이 없어요', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF414B44))), const SizedBox(height: 10),
    const Text('오른쪽 위 ＋를 눌러\n모임을 만들거나 초대 코드로 참여해보세요.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.9, color: Color(0xFF87918A))),
  ]));
}
