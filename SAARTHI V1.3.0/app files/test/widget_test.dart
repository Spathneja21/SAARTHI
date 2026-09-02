import 'package:flutter_test/flutter_test.dart';

import 'package:saarthi/app.dart';

void main() {
  testWidgets('Saarthi app shows splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SaarthiApp());

    expect(find.text('S.A.A.R.T.H.I'), findsOneWidget);
  });
}
