import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Uses Android's document picker without broad storage permissions.
/// Cancellation is distinct from a successfully saved export.
Future<bool> downloadFile(
  Uint8List bytes,
  String filename,
  String mediaType,
) async {
  final path = await FilePicker.saveFile(
    dialogTitle: 'Simpan hasil Modellyng',
    fileName: filename,
    bytes: bytes,
  );
  return path != null;
}
