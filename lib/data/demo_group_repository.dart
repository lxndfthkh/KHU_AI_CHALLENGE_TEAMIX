import 'group_repository.dart';

class DemoGroupRepository implements GroupRepository {
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
