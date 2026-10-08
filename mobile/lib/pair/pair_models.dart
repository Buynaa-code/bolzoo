import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class PairPerson {
  const PairPerson({required this.userId, required this.displayName});
  final String userId;
  final String displayName;

  factory PairPerson.fromJson(Map<String, dynamic> json) => PairPerson(
    userId: json['user_id'] as String,
    displayName: json['display_name'] as String,
  );
}

class PairProfile extends PairPerson {
  const PairProfile({
    required super.userId,
    required super.displayName,
    required this.version,
  });
  final int version;

  factory PairProfile.fromJson(Map<String, dynamic> json) => PairProfile(
    userId: json['user_id'] as String,
    displayName: json['display_name'] as String,
    version: (json['version'] as num).toInt(),
  );
}

class ActivePair {
  const ActivePair({
    required this.id,
    required this.version,
    required this.partner,
  });
  final String id;
  final int version;
  final PairPerson partner;

  factory ActivePair.fromJson(Map<String, dynamic> json) => ActivePair(
    id: json['id'] as String,
    version: (json['version'] as num).toInt(),
    partner: PairPerson.fromJson(json['partner'] as Map<String, dynamic>),
  );
}

class PairInvitation {
  const PairInvitation({
    required this.id,
    required this.version,
    required this.state,
    required this.role,
    required this.creator,
    required this.expiresAt,
    this.requester,
  });
  final String id;
  final int version;
  final String state;
  final String role;
  final PairPerson creator;
  final PairPerson? requester;
  final DateTime expiresAt;

  bool get isCreator => role == 'creator';
  bool get isPending => state == 'awaiting_creator';
  bool get isOpen => state == 'open';

  factory PairInvitation.fromJson(Map<String, dynamic> json) => PairInvitation(
    id: json['id'] as String,
    version: (json['version'] as num).toInt(),
    state: json['state'] as String,
    role: json['role'] as String,
    creator: PairPerson.fromJson(json['creator'] as Map<String, dynamic>),
    requester: json['requester'] == null
        ? null
        : PairPerson.fromJson(json['requester'] as Map<String, dynamic>),
    expiresAt: DateTime.parse(json['expires_at'] as String),
  );
}

class PairSnapshot {
  const PairSnapshot({
    required this.serverTime,
    required this.profile,
    required this.invitations,
    this.pair,
  });
  final DateTime serverTime;
  final PairProfile profile;
  final ActivePair? pair;
  final List<PairInvitation> invitations;

  factory PairSnapshot.fromJson(Map<String, dynamic> json) => PairSnapshot(
    serverTime: DateTime.parse(json['server_time'] as String),
    profile: PairProfile.fromJson(json['profile'] as Map<String, dynamic>),
    pair: json['pair'] == null
        ? null
        : ActivePair.fromJson(json['pair'] as Map<String, dynamic>),
    invitations: List.unmodifiable(
      (json['invitations'] as List).map(
        (item) => PairInvitation.fromJson(item as Map<String, dynamic>),
      ),
    ),
  );
}

enum PairCommandKind { create, request, confirm, close, unlink, updateName }

/// Memory-only command. A retry reuses this exact ID and immutable payload.
/// No toString override: token-bearing parameters must not enter diagnostics.
class PairCommand {
  PairCommand._(this.kind, this.rpc, Map<String, dynamic> parameters, {
    this.inviteToken,
  }) : parameters = Map.unmodifiable(parameters);

  final PairCommandKind kind;
  final String rpc;
  final Map<String, dynamic> parameters;
  final String? inviteToken;

  factory PairCommand.create() {
    final token = base64UrlEncode(_randomBytes(32)).replaceAll('=', '');
    return PairCommand._(
      PairCommandKind.create,
      'hamtdaa_create_pair_invite',
      {
        'p_command_id': _commandId(),
        'p_token_hash': sha256.convert(utf8.encode(token)).toString(),
      },
      inviteToken: token,
    );
  }

  factory PairCommand.request(String token, int version) => PairCommand._(
    PairCommandKind.request,
    'hamtdaa_request_pair',
    {
      'p_command_id': _commandId(),
      'p_token': token,
      'p_expected_version': version,
    },
  );

  factory PairCommand.confirm(PairInvitation invitation) => PairCommand._(
    PairCommandKind.confirm,
    'hamtdaa_confirm_pair',
    {
      'p_command_id': _commandId(),
      'p_invitation_id': invitation.id,
      'p_expected_version': invitation.version,
    },
  );

  factory PairCommand.close(PairInvitation invitation, String action) {
    if (!const {'revoke', 'decline', 'cancel'}.contains(action)) {
      throw ArgumentError.value(action, 'action');
    }
    return PairCommand._(
      PairCommandKind.close,
      'hamtdaa_close_pair_invite',
      {
        'p_command_id': _commandId(),
        'p_invitation_id': invitation.id,
        'p_expected_version': invitation.version,
        'p_action': action,
      },
    );
  }

  factory PairCommand.unlink(ActivePair pair) => PairCommand._(
    PairCommandKind.unlink,
    'hamtdaa_unlink_pair',
    {
      'p_command_id': _commandId(),
      'p_pair_id': pair.id,
      'p_expected_version': pair.version,
    },
  );

  // The existing profile RPC uses optimistic versioning, not command receipts.
  // On an ambiguous network result the next status read reconciles the name.
  factory PairCommand.updateName(String name, int version) => PairCommand._(
    PairCommandKind.updateName,
    'hamtdaa_update_profile',
    {'p_display_name': name.trim(), 'p_expected_version': version},
  );

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List.generate(length, (_) => random.nextInt(256));
  }

  static String _commandId() {
    final bytes = _randomBytes(16);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class PairFailure implements Exception {
  const PairFailure(this.code, {this.retryable = false});
  final String code;
  final bool retryable;
  bool get isAuth => code == 'unauthenticated' || code == 'forbidden';

  String get message => switch (code) {
    'unauthenticated' => 'Нэвтрэлт дууссан байна. Дахин нэвтрээрэй.',
    'forbidden' => 'Энэ үйлдлийг хийх эрх өөрчлөгдсөн байна.',
    'conflict' => 'Мэдээлэл өөрчлөгдсөн байна. Шинэчилж хараад дахин сонгоорой.',
    'already_paired' => 'Та эсвэл нөгөө хүн аль хэдийн хосоор холбогдсон байна.',
    'not_found' || 'expired' => 'Урилга хүчингүй эсвэл хугацаа нь дууссан байна.',
    'invalid_state' => 'Энэ хүсэлтийн төлөв өөрчлөгдсөн байна. Шинэчилж шалгаарай.',
    'rate_limited' => 'Олон хүсэлт илгээлээ. Түр хүлээгээд дахин оролдоорой.',
    'validation' => 'Оруулсан мэдээллээ шалгаарай.',
    'idempotency_mismatch' => 'Хүсэлтийг баталгаажуулж чадсангүй. Шинэчилж шалгаарай.',
    _ => 'Холболтыг шалгаж чадсангүй. Интернэтээ шалгаад дахин оролдоорой.',
  };

  @override
  String toString() => 'PairFailure($code)';
}
