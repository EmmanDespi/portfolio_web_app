import 'dart:html' as html;

Future<bool> downloadResume() async {
  final link = html.AnchorElement(href: 'assets/Emmanuel_Despi.pdf')
    ..download = 'Emmanuel_Despi.pdf'
    ..style.display = 'none';
  html.document.body?.children.add(link);
  link.click();
  link.remove();
  return true;
}
