import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The owner's business details, printed on invoices and quotations.
typedef BusinessInfo = ({String name, String phone, String address});

const _kName = 'business.name';
const _kPhone = 'business.phone';
const _kAddress = 'business.address';

final businessInfoProvider = FutureProvider.autoDispose<BusinessInfo>((
  ref,
) async {
  final prefs = SharedPreferencesAsync();
  return (
    name: await prefs.getString(_kName) ?? '',
    phone: await prefs.getString(_kPhone) ?? '',
    address: await prefs.getString(_kAddress) ?? '',
  );
});

Future<void> saveBusinessInfo(BusinessInfo info) async {
  final prefs = SharedPreferencesAsync();
  await prefs.setString(_kName, info.name.trim());
  await prefs.setString(_kPhone, info.phone.trim());
  await prefs.setString(_kAddress, info.address.trim());
}
