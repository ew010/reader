import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import '../models/annotation.dart';

class AnnotatablePageWidget extends StatefulWidget {
  const AnnotatablePageWidget({
    super.key,
    required this.page,
    required this.imageBytes,
    required this.imageSize,
    required this.tool,
    required this.color,
    required this.penWidth,
    required this.fontSize,
    required this.annotations,
    required this.onChanged,
    required this.onSelectionCaptured,
  });

  final int page;
  final Uint8List imageBytes;
  final Size imageSize;
  final ToolType tool;
  final Color color;
  final double penWidth;
  final double fontSize;
  final List<AnnotationItem> annotations;
  final ValueChanged<List<AnnotationItem>> onChanged;
  final Future<void> Function({required int page, required Rect rect, required Uint8List pngBytes}) onSelectionCaptured;

  @override
  State<AnnotatablePageWidget> createState() => _AnnotatablePageWidgetState();
}

class _AnnotatablePageWidgetState extends State<AnnotatablePageWidget> {
  final GlobalKey _boundaryKey = GlobalKey();

  Rect? _draftRect;
  List<Offset> _draftPath = [];
  Offset? _start;

  Future<void> _handlePanStart(DragStartDetails details) async {
    final p = details.localPosition;

    if (widget.tool == ToolType.text) {
      final text = await _askText(context, title: '添加文字');
      if (text == null || text.trim().isEmpty) return;
      final list = [...widget.annotations];
      list.add(AnnotationItem.text(
        color: widget.color,
        position: _toNormalized(p),
        text: text,
        fontSize: widget.fontSize,
      ));
      widget.onChanged(list);
      return;
    }

    if (widget.tool == ToolType.eraser) {
      final list = [...widget.annotations];
      final idx = list.lastIndexWhere((e) => _containsPoint(e, p));
      if (idx >= 0) {
        list.removeAt(idx);
        widget.onChanged(list);
      }
      return;
    }

    setState(() {
      _start = p;
      if (widget.tool == ToolType.draw) {
        _draftPath = [p];
      } else if (widget.tool == ToolType.select || widget.tool == ToolType.highlight) {
        _draftRect = Rect.fromPoints(p, p);
      }
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final p = details.localPosition;
    if (_start == null) return;

    setState(() {
      if (widget.tool == ToolType.draw) {
        _draftPath.add(p);
      } else if (widget.tool == ToolType.select || widget.tool == ToolType.highlight) {
        _draftRect = Rect.fromPoints(_start!, p);
      }
    });
  }

  Future<void> _handlePanEnd(DragEndDetails details) async {
    if (_start == null) return;

    final list = [...widget.annotations];
    if (widget.tool == ToolType.draw && _draftPath.length > 1) {
      list.add(AnnotationItem.draw(
        color: widget.color,
        width: widget.penWidth,
        points: _draftPath.map(_toNormalized).toList(),
      ));
      widget.onChanged(list);
    }

    if ((widget.tool == ToolType.select || widget.tool == ToolType.highlight) && _draftRect != null) {
      final rect = _normalizedRect(_draftRect!);
      if (rect.width > 10 && rect.height > 10) {
        final normalized = _toNormalizedRect(rect);
        if (widget.tool == ToolType.select) {
          list.add(AnnotationItem.rect(color: widget.color, rect: normalized));
        } else {
          list.add(AnnotationItem.highlight(color: widget.color, rect: normalized));
        }
        widget.onChanged(list);
        final png = await _captureSelection(rect);
        if (png != null) {
          await widget.onSelectionCaptured(page: widget.page, rect: normalized, pngBytes: png);
        }
      }
    }

    setState(() {
      _start = null;
      _draftRect = null;
      _draftPath = [];
    });
  }

  Future<Uint8List?> _captureSelection(Rect rect) async {
    final context = _boundaryKey.currentContext;
    if (context == null) return null;

    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final ratio = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final image = await boundary.toImage(pixelRatio: ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;

    final decoded = img.decodePng(bytes.buffer.asUint8List());
    if (decoded == null) return null;

    final x = (rect.left * ratio).round().clamp(0, decoded.width - 1);
    final y = (rect.top * ratio).round().clamp(0, decoded.height - 1);
    final w = (rect.width * ratio).round().clamp(1, decoded.width - x);
    final h = (rect.height * ratio).round().clamp(1, decoded.height - y);

    final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
    return Uint8List.fromList(img.encodePng(cropped));
  }

  Offset _toNormalized(Offset p) {
    final w = widget.imageSize.width;
    final h = widget.imageSize.height;
    return Offset((p.dx / w).clamp(0, 1), (p.dy / h).clamp(0, 1));
  }

  Rect _toNormalizedRect(Rect r) {
    final w = widget.imageSize.width;
    final h = widget.imageSize.height;
    return Rect.fromLTWH(
      (r.left / w).clamp(0, 1),
      (r.top / h).clamp(0, 1),
      (r.width / w).clamp(0, 1),
      (r.height / h).clamp(0, 1),
    );
  }

  Rect _normalizedRect(Rect r) {
    return Rect.fromLTRB(
      math.min(r.left, r.right),
      math.min(r.top, r.bottom),
      math.max(r.left, r.right),
      math.max(r.top, r.bottom),
    );
  }

  Offset _fromNormalized(Offset p) {
    return Offset(p.dx * widget.imageSize.width, p.dy * widget.imageSize.height);
  }

  Rect _fromNormalizedRect(Rect r) {
    return Rect.fromLTWH(
      r.left * widget.imageSize.width,
      r.top * widget.imageSize.height,
      r.width * widget.imageSize.width,
      r.height * widget.imageSize.height,
    );
  }

  bool _containsPoint(AnnotationItem ann, Offset p) {
    switch (ann.type) {
      case AnnotationType.rect:
      case AnnotationType.highlight:
        return _fromNormalizedRect(ann.rect!).inflate(8).contains(p);
      case AnnotationType.draw:
        for (final point in ann.points) {
          final d = (_fromNormalized(point) - p).distance;
          if (d <= math.max(8, ann.width * 2)) return true;
        }
        return false;
      case AnnotationType.text:
        final pos = _fromNormalized(ann.position!);
        final estimated = Rect.fromLTWH(
          pos.dx - 4,
          pos.dy - ann.fontSize,
          (ann.text?.length ?? 0) * ann.fontSize * 0.7 + 8,
          ann.fontSize + 12,
        );
        return estimated.contains(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: SizedBox(
        width: widget.imageSize.width,
        height: widget.imageSize.height,
        child: GestureDetector(
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(widget.imageBytes, fit: BoxFit.fill),
              CustomPaint(
                painter: _AnnotationPainter(
                  annotations: widget.annotations,
                  fromNormalized: _fromNormalized,
                  fromNormalizedRect: _fromNormalizedRect,
                ),
              ),
              CustomPaint(
                painter: _DraftPainter(
                  rect: _draftRect,
                  path: _draftPath,
                  tool: widget.tool,
                  color: widget.color,
                  width: widget.penWidth,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  const _AnnotationPainter({
    required this.annotations,
    required this.fromNormalized,
    required this.fromNormalizedRect,
  });

  final List<AnnotationItem> annotations;
  final Offset Function(Offset) fromNormalized;
  final Rect Function(Rect) fromNormalizedRect;

  @override
  void paint(Canvas canvas, Size size) {
    for (final ann in annotations) {
      switch (ann.type) {
        case AnnotationType.rect:
          final p = Paint()
            ..color = ann.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2;
          canvas.drawRect(fromNormalizedRect(ann.rect!), p);
          break;
        case AnnotationType.highlight:
          final p = Paint()
            ..color = ann.color.withValues(alpha: 0.35)
            ..style = PaintingStyle.fill;
          canvas.drawRect(fromNormalizedRect(ann.rect!), p);
          break;
        case AnnotationType.draw:
          final p = Paint()
            ..color = ann.color
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = ann.width;
          final pts = ann.points.map(fromNormalized).toList();
          for (var i = 0; i < pts.length - 1; i++) {
            canvas.drawLine(pts[i], pts[i + 1], p);
          }
          break;
        case AnnotationType.text:
          final pos = fromNormalized(ann.position!);
          final text = TextPainter(
            text: TextSpan(
              text: ann.text,
              style: TextStyle(color: ann.color, fontSize: ann.fontSize),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: size.width - pos.dx);
          text.paint(canvas, pos);
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) {
    return oldDelegate.annotations != annotations;
  }
}

class _DraftPainter extends CustomPainter {
  const _DraftPainter({
    required this.rect,
    required this.path,
    required this.tool,
    required this.color,
    required this.width,
  });

  final Rect? rect;
  final List<Offset> path;
  final ToolType tool;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    if ((tool == ToolType.select || tool == ToolType.highlight) && rect != null) {
      final normalized = Rect.fromLTRB(
        math.min(rect!.left, rect!.right),
        math.min(rect!.top, rect!.bottom),
        math.max(rect!.left, rect!.right),
        math.max(rect!.top, rect!.bottom),
      );
      if (tool == ToolType.highlight) {
        canvas.drawRect(
          normalized,
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..style = PaintingStyle.fill,
        );
      } else {
        canvas.drawRect(
          normalized,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    if (tool == ToolType.draw && path.length > 1) {
      final p = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width;
      for (var i = 0; i < path.length - 1; i++) {
        canvas.drawLine(path[i], path[i + 1], p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DraftPainter oldDelegate) {
    return oldDelegate.rect != rect ||
        oldDelegate.path != path ||
        oldDelegate.color != color ||
        oldDelegate.width != width;
  }
}

Future<String?> _askText(BuildContext context, {required String title}) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        minLines: 3,
        maxLines: 8,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
      ],
    ),
  );
  if (ok != true) return null;
  return controller.text;
}
