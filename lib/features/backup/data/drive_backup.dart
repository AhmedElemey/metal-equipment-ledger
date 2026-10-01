import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/database/app_database.dart';
import '../../voice_notes/data/voice_notes_providers.dart';
import 'excel_export.dart';

class BackupNotConnected implements Exception {
  const BackupNotConnected();
}

/// The phone has no data. Uploading would overwrite a real backup with an
/// empty one (e.g. right after installing on a new phone), so we never do.
class NothingToBackUp implements Exception {
  const NothingToBackUp();
}

class NoBackupFound implements Exception {
  const NoBackupFound();
}

typedef DriveBackupFile = ({String id, DateTime modifiedAt});

/// Backs up to, and restores from, the user's Google Drive.
///
/// Uses the `drive.file` scope: the app only sees files it created itself
/// (from any install with the same OAuth client — so a new phone finds the
/// old phone's backup), needs no Google verification, and can't touch the
/// user's other files. The same files are updated every day; Drive keeps
/// their older revisions, so earlier days stay recoverable. Voice notes are
/// uploaded once each into a sub-folder (they never change).
abstract final class DriveBackup {
  static const _scopes = [drive.DriveApi.driveFileScope];
  static const folderName = 'دفتر المعدات - نسخ احتياطية';
  static const voiceFolderName = 'ملاحظات صوتية';
  static const excelName = 'دفتر المعدات - البيانات.xlsx';
  static const dbName = 'metal_ledger_backup.sqlite';
  static const _folderMime = 'application/vnd.google-apps.folder';

