import 'package:flutter/material.dart';

class ScreenshotItem {
  ScreenshotItem({
    required this.path,
    required this.page,
    required this.rect,
    this.note = '',
  });

  final String path;
  final int page;
  final Rect rect;
  String note;
}
