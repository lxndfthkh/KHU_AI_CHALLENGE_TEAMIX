import 'package:flutter/material.dart';

import '../data/firestore_pending_join.dart';
import '../theme.dart';
import 'group_card_palette.dart';

/// What a member sees after asking to join, until an operator decides
/// (화면흐름 v8 S-06 → H-01 대기 카드). It follows the request live, so an
/// approval or rejection shows here even before going back to the home.
class PendingJoinScreen extends StatelessWidget {
  const PendingJoinScreen({super.key, required this.groupName, this.request});

  final String groupName;

  /// Null in demo mode: the screen then shows a plain pending request.
  final Stream<PendingJoin?>? request;

  static const _palette = GroupCardPalette.pending;

  static String _date(DateTime? at) =>
      at == null ? '방금' : '${at.year}년 ${at.month}월 ${at.day}일';

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: teamixBackground,
    appBar: AppBar(
      leading: IconButton(
        tooltip: '내 모임으로 돌아가기',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.chevron_left, size: 28),
      ),
      title: const Text(
        '가입 대기',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      centerTitle: true,
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: StreamBuilder<PendingJoin?>(
          stream: request ?? Stream.value(const PendingJoin(status: 'pending')),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _Message('요청 상태를 불러오지 못했어요.\n잠시 후 다시 열어 주세요.');
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final join = snapshot.data;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                _header(join),
                const SizedBox(height: 14),
                ..._body(context, join),
              ],
            );
          },
        ),
      ),
    ),
  );

  /// Which group was asked and where the request stands, at a glance.
  Widget _header(PendingJoin? join) {
    final name = join?.groupName ?? groupName;
    final description = join?.description;
    final (label, chip) = switch (join?.status) {
      'approved' => ('가입 완료', mint),
      'rejected' => ('승인되지 않음', butter),
      _ => ('승인 대기 중', teamixBackground),
    };
    return Container(
      key: const ValueKey('pending-header'),
      padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
      decoration: BoxDecoration(
        color: _palette.background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: teamixCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '참여를 요청한 모임',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _palette.accent,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: teamixBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.schedule, color: _palette.accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: _palette.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: chip,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _palette.accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_date(join?.requestedAt)} 요청',
                style: const TextStyle(
                  fontSize: 11,
                  color: teamixRequestForeground,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, PendingJoin? join) =>
      switch (join?.status) {
        'pending' => [
          _Step(
            done: true,
            title: '참여 요청 보냄',
            detail: _date(join!.requestedAt),
          ),
          const _Step(current: true, title: '임원진 확인 중'),
          const _Step(title: '가입 완료', last: true),
          const SizedBox(height: 14),
          const _Note([
            '임원진이 승인하면 이 모임이 내 모임 목록에 들어와 바로 열 수 있어요.',
            '승인 전에는 모임의 소모임과 멤버를 볼 수 없어요.',
            '확인이 늦어지면 초대해 준 임원진에게 알려 주세요.',
          ]),
        ],
        'approved' => [
          _Result(
            key: const ValueKey('pending-approved'),
            color: mint,
            title: '가입됐어요',
            body: '이제 내 모임 목록에서 ${join!.groupName ?? groupName}을(를) 열 수 있어요.',
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('내 모임으로'),
          ),
        ],
        'rejected' => [
          _Result(
            key: const ValueKey('pending-rejected'),
            color: butter,
            title: '참여가 승인되지 않았어요',
            body:
                '${_date(join!.decidedAt)}에 처리됐어요. '
                '다시 참여하려면 임원진에게 문의해 주세요.',
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
        _ => const [_Message('이 모임의 참여 요청을 찾을 수 없어요.')],
      };
}

/// One row of the request timeline; [current] marks the step in progress.
class _Step extends StatelessWidget {
  const _Step({
    required this.title,
    this.detail,
    this.done = false,
    this.current = false,
    this.last = false,
  });

  final String title;
  final String? detail;
  final bool done, current, last;

  @override
  Widget build(BuildContext context) {
    final accent = GroupCardPalette.pending.accent;
    final on = done || current;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? accent : teamixBackground,
                  border: Border.all(
                    color: on ? accent : teamixCardBorder,
                    width: 2,
                  ),
                ),
                child: done
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : current
                    ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                          ),
                        ),
                      )
                    : null,
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? accent : teamixCardBorder,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                      color: on ? ink : teamixMuted,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: teamixRequestForeground,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: teamixActionBackground,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '· $line',
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: teamixActionForeground,
              ),
            ),
          ),
      ],
    ),
  );
}

class _Result extends StatelessWidget {
  const _Result({
    super.key,
    required this.color,
    required this.title,
    required this.body,
  });

  final Color color;
  final String title, body;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          body,
          style: const TextStyle(fontSize: 12, height: 1.5, color: ink),
        ),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 60),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, color: teamixMuted),
    ),
  );
}