  static const _kConnected = 'backup.connected';
  static const _kFolderId = 'backup.folderId';
  static const _kVoiceFolderId = 'backup.voiceFolderId';
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
    for (final key in [
      _kConnected,
      _kFolderId,
      _kVoiceFolderId,
      _kExcelId,
      _kDbId,
    ]) {
      await _prefs.remove(key);
    }
  }

  /// Non-interactive; safe to call from the background task.
  static Future<void> run(AppDatabase db) async {
    if ((await db.counts()).parties == 0) throw const NothingToBackUp();
    await _withApi((api) async {
      final folderId = await _folder(api, _kFolderId, folderName, null);

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

      await _uploadVoiceNotes(api, folderId);
      await _prefs.setInt(lastBackupKey, DateTime.now().millisecondsSinceEpoch);
    });
  }

  /// The most recent database backup this app put on Drive, if any.
  static Future<DriveBackupFile?> findBackup() =>
      _withApi((api) async => _findDbBackup(api));

  /// Replaces all data on this phone with the latest Drive backup, then
  /// downloads any voice notes it references. Returns the restored counts.
  static Future<DataCounts> restore(AppDatabase db) {
    return _withApi((api) async {
      final backup = await _findDbBackup(api);
      if (backup == null) throw const NoBackupFound();

      final tmp = File(
        p.join((await getTemporaryDirectory()).path, 'restore_$dbName'),
      );
      try {
        await _download(api, backup.id, tmp);
        final counts = await db.replaceAllFrom(tmp);

        // Keep backing up into the same Drive files from now on.
        final file =
            await api.files.get(backup.id, $fields: 'parents') as drive.File;
        final folderId = file.parents?.firstOrNull;
        await _prefs.setString(_kDbId, backup.id);
        if (folderId != null) {
          await _prefs.setString(_kFolderId, folderId);
          await _downloadVoiceNotes(api, db, folderId);
        }
        await _prefs.setInt(
          lastBackupKey,
          DateTime.now().millisecondsSinceEpoch,
        );
        return counts;
      } finally {
        if (tmp.existsSync()) await tmp.delete();
      }
    });
  }

  // ---------------------------------------------------------------- helpers

  static Future<T> _withApi<T>(
    Future<T> Function(drive.DriveApi api) body,
  ) async {
    if (!await isConnected()) throw const BackupNotConnected();
    await _ensureInit();
    final auth = await GoogleSignIn.instance.authorizationClient
        .authorizationForScopes(_scopes);
    if (auth == null) throw const BackupNotConnected();
    final client = _BearerClient(auth.accessToken);
    try {
      return await body(drive.DriveApi(client));
    } finally {
      client.close();
    }
  }

  static Future<DriveBackupFile?> _findDbBackup(drive.DriveApi api) async {
    final found = await _search(api, "name = '$dbName'");
    final f = found.firstOrNull;
    if (f == null) return null;
    return (id: f.id!, modifiedAt: f.modifiedTime!.toLocal());
  }

  /// App-visible, non-trashed files matching [query], newest first.
  static Future<List<drive.File>> _search(
    drive.DriveApi api,
    String query,
  ) async {
    final result = <drive.File>[];
    String? page;
    do {
      final list = await api.files.list(
        q: '$query and trashed = false',
        orderBy: 'modifiedTime desc',
        $fields: 'nextPageToken, files(id, name, modifiedTime)',
        pageSize: 1000,
        pageToken: page,
      );
      result.addAll(list.files ?? const []);
      page = list.nextPageToken;
    } while (page != null);
    return result;
  }

  /// The saved folder, else an existing one with that name (e.g. made by a
  /// previous install), else a new one.
  static Future<String> _folder(
    drive.DriveApi api,
    String idKey,
    String name,
    String? parentId,
  ) async {
    final saved = await _prefs.getString(idKey);
    if (saved != null && await _exists(api, saved)) return saved;
    final inParent = parentId == null ? '' : " and '$parentId' in parents";
    final existing = await _search(
      api,
      "name = '$name' and mimeType = '$_folderMime'$inParent",
    );
    final id =
        existing.firstOrNull?.id ??
        (await api.files.create(
          drive.File()
            ..name = name
            ..mimeType = _folderMime
            ..parents = parentId == null ? null : [parentId],
        )).id!;
    await _prefs.setString(idKey, id);
    return id;
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
    var id = await _prefs.getString(idKey);
    if (id != null && !await _exists(api, id)) id = null;
    id ??= (await _search(
      api,
      "name = '$name' and '$folderId' in parents",
    )).firstOrNull?.id;
    if (id != null) {
      await api.files.update(drive.File(), id, uploadMedia: media());
    } else {
      id = (await api.files.create(
        drive.File()
          ..name = name
          ..parents = [folderId],
        uploadMedia: media(),
      )).id!;
    }
    await _prefs.setString(idKey, id);
  }

  /// Uploads local voice notes that aren't on Drive yet.
  static Future<void> _uploadVoiceNotes(
    drive.DriveApi api,
    String folderId,
  ) async {
    // Only finished recordings — not ".part" leftovers of a cut download.
    final local = (await voiceNotesDir()).listSync().whereType<File>().where(
      (f) => f.path.endsWith('.m4a'),
    );
    if (local.isEmpty) return;
    final voiceFolder = await _folder(
      api,
      _kVoiceFolderId,
      voiceFolderName,
      folderId,
    );
    final remote = {
      for (final f in await _search(api, "'$voiceFolder' in parents")) f.name,
    };
    for (final file in local) {
      final name = p.basename(file.path);
      if (remote.contains(name)) continue;
      await api.files.create(
        drive.File()
          ..name = name
          ..parents = [voiceFolder],
        uploadMedia: drive.Media(
          file.openRead(),
          file.lengthSync(),
          contentType: 'audio/mp4',
        ),
      );
    }
  }

  /// Downloads the voice notes the restored data references but this phone
  /// doesn't have.
  static Future<void> _downloadVoiceNotes(
    drive.DriveApi api,
    AppDatabase db,
    String folderId,
  ) async {
    final wanted = {
      for (final n in await db.select(db.voiceNotes).get()) n.fileName,
    };
    if (wanted.isEmpty) return;
    final voiceFolder = (await _search(
      api,
      "name = '$voiceFolderName' and mimeType = '$_folderMime' "
      "and '$folderId' in parents",
    )).firstOrNull?.id;
    if (voiceFolder == null) return;
    await _prefs.setString(_kVoiceFolderId, voiceFolder);
    for (final f in await _search(api, "'$voiceFolder' in parents")) {
      if (!wanted.contains(f.name)) continue;
      final target = await voiceNoteFile(f.name!);
      if (!target.existsSync()) await _download(api, f.id!, target);
    }
  }

  static Future<void> _download(
    drive.DriveApi api,
    String id,
    File target,
  ) async {
    final media = await api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    // Write to a side file first so a dropped connection never leaves a
    // half-written file under the real name.
    final partial = File('${target.path}.part');
    await media.stream.pipe(partial.openWrite());
    await partial.rename(target.path);
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
