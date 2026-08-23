// ignore_for_file: deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

void downloadFile(Uint8List bytes, String filename, String mediaType) {
  final blob = html.Blob(<Object>[bytes], mediaType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
