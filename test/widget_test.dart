import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/app/app.dart';

void main() {
  testWidgets('shows the notebook library shell', (WidgetTester tester) async {
    await tester.pumpWidget(const InkNestApp());

    expect(find.text('InkNest Notes'), findsOneWidget);
    expect(find.text('No notebooks yet'), findsOneWidget);
    expect(find.text('New notebook'), findsWidgets);
  });
}
