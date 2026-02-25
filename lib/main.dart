import 'package:flutter/material.dart';

import 'pages/pdf_reader_page.dart';

void main() {
  runApp(const PdfReaderApp());
}

class PdfReaderApp extends StatelessWidget {
  const PdfReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '阅读',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const PdfReaderPage(),
    );
  }
}
