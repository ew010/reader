import 'package:flutter/material.dart';

enum ToolType { view, select, draw, highlight, eraser, text }
enum AnnotationType { rect, draw, highlight, text }

class AnnotationItem {
  AnnotationItem.rect({
    required this.color,
    required this.rect,
  })  : type = AnnotationType.rect,
        points = const [],
        text = null,
        position = null,
        width = 2,
        fontSize = 16;

  AnnotationItem.highlight({
    required this.color,
    required this.rect,
  })  : type = AnnotationType.highlight,
        points = const [],
        text = null,
        position = null,
        width = 2,
        fontSize = 16;

  AnnotationItem.draw({
    required this.color,
    required this.points,
    required this.width,
  })  : type = AnnotationType.draw,
        rect = null,
        text = null,
        position = null,
        fontSize = 16;

  AnnotationItem.text({
    required this.color,
    required this.position,
    required this.text,
    required this.fontSize,
  })  : type = AnnotationType.text,
        rect = null,
        points = const [],
        width = 2;

  final AnnotationType type;
  final Color color;
  final Rect? rect;
  final List<Offset> points;
  final String? text;
  final Offset? position;
  final double width;
  final double fontSize;

  Map<String, dynamic> toJson() {
    switch (type) {
      case AnnotationType.rect:
      case AnnotationType.highlight:
        final r = rect!;
        return {
          'type': type.name,
          'color': '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}',
          'rect': [r.left, r.top, r.width, r.height],
        };
      case AnnotationType.draw:
        return {
          'type': type.name,
          'color': '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}',
          'width': width,
          'points': points.map((e) => [e.dx, e.dy]).toList(),
        };
      case AnnotationType.text:
        return {
          'type': type.name,
          'color': '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}',
          'fontSize': fontSize,
          'position': [position!.dx, position!.dy],
          'text': text,
        };
    }
  }

  static AnnotationItem fromJson(Map<String, dynamic> json) {
    final colorHex = (json['color'] as String?) ?? '#ffff0000';
    final color = _parseColor(colorHex);
    final type = AnnotationType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => AnnotationType.rect,
    );

    switch (type) {
      case AnnotationType.rect:
        final r = json['rect'] as List<dynamic>;
        return AnnotationItem.rect(
          color: color,
          rect: Rect.fromLTWH(
            (r[0] as num).toDouble(),
            (r[1] as num).toDouble(),
            (r[2] as num).toDouble(),
            (r[3] as num).toDouble(),
          ),
        );
      case AnnotationType.highlight:
        final r = json['rect'] as List<dynamic>;
        return AnnotationItem.highlight(
          color: color,
          rect: Rect.fromLTWH(
            (r[0] as num).toDouble(),
            (r[1] as num).toDouble(),
            (r[2] as num).toDouble(),
            (r[3] as num).toDouble(),
          ),
        );
      case AnnotationType.draw:
        final pts = (json['points'] as List<dynamic>)
            .map((e) => Offset((e[0] as num).toDouble(), (e[1] as num).toDouble()))
            .toList();
        return AnnotationItem.draw(
          color: color,
          points: pts,
          width: (json['width'] as num?)?.toDouble() ?? 2,
        );
      case AnnotationType.text:
        final pos = json['position'] as List<dynamic>;
        return AnnotationItem.text(
          color: color,
          position: Offset((pos[0] as num).toDouble(), (pos[1] as num).toDouble()),
          text: (json['text'] as String?) ?? '',
          fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16,
        );
    }
  }

  static Color _parseColor(String hex) {
    var normalized = hex.replaceAll('#', '');
    if (normalized.length == 6) {
      normalized = 'ff$normalized';
    }
    return Color(int.tryParse(normalized, radix: 16) ?? 0xffff0000);
  }
}
