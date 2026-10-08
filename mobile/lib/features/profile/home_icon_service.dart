import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

enum HomeIconPinResult { requested, updated, unsupported }

class HomeIconService {
  const HomeIconService();
  static const _channel = MethodChannel('mn.moch.hamtdaa/home_icon');

  Future<HomeIconPinResult> pin(Uint8List png, String name) async {
    final result = await _channel.invokeMethod<String>('pinPhotoIcon', {
      'png': png,
      'label': name,
    });
    return switch (result) {
      'requested' => HomeIconPinResult.requested,
      'updated' => HomeIconPinResult.updated,
      'unsupported' => HomeIconPinResult.unsupported,
      _ => throw const FormatException('Unknown shortcut result.'),
    };
  }

  Future<ShareResultStatus> share(Uint8List png, Rect origin) async {
    final temporary = await getTemporaryDirectory();
    // Unique staging prevents concurrent exports from removing one another.
    final directory = await temporary.createTemp('hamtdaa-home-icon-');
    try {
      final file = await File('${directory.path}/hamtdaa-icon.png')
          .writeAsBytes(png, flush: true);
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        subject: 'Хамтдаа — бидний дүрс',
        sharePositionOrigin: origin,
      ));
      return result.status;
    } finally {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }
}
