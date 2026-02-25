import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/annotation.dart';
import '../models/screenshot_item.dart';

class PdfStoragePaths {
  const PdfStoragePaths({
    required this.screenshotDir,
    required this.annotationsFile,
    required this.notesFile,
  });

  final String screenshotDir;
  final String annotationsFile;
  final String notesFile;
}

class StorageService {
  PdfStoragePaths buildPaths(String pdfPath) {
    final pdfName = p.basenameWithoutExtension(pdfPath);
    final dir = p.dirname(pdfPath);
    return PdfStoragePaths(
      screenshotDir: p.join(dir, '${pdfName}_screenshots'),
      annotationsFile: p.join(dir, '${pdfName}_annotations.json'),
      notesFile: p.join(dir, '${pdfName}_screenshot_notes.json'),
    );
  }

  Future<void> ensureScreenshotDir(String screenshotDir) async {
    await Directory(screenshotDir).create(recursive: true);
  }

  Future<void> saveAnnotations(String path, Map<int, List<AnnotationItem>> data) async {
    final out = <String, dynamic>{};
    for (final entry in data.entries) {
      out['${entry.key}'] = entry.value.map((e) => e.toJson()).toList();
    }
    await File(path).writeAsString(_prettyJson(out));
  }

  Future<Map<int, List<AnnotationItem>>> loadAnnotations(String path) async {
    final file = File(path);
    if (!await file.exists()) return {};

    final raw = await file.readAsString();
    final json = _tryParseJson(raw);
    if (json is! Map<String, dynamic>) return {};

    final out = <int, List<AnnotationItem>>{};
    json.forEach((k, v) {
      final page = int.tryParse(k);
      if (page == null || v is! List) return;
      out[page] = v.whereType<Map<String, dynamic>>().map(AnnotationItem.fromJson).toList();
    });
    return out;
  }

  Future<Map<String, String>> readScreenshotNotes(String path) async {
    final file = File(path);
    if (!await file.exists()) return {};

    final json = _tryParseJson(await file.readAsString());
    if (json is! Map<String, dynamic>) return {};
    return json.map((k, v) => MapEntry(k, v.toString()));
  }

  Future<void> saveScreenshotNotes(String path, List<ScreenshotItem> screenshots) async {
    final out = <String, String>{};
    for (final s in screenshots) {
      if (s.note.trim().isEmpty) continue;
      out[p.basename(s.path)] = s.note.trim();
    }
    await File(path).writeAsString(_prettyJson(out));
  }

  Future<List<ScreenshotItem>> loadScreenshots({
    required String screenshotDir,
    required Map<String, String> notes,
  }) async {
    final dir = Directory(screenshotDir);
    if (!await dir.exists()) return [];

    final files = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.png'))
        .cast<File>()
        .toList();

    final out = <ScreenshotItem>[];
    for (final file in files) {
      final name = p.basename(file.path);
      final m = RegExp(r'^screenshot_(\d+)_').firstMatch(name);
      if (m == null) continue;
      final page = int.tryParse(m.group(1) ?? '') ?? 1;
      out.add(
        ScreenshotItem(
          path: file.path,
          page: page,
          rect: Rect.zero,
          note: notes[name] ?? '',
        ),
      );
    }
    out.sort((a, b) => a.page.compareTo(b.page));
    return out;
  }

  dynamic _tryParseJson(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  String _prettyJson(Object data) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(data);
  }
}
