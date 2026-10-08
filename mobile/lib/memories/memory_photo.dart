import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'memory_models.dart';

const memoryInputByteLimit = 20 * 1024 * 1024;
const memoryPhotoByteLimit = 768 * 1024;
const memoryThumbnailByteLimit = 64 * 1024;

class MemoryPhotoException implements Exception {
  const MemoryPhotoException(this.message);
  final String message;
}

/// Only the normalized pixels leave the editor. EXIF and other source metadata
/// are removed after applying the camera orientation.
Future<MemoryPhoto> normalizeMemoryPhoto(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > memoryInputByteLimit) {
    throw const MemoryPhotoException('20 MB хүртэл хэмжээтэй зураг сонгоорой.');
  }
  return compute(_normalize, bytes);
}

MemoryPhoto _normalize(Uint8List bytes) {
  try {
    // Probe only formats supported by the gallery upload. Read dimensions before
    // allocating the decoded pixels, and decode one frame of animated files.
    final img.Decoder decoder;
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      decoder = img.JpegDecoder();
    } else if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      decoder = img.PngDecoder();
    } else if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      decoder = img.WebPDecoder();
    } else {
      throw const MemoryPhotoException('JPG, PNG эсвэл WebP зураг сонгоорой.');
    }
    final info = decoder.startDecode(bytes);
    if (info == null || info.width < 1 || info.height < 1) {
      throw const MemoryPhotoException(
        'Энэ зургийг нээж чадсангүй. Өөр зураг сонгоорой.',
      );
    }
    if (info.width * info.height > 32000000) {
      throw const MemoryPhotoException(
        'Зургийн хэмжээ хэт том байна. Жижигрүүлээд дахин сонгоорой.',
      );
    }
    final decoded = decoder.decodeFrame(0);
    if (decoded == null) {
      throw const MemoryPhotoException(
        'Энэ зургийг нээж чадсангүй. Өөр зураг сонгоорой.',
      );
    }
    final oriented =
        decoded.exif.imageIfd.hasOrientation &&
            decoded.exif.imageIfd.orientation != 1
        ? img.bakeOrientation(decoded)
        : decoded;
    var photo = _resize(oriented, 1280);
    photo.exif = img.ExifData();
    photo.iccProfile = null;
    var quality = 82;
    var encoded = img.encodeJpg(photo, quality: quality);
    while (encoded.length > memoryPhotoByteLimit && quality > 52) {
      quality -= 10;
      encoded = img.encodeJpg(photo, quality: quality);
    }
    while (encoded.length > memoryPhotoByteLimit &&
        math.max(photo.width, photo.height) > 320) {
      photo = _resize(
        photo,
        (math.max(photo.width, photo.height) * .8).floor(),
      );
      encoded = img.encodeJpg(photo, quality: quality);
    }
    final thumbnail = img.encodeJpg(_resize(photo, 160), quality: 76);
    if (encoded.length > memoryPhotoByteLimit ||
        thumbnail.length > memoryThumbnailByteLimit) {
      throw const MemoryPhotoException(
        'Зургийг бэлтгэж чадсангүй. Өөр зураг сонгоорой.',
      );
    }
    return MemoryPhoto(photo: encoded, thumbnail: thumbnail);
  } on MemoryPhotoException {
    rethrow;
  } catch (_) {
    throw const MemoryPhotoException(
      'Энэ зургийг нээж чадсангүй. Өөр зураг сонгоорой.',
    );
  }
}

img.Image _resize(img.Image source, int longest) {
  final edge = math.max(source.width, source.height);
  if (edge <= longest) return source;
  return img.copyResize(
    source,
    width: math.max(1, (source.width * longest / edge).round()),
    height: math.max(1, (source.height * longest / edge).round()),
    interpolation: img.Interpolation.average,
  );
}
