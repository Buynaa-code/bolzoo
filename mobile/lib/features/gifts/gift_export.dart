import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models.dart';

Future<String> captureGiftPng(
  GlobalKey boundaryKey, {
  bool permanent = false,
  Directory? documentsDirectory,
}) async {
  final boundary = boundaryKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) {
    throw StateError('Gift is not visible.');
  }
  await WidgetsBinding.instance.endOfFrame;
  final picture = await boundary.toImage(pixelRatio: 3);
  try {
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Could not create PNG.');
    final base = permanent
        ? documentsDirectory ?? await getApplicationDocumentsDirectory()
        : await getTemporaryDirectory();
    final directory = Directory(
      '${base.path}/${permanent ? 'memories_media' : 'gift_exports'}',
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}/${newLocalId()}.png');
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file.path;
  } finally {
    picture.dispose();
  }
}

Future<void> shareGiftPng(
  GlobalKey boundaryKey,
  BuildContext context, {
  required String title,
}) async {
  final box = context.findRenderObject();
  final origin = box is RenderBox
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  final path = await captureGiftPng(boundaryKey);
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'image/png')],
        subject: title,
        sharePositionOrigin: origin,
      ),
    );
  } finally {
    final temporary = File(path);
    if (await temporary.exists()) await temporary.delete();
  }
}
