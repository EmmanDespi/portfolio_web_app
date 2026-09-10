import 'package:url_launcher/url_launcher.dart';

Future<bool> downloadResume() {
  return launchUrl(
    Uri.parse('assets/Emmanuel_Despi.pdf'),
    mode: LaunchMode.externalApplication,
  );
}
