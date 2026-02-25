import 'dart:typed_data';

import 'package:flutter/material.dart';

class RenderedPage {
  const RenderedPage({required this.bytes, required this.size});

  final Uint8List bytes;
  final Size size;
}
