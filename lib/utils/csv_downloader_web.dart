import 'dart:html' as html;
import 'dart:typed_data';

Future<bool> downloadCsv(String fileName, Uint8List bytes) async {
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final link = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.children.add(link);
  link.click();
  link.remove();
  html.Url.revokeObjectUrl(url);
  return true;
}
