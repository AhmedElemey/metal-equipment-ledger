import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/section_header.dart';
import '../data/photos.dart';

const _thumb = 96.0;

/// "الصور" header + a horizontal strip of thumbnails, as a sliver.
class OrderPhotosSliver extends ConsumerWidget {
  const OrderPhotosSliver({super.key, required this.orderId});

  final int orderId;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('التقاط صورة'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختيار من المعرض'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      await addOrderPhoto(db, orderId, source);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('تعذر إضافة الصورة: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos =
        ref.watch(orderPhotosProvider(orderId)).value ?? const <OrderPhoto>[];
    final dir = ref.watch(photosDirProvider).value;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'الصور (${photos.length})',
            action: TextButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('إضافة'),
            ),
          ),
          if (photos.isNotEmpty && dir != null)
            SizedBox(
              height: _thumb,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _Thumbnail(
                  photo: photos[i],
                  file: File(p.join(dir.path, photos[i].fileName)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.photo, required this.file});

  final OrderPhoto photo;
  final File file;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PhotoViewer(photo: photo, file: file),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          file,
          width: _thumb,
          height: _thumb,
          fit: BoxFit.cover,
          // Decode at thumbnail size, not the full photo.
          cacheWidth: (_thumb * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, _, _) => const SizedBox.square(
            dimension: _thumb,
            child: Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    );
  }
}

class _PhotoViewer extends ConsumerWidget {
  const _PhotoViewer({required this.photo, required this.file});

  final OrderPhoto photo;
  final File file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            tooltip: 'حذف',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final db = ref.read(databaseProvider);
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('حذف الصورة؟'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('إلغاء'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(
                        'حذف',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              Navigator.of(context).pop();
              await deleteOrderPhoto(db, photo);
            },
          ),
        ],
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(child: Image.file(file)),
      ),
    );
  }
}
