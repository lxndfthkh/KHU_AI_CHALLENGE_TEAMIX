import 'package:flutter/material.dart';
import '../models/matching.dart';
import '../services/team_matching_service.dart';
import '../theme.dart';
import 'matching_result_screen.dart';

class MatchingRunningScreen extends StatefulWidget {
  const MatchingRunningScreen({super.key, required this.input, required this.service});
  final MatchingInput input;
  final TeamMatchingService service;
  @override
  State<MatchingRunningScreen> createState() => _MatchingRunningScreenState();
}

class _MatchingRunningScreenState extends State<MatchingRunningScreen> {
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _run(widget.service);
  }

  Future<void> _run(TeamMatchingService service) async {
    setState(() { _busy = true; _error = null; });
    try {
      final result = await service.match(widget.input);
      if (!mounted) return;
      if (!['OPTIMAL', 'FEASIBLE'].contains(result.status) || result.teams.isEmpty) {
        setState(() {
          _busy = false;
          _error = result.messages.isEmpty
            ? '편성 결과를 만들지 못했어요. 설정을 확인하거나 시연 결과를 확인해 주세요.'
            : result.messages.map(matchingDisplayMessage).join('\n');
        });
        return;
      }
      Navigator.of(context).pushReplacement<void, void>(MaterialPageRoute<void>(
        builder: (_) => MatchingResultScreen(
          result: result, demo: service is DemoTeamMatchingService,
        ),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '편성 요청에 실패했어요. 서버 연결 또는 응답을 확인해 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: teamixBackground,
    appBar: AppBar(title: const Text('팀 편성')),
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(21)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_busy) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              const Text('추천 편성안을 만들고 있어요',
                style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const Text('약 10~20초 소요'),
            ] else ...[
              const Icon(Icons.error_outline, color: teamixPrimary, size: 40),
              const SizedBox(height: 16),
              Text(_error ?? '편성을 완료하지 못했어요.', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(onPressed: () => _run(DemoTeamMatchingService()),
                child: const Text('시연 결과로 보기')),
              TextButton(onPressed: () => Navigator.of(context).pop(),
                child: const Text('설정으로 돌아가기')),
            ],
          ]),
        ),
      ),
    )),
  );
}
