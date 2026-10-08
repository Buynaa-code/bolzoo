part of 'app_controller.dart';

extension AppCloud on AppController {
  bool get cloudAvailable => _cloud != null;
  int get cloudEpoch => _cloudEpoch;
  bool hasRemoteItem(String id) => _items[id]?.deleted == false;
  String? get currentUserId => _cloud?.userId;
  bool isPartnerItem(String id) => _items[id]?.partner == true;
  bool canEdit(String id) => !isPartnerItem(id);
  String ownerName(String id) => _items[id]?.ownerName ?? data.profile.name;
  String consentState(String id) =>
      _items[id]?.payload['status'] as String? ?? 'active';
  DateTime? proposedEventTime(String id) {
    final item = _items[id];
    if (item == null ||
        item.deleted ||
        item.kind != 'event' ||
        item.payload['status'] != 'proposed')
      return null;
    final value = item.payload['proposedAt'];
    return value is String ? DateTime.tryParse(value)?.toLocal() : null;
  }

  Uint8List? mediaBytes(String key) => _media[key];
  ContentRepository? get contentRepository => _cloud;

  void connectCloud(ContentRepository repository) {
    if (identical(_cloud, repository)) return;
    if (_cloud != null && _cloud!.userId != repository.userId) {
      throw StateError('An AppController belongs to one account.');
    }
    _clearShared();
    _commands.clear();
    _commandVersions.clear();
    _pendingSaves.clear();
    _pendingDeletes.clear();
    _cloudMutation = null;
    _cloud = repository;
    _cloudTimer?.cancel();
    _cloudTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_foreground) unawaited(refreshCloud());
    });
    unawaited(refreshCloud());
  }

  bool _current(ContentRepository repository, int epoch) =>
      !_disposed &&
      !_deletingAccount &&
      _foreground &&
      identical(_cloud, repository) &&
      epoch == _cloudEpoch;

  void _requireCurrent(ContentRepository repository, int epoch) {
    if (!_current(repository, epoch))
      throw const ContentException('stale_response');
  }

  void setCloudForeground(bool foreground) {
    if (_deletingAccount && foreground) return;
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      _clearShared();
    } else {
      unawaited(refreshCloud());
    }
  }

  /// Revoke the current projection immediately after a pair change.
  void invalidateSharedContent() {
    _clearShared();
    unawaited(refreshCloud());
  }

  void _clearShared() {
    _cloudEpoch++;
    // Own shared records also carry a partner's comments and reactions. Only
    // the sanitized own cache may survive a lost lease or background transition.
    _items.clear();
    _media.clear();
    _mediaFailed.clear();
    _cloudNotices.clear();
    _cloudMutation?.items.clear();
    _cloudMutation?.media.clear();
    _leaseTimer?.cancel();
    _notifyIfActive();
  }

  Future<void> refreshCloud() async {
    final repository = _cloud;
    if (repository == null ||
        _cloudLoading ||
        _disposed ||
        _deletingAccount ||
        !_foreground)
      return;
    final epoch = _cloudEpoch;
    _cloudLoading = true;
    try {
      await _enqueue(() => _refreshSnapshot(repository, epoch));
    } catch (_) {
      if (_current(repository, epoch)) {
        cloudError =
            'Шинэчилж чадсангүй. Өөрийн хадгалсан мэдээлэл харагдаж байна.';
        _clearShared();
      }
    } finally {
      _cloudLoading = false;
      _notifyIfActive();
      // A foreground transition while a previous request was running must
      // start a fresh lease, not wait for the periodic timer.
      if (!_disposed &&
          _foreground &&
          epoch != _cloudEpoch &&
          _items.isEmpty &&
          cloudError == null) {
        unawaited(refreshCloud());
      }
    }
  }

  Future<void> _refreshSnapshot(ContentRepository repository, int epoch) async {
    if (!_current(repository, epoch)) return;
    final records = await repository.snapshot();
    if (!_current(repository, epoch)) return;
    final own = _cacheOwn(_data, items: records);
    await _store.write(own);
    if (!_current(repository, epoch)) return;
    final previous = Map<String, ContentItem>.from(_items);
    _data = own;
    _items
      ..clear()
      ..addEntries(records.map((i) => MapEntry(i.id, i)));
    _pruneMedia();
    _mediaFailed.clear();
    for (final item in records.where((i) => !i.deleted && i.pairId != null)) {
      final old = previous[item.id];
      final status = item.payload['status'];
      if (item.partner ||
          (old != null &&
              old.payload['status'] != status &&
              status == 'accepted')) {
        final id = '${item.id}:${item.version}';
        if (!_cloudNotices.any((n) => n.id == id)) {
          _cloudNotices.add(
            AppNotice(
              id: id,
              title: status == 'accepted'
                  ? 'Урилгыг зөвшөөрлөө'
                  : item.kind == 'memory'
                  ? 'Шинэ дурсамж'
                  : item.kind == 'invitation'
                  ? 'Болзооны урилга'
                  : 'Хамтын мэдээлэл',
              body:
                  item.payload['title'] as String? ??
                  item.payload['name'] as String? ??
                  'Шинэ мэдээлэл нэмэгдлээ',
              createdAt: item.updatedAt.toLocal(),
              kind: item.kind,
              sourceId: item.id,
              read: _readNotices.contains(id),
            ),
          );
        }
      }
    }
    _cloudNotices.removeWhere(
      (n) => !_items.containsKey(n.sourceId) || _items[n.sourceId]!.deleted,
    );
    if (_cloudNotices.length > 100)
      _cloudNotices.removeRange(0, _cloudNotices.length - 100);
    cloudError = null;
    _leaseTimer?.cancel();
    _leaseTimer = Timer(const Duration(seconds: 45), _clearShared);
    _notifyIfActive();
    unawaited(_syncCloudReminders(epoch));
    _pumpMedia();
  }

  Future<void> _syncCloudReminders(int epoch) async {
    try {
      await onEventsChanged?.call(_data.events);
      if (!_disposed && epoch == _cloudEpoch) reminderError = null;
    } catch (_) {
      if (!_disposed && epoch == _cloudEpoch) {
        reminderError = 'Болзоо хадгалагдсан ч сануулга тохируулж чадсангүй.';
        _notifyIfActive();
      }
    }
  }

  void _pruneMedia() {
    final validKeys = _items.values
        .where((i) => !i.deleted)
        .map((i) => i.payload['mediaKey'])
        .whereType<String>()
        .toSet();
    _media.removeWhere((key, _) => !validKeys.contains(key));
  }

  void _pumpMedia() {
    final repository = _cloud;
    if (repository == null || _disposed || !_foreground) return;
    for (final item in _items.values.where((i) => !i.deleted)) {
      if (_mediaFetching.length >= 2) break;
      final key = item.payload['mediaKey'] as String?;
      if (key == null ||
          _media.containsKey(key) ||
          _mediaFetching.containsKey(key) ||
          _mediaFailed.contains(key))
        continue;
      final epoch = _cloudEpoch;
      _mediaFetching[key] = epoch;
      unawaited(_fetchMedia(repository, epoch, item.id, key));
    }
  }

  Future<void> _fetchMedia(
    ContentRepository repository,
    int epoch,
    String id,
    String key,
  ) async {
    try {
      final bytes = await repository
          .downloadPhoto(key)
          .timeout(const Duration(seconds: 20));
      if (_current(repository, epoch) &&
          _items[id]?.deleted == false &&
          _items[id]?.payload['mediaKey'] == key) {
        _media[key] = bytes;
        _notifyIfActive();
      }
    } catch (_) {
      if (_current(repository, epoch)) _mediaFailed.add(key);
    } finally {
      if (_mediaFetching[key] == epoch) _mediaFetching.remove(key);
      _pumpMedia();
    }
  }

  AppData _visibleData() {
    if (_items.isEmpty &&
        _cloudNotices.isEmpty &&
        !_data.notices.any((n) => n.kind == 'read-marker')) {
      return _data;
    }
    var result = _data;
    for (final item in _items.values) {
      result = _apply(result, item, cache: false);
    }
    final notices = {
      ...{
        for (final n in result.notices.where((n) => n.kind != 'read-marker'))
          n.id: n,
      },
      ...{
        for (final n in _cloudNotices)
          n.id: n.copyWith(read: _readNotices.contains(n.id)),
      },
    }.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final eventIds = result.events.map((e) => e.id).toSet();
    final placeIds = result.places.map((p) => p.id).toSet();
    return result.copyWith(
      notices: notices,
      memories: result.memories
          .map(
            (m) => m.copyWith(
              eventId: eventIds.contains(m.eventId) ? m.eventId : null,
              placeId: placeIds.contains(m.placeId) ? m.placeId : null,
            ),
          )
          .toList(),
    );
  }

  AppData _cacheOwn(AppData source, {Iterable<ContentItem>? items}) {
    var result = source;
    for (final item in (items ?? _items.values).where((i) => !i.partner)) {
      result = _apply(result, item, cache: true);
    }
    // Disk contains only this account's records, never partner records or comments.
    final ownIds = result.events.map((e) => e.id).toSet();
    final ownPlaceIds = result.places.map((p) => p.id).toSet();
    return result.copyWith(
      memories: result.memories
          .map(
            (m) => m.copyWith(
              eventId: ownIds.contains(m.eventId) ? m.eventId : null,
              placeId: ownPlaceIds.contains(m.placeId) ? m.placeId : null,
              comments: const [],
              likeCount: 0,
              likedByMe: false,
            ),
          )
          .toList(),
    );
  }

  AppData _apply(AppData source, ContentItem item, {required bool cache}) {
    final p = Map<String, dynamic>.from(item.payload)..['id'] = item.id;
    p['createdAt'] ??= localDateTime(item.updatedAt).toIso8601String();
    if (item.deleted) {
      return source.copyWith(
        events: source.events.where((e) => e.id != item.id).toList(),
        memories: source.memories
            .where((m) => m.id != item.id)
            .map(
              (m) => m.copyWith(
                eventId: m.eventId == item.id ? null : m.eventId,
                placeId: m.placeId == item.id ? null : m.placeId,
              ),
            )
            .toList(),
        places: source.places.where((x) => x.id != item.id).toList(),
        gifts: source.gifts.copyWith(
          invitations: source.gifts.invitations
              .where((x) => x.id != item.id)
              .toList(),
          greetings: source.gifts.greetings
              .where((x) => x.id != item.id)
              .toList(),
        ),
      );
    }
    p['shared'] = item.pairId != null;
    switch (item.kind) {
      case 'event':
        return source.copyWith(
          events: _upsert(source.events, DateEvent.fromJson(p), (e) => e.id),
        );
      case 'memory':
        final old = source.memories.where((m) => m.id == item.id).firstOrNull;
        p['photoPath'] = item.partner ? null : old?.photoPath;
        if (cache) {
          p['comments'] = [];
          p['likeCount'] = 0;
          p['likedByMe'] = false;
        }
        // Some accounts have not chosen a display name yet.
        if (p['comments'] is List)
          p['comments'] = (p['comments'] as List)
              .map(
                (c) => {
                  ...Map<String, dynamic>.from(c as Map),
                  'authorName':
                      (c['authorName'] as String?)?.trim().isNotEmpty == true
                      ? c['authorName']
                      : 'Бид',
                },
              )
              .toList();
        return source.copyWith(
          memories: _upsert(
            source.memories,
            MemoryEntry.fromJson(p),
            (m) => m.id,
          ),
        );
      case 'place':
        return source.copyWith(
          places: _upsert(source.places, PlaceEntry.fromJson(p), (x) => x.id),
        );
      case 'greeting':
        return source.copyWith(
          gifts: source.gifts.copyWith(
            greetings: _upsert(
              source.gifts.greetings,
              FlowerGreeting.fromJson(p),
              (g) => g.id,
            ),
          ),
        );
      case 'invitation':
        final invitation = invitationFromItem(item);
        var events = source.events.where((e) => e.id != item.id).toList();
        if (invitation.state == InvitationState.accepted && !cache)
          events.add(
            DateEvent(
              id: item.id,
              title: invitation.title,
              startsAt: invitation.startsAt,
              createdAt: invitation.createdAt,
              place: invitation.place,
              note: invitation.message,
              shared: true,
              templateId: invitation.templateId,
            ),
          );
        return source.copyWith(
          events: events,
          gifts: source.gifts.copyWith(
            invitations: _upsert(
              source.gifts.invitations,
              invitation,
              (i) => i.id,
            ),
          ),
        );
      default:
        return source;
    }
  }

  DateInvitation invitationFromItem(ContentItem item) {
    final p = Map<String, dynamic>.from(item.payload)
      ..addAll({
        'id': item.id,
        'state': item.payload['status'] ?? 'pending',
        'creatorId': item.ownerId,
        'recipientId': item.partner ? currentUserId : null,
        'version': item.version,
        'shareUrl': null,
      });
    return DateInvitation.fromJson(p);
  }

  Future<void> acceptContentItem(ContentItem item, {int? epoch}) {
    final captured = epoch ?? _cloudEpoch;
    final repository = _cloud;
    return _enqueue(() async {
      if (repository == null) throw const ContentException('stale_response');
      _requireCurrent(repository, captured);
      final existing = _items[item.id];
      if (existing != null && existing.revision > item.revision) return;
      final next = _cacheOwn(
        _data,
        items: [..._items.values.where((i) => i.id != item.id), item],
      );
      await _store.write(next);
      _requireCurrent(repository, captured);
      _items[item.id] = item;
      _pruneMedia();
      _data = next;
      _notifyIfActive();
      unawaited(_syncCloudReminders(captured));
      _pumpMedia();
    });
  }

  Future<ContentItem> _command(
    String signature,
    int? version,
    Future<ContentItem> Function(String command, int? version) action,
  ) async {
    final command = _commands.putIfAbsent(signature, () => const Uuid().v4());
    final expected = _commandVersions.putIfAbsent(signature, () => version);
    try {
      final item = await action(command, expected);
      return item;
    } on ContentException catch (error) {
      // Uncertain writes replay their original receipt and original version,
      // even if a metadata refresh has observed the first successful attempt.
      if (!const {
        'network',
        'media_upload',
        'media_download',
        'rate_limited',
        'conflict',
        'stale_response',
      }.contains(error.code)) {
        _commands.remove(signature);
        _commandVersions.remove(signature);
      }
      rethrow;
    }
  }

  void _forgetCommand(String signature) {
    _commands.remove(signature);
    _commandVersions.remove(signature);
  }

  ContentItem _receiptWithoutSocial(ContentItem item) => ContentItem.fromJson({
    'id': item.id,
    'kind': item.kind,
    'owner_id': item.ownerId,
    'owner_name': item.ownerName,
    'pair_id': item.pairId,
    'version': item.version,
    'revision': item.revision,
    'state': item.deleted ? 'deleted' : 'active',
    'role': item.partner ? 'partner' : 'owner',
    'updated_at': item.updatedAt.toIso8601String(),
    'payload': {...item.payload}
      ..removeWhere(
        (key, _) => const {'comments', 'likeCount', 'likedByMe'}.contains(key),
      ),
  });

  Future<void> _cloudSocial(String id, {bool? liked, String? text}) =>
      _enqueue(() async {
        if (text != null && (text.trim().isEmpty || text.trim().length > 1000))
          throw ArgumentError('Сэтгэгдэл 1–1000 тэмдэгт байна.');
        final repository = _cloud;
        final epoch = _cloudEpoch;
        if (repository == null || !_foreground || !_items.containsKey(id))
          throw const ContentException('not_found');
        final signature = jsonEncode(['social', id, liked, text?.trim()]);
        final item = await _command(
          signature,
          null,
          (command, _) => liked != null
              ? repository.react(commandId: command, id: id, liked: liked)
              : repository.comment(
                  commandId: command,
                  id: id,
                  text: text!.trim(),
                ),
        );
        _requireCurrent(repository, epoch);
        _items[id] = item;
        _forgetCommand(signature);
        _notifyIfActive();
      });

  Future<void> respondToEvent(
    String id, {
    required bool accept,
    DateTime? proposedAt,
  }) async {
    final item = _items[id];
    final repository = _cloud;
    final epoch = _cloudEpoch;
    if (repository == null || item == null || !_foreground)
      throw const ContentException('not_found');
    final signature = jsonEncode([
      'respond',
      id,
      accept,
      proposedAt?.toIso8601String(),
    ]);
    final result = await _command(
      signature,
      item.version,
      (command, version) => repository.respond(
        commandId: command,
        id: id,
        expectedVersion: version!,
        action: accept ? 'accept' : 'propose',
        proposedAt: proposedAt,
      ),
    );
    _requireCurrent(repository, epoch);
    await acceptContentItem(result, epoch: epoch);
    _forgetCommand(signature);
  }

  bool isInvitationEvent(String id) => _items[id]?.kind == 'invitation';

  Future<AppData> _syncChanges(AppData before, AppData next) async {
    _cloudMutation = null;
    final repository = _cloud;
    if (repository == null) return next;
    final epoch = _cloudEpoch;
    final mutation = _CloudMutation(repository, epoch, Map.of(_items));
    _requireCurrent(repository, epoch);
    Map<String, ({String kind, Map<String, Object?> json, bool shared})>
    records(AppData d) => {
      for (final e in d.events)
        e.id: (kind: 'event', json: e.toJson(), shared: e.shared),
      for (final m in d.memories)
        m.id: (kind: 'memory', json: m.toJson(), shared: m.shared),
      for (final p in d.places)
        p.id: (kind: 'place', json: p.toJson(), shared: p.shared),
      for (final g in d.gifts.greetings)
        g.id: (kind: 'greeting', json: g.toJson(), shared: false),
    };
    final old = records(before), updated = records(next);
    for (final id in {...old.keys, ...updated.keys}) {
      final prior = old[id], fresh = updated[id];
      if (jsonEncode(prior?.json) == jsonEncode(fresh?.json)) continue;
      _requireCurrent(repository, epoch);
      if (isPartnerItem(id)) throw const ContentException('forbidden');
      final remote = _items[id];
      if (fresh == null) {
        if (remote != null && !remote.deleted) {
          final signature = jsonEncode(['delete', id]);
          final item = _pendingDeletes[id] ??= await _command(
            signature,
            remote.version,
            (command, version) => repository.delete(
              commandId: command,
              id: id,
              expectedVersion: version!,
            ),
          );
          _requireCurrent(repository, epoch);
          mutation.items[id] = item;
          mutation.deletedIds.add(id);
          mutation.commands.add(signature);
        }
        continue;
      }
      final payload = Map<String, Object?>.from(fresh.json)
        ..removeWhere(
          (key, _) => {
            'id',
            'shared',
            'photoPath',
            'likedByMe',
            'likeCount',
            'comments',
          }.contains(key),
        );
      // Keep the whole upload intent across failure. Metadata, upload, and media
      // attachment are distinct operations, and each completed stage is reused.
      final signature = jsonEncode([
        'save',
        id,
        fresh.kind,
        payload,
        fresh.shared,
        fresh.json['photoPath'],
      ]);
      final pending = _pendingSaves.putIfAbsent(
        signature,
        () => _PendingContentSave(remote?.version),
      );
      try {
        if (pending.base == null) {
          pending.base = _receiptWithoutSocial(
            await _command(
              signature,
              pending.expectedVersion,
              (command, version) => repository.save(
                commandId: command,
                id: id,
                kind: fresh.kind,
                payload: payload,
                shared: fresh.shared,
                expectedVersion: version,
              ),
            ),
          );
        }
        _requireCurrent(repository, epoch);
        var item = pending.base!;
        final path = fresh.json['photoPath'] as String?;
        final needsPhoto =
            fresh.kind == 'memory' &&
            path != null &&
            (payload['mediaKey'] == null || path != prior?.json['photoPath']);
        if (needsPhoto) {
          final file = File(path);
          if (!await file.exists())
            throw const ContentException('media_missing');
          final bytes = await file.readAsBytes();
          if (bytes.length > 10 * 1024 * 1024)
            throw const ContentException('media_too_large');
          final ext = bytes.length > 3 && bytes[0] == 0xff && bytes[1] == 0xd8
              ? 'jpg'
              : bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50
              ? 'png'
              : 'webp';
          pending.mediaKey ??= await repository.uploadPhoto(id, bytes, ext);
          _requireCurrent(repository, epoch);
          payload['mediaKey'] = pending.mediaKey;
          pending.attached ??= _receiptWithoutSocial(
            await _command(
              '$signature:media',
              pending.base!.version,
              (command, version) => repository.save(
                commandId: command,
                id: id,
                kind: 'memory',
                payload: payload,
                shared: fresh.shared,
                expectedVersion: version,
              ),
            ),
          );
          item = pending.attached!;
          _requireCurrent(repository, epoch);
          mutation.media[pending.mediaKey!] = bytes;
        }
        final current = mutation.items[id];
        mutation.items[id] = current != null && current.revision > item.revision
            ? current
            : item;
        mutation.saves.add(signature);
        mutation.commands.addAll([signature, '$signature:media']);
      } on ContentException catch (error) {
        if (!const {
          'network',
          'media_upload',
          'media_download',
          'rate_limited',
          'conflict',
          'stale_response',
        }.contains(error.code))
          _pendingSaves.remove(signature);
        rethrow;
      }
    }
    _cloudMutation = mutation;
    return _cacheOwn(next, items: mutation.items.values);
  }

  void _commitCloudChanges() {
    final mutation = _cloudMutation;
    if (mutation == null) return;
    _requireCurrent(mutation.repository, mutation.epoch);
    _items
      ..clear()
      ..addAll(mutation.items);
    _media.addAll(mutation.media);
    _pruneMedia();
    for (final signature in mutation.commands) {
      _forgetCommand(signature);
    }
    for (final signature in mutation.saves) {
      _pendingSaves.remove(signature);
    }
    for (final id in mutation.deletedIds) {
      _pendingDeletes.remove(id);
    }
    _cloudMutation = null;
  }
}

class _PendingContentSave {
  _PendingContentSave(this.expectedVersion);
  final int? expectedVersion;
  ContentItem? base, attached;
  String? mediaKey;
}

class _CloudMutation {
  _CloudMutation(this.repository, this.epoch, this.items);
  final ContentRepository repository;
  final int epoch;
  final Map<String, ContentItem> items;
  final Map<String, Uint8List> media = {};
  final Set<String> commands = {}, saves = {}, deletedIds = {};
}
