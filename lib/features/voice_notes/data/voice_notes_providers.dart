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
class VoiceNotePlayer extends Notifier<int?> {
  AudioPlayer? _player;

  @override
  int? build() {
    final player = AudioPlayer();
    final sub = player.onPlayerComplete.listen((_) => state = null);
    ref.onDispose(() {
      unawaited(sub.cancel());
      unawaited(player.dispose());
    });
    _player = player;
    return null;
  }

  Future<void> toggle(VoiceNote note) async {
    final player = _player!;
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
