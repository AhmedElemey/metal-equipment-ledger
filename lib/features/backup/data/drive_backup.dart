import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/database/app_database.dart';
import 'excel_export.dart';

class BackupNotConnected implements Exception {
  const BackupNotConnected();
}

/// Uploads the daily backup to the user's Google Drive.
///
/// Uses the `drive.file` scope: the app only sees files it created itself,
/// which needs no Google verification and can't touch the user's other files.
/// The same two files are updated every day; Drive keeps their older
/// revisions, so earlier days stay recoverable.
abstract final class DriveBackup {
  static const _scopes = [drive.DriveApi.driveFileScope];
  static const folderName = 'دفتر المعدات - نسخ احتياطية';
  static const excelName = 'دفتر المعدات - البيانات.xlsx';
  static const dbName = 'metal_ledger_backup.sqlite';

  static const _kConnected = 'backup.connected';
  static const _kFolderId = 'backup.folderId';
  static const _kExcelId = 'backup.excelId';
  static const _kDbId = 'backup.dbId';
  static const lastBackupKey = 'backup.lastAt';

  // Uncached: the background isolate and the UI isolate both write these.
  static final _prefs = SharedPreferencesAsync();

  static Future<void>? _init;
  static Future<void> _ensureInit() =>
      _init ??= GoogleSignIn.instance.initialize();

  static Future<bool> isConnected() async =>
      await _prefs.getBool(_kConnected) ?? false;

  static Future<DateTime?> lastBackupAt() async {
    final ms = await _prefs.getInt(lastBackupKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Interactive: must be called from a user action (shows Google's UI).
  static Future<void> connect() async {
    await _ensureInit();
    await GoogleSignIn.instance.authorizationClient.authorizeScopes(_scopes);
    await _prefs.setBool(_kConnected, true);
  }

  static Future<void> disconnect() async {
    await _ensureInit();
    await GoogleSignIn.instance.disconnect();
    await _prefs.remove(_kConnected);
  }

  /// Non-interactive; safe to call from the background task.
  static Future<void> run(AppDatabase db) async {
    if (!await isConnected()) throw const BackupNotConnected();
    await _ensureInit();
    final auth = await GoogleSignIn.instance.authorizationClient
        .authorizationForScopes(_scopes);
    if (auth == null) throw const BackupNotConnected();

    final client = _BearerClient(auth.accessToken);
    try {
      final api = drive.DriveApi(client);
      final folderId = await _folderId(api);

      final excel = await buildExcelReport(db);
      await _upsert(
        api,
        _kExcelId,
        excelName,
        folderId,
        excel,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );

      final tmp = File(p.join((await getTemporaryDirectory()).path, dbName));
      await db.snapshotTo(tmp);
      try {
        await _upsert(
          api,
          _kDbId,
          dbName,
          folderId,
          await tmp.readAsBytes(),
          'application/x-sqlite3',
        );
      } finally {
        await tmp.delete();
      }

      await _prefs.setInt(lastBackupKey, DateTime.now().millisecondsSinceEpoch);
    } finally {
      client.close();
    }
  }

  static Future<String> _folderId(drive.DriveApi api) async {
    final saved = await _prefs.getString(_kFolderId);
    if (saved != null && await _exists(api, saved)) return saved;
    final folder = await api.files.create(
      drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder',
    );
    await _prefs.setString(_kFolderId, folder.id!);
    return folder.id!;
  }

  static Future<void> _upsert(
    drive.DriveApi api,
    String idKey,
    String name,
    String folderId,
    List<int> bytes,
    String mimeType,
  ) async {
    drive.Media media() =>
        drive.Media(Stream.value(bytes), bytes.length, contentType: mimeType);
    final saved = await _prefs.getString(idKey);
    if (saved != null && await _exists(api, saved)) {
      await api.files.update(drive.File(), saved, uploadMedia: media());
      return;
    }
    final created = await api.files.create(
      drive.File()
        ..name = name
        ..parents = [folderId],
      uploadMedia: media(),
    );
    await _prefs.setString(idKey, created.id!);
  }

  /// False if the user deleted or trashed the file in Drive.
  static Future<bool> _exists(drive.DriveApi api, String id) async {
    try {
      final f = await api.files.get(id, $fields: 'trashed') as drive.File;
      return f.trashed != true;
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 404) return false;
      rethrow;
    }
  }
}

class _BearerClient extends http.BaseClient {
  _BearerClient(this._token);

  final String _token;
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
