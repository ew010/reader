import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/screenshot_item.dart';

class ScreenshotPanel extends StatelessWidget {
  const ScreenshotPanel({
    super.key,
    required this.screenshots,
    required this.onlyCurrentPage,
    required this.onOnlyCurrentPageChanged,
    required this.onOpenMindMap,
    required this.onTap,
    required this.onEditNote,
    required this.onDelete,
  });

  final List<ScreenshotItem> screenshots;
  final bool onlyCurrentPage;
  final ValueChanged<bool> onOnlyCurrentPageChanged;
  final VoidCallback onOpenMindMap;
  final ValueChanged<ScreenshotItem> onTap;
  final ValueChanged<ScreenshotItem> onEditNote;
  final ValueChanged<ScreenshotItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                const Expanded(child: Text('截图列表')),
                OutlinedButton(
                  onPressed: onOpenMindMap,
                  child: const Text('思维导图'),
                ),
                const SizedBox(width: 8),
                const Text('仅当前页'),
                Checkbox(
                  value: onlyCurrentPage,
                  onChanged: (v) => onOnlyCurrentPageChanged(v ?? false),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: screenshots.length,
              itemBuilder: (context, index) {
                final shot = screenshots[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: InkWell(
                    onTap: () => onTap(shot),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '第 ${shot.page} 页',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'note') {
                                    onEditNote(shot);
                                  } else if (v == 'delete') {
                                    onDelete(shot);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(value: 'note', child: Text('备注')),
                                  PopupMenuItem(value: 'delete', child: Text('删除')),
                                ],
                              ),
                            ],
                          ),
                          Text(
                            shot.note.isEmpty ? p.basename(shot.path) : shot.note,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Image.file(
                              File(shot.path),
                              fit: BoxFit.none,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Text('图片加载失败'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
