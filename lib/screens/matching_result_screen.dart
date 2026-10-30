import 'package:flutter/material.dart';
import '../models/matching.dart';
import '../theme.dart';

const _demoNicknames = [
  '봄이', '하늘', '나래', '다온', '라온',
  '마루', '별하', '새봄', '아라', '여울',
  '온유', '이든', '자람', '초롱', '하람',
  '해솔', '가온', '누리', '도담', '소담',
];

String matchingNickname(String id) {
  final match = RegExp(r'^member_(\d{2})$').firstMatch(id);
  final index = match == null ? -1 : int.parse(match.group(1)!) - 1;
  return index >= 0 && index < _demoNicknames.length
    ? _demoNicknames[index] : '가상 참가원';
}

String matchingDisplayMessage(String message) => message.replaceAllMapped(
  RegExp(r'member_\d+'), (match) => matchingNickname(match.group(0)!),
);

class MatchingResultScreen extends StatelessWidget {
  const MatchingResultScreen({super.key, required this.result, this.demo = false});
  final MatchingResult result;
  final bool demo;

  Widget _distribution(String title, Map<String, int>? values) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text('$title: ${values == null || values.isEmpty ? '정보 없음' : values.entries.map((e) => '${e.key} ${e.value}명').join(' · ')}'),
  );

  Widget _team(MatchingTeamResult team, int index) => Container(
    key: ValueKey('matching-team-card-$index'),
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: index.isEven ? mint : butter,
      borderRadius: BorderRadius.circular(21),
      border: Border.all(color: teamixCardBorder),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${index + 1}팀 · ${team.size}명',
        style: const TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final id in team.participants)
          Chip(label: Text(matchingNickname(id)), backgroundColor: teamixBackground),
      ]),
      if (team.commonTimes != null) Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text('공통 시간: ${team.commonTimes!.isEmpty ? '없음' : team.commonTimes!.join(' · ')}'),
      ),
      if (team.rolePreferences != null) _distribution('희망 역할', team.rolePreferences),
      if (team.selfReportedExperience != null) Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text('경험 평균(자가 응답): ${team.selfReportedExperience!.mean?.value?.toStringAsFixed(1) ?? '정보 없음'}'),
      ),
      if (team.interests != null) _distribution('관심사', team.interests),
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: teamixBackground,
    appBar: AppBar(title: const Text('편성 결과')),
    body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(14)),
            child: const Text('추천 편성안',
              style: TextStyle(color: teamixPrimary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          const Text('아직 확정·공개되지 않은 편성안이에요. 경험 수준은 자가 응답이에요.'),
          if (demo) const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('시연 결과: 가상 참가원 20명·4팀의 고정 예시로, 변경한 설정을 계산한 결과가 아니에요.'),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < result.teams.length; i++) _team(result.teams[i], i),
        ]),
      ),
    )),
  );
}
