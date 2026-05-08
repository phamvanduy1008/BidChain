import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/auction_repository.dart';
import 'auction_event.dart';
import 'auction_state.dart';

class AuctionBloc extends Bloc<AuctionEvent, AuctionState> {
  final AuctionRepository repository;

  AuctionBloc({required this.repository}) : super(AuctionInitial()) {
    on<GetAuctions>(_onGetAuctions);
    on<RefreshAuctions>(_onRefreshAuctions);
  }

  Future<void> _onGetAuctions(
    GetAuctions event,
    Emitter<AuctionState> emit,
  ) async {
    emit(AuctionLoading());
    await _loadAuctionData(emit);
  }

  Future<void> _onRefreshAuctions(
    RefreshAuctions event,
    Emitter<AuctionState> emit,
  ) async {
    await _loadAuctionData(emit);
  }

  Future<void> _loadAuctionData(Emitter<AuctionState> emit) async {
    final allResult = await repository.getAuctions();
    final activeResult = await repository.getActiveAuctions();

    allResult.fold(
      (failure) => emit(AuctionError(failure.message)),
      (auctions) {
        activeResult.fold(
          (failure) => emit(AuctionError(failure.message)),
          (activeAuctions) =>
              emit(AuctionLoaded(auctions, activeAuctions: activeAuctions)),
        );
      },
    );
  }
}
