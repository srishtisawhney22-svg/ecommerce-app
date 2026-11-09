import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/main.dart';

void main() {
  testWidgets('shopping app opens', (WidgetTester tester) async {
    await tester.pumpWidget(const ShopApp());

    expect(find.text('Everyday Shop'), findsOneWidget);
  });
}