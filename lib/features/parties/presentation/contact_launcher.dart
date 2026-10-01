import 'package:url_launcher/url_launcher.dart';

/// Egyptian mobile "01xxxxxxxxx" → international "201xxxxxxxxx".
String toInternationalEgypt(String phone) {
  var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('0')) digits = '20${digits.substring(1)}';
  return digits;
}

Future<bool> callPhone(String phone) =>
    launchUrl(Uri(scheme: 'tel', path: phone));

Future<bool> openWhatsApp(String phone) => launchUrl(
  Uri.parse('https://wa.me/${toInternationalEgypt(phone)}'),
  mode: LaunchMode.externalApplication,
);
