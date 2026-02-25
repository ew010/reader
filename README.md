# PDF Reader Flutter

这是把原 `pdf_reader.py`（PyQt5 + PyMuPDF）重构后的 Flutter 版本。

## 已迁移功能

- 打开 PDF 文件
- 单页/连续阅读模式
- 标注工具：圈选、涂鸦、高亮、文字、橡皮
- 缩放
- 选区截图并保存到 `xxx_screenshots` 目录
- 右侧截图列表、备注、删除、跳页
- 标注导入/导出 JSON
- 截图备注保存/加载 JSON

## 项目结构

- `pubspec.yaml`：依赖定义
- `lib/main.dart`：应用入口
- `lib/pages/pdf_reader_page.dart`：主页面与状态管理
- `lib/models/`：标注、截图、渲染模型
- `lib/services/`：PDF 渲染缓存、本地持久化
- `lib/widgets/`：标注画布、截图侧栏

## 运行

1. 安装 Flutter SDK（建议 stable 3.22+）
2. 在项目根目录执行：

```bash
flutter pub get
flutter run -d macos
```

也可改为 Windows/Linux/Android/iOS 目标。

## GitHub Actions 构建

已提供工作流文件：

- `.github/workflows/ci.yml`

触发方式：

- push 到 `main`/`master`
- Pull Request
- 手动 `workflow_dispatch`

会执行：

- `flutter analyze`
- `flutter test`
- Android 构建（`apk` + `aab`）
- iOS 构建（`--no-codesign`，产物为 `Runner.app.zip`）
- Windows 构建（Release 目录）

## 数据文件

打开 `/path/to/a.pdf` 时，会自动生成：

- `/path/to/a_screenshots/` 截图目录
- `/path/to/a_annotations.json` 标注文件
- `/path/to/a_screenshot_notes.json` 截图备注

## 说明

当前实现以桌面端交互优先。
