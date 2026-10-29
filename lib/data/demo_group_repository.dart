import 'group_repository.dart';

class DemoGroupRepository implements GroupRepository {
  DemoGroupRepository({bool seedExamples = false}) {
    if (seedExamples) {
      _memberships.addAll(exampleMemberships);
    }
  }

  static const Map<String, String> exampleMemberships = {
    '경희 메이커스': 'owner',
    '주말 산책 모임': 'member',
    '참여 요청한 모임': 'pending',
  };

  static const Map<String, List<String>> exampleActivities = {
    '경희 메이커스': [
      '캠퍼스 불편 해결 미니 프로젝트',
      '메이커스 미니 프로젝트',
    ],
    '주말 산책 모임': [
      '느긋하게 걷는 주말',
      '노을 따라 저녁 산책',
    ],
    '참여 요청한 모임': [
      '함께 시작하는 첫 프로젝트',
      '아이디어 나누는 저녁',
    ],
  };

  // In-memory UI fixtures only; DateTime becomes Timestamp in a future adapter.
  static List<DemoSubgroup> subgroupsFor(String groupName) => [
    for (final title in exampleActivities[groupName] ?? const <String>[])
      DemoSubgroup(
        groupId: groupName,
        title: title,
        description: '캠퍼스의 작은 불편을 찾고,\n팀별로 해결 아이디어를 만드는 활동이에요.',
        goal: '캠퍼스 불편 해결',
        recruitmentCapacity: 20,
        applicationCount: 12,
        deadline: DateTime(2026, 10, 30, 15),
        status: 'recruiting',
        matchingSettings: const {
          'teamCount': 4,
          'teamCapacities': [5, 5, 5, 5],
          'method': 'balanced',
          'priority': ['role', 'time', 'experience', 'size'],
          'requireCommonTime': false,
        },
      ),
  ];
  final Map<String, String> _memberships = <String, String>{};

  @override
  String get invitationCode => 'TEAM24';

  @override
  String get invitedGroupName => '경희 메이커스';

  @override
  Map<String, String> get memberships =>
      Map<String, String>.unmodifiable(_memberships);

  @override
  bool isValidInvite(String code) => code == invitationCode;

  @override
  String? membershipStatus(String group) => _memberships[group];

  @override
  bool containsGroup(String group) => _memberships.containsKey(group);

  @override
  void requestMembership(String group) {
    _memberships[group] = 'pending';
  }

  @override
  void createGroup(String group) {
    _memberships[group] = 'owner';
  }

  @override
  void clearMemberships() {
    _memberships.clear();
  }
}


/// Display fixture, not a Firestore document or an authorization source.
class DemoSubgroup {
  const DemoSubgroup({
    required this.groupId,
    required this.title,
    required this.description,
    required this.goal,
    required this.recruitmentCapacity,
    required this.applicationCount,
    required this.deadline,
    required this.status,
    required this.matchingSettings,
  });
  final String groupId, title, description, goal, status;
  final int recruitmentCapacity, applicationCount;
  final DateTime deadline;
  final Map<String, Object> matchingSettings;
}
