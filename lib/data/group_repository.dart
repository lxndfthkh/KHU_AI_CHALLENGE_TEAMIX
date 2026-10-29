abstract class GroupRepository {
  String get invitationCode;

  String get invitedGroupName;

  Map<String, String> get memberships;

  bool isValidInvite(String code);

  String? membershipStatus(String group);

  bool containsGroup(String group);

  void requestMembership(String group);

  void createGroup(String group);

  void clearMemberships();
}
