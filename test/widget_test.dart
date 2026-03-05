import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader_flutter/main.dart';

void main() {
  testWidgets('app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const PdfReaderApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
