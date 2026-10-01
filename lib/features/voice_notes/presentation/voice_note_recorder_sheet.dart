import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../data/voice_notes_providers.dart';

Future<void> showVoiceNoteRecorder(
  BuildContext context, {
  required int partyId,
  int? orderId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => VoiceNoteRecorderSheet(partyId: partyId, orderId: orderId),
  );
}

class VoiceNoteRecorderSheet extends ConsumerStatefulWidget {
  const VoiceNoteRecorderSheet({
    super.key,
    required this.partyId,
    this.orderId,
  });

  final int partyId;
  final int? orderId;

  @override
  ConsumerState<VoiceNoteRecorderSheet> createState() =>
      _VoiceNoteRecorderSheetState();
}

class _VoiceNoteRecorderSheetState
    extends ConsumerState<VoiceNoteRecorderSheet> {
  final _recorder = AudioRecorder();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  String? _path;
  bool _recording = false;
  bool _saved = false;

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_recorder.dispose());
    // Closed without saving: don't leave an orphan audio file behind.
    final path = _path;
    if (!_saved && path != null) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب السماح باستخدام الميكروفون')),
      );
      return;
    }
    final dir = await voiceNotesDir();
    if (!mounted) return;
    // Set before starting so dispose() cleans the file up if the sheet closes.
    final path = _path = p.join(
      dir.path,
      'note_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _recorder.start(const RecordConfig(), path: path);
    if (!mounted) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });
    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
    });
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    await _recorder.stop();
    if (!mounted) return;
    setState(() => _recording = false);
  }

  Future<void> _save() async {
    final path = _path;
    if (path == null) return;
    await ref
        .read(databaseProvider)
        .addVoiceNote(
          VoiceNotesCompanion.insert(
            partyId: widget.partyId,
            orderId: Value(widget.orderId),
            fileName: p.basename(path),
            durationMs: _elapsed.inMilliseconds,
          ),
        );
    _saved = true;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasRecording = _path != null && !_recording;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _recording ? 'جاري التسجيل…' : 'ملاحظة صوتية',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              formatDuration(_elapsed),
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 16),
            SizedBox.square(
              dimension: 88,
              child: FloatingActionButton(
                heroTag: null,
                shape: const CircleBorder(),
                backgroundColor: _recording ? AppColors.danger : null,
                onPressed: _recording ? _stop : (hasRecording ? null : _start),
                child: Icon(_recording ? Icons.stop : Icons.mic, size: 44),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _recording ? 'اضغط للإيقاف' : 'اضغط على الميكروفون للتسجيل',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _recording
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: hasRecording ? _save : null,
                    icon: const Icon(Icons.check),
                    label: const Text('حفظ'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
