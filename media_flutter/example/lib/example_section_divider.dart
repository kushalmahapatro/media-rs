import 'package:flutter/material.dart';

/// Spacing + divider between major blocks in the example app tabs.
class ExampleSectionDivider extends StatelessWidget {
  const ExampleSectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Divider(height: 1, thickness: 1, color: c.outlineVariant),
        const SizedBox(height: 20),
      ],
    );
  }
}
