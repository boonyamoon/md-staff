import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/repositories/floor_repository.dart';
import '../data/repositories/menu_repository.dart';
import '../data/repositories/setup_repository.dart';
import '../data/repositories/shift_repository.dart';
import 'network/api_client.dart';
import 'storage/credential_store.dart';

final credentialStoreProvider = Provider<CredentialStore>((ref) => CredentialStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(credentials: ref.watch(credentialStoreProvider));
  ref.onDispose(client.dispose);
  return client;
});

final setupRepositoryProvider = Provider<SetupRepository>(
  (ref) => SetupRepository(
    api: ref.watch(apiClientProvider),
    credentials: ref.watch(credentialStoreProvider),
  ),
);

final shiftRepositoryProvider = Provider<ShiftRepository>(
  (ref) => ShiftRepository(
    api: ref.watch(apiClientProvider),
    credentials: ref.watch(credentialStoreProvider),
  ),
);

final floorRepositoryProvider = Provider<FloorRepository>(
  (ref) => FloorRepository(api: ref.watch(apiClientProvider)),
);

final menuRepositoryProvider = Provider<MenuRepository>(
  (ref) => MenuRepository(api: ref.watch(apiClientProvider)),
);

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
});

/// A sensible default for the `device_name` a manager sees in the terminal list: the phone's own
/// model, which is what a shop with four identical handsets will rename anyway.
final deviceNameProvider = FutureProvider<String>((ref) async {
  final plugin = DeviceInfoPlugin();
  try {
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      final name = '${info.manufacturer} ${info.model}'.trim();
      return name.isEmpty ? 'Android' : name;
    }
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      return info.name.isNotEmpty ? info.name : info.utsname.machine;
    }
  } on MissingPluginException {
    // Unit tests and desktop builds have no platform channel; a name is still required.
  }
  return 'Staff handset';
});
