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
      '작은 아이디어, 함께 만들기',
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
