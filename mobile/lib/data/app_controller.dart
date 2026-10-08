import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../content/content_repository.dart';

import 'app_store.dart';
import 'models.dart';

export 'app_store.dart';
export 'models.dart';

part 'app_cloud.dart';

class AppController extends ChangeNotifier {
  AppController(this._store);

  final AppStore _store;
  Future<void> Function(List<DateEvent>)? onEventsChanged;
  String? reminderError;
  ContentRepository? _cloud;
  final Map<String, ContentItem> _items = {};
  final Map<String, Uint8List> _media = {};
  final Map<String, String> _commands = {};
  final Map<String, int?> _commandVersions = {};
  final Map<String, int> _mediaFetching = {};
  final Set<String> _mediaFailed = {};
  final Map<String, _PendingContentSave> _pendingSaves = {};
  final Map<String, ContentItem> _pendingDeletes = {};
  _CloudMutation? _cloudMutation;
  Timer? _cloudTimer, _leaseTimer;
  bool _foreground = true, _cloudLoading = false;
  String? cloudError;
  int _cloudEpoch = 0;
  final Set<String> _readNotices = {};
  final List<AppNotice> _cloudNotices = [];

  AppData _data = AppData();
  bool _loaded = false;
  bool _disposed = false;
  bool _deletingAccount = false;
  Future<void> _pending = Future<void>.value();

  AppData get data => _visibleData();
  bool get loaded => _loaded;
  Directory? get storageDirectory =>
      _store is FileBackedAppStore ? _store.directory : null;

  /// Export the private cache, never the merged partner projection.
  Future<AppData> exportOwnSnapshot() async {
    await _pending;
    _ensureNotDisposed();
    return cloudAvailable ? _cacheOwn(_data) : _data;
  }

  /// Blocks new writes and drains preceding ones before local account erasure.
  Future<void> freezeForAccountDeletion() async {
    _deletingAccount = true;
    _cloudTimer?.cancel();
    _leaseTimer?.cancel();
    setCloudForeground(false);
    await _pending;
    _data = AppData();
    _notifyIfActive();
  }

  Future<void> load() => _enqueue(() async {
    _ensureNotDisposed();
    final snapshot = await _store.read();
    _data = snapshot;
    _readNotices.addAll(snapshot.notices.where((n) => n.read).map((n) => n.id));
    _loaded = true;
    _notifyIfActive();
  });

  Future<void> saveEvent(DateEvent event) => _mutate((current) {
    _validateId(event.id);
    final title = _validatedTitle(event.title);
    final normalized = event.copyWith(
      title: title,
      startsAt: localDateTime(event.startsAt),
      createdAt: localDateTime(event.createdAt),
      place: event.place.trim(),
      note: event.note.trim(),
    );
    return current.copyWith(
      events: _upsert(current.events, normalized, (item) => item.id),
    );
  });

  Future<void> deleteEvent(String id) => _mutate((current) {
    _validateId(id);
    return current.copyWith(
      events: current.events.where((event) => event.id != id).toList(),
      memories: current.memories
          .map(
            (memory) =>
                memory.eventId == id ? memory.copyWith(eventId: null) : memory,
          )
          .toList(),
    );
  });

  Future<void> saveMemory(MemoryEntry memory) => _mutate((current) {
    _validateId(memory.id);
    final title = _validatedTitle(memory.title);
    if (memory.eventId != null &&
        !data.events.any((event) => event.id == memory.eventId)) {
      throw ArgumentError('The linked event no longer exists.');
    }
    final normalized = memory.copyWith(
      title: title,
      date: localCalendarDay(memory.date),
      text: memory.text.trim(),
    );
    return current.copyWith(
      memories: _upsert(current.memories, normalized, (item) => item.id),
    );
  });

  Future<void> deleteMemory(String id) => _mutate((current) {
    _validateId(id);
    return current.copyWith(
      memories: current.memories.where((memory) => memory.id != id).toList(),
    );
  });

  Future<void> savePlace(PlaceEntry place) => _mutate((current) {
    _validateId(place.id);
    final normalized = PlaceEntry.fromJson(
      place
          .copyWith(
            name: _validatedTitle(place.name),
            address: place.address.trim(),
            note: place.note.trim(),
          )
          .toJson(),
    );
    return current.copyWith(
      places: _upsert(current.places, normalized, (p) => p.id),
    );
  });

  Future<void> deletePlace(String id) => _mutate(
    (current) => current.copyWith(
      places: current.places.where((p) => p.id != id).toList(),
      memories: current.memories
          .map((m) => m.placeId == id ? m.copyWith(placeId: null) : m)
          .toList(),
    ),
  );

  Future<void> toggleMemoryLike(String id) => cloudAvailable
      ? _cloudSocial(
          id,
          liked: !data.memories.firstWhere((m) => m.id == id).likedByMe,
        )
      : _mutate(
          (current) => current.copyWith(
            memories: current.memories
                .map(
                  (m) => m.id == id
                      ? m.copyWith(
                          likedByMe: !m.likedByMe,
                          likeCount: (m.likeCount + (m.likedByMe ? -1 : 1))
                              .clamp(0, 2),
                        )
                      : m,
                )
                .toList(),
          ),
        );

