import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/memories/memory_photo.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'normalization orients pixels, limits output sizes and strips metadata',
    () async {
      final source = img.Image(width: 1800, height: 900);
      img.fill(source, color: img.ColorRgb8(210, 60, 130));
      source.exif.imageIfd.orientation = 6;
      source.exif.imageIfd.imageDescription = 'Private camera metadata';
      final normalized = await normalizeMemoryPhoto(
        img.encodeJpg(source, quality: 90),
      );
      final photo = img.decodeJpg(normalized.photo)!;
      final thumbnail = img.decodeJpg(normalized.thumbnail)!;
      expect(photo.width, 640);
      expect(photo.height, 1280);
      expect(thumbnail.width, 80);
      expect(thumbnail.height, 160);
      expect(photo.exif.isEmpty, isTrue);
      expect(thumbnail.exif.isEmpty, isTrue);
      expect(normalized.photo.length, lessThanOrEqualTo(memoryPhotoByteLimit));
      expect(
        normalized.thumbnail.length,
        lessThanOrEqualTo(memoryThumbnailByteLimit),
      );
    },
  );

  test(
    'rejects empty, oversized and invalid input without an upload copy',
    () async {
      for (final bytes in [
        Uint8List(0),
        Uint8List(memoryInputByteLimit + 1),
        Uint8List.fromList([1, 2, 3]),
      ]) {
        await expectLater(
          normalizeMemoryPhoto(bytes),
          throwsA(isA<MemoryPhotoException>()),
        );
      }
    },
  );

  test(
    'rejects excessive dimensions from JPEG header before decoding pixels',
    () async {
      final bytes = img.encodeJpg(img.Image(width: 1, height: 1));
      final forged = Uint8List.fromList(bytes);
      final start = [
        for (var i = 0; i < forged.length - 8; i++)
          if (forged[i] == 0xff && forged[i + 1] == 0xc0) i,
      ].single;
      // A valid JPEG header claiming 10,000 by 10,000 pixels, with no such pixel
      // data. The dimension-specific error proves validation precedes decoding.
      forged[start + 5] = forged[start + 7] = 0x27;
      forged[start + 6] = forged[start + 8] = 0x10;
      await expectLater(
        normalizeMemoryPhoto(forged),
        throwsA(
          isA<MemoryPhotoException>().having(
            (e) => e.message,
            'message',
            contains('хэмжээ хэт том'),
          ),
        ),
      );
    },
  );
}
