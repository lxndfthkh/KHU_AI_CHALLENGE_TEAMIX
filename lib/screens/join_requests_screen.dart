import 'package:flutter/material.dart';

import '../data/firestore_join_requests.dart';
import '../theme.dart';

/// Operator screen for pending join requests (v7: 임원진 승인).
class JoinRequestsScreen extends StatefulWidget {
  const JoinRequestsScreen({
    super.key,
    required this.groupName,
    required this.requests,
    required this.onDecide,
  });

  final String groupName;
  final Stream<List<JoinRequest>> requests;
  final Future<void> Function(JoinRequest request, bool approve) onDecide;

  @override
  State<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends State<JoinRequestsScreen> {
  final _working = <String>{};

  Future<void> _decide(JoinRequest request, bool approve) async {
    setState(() => _working.add(request.userId));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onDecide(request, approve);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${request.displayName}님의 요청을 ${approve ? '승인' : '거절'}했어요.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('처리하지 못했어요. 이미 처리된 요청일 수 있어요.')),
      );
    } finally {
      if (mounted) setState(() => _working.remove(request.userId));
    }
  }

  String _date(DateTime? at) =>
      at == null ? '방금' : '${at.month}월 ${at.day}일 요청';

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: teamixBackground,
    appBar: AppBar(
      leading: IconButton(
        tooltip: '모임 홈으로 돌아가기',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.chevron_left, size: 28),
      ),
      title: const Text(
        '가입 요청 관리',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      centerTitle: true,
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: StreamBuilder<List<JoinRequest>>(
          stream: widget.requests,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _Message('요청 목록을 불러오지 못했어요.');
            }
            final requests = snapshot.data;
            if (requests == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (requests.isEmpty) {
              return const _Message('기다리는 가입 요청이 없어요.');
            }
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: requests.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Text(
                    '${widget.groupName} · 대기 ${requests.length}명',
                    style: const TextStyle(fontSize: 12, color: teamixMuted),
                  );
                }
                final request = requests[i - 1];
                final working = _working.contains(request.userId);
                return Material(
                  color: lilac,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.displayName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _date(request.requestedAt),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: teamixRequestForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: working
                              ? null
                              : () => _decide(request, false),
                          child: const Text('거절'),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(64, 38),
                          ),
                          onPressed: working
                              ? null
                              : () => _decide(request, true),
                          child: const Text('승인'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
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
