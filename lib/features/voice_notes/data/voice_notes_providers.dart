import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

typedef VoiceNotesKey = ({int partyId, int? orderId});

final voiceNotesProvider = StreamProvider.autoDispose
    .family<List<VoiceNote>, VoiceNotesKey>(
      (ref, key) => ref
          .watch(databaseProvider)
          .watchVoiceNotes(partyId: key.partyId, orderId: key.orderId),
    );

Future<Directory> voiceNotesDir() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, 'voice_notes')).create(recursive: true);
}

Future<File> voiceNoteFile(String fileName) async =>
    File(p.join((await voiceNotesDir()).path, fileName));

/// Deletes the row first, then the audio file (a missing file is harmless,
/// a row pointing to a deleted file is not).
Future<void> deleteVoiceNote(AppDatabase db, VoiceNote note) async {
  await db.deleteVoiceNote(note.id);
  final file = await voiceNoteFile(note.fileName);
  if (file.existsSync()) await file.delete();
}

/// Plays one voice note at a time. State is the id of the playing note.
///
/// The native player is created on the first play, not when a list of
/// notes is merely shown.
class VoiceNotePlayer extends Notifier<int?> {
  AudioPlayer? _player;
  StreamSubscription<void>? _completeSub;

  @override
  int? build() {
    ref.onDispose(() {
      unawaited(_completeSub?.cancel());
      unawaited(_player?.dispose());
    });
    return null;
  }

  AudioPlayer _playerOrCreate() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _completeSub = player.onPlayerComplete.listen((_) => state = null);
    return _player = player;
  }

  Future<void> toggle(VoiceNote note) async {
    final player = _playerOrCreate();
    if (state == note.id) {
      await player.stop();
      state = null;
      return;
    }
    await player.stop();
    final file = await voiceNoteFile(note.fileName);
    if (!ref.mounted) return;
    state = note.id;
    await player.play(DeviceFileSource(file.path));
  }
}

final voiceNotePlayerProvider =
    NotifierProvider.autoDispose<VoiceNotePlayer, int?>(VoiceNotePlayer.new);
