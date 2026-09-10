import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> downloadCsv(String fileName, Uint8List bytes) async {
  final path = await FilePicker.platform.saveFile(
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['csv'],
    bytes: bytes,
  );
  return path != null;
}
