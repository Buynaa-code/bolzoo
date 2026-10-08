import '../data/app_controller.dart';
import '../features/gifts/gift_gateway.dart';
import 'content_repository.dart';

class SupabaseGiftGateway implements GiftGateway {
  SupabaseGiftGateway(this.controller, this.repository);
  final AppController controller;
  final ContentRepository repository;
  @override
  String get currentUserId => repository.userId;
  @override
  Future<List<DateInvitation>> list() async {
    await controller.refreshCloud();
    if (controller.cloudError != null)
      throw const GiftGatewayException(
        'Урилгыг шинэчилж чадсангүй. Дахин оролдоно уу.',
      );
    return controller.data.gifts.invitations
        .where((i) => i.state != InvitationState.draft)
        .toList();
  }

  @override
  Future<DateInvitation> publish(
    DateInvitation draft, {
    required String commandId,
  }) async {
    try {
      final epoch = controller.cloudEpoch;
      if (!identical(controller.contentRepository, repository)) {
        throw const ContentException('stale_response');
      }
      final p = draft.toJson()
        ..removeWhere(
          (key, _) => {
            'id',
            'state',
            'creatorId',
            'recipientId',
            'version',
            'proposedAt',
            'shareUrl',
          }.contains(key),
        );
      final item = await repository.save(
        commandId: commandId,
        id: draft.id,
        kind: 'invitation',
        payload: p,
        shared: true,
        expectedVersion: draft.state == InvitationState.draft
            ? null
            : draft.version,
      );
      await controller.acceptContentItem(item, epoch: epoch);
      return controller.invitationFromItem(item);
    } catch (e) {
      throw GiftGatewayException(e.toString());
    }
  }

  @override
  Future<DateInvitation> respond(
    DateInvitation invitation, {
    required InvitationResponse response,
    required String commandId,
    DateTime? proposedAt,
  }) async {
    try {
      final epoch = controller.cloudEpoch;
      if (!identical(controller.contentRepository, repository)) {
        throw const ContentException('stale_response');
      }
      final item = await repository.respond(
        commandId: commandId,
        id: invitation.id,
        expectedVersion: invitation.version,
        action: response == InvitationResponse.accept ? 'accept' : 'propose',
        proposedAt: proposedAt,
      );
      await controller.acceptContentItem(item, epoch: epoch);
      return controller.invitationFromItem(item);
    } catch (e) {
      throw GiftGatewayException(e.toString());
    }
  }
}
