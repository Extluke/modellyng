import 'dart:typed_data';

import 'download_file_stub.dart'
    if (dart.library.io) 'download_file_native.dart'
    if (dart.library.html) 'download_file_web.dart'
    as implementation;

Future<bool> downloadFile(Uint8List bytes, String filename, String mediaType) {
  return implementation.downloadFile(bytes, filename, mediaType);
}
