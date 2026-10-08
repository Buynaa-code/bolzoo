import 'pair_models.dart';

abstract interface class PairRepository {
  Stream<void> get invalidations;
  Future<PairSnapshot> status();
  Future<PairInvitation> preview(String token);
  Future<Map<String, dynamic>> execute(PairCommand command);
  void dispose();
}
