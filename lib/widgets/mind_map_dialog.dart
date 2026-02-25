import 'dart:io';

import 'package:flutter/material.dart';

import '../models/mind_map_node.dart';

class MindMapDialog extends StatefulWidget {
  const MindMapDialog({
    super.key,
    required this.nodes,
    required this.onNodeMoved,
  });

  final Map<String, MindMapNode> nodes;
  final void Function(String nodeId, Offset newOffset) onNodeMoved;

  @override
  State<MindMapDialog> createState() => _MindMapDialogState();
}

class _MindMapDialogState extends State<MindMapDialog> {
  late final Map<String, MindMapNode> _localNodes = Map<String, MindMapNode>.from(widget.nodes);

  void _moveNode(String nodeId, Offset newOffset) {
    final node = _localNodes[nodeId];
    if (node == null) return;
    setState(() {
      _localNodes[nodeId] = node.copyWith(offset: newOffset);
    });
    widget.onNodeMoved(nodeId, newOffset);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 1100,
        height: 700,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  const Expanded(child: Text('思维导图', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.3,
                maxScale: 3,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: SizedBox(
                  width: 2200,
                  height: 1600,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _MindMapLinkPainter(nodes: _localNodes),
                        ),
                      ),
                      ..._localNodes.values.map(
                        (node) => Positioned(
                          left: node.offset.dx,
                          top: node.offset.dy,
                          child: _MindMapNodeCard(
                            node: node,
                            onMoved: (delta) => _moveNode(node.id, node.offset + delta),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MindMapNodeCard extends StatelessWidget {
  const _MindMapNodeCard({
    required this.node,
    required this.onMoved,
  });

  final MindMapNode node;
  final ValueChanged<Offset> onMoved;

  @override
  Widget build(BuildContext context) {
    final isRoot = node.parentId == null;
    return GestureDetector(
      onPanUpdate: (details) => onMoved(details.delta),
      child: Container(
        width: isRoot ? 220 : 180,
        constraints: const BoxConstraints(minHeight: 70),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isRoot ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isRoot ? Colors.blue : Colors.grey.shade400, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              node.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: isRoot ? 14 : 12, fontWeight: FontWeight.w600),
            ),
            if (node.imagePath != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(node.imagePath!),
                  width: double.infinity,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 72,
                    color: Colors.grey.shade100,
                    alignment: Alignment.center,
                    child: const Text('图片缺失', style: TextStyle(fontSize: 11)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MindMapLinkPainter extends CustomPainter {
  const _MindMapLinkPainter({required this.nodes});

  final Map<String, MindMapNode> nodes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueGrey.shade300
      ..strokeWidth = 1.6;

    for (final node in nodes.values) {
      final parentId = node.parentId;
      if (parentId == null) continue;
      final parent = nodes[parentId];
      if (parent == null) continue;

      final p1 = parent.offset + const Offset(90, 40);
      final p2 = node.offset + const Offset(75, 35);
      final cp1 = Offset((p1.dx + p2.dx) / 2, p1.dy);
      final cp2 = Offset((p1.dx + p2.dx) / 2, p2.dy);

      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MindMapLinkPainter oldDelegate) => oldDelegate.nodes != nodes;
}
