// 非 Web 用：從檔案路徑顯示背景圖
import 'dart:io';

import 'package:flutter/material.dart';

Widget buildBackgroundImageFromPath(String path) {
  final file = File(path);
  if (!file.existsSync()) return Container(color: const Color(0xFF0D0D0D));
  return Image.file(file, fit: BoxFit.cover);
}
