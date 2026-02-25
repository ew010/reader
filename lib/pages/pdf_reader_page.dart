import 'dart:convert';
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

class LibraryFolder {
  LibraryFolder({
    required this.id,
    required this.name,
    required this.files,
    this.expanded = true,
  });

  final String id;
  final String name;
  final List<String> files;
  final bool expanded;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'files': files,
      'expanded': expanded,
    };
  }

  static LibraryFolder fromJson(Map<String, dynamic> json) {
    return LibraryFolder(
      id: (json['id'] as String?) ?? 'folder_${DateTime.now().millisecondsSinceEpoch}',
      name: (json['name'] as String?) ?? '未命名文件夹',
      files: (json['files'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      expanded: (json['expanded'] as bool?) ?? true,
    );
  }

  LibraryFolder copyWith({
    String? id,
    String? name,
    List<String>? files,
    bool? expanded,
  }) {
    return LibraryFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      files: files ?? this.files,
      expanded: expanded ?? this.expanded,
    );
  }
}

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
  final Set<String> _hiddenMindMapShotNodeIds = {};
  List<LibraryFolder> _libraryFolders = [];
  String? _selectedFolderId;
  bool _libraryReady = false;
  final Map<String, MindMapNode> _mindMapNodes = {
    'root': const MindMapNode(
      id: 'root',
      parentId: null,
      title: '截图根节点',
      offset: Offset(960, 80),
    ),
  };

  @override
  void initState() {
    super.initState();
    _initLibrary();
  }

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

    await _openPdfPath(result.files.single.path!);
  }

  Future<void> _openPdfPath(String path) async {
    final doc = await PdfDocument.openFile(path);
    final paths = _storageService.buildPaths(path);
    await _storageService.ensureScreenshotDir(paths.screenshotDir);

    _document?.close();
    _pdfService.clearDocumentCache();
    _allAnnotations.clear();
    _screenshots.clear();
    _hiddenMindMapShotNodeIds.clear();
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

  String get _libraryFilePath {
    final home = Platform.environment['HOME'] ?? '.';
    return p.join(home, '.reader_library.json');
  }

  Future<void> _initLibrary() async {
    await _loadLibrary();
    if (_libraryFolders.isEmpty) {
      _libraryFolders = [
        LibraryFolder(id: 'default', name: '默认文件夹', files: []),
      ];
      _selectedFolderId = 'default';
      await _saveLibrary();
    } else {
      _selectedFolderId ??= _libraryFolders.first.id;
    }
    if (mounted) {
      setState(() {
        _libraryReady = true;
      });
    }
  }

  Future<void> _loadLibrary() async {
    final file = File(_libraryFilePath);
    if (!await file.exists()) {
      _libraryFolders = [];
      return;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final foldersRaw = decoded['folders'] as List<dynamic>? ?? [];
      _libraryFolders = foldersRaw
          .whereType<Map<String, dynamic>>()
          .map(LibraryFolder.fromJson)
          .toList();
      _selectedFolderId = decoded['selectedFolderId'] as String?;
    } catch (_) {
      _libraryFolders = [];
    }
  }

  Future<void> _saveLibrary() async {
    final data = {
      'selectedFolderId': _selectedFolderId,
      'folders': _libraryFolders.map((f) => f.toJson()).toList(),
    };
    await File(_libraryFilePath).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '输入文件夹名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final folder = LibraryFolder(
      id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      files: [],
    );
    setState(() {
      _libraryFolders.add(folder);
      _selectedFolderId = folder.id;
    });
    await _saveLibrary();
  }

  Future<void> _renameFolder(String folderId) async {
    final index = _libraryFolders.indexWhere((f) => f.id == folderId);
    if (index < 0) return;
    final oldFolder = _libraryFolders[index];
    final controller = TextEditingController(text: oldFolder.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名文件夹'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '输入新名称'),
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
    if (newName == null || newName.isEmpty) return;
    setState(() {
      _libraryFolders[index] = oldFolder.copyWith(name: newName);
    });
    await _saveLibrary();
  }

  Future<void> _deleteFolder(String folderId) async {
    final index = _libraryFolders.indexWhere((f) => f.id == folderId);
    if (index < 0) return;
    final folder = _libraryFolders[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件夹'),
        content: Text('确认删除“${folder.name}”？文件条目会从列表中移除。'),
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
      _libraryFolders.removeAt(index);
      if (_libraryFolders.isEmpty) {
        final fallback = LibraryFolder(id: 'default', name: '默认文件夹', files: []);
        _libraryFolders = [fallback];
        _selectedFolderId = fallback.id;
      } else if (_selectedFolderId == folderId) {
        _selectedFolderId = _libraryFolders.first.id;
      }
    });
    await _saveLibrary();
  }

  Future<void> _addFileToSelectedFolder() async {
    final folderIndex = _libraryFolders.indexWhere((f) => f.id == _selectedFolderId);
    if (folderIndex < 0) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );
    if (result == null) return;

    final files = result.files.map((f) => f.path).whereType<String>().toList();
    if (files.isEmpty) return;

    final existing = _libraryFolders[folderIndex];
    final merged = [...existing.files];
    for (final file in files) {
      if (!merged.contains(file)) merged.add(file);
    }
    setState(() {
      _libraryFolders[folderIndex] = existing.copyWith(files: merged);
    });
    await _saveLibrary();
  }

  Future<void> _removeFileFromFolder(String folderId, String filePath) async {
    final folderIndex = _libraryFolders.indexWhere((f) => f.id == folderId);
    if (folderIndex < 0) return;
    final folder = _libraryFolders[folderIndex];
    final nextFiles = [...folder.files]..remove(filePath);
    setState(() {
      _libraryFolders[folderIndex] = folder.copyWith(files: nextFiles);
    });
    await _saveLibrary();
  }

  Future<void> _toggleFolderExpanded(String folderId) async {
    final folderIndex = _libraryFolders.indexWhere((f) => f.id == folderId);
    if (folderIndex < 0) return;
    final folder = _libraryFolders[folderIndex];
    setState(() {
      _libraryFolders[folderIndex] = folder.copyWith(expanded: !folder.expanded);
      _selectedFolderId = folderId;
    });
    await _saveLibrary();
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
      if (_hiddenMindMapShotNodeIds.contains(id)) {
        index++;
        continue;
      }
      if (existing != null) {
        _mindMapNodes[id] = existing.copyWith(
          title: 'P${shot.page} - ${p.basename(shot.path)}',
          imagePath: shot.path,
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
    final validShotNodeIds = _screenshots.map(_mindMapNodeIdForShot).toSet();
    _hiddenMindMapShotNodeIds.removeWhere((id) => !validShotNodeIds.contains(id));
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
        onNodeRenamed: _renameMindMapNode,
        onNodeDeleted: _deleteMindMapNode,
        onNodeReparented: _reparentMindMapNode,
      ),
    );
  }

  void _renameMindMapNode(String nodeId, String newTitle) {
    final node = _mindMapNodes[nodeId];
    if (node == null) return;
    setState(() {
      _mindMapNodes[nodeId] = node.copyWith(title: newTitle);
    });
  }

  void _deleteMindMapNode(String nodeId) {
    final node = _mindMapNodes[nodeId];
    if (node == null || node.parentId == null) return;
    setState(() {
      final children = _mindMapNodes.values.where((n) => n.parentId == nodeId).toList();
      for (final child in children) {
        _mindMapNodes[child.id] = child.copyWith(parentId: 'root');
      }
      _mindMapNodes.remove(nodeId);
      if (nodeId.startsWith('shot:')) {
        _hiddenMindMapShotNodeIds.add(nodeId);
      }
    });
  }

  void _reparentMindMapNode(String nodeId, String? newParentId) {
    final node = _mindMapNodes[nodeId];
    if (node == null || node.parentId == null) return;
    final parentId = newParentId ?? 'root';
    if (!_mindMapNodes.containsKey(parentId) || parentId == nodeId) return;
    setState(() {
      _mindMapNodes[nodeId] = node.copyWith(parentId: parentId);
    });
  }

  Future<void> _jumpToPage(PdfDocument doc) async {
    final controller = TextEditingController(text: '$_currentPage');
    final page = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到指定页'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '请输入 1 - ${doc.pagesCount}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, parsed);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (page == null) return;

    if (page < 1 || page > doc.pagesCount) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('页码超出范围：1 - ${doc.pagesCount}')),
      );
      return;
    }

    setState(() {
      _continuousMode = false;
      _currentPage = page;
    });
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
            child: Row(
              children: [
                SizedBox(
                  width: 300,
                  child: _buildLibraryPanel(),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: doc == null
                      ? const Center(child: Text('点击“打开PDF”开始'))
                      : _buildReaderContent(doc),
                ),
              ],
            ),
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

  Widget _buildLibraryPanel() {
    if (!_libraryReady) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '文件列表',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '新建文件夹',
                onPressed: _createFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              IconButton(
                tooltip: '添加PDF',
                onPressed: _addFileToSelectedFolder,
                icon: const Icon(Icons.note_add_outlined),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _libraryFolders.length,
            itemBuilder: (context, index) {
              final folder = _libraryFolders[index];
              final isSelected = folder.id == _selectedFolderId;
              final header = ListTile(
                dense: true,
                selected: isSelected,
                leading: Icon(folder.expanded ? Icons.folder_open : Icons.folder),
                title: Text(folder.name),
                subtitle: Text('${folder.files.length} 个文件'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: '文件夹操作',
                      onSelected: (value) {
                        if (value == 'rename') {
                          _renameFolder(folder.id);
                        } else if (value == 'delete') {
                          _deleteFolder(folder.id);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('重命名')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.more_vert, size: 18),
                      ),
                    ),
                    Icon(folder.expanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
                onTap: () => _toggleFolderExpanded(folder.id),
              );
              if (!folder.expanded) return header;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  ...folder.files.map(
                    (filePath) => Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        title: Text(
                          p.basename(filePath),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          filePath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setState(() => _selectedFolderId = folder.id);
                          if (!await File(filePath).exists()) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(content: Text('文件不存在: $filePath')),
                            );
                            return;
                          }
                          await _openPdfPath(filePath);
                        },
                        trailing: IconButton(
                          tooltip: '移除',
                          onPressed: () => _removeFileFromFolder(folder.id, filePath),
                          icon: const Icon(Icons.close, size: 16),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
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
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _jumpToPage(doc),
                    child: const Text('跳转'),
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
