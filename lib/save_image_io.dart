import 'dart:io';

import 'package:image_picker/image_picker.dart';

import 'package:path_provider/path_provider.dart';

Future<String?> savePickedImageToAppDir(XFile xFile) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final ext = xFile.name.contains('.') ? xFile.name.split('.').last : 'jpg';
    final path = '${dir.path}/anya_bg_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final bytes = await xFile.readAsBytes();
    await File(path).writeAsBytes(bytes);
    return path;
  } catch (_) {
    return null;
  }
}
