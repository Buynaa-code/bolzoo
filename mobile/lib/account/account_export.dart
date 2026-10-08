import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/app_controller.dart';
import 'account_repository.dart';

/// Streaming ZIP creation keeps full-resolution photo collections off the heap.
/// Returns a unique staging directory; callers must erase it after sharing.
Future<Directory> buildAccountExport({
  required AppData ownData,
  required Directory temporaryDirectory,
  AccountRepository? repository,
  bool Function()? isCurrent,
}) async {
  void check() {
    if (isCurrent?.call() == false || repository?.sessionCurrent == false) {
      throw const AccountOperationException('session_changed');
    }
  }
  check();
  final staging = await Directory('${temporaryDirectory.path}/account_exports')
      .create(recursive: true);
  final work = await staging.createTemp('export-');
  final encoder = ZipFileEncoder();
  var opened = false;
  try {
    final remote = await repository?.exportData();
    check();
    encoder.create('${work.path}/hamtdaa.zip');
    opened = true;
    final photoIndex = <Map<String, Object?>>[];
    var index = 0;
    final localJson = ownData.toJson();
    final memories = localJson['memories'] as List;
    for (final raw in memories) {
      final memory = raw as Map;
      final path = memory.remove('photoPath');
      if (path == null) continue;
      if (path is! String || !File(path).isAbsolute) {
        throw const AccountOperationException('invalid_photo');
      }
      // Fail visibly if a referenced photo is missing; never claim a partial
      // archive is a complete backup. The original file is never altered.
      final file = File(path);
      final extension = path.split('.').last.toLowerCase();
      final safeExtension = const {'png','jpg','jpeg','webp','heic','heif'}
          .contains(extension) ? extension : 'bin';
      final name = 'photos/local-${++index}.$safeExtension';
      await encoder.addFile(file, name);
      check();
      memory['exportPhoto'] = name;
      photoIndex.add({'memoryId': memory['id'], 'file': name});
    }
    if (remote != null) {
      final seen = <String>{};
      for (final raw in remote['media'] as List) {
        if (raw is! Map || raw['key'] is! String) {
          throw const AccountOperationException('invalid_media');
        }
        final key = raw['key'] as String;
        if (!seen.add(key)) continue;
        final bytes = await repository!.downloadMedia(key);
        check();
        final extension = key.split('.').last;
        final safeExtension = const {'png','jpg','jpeg','webp'}.contains(extension)
            ? extension : 'bin';
        final name = 'photos/cloud-${++index}.$safeExtension';
        encoder.addArchiveFile(ArchiveFile.bytes(name, bytes));
        photoIndex.add({'mediaKey': key, 'file': name});
      }
    }
    final manifest = {
      'format': 'hamtdaa-personal-export', 'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'deviceRecords': localJson,
      'cloudRecords': ?remote,
      'photos': photoIndex,
    };
    encoder.addArchiveFile(ArchiveFile.string('records.json',
        const JsonEncoder.withIndent('  ').convert(manifest)));
    encoder.addArchiveFile(ArchiveFile.string('README.txt',
      'Хамтдаа — таны мэдээллийн хуулбар\n\n'
      'records.json: энэ төхөөрөмжийн өөрийн бүртгэл, үүлэн хадгалалтын '
      'өөрийн бүртгэл (нэвтэрсэн бол), зурагтай холбох жагсаалт.\n'
      'photos/: таны зургууд. Хосын үүсгэсэн бүртгэл ороогүй.\n'
      'Хуулбар хувийн мэдээлэлтэй. Зөвхөн өөрийн сонгосон газарт хадгална уу.\n'
      'Энэ нь мэдээллээ авч үлдэх архив; апп руу буцааж оруулах үйлдэл одоогоор байхгүй.\n'));
    await encoder.close();
    opened = false;
    check();
    return work;
  } catch (_) {
    if (opened) { try { await encoder.close(); } catch (_) {} }
    if (await work.exists()) await work.delete(recursive: true);
    rethrow;
  }
}

Future<void> shareAccountExport(BuildContext context, AppController controller,
    {AccountRepository? repository}) async {
  final box = context.findRenderObject();
  final origin = box is RenderBox ? box.localToGlobal(Offset.zero) & box.size : null;
  final data = await controller.exportOwnSnapshot();
  if (!context.mounted) return;
  final work = await buildAccountExport(
    ownData: data, temporaryDirectory: await getTemporaryDirectory(),
    repository: repository, isCurrent: () => context.mounted,
  );
  try {
    if (!context.mounted || repository?.sessionCurrent == false) {
      throw const AccountOperationException('session_changed');
    }
    await SharePlus.instance.share(ShareParams(
      files: [XFile('${work.path}/hamtdaa.zip', mimeType: 'application/zip')],
      subject: 'Хамтдаа — миний мэдээлэл', sharePositionOrigin: origin,
    ));
  } finally {
    if (await work.exists()) await work.delete(recursive: true);
  }
}
