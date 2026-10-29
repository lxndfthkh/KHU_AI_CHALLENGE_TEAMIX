import 'package:flutter/material.dart';

import '../theme.dart';
import 'matching_settings_screen.dart';

/// UI preview only: operator access here is not an authorization decision.
class GroupHome extends StatelessWidget {
  const GroupHome({super.key});

  void _preview(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature 기능은 아직 연결되지 않은 시연 화면이에요.')),
    );
  }

  void _more(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: teamixBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.rate_review_outlined),
              title: const Text('소모임 평가하기'),
              onTap: () {
                Navigator.pop(sheet);
                _preview(context, '소모임 선택 및 평가');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('모임 나가기'),
              onTap: () {
                Navigator.pop(sheet);
                _preview(context, '모임 나가기');
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: teamixBackground,
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: '내 모임으로 돌아가기',
                    icon: const Icon(
                      Icons.chevron_left,
                      size: 28,
                      color: ink,
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'teamix',
                              style: TextStyle(color: ink),
                            ),
                            TextSpan(
                              text: '.',
                              style: TextStyle(color: teamixLogoAccent),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ),
                  SizedBox.square(
                    dimension: 36,
                    child: Material(
                      color: teamixAccountBackground,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _more(context),
                        child: const Tooltip(
                          message: '모임 메뉴',
                          child: Icon(
                            Icons.more_horiz,
                            color: teamixPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 21),
              Row(
                children: [
                  Container(
                    width: 49,
                    height: 49,
                    decoration: BoxDecoration(
                      color: mint,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.filter_vintage_outlined,
                      size: 29,
                      color: teamixPrimary,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '경희 메이커스',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: mint,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            '운영진',
                            style: TextStyle(
                              fontSize: 10,
                              color: teamixPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 19),
              Row(
                children: [
                  Expanded(
                    child: _Action(
                      icon: Icons.north_east,
                      text: '초대 공유',
                      onTap: () => _preview(context, '초대 공유'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Action(
                      icon: Icons.list,
                      text: '부원 관리',
                      onTap: () => _preview(context, '부원 관리'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Action(
                      icon: Icons.add,
                      text: '소모임 창설',
                      onTap: () => _preview(context, '소모임 창설'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const MatchingSettingsScreen(),
                  ),
                ),
                icon: const Icon(Icons.groups_outlined),
                label: const Text('팀 편성'),
              ),
              const SizedBox(height: 16),
              Material(
                color: lilac,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _preview(context, '가입 요청 관리'),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Text(
                          '가입 요청 관리',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: teamixRequestForeground,
                          ),
                        ),
                        Spacer(),
                        Text(
                          '확인하기 ›',
                          style: TextStyle(
                            fontSize: 10,
                            color: teamixRequestForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '진행 중인 소모임',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _preview(context, '소모임 전체 목록'),
                    child: const Text(
                      '전체 보기 ›',
                      style: TextStyle(fontSize: 10, color: teamixMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _Activity(
                title: '작은 아이디어, 함께 만들기',
                questions: '희망 역할 · 가능 시간 · 경험 수준',
                color: mint,
                accent: teamixPrimary,
                onDetail: () => _preview(context, '소모임 상세보기'),
                onEdit: () => _preview(context, '소모임 내용·상태 수정'),
              ),
              const SizedBox(height: 10),
              _Activity(
                title: '메이커스 미니 프로젝트',
                questions: '희망 역할 · 관심 분야',
                color: butter,
                accent: teamixPeachAccent,
                onDetail: () => _preview(context, '소모임 상세보기'),
                onEdit: () => _preview(context, '소모임 내용·상태 수정'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: teamixActionBackground,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: teamixActionForeground),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 11,
                  color: teamixActionForeground,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Activity extends StatelessWidget {
  const _Activity({
    required this.title,
    required this.questions,
    required this.color,
    required this.accent,
    required this.onDetail,
    required this.onEdit,
  });

  final String title, questions;
  final Color color, accent;
  final VoidCallback onDetail, onEdit;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(21),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '프로젝트',
              style: TextStyle(fontSize: 10, color: accent),
            ),
            const Spacer(),
            Container(
              height: 22,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: teamixBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '참가 모집 중',
                style: TextStyle(fontSize: 9, color: accent),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox.square(
              dimension: 22,
              child: Material(
                color: teamixBackground.withAlpha(180),
                shape: CircleBorder(
                  side: BorderSide(color: accent.withAlpha(45)),
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onEdit,
                  child: Tooltip(
                    message: '소모임 관리 및 수정',
                    child: Icon(
                      Icons.settings_outlined,
                      size: 13,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -.5,
            color: ink,
          ),
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: Text(
                questions,
                style: TextStyle(fontSize: 10, color: accent),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: onDetail,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(
                  '소모임 상세보기 ↗',
                  style: TextStyle(fontSize: 9, color: accent),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
