import 'package:url_launcher/url_launcher.dart';

/// يحول الرقم العراقي لصيغة دولية بدون +، مثل: 07701234567 ← 9647701234567
String internationalPhone(String phone) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('0')) digits = '964${digits.substring(1)}';
  if (digits.startsWith('7') && digits.length == 10) digits = '964$digits';
  return digits;
}

Uri whatsappUri(String phone, {String message = ''}) => Uri.https(
      'wa.me',
      '/${internationalPhone(phone)}',
      message.isEmpty ? null : {'text': message},
    );

Uri callUri(String phone) => Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), ''));

Future<bool> openWhatsapp(String phone, {String message = ''}) =>
    launchUrl(whatsappUri(phone, message: message), mode: LaunchMode.externalApplication);

Future<bool> callPhone(String phone) => launchUrl(callUri(phone));

Future<bool> openLink(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
