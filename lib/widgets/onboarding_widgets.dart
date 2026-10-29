import 'package:flutter/material.dart';

import '../theme.dart';

class OnboardingWidgets {
  const OnboardingWidgets({required this.busy});

  final bool busy;

  Widget button(String label, VoidCallback action) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: FilledButton(onPressed: busy ? null : action, child: Text(label)),
  );

  Widget title(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: ink,
      ),
    ),
  );

  Widget panel(Color color, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    ),
  );

  Widget field(
    String label,
    TextEditingController controller, {
    bool secret = false,
    TextInputType keyboardType = TextInputType.text,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controller,
      obscureText: secret,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
    ),
  );
}
