import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../models/rendered_page.dart';

class PdfService {
  final Map<String, RenderedPage> _renderCache = {};

  Future<RenderedPage> renderPage({
    required PdfDocument document,
    required int page,
    required double zoom,
  }) async {
    final key = '$page@${zoom.toStringAsFixed(2)}';
    final cached = _renderCache[key];
    if (cached != null) return cached;

    final pdfPage = await document.getPage(page);
    final w = (pdfPage.width * zoom).clamp(1, 8000).toDouble();
    final h = (pdfPage.height * zoom).clamp(1, 8000).toDouble();
    final image = await pdfPage.render(width: w, height: h, format: PdfPageImageFormat.png);
    await pdfPage.close();

    if (image == null) {
      throw StateError('Render page failed');
    }

    final rendered = RenderedPage(
      bytes: image.bytes,
      size: Size((image.width ?? 0).toDouble(), (image.height ?? 0).toDouble()),
    );
    _renderCache[key] = rendered;
    return rendered;
  }

  void clearCache() => _renderCache.clear();
}
