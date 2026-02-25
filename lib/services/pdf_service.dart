import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../models/rendered_page.dart';

class PdfService {
  static const int _maxRenderCacheEntries = 24;
  static const double _maxRenderPixels = 16 * 1000 * 1000; // 16MP

  final Map<String, RenderedPage> _renderCache = {};
  final List<String> _renderCacheOrder = [];
  final Map<int, double> _pageWidthCache = {};

  Future<RenderedPage> renderPage({
    required PdfDocument document,
    required int page,
    required double zoom,
  }) async {
    final key = '$page@${zoom.toStringAsFixed(2)}';
    final cached = _renderCache[key];
    if (cached != null) {
      _touchCacheKey(key);
      return cached;
    }

    final pdfPage = await document.getPage(page);
    final width = (pdfPage.width * zoom).clamp(1, 8000).toDouble();
    final height = (pdfPage.height * zoom).clamp(1, 8000).toDouble();
    final pixelCount = width * height;
    final scale = pixelCount > _maxRenderPixels
        ? math.sqrt(_maxRenderPixels / pixelCount)
        : 1.0;
    final w = (width * scale).clamp(1, 8000).toDouble();
    final h = (height * scale).clamp(1, 8000).toDouble();
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
    _touchCacheKey(key);
    _evictRenderCacheIfNeeded();
    return rendered;
  }

  Future<double> getPageWidth({
    required PdfDocument document,
    required int page,
  }) async {
    final cached = _pageWidthCache[page];
    if (cached != null) return cached;

    final pdfPage = await document.getPage(page);
    final width = pdfPage.width;
    await pdfPage.close();
    _pageWidthCache[page] = width;
    return width;
  }

  void _touchCacheKey(String key) {
    _renderCacheOrder.remove(key);
    _renderCacheOrder.add(key);
  }

  void _evictRenderCacheIfNeeded() {
    while (_renderCacheOrder.length > _maxRenderCacheEntries) {
      final oldestKey = _renderCacheOrder.removeAt(0);
      _renderCache.remove(oldestKey);
    }
  }

  void clearRenderCache() {
    _renderCache.clear();
    _renderCacheOrder.clear();
  }

  void clearDocumentCache() {
    _renderCache.clear();
    _renderCacheOrder.clear();
    _pageWidthCache.clear();
  }
}
