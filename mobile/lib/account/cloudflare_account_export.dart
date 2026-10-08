import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;

import '../cloudflare/cloudflare_auth_repository.dart';
import '../memories/memory_models.dart';
import '../memories/memory_repository.dart';
import '../wishes/wish_models.dart';

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// The profile page is the identity and pair snapshot for the whole export.
String? cloudflareExportPair(
  Map<String, dynamic> page,
  CloudflareCredential credential,
) {
  final account = page['account'];
  if (page['schema_version'] != 1 ||
      page['section'] != 'profile' ||
      account is! Map ||
      account['id'] != credential.scope.userId ||
      !page.containsKey('pair')) {
    throw const FormatException('invalid_export');
  }
  final pair = page['pair'];
  if (pair == null) return null;
  if (pair is! Map ||
      pair['id'] is! String ||
      !_uuid.hasMatch(pair['id'] as String)) {
    throw const FormatException('invalid_export');
  }
  return pair['id'] as String;
}

/// Writes one photo page directly into the ZIP, retaining only bounded account
/// JSON and ZIP directory metadata. Caller erases the unique directory after
/// sharing. Any interrupted or changed scope discards the entire staging area.
Future<Directory> buildCloudflareAccountExport({
  required CloudflareAuthRepository auth,
  required CloudflareCredential credential,
  required List<Map<String, dynamic>> pages,
  required Directory temporaryDirectory,
  required bool Function() isCurrent,
  http.Client? memoryClient,
}) async {
  void check() {
    if (!isCurrent() || !auth.accepts(credential)) {
      throw const FormatException('session_changed');
    }
  }

  check();
  if (pages.isEmpty || pages.length > 200) {
    throw const FormatException('invalid_export');
  }
  final pairId = cloudflareExportPair(pages.first, credential);
  final client = memoryClient ?? http.Client();
  final endpoint = CloudflareMemoryRepository.endpointFor(auth);
  if (endpoint.scheme != 'https' ||
      endpoint.host.isEmpty ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment) {
    if (memoryClient == null) client.close();
    throw const FormatException('invalid_origin');
  }
  Directory? work;
  final encoder = ZipFileEncoder();
  var opened = false;
  Completer<void>? pending;
  final sessions = auth.sessions.listen((_) {
    if (!auth.accepts(credential) && pending?.isCompleted == false) {
      pending!.complete();
    }
  });
  Future<Map<String, dynamic>> page(
    String path,
    Map<String, dynamic> body, {
    int maxBytes = 1200 * 1024,
  }) async {
    check();
    final abort = Completer<void>();
    pending = abort;
    try {
      return await (() async {
        final request = http.AbortableRequest(
          'POST',
          endpoint.resolve(path),
          abortTrigger: abort.future,
        )..followRedirects = false;
        request.headers.addAll({
          'Authorization': 'Bearer ${credential.token}',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Cache-Control': 'no-store',
        });
        request.body = jsonEncode(body);
        final response = await client.send(request);
        check();
        final buffer = BytesBuilder(copy: false);
        var length = 0;
        await for (final chunk in response.stream) {
          check();
          length += chunk.length;
          if (length > maxBytes) throw const FormatException('export_limit');
          buffer.add(chunk);
        }
        check();
        if (response.statusCode == 401) {
          await auth.reject(credential);
          throw const FormatException('session_changed');
        }
        if (response.statusCode != 200) {
          throw const FormatException('private_export_failed');
        }
        final data = jsonDecode(utf8.decode(buffer.takeBytes()));
        if (data is! Map<String, dynamic> || data['ok'] != true) {
          throw const FormatException('invalid_export');
        }
        return data;
      })().timeout(const Duration(seconds: 35));
    } catch (_) {
      check();
      throw const FormatException('private_export_failed');
    } finally {
      if (!abort.isCompleted) abort.complete();
      if (identical(pending, abort)) pending = null;
    }
  }

  try {
    work = await temporaryDirectory.createTemp('hamtdaa-export-');
    check();
    encoder.createWithStream(
      OutputFileStream('${work.path}/hamtdaa-data.zip', bufferSize: 64 * 1024),
    );
    opened = true;
    var count = 0, totalPhotoBytes = 0;
    var wishlist = WishExport(wishes: const [], likedWishIds: const []);
    if (pairId != null) {
      String? cursor;
      do {
        final response = await page('/v1/memories/export', {
          'expected_pair_id': pairId,
          'cursor': ?cursor,
        });
        check();
        final records = response['memories'];
        final next = response['next_cursor'];
        if (records is! List ||
            records.length > 1 ||
            !response.containsKey('next_cursor') ||
            (next != null && (next is! String || !_uuid.hasMatch(next)))) {
          throw const FormatException('invalid_export');
        }
        if (records.isEmpty) {
          if (next != null) throw const FormatException('invalid_cursor');
          break;
        }
        if (++count > 1000 || records.single is! Map) {
          throw const FormatException('export_limit');
        }
        final raw = Map<String, dynamic>.from(records.single as Map);
        final memory = SharedMemory.fromJson(raw);
        if (!_uuid.hasMatch(memory.id) ||
            memory.creatorId != credential.scope.userId ||
            memory.pairId != pairId ||
            memory.title.length > 80 ||
            memory.note.length > 2000 ||
            (cursor != null && memory.id.compareTo(cursor) <= 0) ||
            (next != null && next != memory.id)) {
          throw const FormatException('invalid_export');
        }
        final photo = _jpeg(raw.remove('photo_base64'), 768 * 1024);
        final thumbnail = _jpeg(raw.remove('thumbnail_base64'), 64 * 1024);
        totalPhotoBytes += photo.length + thumbnail.length;
        if (totalPhotoBytes > 900 * 1024 * 1024) {
          throw const FormatException('export_limit');
        }
        final base = 'memories/${count.toString().padLeft(4, '0')}';
        // JPEGs are already compressed. Store directly so no accumulated
        // Archive or extra deflate buffers keep the photo collection in RAM.
        encoder.addArchiveFile(
          ArchiveFile.bytes('$base.jpg', photo)
            ..compression = CompressionType.none,
        );
        encoder.addArchiveFile(
          ArchiveFile.bytes('$base-thumbnail.jpg', thumbnail)
            ..compression = CompressionType.none,
        );
        encoder.addArchiveFile(
          ArchiveFile.string(
            '$base.json',
            jsonEncode({
              'id': memory.id,
              'pair_id': memory.pairId,
              'creator_id': memory.creatorId,
              'day': memory.day,
              'title': memory.title,
              'note': memory.note,
              'sticker': memory.sticker,
              'version': memory.version,
              'created_at': memory.createdAt.toUtc().toIso8601String(),
              'photo': '$base.jpg',
              'thumbnail': '$base-thumbnail.jpg',
            }),
          ),
        );
        cursor = next as String?;
      } while (cursor != null);
      final response = await page('/v1/wishes/export', {
        'expected_pair_id': pairId,
      }, maxBytes: 2 * 1024 * 1024);
      check();
      if (response['pair_id'] != pairId) {
        throw const FormatException('invalid_export');
      }
      wishlist = WishExport.fromJson(
        response,
        pairId: pairId,
        actorId: credential.scope.userId,
      );
    }
    check();
    encoder.addArchiveFile(
      ArchiveFile.string(
        'wishlist.json',
        jsonEncode({
          'scope': 'own_current_pair',
          'pair_id': pairId,
          ...wishlist.toJson(),
        }),
      ),
    );
    encoder.addArchiveFile(
      ArchiveFile.string(
        'records.json',
        jsonEncode({
          'pages': pages,
          'memories': {
            'scope': 'own_current_pair',
            'pair_id': pairId,
            'count': count,
            'directory': 'memories/',
          },
          'wishlist': {
            'scope': 'own_current_pair',
            'pair_id': pairId,
            'count': wishlist.wishes.length,
            'likes_count': wishlist.likedWishIds.length,
            'file': 'wishlist.json',
          },
        }),
      ),
    );
    encoder.addArchiveFile(
      ArchiveFile.string(
        'README.txt',
        'Хамтдаа — миний мэдээлэл\n\n'
            'records.json: бүртгэл, хуанли, өдрийн хариу болон захиалгын мэдээлэл.\n'
            'memories/: одоо холбогдсон хостойгоо үүсгэсэн ӨӨРИЙН дурсамжууд. '
            'Дурсамж бүрийн JSON файл нь зураг, жижиг зурагтайгаа холбогдоно. '
            'Хосын тань оруулсан болон хуучин салсан холбооны дурсамж ороогүй.\n'
            'wishlist.json: одоогийн хосын холбоонд ӨӨРИЙН нэмсэн хүсэл болон '
            'өөрийн зүрх дарсан хүслийн дугаарууд. Хосын тань нэмсэн хүслийн '
            'агуулга, хосын зүрхний мэдээлэл ороогүй.\n'
            'Хосоороо холбогдоогүй бол дурсамж, хүслийн хэсэг хоосон байна.\n'
            'Энэ нь хувийн мэдээллийн хуулбар; апп руу буцааж оруулах боломж одоогоор байхгүй.\n',
      ),
    );
    await encoder.close();
    opened = false;
    check();
    // The account sections also contain currently permitted partner records.
    // A pair change anywhere during the export invalidates the whole archive.
    final verified = await auth.transport.send(
      'POST',
      '/v1/account/export',
      token: credential.token,
      body: const {},
    );
    check();
    if (verified.status == 401) {
      await auth.reject(credential);
      throw const FormatException('session_changed');
    }
    final profile = verified.body['export'];
    if (verified.status != 200 ||
        verified.body['ok'] != true ||
        profile is! Map<String, dynamic> ||
        profile['next_cursor'] != null ||
        !profile.containsKey('next_cursor') ||
        cloudflareExportPair(profile, credential) != pairId) {
      throw const FormatException('pair_changed');
    }
    check();
    return work;
  } catch (_) {
    if (opened) {
      try {
        await encoder.close();
      } catch (_) {}
    }
    if (work != null && await work.exists()) await work.delete(recursive: true);
    rethrow;
  } finally {
    if (pending?.isCompleted == false) pending!.complete();
    await sessions.cancel();
    if (memoryClient == null) client.close();
  }
}

Uint8List _jpeg(Object? raw, int maxBytes) {
  if (raw is! String ||
      raw.isEmpty ||
      raw.length > ((maxBytes + 2) ~/ 3) * 4 ||
      raw.length % 4 != 0 ||
      !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(raw)) {
    throw const FormatException('invalid_photo');
  }
  final bytes = base64Decode(raw);
  if (bytes.length < 4 ||
      bytes.length > maxBytes ||
      bytes[0] != 0xff ||
      bytes[1] != 0xd8 ||
      bytes[bytes.length - 2] != 0xff ||
      bytes.last != 0xd9) {
    throw const FormatException('invalid_photo');
  }
  return bytes;
}
