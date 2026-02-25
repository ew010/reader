import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';

import '../models/annotation.dart';
import '../models/mind_map_node.dart';
import '../models/rendered_page.dart';
import '../models/screenshot_item.dart';
import '../services/pdf_service.dart';
import '../services/storage_service.dart';
import '../widgets/annotatable_page_widget.dart';
import '../widgets/mind_map_dialog.dart';
import '../widgets/screenshot_panel.dart';

enum ViewMode { both, pdfOnly, screenshotsOnly }

class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({super.key});

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  final PdfService _pdfService = PdfService();
  final StorageService _storageService = StorageService();

  PdfDocument? _document;
  String? _pdfPath;
  int _currentPage = 1;
  double _zoom = 2.2;
  bool _autoFitWidth = true;
  bool _continuousMode = false;
  bool _onlyCurrentPageScreenshots = false;
  ViewMode _viewMode = ViewMode.both;

  ToolType _tool = ToolType.select;
  Color _color = Colors.red;
  double _penWidth = 2;
  double _fontSize = 16;

  String? _screenshotDir;
  String? _annotationsFile;
  String? _notesFile;

  final Map<int, List<AnnotationItem>> _allAnnotations = {};
  final List<ScreenshotItem> _screenshots = [];
  final Map<String, MindMapNode> _mindMapNodes = {
    'root': const MindMapNode(
      id: 'root',
      parentId: null,
      title: '截图根节点',
      offset: Offset(960, 80),
    ),
  };

  @override
  void dispose() {
    _saveAnnotations();
    _saveScreenshotNotes();
    _document?.close();
    super.dispose();
  }

  Future<void> _openPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) {
      return;
    }

    final path = result.files.single.path!;
    final doc = await PdfDocument.openFile(path);
    final paths = _storageService.buildPaths(path);
    await _storageService.ensureScreenshotDir(paths.screenshotDir);

    _document?.close();
    _pdfService.clearDocumentCache();
    _allAnnotations.clear();
    _screenshots.clear();
    _mindMapNodes
      ..clear()
      ..addAll({
        'root': const MindMapNode(
          id: 'root',
          parentId: null,
          title: '截图根节点',
          offset: Offset(960, 80),
        ),
      });

    setState(() {
      _document = doc;
      _pdfPath = path;
      _screenshotDir = paths.screenshotDir;
      _annotationsFile = paths.annotationsFile;
      _notesFile = paths.notesFile;
      _currentPage = 1;
    });

    await _loadAnnotations();
    await _loadScreenshots();
    _syncMindMapFromScreenshots();
    if (mounted) setState(() {});
  }

  Future<RenderedPage> _renderPage(int page, {required double viewportWidth}) async {
    final doc = _document;
    if (doc == null) throw StateError('No PDF open');
    final effectiveZoom = await _resolveZoom(page: page, viewportWidth: viewportWidth);
    return _pdfService.renderPage(document: doc, page: page, zoom: effectiveZoom);
  }

  Future<double> _resolveZoom({required int page, required double viewportWidth}) async {
    if (!_autoFitWidth) return _zoom;

    final doc = _document;
    if (doc == null) return _zoom;

    final pageWidth = await _pdfService.getPageWidth(document: doc, page: page);
    final horizontalPadding = _continuousMode ? 40.0 : 24.0;
    final targetWidth = (viewportWidth - horizontalPadding).clamp(200.0, 4000.0);
    return (targetWidth / pageWidth).clamp(0.5, 5.0);
  }

  Future<void> _changeZoom(double scale) async {
    if (_document == null) return;
    setState(() {
      _autoFitWidth = false;
      _zoom = (_zoom * scale).clamp(0.5, 5.0);
      _pdfService.clearRenderCache();
    });
  }

  void _toggleAutoFitWidth() {
    setState(() {
      _autoFitWidth = !_autoFitWidth;
      _pdfService.clearRenderCache();
    });
  }

  void _setTool(ToolType tool) {
    setState(() {
      _tool = tool;
    });
  }

  List<ScreenshotItem> get _visibleScreenshots {
    if (!_onlyCurrentPageScreenshots) return _screenshots;
    return _screenshots.where((e) => e.page == _currentPage).toList();
  }

  Future<void> _onSelectionCaptured({
    required int page,
    required Rect rect,
    required Uint8List pngBytes,
  }) async {
    final dir = _screenshotDir;
    if (dir == null) return;

    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'screenshot_${page}_$ts.png';
    final filePath = p.join(dir, fileName);
    await File(filePath).writeAsBytes(pngBytes, flush: true);

    setState(() {
      _screenshots.add(ScreenshotItem(path: filePath, page: page, rect: rect));
      _screenshots.sort((a, b) => a.page.compareTo(b.page));
    });
    _syncMindMapFromScreenshots();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('截图已保存: $filePath')),
      );
    }
  }

  Future<void> _saveAnnotations() async {
    final path = _annotationsFile;
    if (path == null || _document == null) return;
    await _storageService.saveAnnotations(path, _allAnnotations);
  }

  Future<void> _loadAnnotations() async {
    final path = _annotationsFile;
    if (path == null) return;
    final loaded = await _storageService.loadAnnotations(path);
    _allAnnotations
      ..clear()
      ..addAll(loaded);
  }

  Future<void> _loadScreenshots() async {
    final dir = _screenshotDir;
    final notesPath = _notesFile;
    if (dir == null || notesPath == null) return;

    final notes = await _storageService.readScreenshotNotes(notesPath);
    final loaded = await _storageService.loadScreenshots(screenshotDir: dir, notes: notes);
    _screenshots
      ..clear()
      ..addAll(loaded);
    _syncMindMapFromScreenshots();
  }

  Future<void> _saveScreenshotNotes() async {
    final path = _notesFile;
    if (path == null) return;
    await _storageService.saveScreenshotNotes(path, _screenshots);
  }

  Future<void> _exportAnnotations() async {
    if (_document == null || _pdfPath == null) return;
    await _saveAnnotations();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('标注已导出到 $_annotationsFile')),
      );
    }
  }

  Future<void> _importAnnotations() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null || picked.files.single.path == null) return;

    final loaded = await _storageService.loadAnnotations(picked.files.single.path!);
    _allAnnotations
      ..clear()
      ..addAll(loaded);

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标注导入成功')),
      );
    }
  }

  Future<void> _editScreenshotNote(ScreenshotItem item) async {
    final controller = TextEditingController(text: item.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('备注'),
        content: TextField(controller: controller, minLines: 3, maxLines: 8),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => item.note = controller.text);
      await _saveScreenshotNotes();
    }
  }

  Future<void> _deleteScreenshot(ScreenshotItem item) async {
    final file = File(item.path);
    if (await file.exists()) {
      await file.delete();
    }
    setState(() {
      _screenshots.remove(item);
    });
    _syncMindMapFromScreenshots();
    await _saveScreenshotNotes();
  }

  String _mindMapNodeIdForShot(ScreenshotItem shot) => 'shot:${Uri.encodeComponent(shot.path)}';

  void _syncMindMapFromScreenshots() {
    final keepIds = <String>{'root'};
    var index = 0;
    for (final shot in _screenshots) {
      final id = _mindMapNodeIdForShot(shot);
      keepIds.add(id);
      final existing = _mindMapNodes[id];
      if (existing != null) {
        _mindMapNodes[id] = existing.copyWith(
          title: 'P${shot.page} - ${p.basename(shot.path)}',
          imagePath: shot.path,
          parentId: 'root',
        );
      } else {
        _mindMapNodes[id] = MindMapNode(
          id: id,
          parentId: 'root',
          title: 'P${shot.page} - ${p.basename(shot.path)}',
          imagePath: shot.path,
          offset: Offset(520 + (index % 4) * 220, 260 + (index ~/ 4) * 150),
        );
      }
      index++;
    }

    final removeIds = _mindMapNodes.keys.where((id) => !keepIds.contains(id)).toList();
    for (final id in removeIds) {
      _mindMapNodes.remove(id);
    }
  }

  void _moveMindMapNode(String nodeId, Offset newOffset) {
    final node = _mindMapNodes[nodeId];
    if (node == null) return;
    setState(() {
      _mindMapNodes[nodeId] = node.copyWith(offset: newOffset);
    });
  }

  Future<void> _openMindMapDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => MindMapDialog(
        nodes: _mindMapNodes,
        onNodeMoved: _moveMindMapNode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = _document;

    return Scaffold(
      appBar: AppBar(
        title: Text(_pdfPath == null ? 'PDF阅读器(Flutter)' : 'PDF阅读器 - ${p.basename(_pdfPath!)}'),
      ),
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: doc == null
                ? const Center(child: Text('点击“打开PDF”开始'))
                : _buildReaderContent(doc),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(onPressed: _openPdf, child: const Text('打开PDF')),
            DropdownButton<ViewMode>(
              value: _viewMode,
              items: const [
                DropdownMenuItem(value: ViewMode.both, child: Text('同时显示')),
                DropdownMenuItem(value: ViewMode.pdfOnly, child: Text('仅PDF')),
                DropdownMenuItem(value: ViewMode.screenshotsOnly, child: Text('仅截图')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _viewMode = v);
              },
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('单页')),
                ButtonSegment(value: true, label: Text('连续')),
              ],
              selected: {_continuousMode},
              onSelectionChanged: (s) => setState(() => _continuousMode = s.first),
            ),
            DropdownButton<ToolType>(
              value: _tool,
              items: ToolType.values.map((e) => DropdownMenuItem(value: e, child: Text(_toolLabel(e)))).toList(),
              onChanged: (v) => v == null ? null : _setTool(v),
            ),
            DropdownButton<Color>(
              value: _color,
              items: const [
                DropdownMenuItem(value: Colors.red, child: Text('红色')),
                DropdownMenuItem(value: Colors.orange, child: Text('橙色')),
                DropdownMenuItem(value: Colors.yellow, child: Text('黄色')),
                DropdownMenuItem(value: Colors.green, child: Text('绿色')),
                DropdownMenuItem(value: Colors.blue, child: Text('蓝色')),
                DropdownMenuItem(value: Colors.black, child: Text('黑色')),
              ],
              onChanged: (v) => v == null ? null : setState(() => _color = v),
            ),
            SizedBox(
              width: 120,
              child: Row(
                children: [
                  const Text('笔触'),
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: 20,
                      value: _penWidth,
                      onChanged: (v) => setState(() => _penWidth = v),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 120,
              child: Row(
                children: [
                  const Text('字号'),
                  Expanded(
                    child: Slider(
                      min: 8,
                      max: 48,
                      value: _fontSize,
                      onChanged: (v) => setState(() => _fontSize = v),
                    ),
                  ),
                ],
              ),
            ),
            FilterChip(
              selected: _autoFitWidth,
              label: const Text('自适应宽度'),
              onSelected: (_) => _toggleAutoFitWidth(),
            ),
            OutlinedButton(onPressed: () => _changeZoom(1.2), child: const Text('+')),
            OutlinedButton(onPressed: () => _changeZoom(1 / 1.2), child: const Text('-')),
            OutlinedButton(onPressed: _exportAnnotations, child: const Text('导出标注')),
            OutlinedButton(onPressed: _importAnnotations, child: const Text('导入标注')),
          ],
        ),
      ),
    );
  }

  Widget _buildReaderContent(PdfDocument doc) {
    final screenshotPanel = SizedBox(
      width: 340,
      child: ScreenshotPanel(
        screenshots: _visibleScreenshots,
        onlyCurrentPage: _onlyCurrentPageScreenshots,
        onOnlyCurrentPageChanged: (v) => setState(() => _onlyCurrentPageScreenshots = v),
        onOpenMindMap: _openMindMapDialog,
        onTap: (shot) => setState(() {
          _continuousMode = false;
          _currentPage = shot.page;
        }),
        onEditNote: _editScreenshotNote,
        onDelete: _deleteScreenshot,
      ),
    );

    switch (_viewMode) {
      case ViewMode.both:
        return Row(
          children: [
            Expanded(child: _buildPdfArea(doc)),
            screenshotPanel,
          ],
        );
      case ViewMode.pdfOnly:
        return _buildPdfArea(doc);
      case ViewMode.screenshotsOnly:
        return screenshotPanel;
    }
  }

  Widget _buildPdfArea(PdfDocument doc) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        if (_continuousMode) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: doc.pagesCount,
            itemBuilder: (context, index) {
              final page = index + 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FutureBuilder<RenderedPage>(
                  future: _renderPage(page, viewportWidth: viewportWidth),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('第 $page 页', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        AnnotatablePageWidget(
                          key: ValueKey('c_page_$page'),
                          page: page,
                          imageBytes: snap.data!.bytes,
                          imageSize: snap.data!.size,
                          tool: _tool,
                          color: _color,
                          penWidth: _penWidth,
                          fontSize: _fontSize,
                          annotations: _allAnnotations[page] ?? const [],
                          onChanged: (list) => setState(() => _allAnnotations[page] = list),
                          onSelectionCaptured: _onSelectionCaptured,
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          );
        }

        return Column(
          children: [
            Expanded(
              child: Center(
                child: FutureBuilder<RenderedPage>(
                  future: _renderPage(_currentPage, viewportWidth: viewportWidth),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const CircularProgressIndicator();
                    }
                    return SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: AnnotatablePageWidget(
                          key: ValueKey('s_page_$_currentPage'),
                          page: _currentPage,
                          imageBytes: snap.data!.bytes,
                          imageSize: snap.data!.size,
                          tool: _tool,
                          color: _color,
                          penWidth: _penWidth,
                          fontSize: _fontSize,
                          annotations: _allAnnotations[_currentPage] ?? const [],
                          onChanged: (list) => setState(() => _allAnnotations[_currentPage] = list),
                          onSelectionCaptured: _onSelectionCaptured,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('$_currentPage / ${doc.pagesCount}'),
                  IconButton(
                    onPressed: _currentPage < doc.pagesCount ? () => setState(() => _currentPage++) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _toolLabel(ToolType tool) {
    switch (tool) {
      case ToolType.view:
        return '查看';
      case ToolType.select:
        return '圈选';
      case ToolType.draw:
        return '涂鸦';
      case ToolType.highlight:
        return '高亮';
      case ToolType.eraser:
        return '橡皮';
      case ToolType.text:
        return '文字';
    }
  }
}
