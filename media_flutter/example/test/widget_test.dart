import 'package:flutter_test/flutter_test.dart';

import 'package:media_example/main.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const MediaExampleApp());
    expect(find.text('media'), findsOneWidget);
  });
}
