import 'package:flutter/material.dart';

class MindMapNode {
  const MindMapNode({
    required this.id,
    required this.parentId,
    required this.title,
    required this.offset,
    this.imagePath,
  });

  final String id;
  final String? parentId;
  final String title;
  final Offset offset;
  final String? imagePath;

  MindMapNode copyWith({
    String? id,
    String? parentId,
    String? title,
    Offset? offset,
    String? imagePath,
  }) {
    return MindMapNode(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      title: title ?? this.title,
      offset: offset ?? this.offset,
      imagePath: imagePath ?? this.imagePath,
    );
  }
}
