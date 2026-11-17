import 'package:flutter_test/flutter_test.dart';
import 'package:lead_app/main.dart';

void main() {
  testWidgets('TirvonaLeadApp initial smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TirvonaLeadApp());
    expect(find.byType(TirvonaLeadApp), findsOneWidget);
  });
}
