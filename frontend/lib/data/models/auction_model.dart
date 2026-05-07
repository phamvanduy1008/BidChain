import '../../domain/entities/auction_entity.dart';
import '../../core/services/server_time_service.dart';

class AuctionModel extends AuctionEntity {
  const AuctionModel({
    required super.auctionId,
    required super.seller,
    required super.startingPrice,
    required super.highestBid,
    required super.highestBidder,
    super.startTime,
    required super.endTime,
    required super.metadataUrl,
    required super.ended,
    super.winner,
    required super.createdAt,
    required super.title,
    required super.description,
    required super.images,
    required super.formattedCurrentPrice,
    required super.sellerName,
    required super.bidCount,
    super.categoryId,
    required super.status,
  });

  factory AuctionModel.fromJson(Map<String, dynamic> json) {
    ServerTimeService().syncFromIso(json['server_time']?.toString());

    return AuctionModel(
      auctionId: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      seller: json['seller_id'] is Map
          ? (json['seller_id']['_id'] ?? '')
          : (json['seller_id'] ?? ''),
      startingPrice: json['start_price']?.toString() ?? '0',
      highestBid: json['current_price']?.toString() ?? '0',
      highestBidder: json['highest_bidder_id'] is Map
          ? (json['highest_bidder_id']['_id'] ?? '')
          : (json['highest_bidder_id'] ?? ''),
      startTime: json['start_time'] != null
          ? DateTime.parse(json['start_time'])
          : null,
      endTime: json['end_time'] != null
          ? DateTime.parse(json['end_time'])
          : DateTime.now(),
      metadataUrl: json['metadata_url'] ?? '',
      ended: json['status'] == 'ENDED' || json['status'] == 'SETTLED',
      winner: json['winner'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      images:
          (json['images'] as List?)?.map((e) => e.toString()).toList() ?? [],
      formattedCurrentPrice: json['formatted_current_price'] ?? '0 VND',
      sellerName: json['seller_id'] is Map
          ? (json['seller_id']['full_name'] ?? 'Unknown')
          : 'Unknown',
      bidCount: json['bid_count'] ?? 0,
      categoryId: json['category_id']?.toString(),
      status: json['status'] ?? 'ACTIVE',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': auctionId,
      'seller_id': seller,
      'start_price': startingPrice,
      'current_price': highestBid,
      'highest_bidder_id': highestBidder,
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'status': status,
      'winner': winner,
      'created_at': createdAt.toIso8601String(),
      'title': title,
      'description': description,
      'images': images,
      'formatted_current_price': formattedCurrentPrice,
      'bid_count': bidCount,
      'category_id': categoryId,
    };
  }
}
