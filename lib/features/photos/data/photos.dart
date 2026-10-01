import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

final orderPhotosProvider = StreamProvider.autoDispose
    .family<List<OrderPhoto>, int>(
      (ref, orderId) => ref.watch(databaseProvider).watchOrderPhotos(orderId),
    );

/// The photos folder never moves while the app runs, so it's resolved once
/// and kept (deliberately not autoDispose).
final photosDirProvider = FutureProvider<Directory>((ref) => photosDir());

Future<Directory> photosDir() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, 'order_photos')).create(recursive: true);
}

Future<File> photoFile(String fileName) async =>
    File(p.join((await photosDir()).path, fileName));

/// Takes or picks a photo (scaled down to save space) and attaches it.
/// Returns false if the user cancelled.
Future<bool> addOrderPhoto(
  AppDatabase db,
  int orderId,
  ImageSource source,
) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 80,
  );
  if (picked == null) return false;
  final name = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
  await File(picked.path).copy((await photoFile(name)).path);
  await db.addOrderPhoto(orderId, name);
  return true;
}

/// Row first, then file: a missing file is harmless, a row pointing to a
/// deleted file is not.
Future<void> deleteOrderPhoto(AppDatabase db, OrderPhoto photo) async {
  await db.deleteOrderPhoto(photo.id);
  final file = await photoFile(photo.fileName);
  if (file.existsSync()) await file.delete();
}

/// Removes the files of photos whose rows are already gone (e.g. their
/// order was deleted and the rows cascaded).
Future<void> deletePhotoFiles(Iterable<OrderPhoto> photos) async {
  for (final photo in photos) {
    final file = await photoFile(photo.fileName);
    if (file.existsSync()) await file.delete();
  }
}
