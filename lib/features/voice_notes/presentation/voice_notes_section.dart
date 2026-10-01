import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/widgets/section_header.dart';
import '../data/voice_notes_providers.dart';
import 'voice_note_recorder_sheet.dart';

/// Header + list of voice notes, as slivers for a [CustomScrollView].
class VoiceNotesSliver extends ConsumerWidget {
  const VoiceNotesSliver({super.key, required this.partyId, this.orderId});

  final int partyId;
  final int? orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes =
        ref
            .watch(voiceNotesProvider((partyId: partyId, orderId: orderId)))
            .value ??
        const <VoiceNote>[];
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: SectionHeader(
            title: 'ملاحظات صوتية (${notes.length})',
            action: TextButton.icon(
              onPressed: () => showVoiceNoteRecorder(
                context,
                partyId: partyId,
                orderId: orderId,
              ),
              icon: const Icon(Icons.mic),
              label: const Text('تسجيل'),
            ),
          ),
        ),
        SliverList.builder(
          itemCount: notes.length,
          itemBuilder: (_, i) => _VoiceNoteTile(note: notes[i]),
        ),
      ],
    );
  }
}

class _VoiceNoteTile extends ConsumerWidget {
  const _VoiceNoteTile({required this.note});

  final VoiceNote note;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الملاحظة الصوتية؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) await deleteVoiceNote(db, note);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(
      voiceNotePlayerProvider.select((id) => id == note.id),
    );
    return Card(
      child: ListTile(
        leading: IconButton.filledTonal(
          icon: Icon(playing ? Icons.stop : Icons.play_arrow),
          onPressed: () =>
              ref.read(voiceNotePlayerProvider.notifier).toggle(note),
        ),
        title: Text(formatDateTime(note.createdAt)),
        subtitle: Text(
          'المدة ${formatDuration(Duration(milliseconds: note.durationMs))}'
          '${note.orderId != null ? ' • طلب رقم ${note.orderId}' : ''}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _confirmDelete(context, ref),
        ),
      ),
    );
  }
}
