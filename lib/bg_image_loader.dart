import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import 'bg_image_stub.dart' if (dart.library.io) 'bg_image_io.dart' as loader;

import 'save_image_stub.dart' if (dart.library.io) 'save_image_io.dart' as saver;

Widget buildBackgroundImageFromPath(String path) => loader.buildBackgroundImageFromPath(path);

Future<String?> savePickedImageToAppDir(XFile xFile) => saver.savePickedImageToAppDir(xFile);
