import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Web link that opens the app with the code pre-filled (`?invite=`).
String inviteLink(String code) => Uri.base
    .replace(path: '/', queryParameters: {'invite': code}, fragment: '')
    .toString();

/// Issues a code through [issue] and shows it with copy buttons.
Future<void> showInviteCodeDialog(
  BuildContext context,
  Future<String> Function() issue,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final String code;
  try {
    code = await issue();
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('초대 코드를 만들지 못했어요. 운영진만 발급할 수 있어요.')),
    );
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: teamixBackground,
      title: const Text('초대 코드'),
      content: InviteCodeCard(code: code),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('닫기'),
        ),
      ],
    ),
  );
}

class InviteCodeCard extends StatelessWidget {
  const InviteCodeCard({super.key, required this.code});

  final String code;

  void _copy(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label을 복사했어요.')));
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SelectableText(
        code,
        key: const ValueKey('invite-code'),
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: 4,
          color: ink,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        '7일 동안 유효해요. 참여 요청은 운영진 승인 후 가입돼요.',
        style: TextStyle(fontSize: 12, color: teamixMuted),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => _copy(context, code, '초대 코드'),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('코드 복사'),
          ),
          OutlinedButton.icon(
            onPressed: () => _copy(context, inviteLink(code), '초대 링크'),
            icon: const Icon(Icons.link, size: 16),
            label: const Text('링크 복사'),
          ),
        ],
      ),
    ],
  );
}
