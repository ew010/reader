import 'dart:io';

import 'package:flutter/material.dart';

import '../models/mind_map_node.dart';

class MindMapDialog extends StatefulWidget {
  const MindMapDialog({
    super.key,
    required this.nodes,
    required this.onNodeMoved,
    required this.onNodeRenamed,
    required this.onNodeDeleted,
    required this.onNodeReparented,
  });

  final Map<String, MindMapNode> nodes;
  final void Function(String nodeId, Offset newOffset) onNodeMoved;
  final void Function(String nodeId, String newTitle) onNodeRenamed;
  final void Function(String nodeId) onNodeDeleted;
  final void Function(String nodeId, String? newParentId) onNodeReparented;

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

  Future<void> _renameNode(String nodeId) async {
    final node = _localNodes[nodeId];
    if (node == null) return;
    final controller = TextEditingController(text: node.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名节点'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '输入节点名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty) return;
    setState(() {
      _localNodes[nodeId] = node.copyWith(title: newTitle);
    });
    widget.onNodeRenamed(nodeId, newTitle);
  }

  bool _isDescendant({
    required String potentialDescendantId,
    required String ancestorId,
  }) {
    var currentId = _localNodes[potentialDescendantId]?.parentId;
    while (currentId != null) {
      if (currentId == ancestorId) return true;
      currentId = _localNodes[currentId]?.parentId;
    }
    return false;
  }

  Future<void> _deleteNode(String nodeId) async {
    final node = _localNodes[nodeId];
    if (node == null || node.parentId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除节点'),
        content: Text('确认删除“${node.title}”？其子节点将挂到根节点。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      final children = _localNodes.values.where((n) => n.parentId == nodeId).toList();
      for (final child in children) {
        _localNodes[child.id] = child.copyWith(parentId: 'root');
      }
      _localNodes.remove(nodeId);
    });
    widget.onNodeDeleted(nodeId);
  }

  void _reparentByDrop(String nodeId) {
    final node = _localNodes[nodeId];
    if (node == null || node.parentId == null) return;

    final nodeCenter = _nodeRect(node).center;
    String? targetParentId;
    for (final candidate in _localNodes.values) {
      if (candidate.id == nodeId) continue;
      if (_isDescendant(potentialDescendantId: candidate.id, ancestorId: nodeId)) continue;
      if (_nodeRect(candidate).inflate(20).contains(nodeCenter)) {
        targetParentId = candidate.id;
        break;
      }
    }

    targetParentId ??= 'root';
    if (targetParentId == node.parentId) return;

    setState(() {
      _localNodes[nodeId] = node.copyWith(parentId: targetParentId);
    });
    widget.onNodeReparented(nodeId, targetParentId);
  }

  Rect _nodeRect(MindMapNode node) {
    final width = node.parentId == null ? 220.0 : 180.0;
    final height = node.imagePath == null ? 92.0 : 170.0;
    return Rect.fromLTWH(node.offset.dx, node.offset.dy, width, height);
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
                            onMoveEnd: () => _reparentByDrop(node.id),
                            onRename: () => _renameNode(node.id),
                            onDelete: () => _deleteNode(node.id),
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
    required this.onMoveEnd,
    required this.onRename,
    required this.onDelete,
  });

  final MindMapNode node;
  final ValueChanged<Offset> onMoved;
  final VoidCallback onMoveEnd;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isRoot = node.parentId == null;
    return GestureDetector(
      onPanUpdate: (details) => onMoved(details.delta),
      onPanEnd: (_) => onMoveEnd(),
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
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_horiz, size: 16),
                  onSelected: (value) {
                    if (value == 'rename') onRename();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) {
                    final items = <PopupMenuEntry<String>>[
                      const PopupMenuItem(value: 'rename', child: Text('重命名')),
                    ];
                    if (!isRoot) {
                      items.add(const PopupMenuItem(value: 'delete', child: Text('删除')));
                    }
                    return items;
                  },
                ),
              ],
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
