import 'dart:async';
import 'package:flutter/material.dart';
import '../data/activity_registration.dart';
import '../data/firestore_activities_source.dart';
import 'activity_forms.dart';

/// A missing registration is an empty query, not a denied nonexistent doc read.
class RegistrationAction extends StatefulWidget {
  const RegistrationAction({super.key, required this.factory, required this.activity});
  final ActivityRegistrationApi Function() factory;
  final ActivityRecord activity;
  @override
  State<RegistrationAction> createState() => _RegistrationActionState();
}
class _RegistrationActionState extends State<RegistrationAction> {
  late ActivityRegistrationApi api;
  StreamSubscription<Map<String, dynamic>?>? subscription;
  Map<String, dynamic>? registration;
  bool loading = true, failed = false, opening = false;
  void subscribe() {
    api = widget.factory();
    subscription = api.ownRegistration(widget.activity.groupId, widget.activity.id).listen((data) {
      if (mounted) {
        setState(() { registration = data; loading = false; failed = false; });
      }
    }, onError: (Object e) {
      if (mounted) {
        setState(() { failed = true; loading = false; registration = null; });
      }
    });
  }
  @override
  void initState() { super.initState(); subscribe(); }
  @override
  void didUpdateWidget(covariant RegistrationAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity.id != widget.activity.id || oldWidget.activity.groupId != widget.activity.groupId) {
      subscription?.cancel();
      api.dispose();
      loading = true;
      failed = false;
      registration = null;
      subscribe();
    }
  }
  @override
  void dispose() { subscription?.cancel(); api.dispose(); super.dispose(); }
  Future<void> open() async {
    setState(() => opening = true);
    final a = widget.activity;
    final result = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => RegistrationScreen(api: api, activityId: a.id, registration: registration,
        canEdit: a.status == 'recruiting' && a.deadlineAt.isAfter(DateTime.now()),
        canCancel: ['recruiting', 'closed'].contains(a.status)),
    ));
    if (mounted) {
      setState(() {
        opening = false;
        if (result != null) { registration = result; }
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    final submitted = registration?['status'] == 'submitted';
    final a = widget.activity;
    final canOpen = submitted || (a.status == 'recruiting' && a.deadlineAt.isAfter(DateTime.now()));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (failed) const Text('신청 상태를 확인하지 못했어요. 화면을 다시 열어 주세요.'),
      FilledButton(onPressed: loading || failed || opening || !canOpen ? null : open,
        child: Text(loading ? '신청 상태 확인 중…' : submitted ? '응답 수정·취소' : '참가 신청하기')),
    ]);
  }
}
