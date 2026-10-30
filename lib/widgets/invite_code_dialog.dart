import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Web link that opens the app with the code pre-filled (`?invite=`).
String inviteLink(String code) => Uri.base
    .replace(path: '/', queryParameters: {'invite': code}, fragment: '')
    .toString();

/// Issues a code through [issue] and shows it with copy buttons, plus
/// 이 코드 끄기 when [deactivate] is given.
Future<void> showInviteCodeDialog(
  BuildContext context,
  Future<String> Function() issue, {
  Future<void> Function(String code)? deactivate,
}) async {
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
        if (deactivate != null)
          TextButton(
            onPressed: () async {
              Navigator.pop(dialog);
              try {
                await deactivate(code);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('이 초대 코드를 껐어요. 더는 참여 요청에 쓸 수 없어요.'),
                  ),
                );
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('초대 코드를 끄지 못했어요.')),
                );
              }
            },
            child: const Text(
              '이 코드 끄기',
              style: TextStyle(color: teamixAddForeground),
            ),
          ),
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
