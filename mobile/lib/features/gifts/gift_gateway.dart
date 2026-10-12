import '../../data/gift_models.dart';

/// Server authority for paired invitations. Local previews never grant response rights.
abstract interface class GiftGateway {
  String get currentUserId;
  Future<List<DateInvitation>> list();
  Future<DateInvitation> publish(
    DateInvitation draft, {
    required String commandId,
  });
  Future<DateInvitation> respond(
    DateInvitation invitation, {
    required InvitationResponse response,
    required String commandId,
    DateTime? proposedAt,
  });
}

class GiftGatewayException implements Exception {
  const GiftGatewayException(this.message);
  final String message;
  @override
  String toString() => message;
}
