import 'dart:typed_data';

import 'download_file_stub.dart'
    if (dart.library.html) 'download_file_web.dart'
    as implementation;

void downloadFile(Uint8List bytes, String filename, String mediaType) {
  implementation.downloadFile(bytes, filename, mediaType);
}