  Future<void> addMemoryComment(String id, String text) => cloudAvailable
      ? _cloudSocial(id, text: text)
      : _mutate((current) {
          final value = text.trim();
          if (value.isEmpty || value.length > 1000)
            throw ArgumentError('Сэтгэгдэл 1–1000 тэмдэгт байна.');
          if (!current.memories.any((m) => m.id == id))
            throw StateError('Дурсамж олдсонгүй.');
          final comment = MemoryComment(
            id: newLocalId(),
            authorName: current.profile.name.isEmpty
                ? 'Би'
                : current.profile.name,
            text: value,
            createdAt: DateTime.now(),
          );
          return current.copyWith(
            memories: current.memories
                .map(
                  (m) => m.id == id
                      ? m.copyWith(comments: [...m.comments, comment])
                      : m,
                )
                .toList(),
          );
        });

  Future<void> saveInvitation(DateInvitation invitation) => _mutate((current) {
    DateInvitation.fromJson(invitation.toJson());
    return current.copyWith(
      gifts: current.gifts.copyWith(
        invitations: _upsert(
          current.gifts.invitations,
          invitation,
          (i) => i.id,
        ),
      ),
    );
  });

  Future<void> deleteInvitation(String id) => _mutate(
    (current) => current.copyWith(
      gifts: current.gifts.copyWith(
        invitations: current.gifts.invitations
            .where((i) => i.id != id)
            .toList(),
      ),
    ),
  );

  Future<void> saveGreeting(FlowerGreeting greeting) => _mutate((current) {
    FlowerGreeting.fromJson(greeting.toJson());
    return current.copyWith(
      gifts: current.gifts.copyWith(
        greetings: _upsert(current.gifts.greetings, greeting, (g) => g.id),
      ),
    );
  });

  Future<void> toggleFavoriteIdea(String id) => _mutate((current) {
    _validateId(id);
    final favorites = current.gifts.favoriteIdeaIds.toSet();
    if (!favorites.add(id)) favorites.remove(id);
    return current.copyWith(
      gifts: current.gifts.copyWith(favoriteIdeaIds: favorites.toList()),
    );
  });

  Future<void> markNoticeRead(String id) async {
    final notice = data.notices.where((n) => n.id == id).firstOrNull;
    if (notice == null) return;
    await _mutate(
      (current) => current.copyWith(
        notices: _upsert(
          current.notices,
          AppNotice(
            id: id,
            title: 'Мэдэгдэл',
            body: '',
            createdAt: notice.createdAt,
            kind: 'read-marker',
            sourceId: '',
            read: true,
          ),
          (n) => n.id,
        ),
      ),
    );
    _readNotices.add(id);
    _notifyIfActive();
  }

  Future<void> updateProfile(UserProfile profile) => _mutate((current) {
    final since = profile.togetherSince == null
        ? null
        : localCalendarDay(profile.togetherSince!);
    if (since != null && since.isAfter(localCalendarDay(DateTime.now()))) {
      throw ArgumentError('Together-since date cannot be in the future.');
    }
    return current.copyWith(
      profile: profile.copyWith(
        name: profile.name.trim(),
        togetherSince: since,
      ),
    );
  });

  Future<void> _mutate(AppData Function(AppData) change) => _enqueue(() async {
    _ensureNotDisposed();
    if (!_loaded) throw StateError('Load app data before changing it.');
    final next = change(_data);
    final synced = await _syncChanges(_data, next);
    await _store.write(synced);
    _commitCloudChanges();
    _data = synced;
    try {
      await onEventsChanged?.call(_data.events);
      reminderError = null;
    } catch (_) {
      reminderError = 'Болзоо хадгалагдсан ч сануулга тохируулж чадсангүй.';
    }
    _notifyIfActive();
  });

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    // A failed operation is returned to its caller but cannot poison the queue.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('App controller has been disposed.');
    if (_deletingAccount) throw StateError('Account deletion is in progress.');
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cloudEpoch++;
    _cloudTimer?.cancel();
    _leaseTimer?.cancel();
    _media.clear();
    _items.clear();
    _commands.clear();
    _commandVersions.clear();
    _pendingSaves.clear();
    _pendingDeletes.clear();
    _cloudMutation = null;
    _mediaFailed.clear();
    super.dispose();
  }
}

void _validateId(String id) {
  if (id.trim().isEmpty || id != id.trim()) {
    throw ArgumentError(
      'A record must have a nonblank ID without outer spaces.',
    );
  }
}

String _validatedTitle(String value) {
  final title = value.trim();
  if (title.isEmpty) throw ArgumentError('A title is required.');
  return title;
}

List<T> _upsert<T>(List<T> existing, T value, String Function(T) idOf) {
  final id = idOf(value);
  final index = existing.indexWhere((item) => idOf(item) == id);
  final result = List<T>.of(existing);
  if (index < 0) {
    result.add(value);
  } else {
    result[index] = value;
  }
  return result;
}
