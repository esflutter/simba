import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

enum UserRole { customer, executor }

enum OrderStatus {
  open,
  accepted,
  awaitingPayment,
  completed,
  cancelled,
}

enum PaymentMethod { cash }

@immutable
class City {
  const City({required this.id, required this.name, required this.center});
  final String id;
  final String name;
  final LatLng center;
}

@immutable
class Category {
  const Category({required this.id, required this.name, required this.icon});
  final String id;
  final String name;
  final String icon;
}

@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    this.photoPath,
    this.rating = 0.0,
    this.reviewsCount = 0,
    this.cityId,
  });

  final String id;
  final String name;
  final String phone;
  final String? photoPath;
  final double rating;
  final int reviewsCount;
  final String? cityId;

  AppUser copyWith({
    String? name,
    String? phone,
    String? photoPath,
    double? rating,
    int? reviewsCount,
    String? cityId,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      photoPath: photoPath ?? this.photoPath,
      rating: rating ?? this.rating,
      reviewsCount: reviewsCount ?? this.reviewsCount,
      cityId: cityId ?? this.cityId,
    );
  }
}

@immutable
class Order {
  const Order({
    required this.id,
    required this.customerId,
    required this.categoryId,
    required this.title,
    required this.description,
    required this.address,
    required this.location,
    required this.priceRub,
    required this.status,
    required this.createdAt,
    this.scheduledAt,
    this.asap = true,
    this.executorId,
    this.photoPaths = const [],
    this.responses = const [],
    this.paymentMethod = PaymentMethod.cash,
    this.forOtherPhone,
  });

  final String id;
  final String customerId;
  final String categoryId;
  final String title;
  final String description;
  final String address;
  final LatLng location;
  final int priceRub;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final bool asap;
  final String? executorId;
  final List<String> photoPaths;
  final List<String> responses;
  final PaymentMethod paymentMethod;
  final String? forOtherPhone;

  Order copyWith({
    OrderStatus? status,
    String? executorId,
    List<String>? responses,
    DateTime? scheduledAt,
    int? priceRub,
  }) =>
      Order(
        id: id,
        customerId: customerId,
        categoryId: categoryId,
        title: title,
        description: description,
        address: address,
        location: location,
        priceRub: priceRub ?? this.priceRub,
        status: status ?? this.status,
        createdAt: createdAt,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        asap: asap,
        executorId: executorId ?? this.executorId,
        photoPaths: photoPaths,
        responses: responses ?? this.responses,
        paymentMethod: paymentMethod,
        forOtherPhone: forOtherPhone,
      );
}

@immutable
class Review {
  const Review({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.orderId,
    required this.rating,
    required this.comment,
    required this.tags,
    required this.createdAt,
  });

  final String id;
  final String fromUserId;
  final String toUserId;
  final String orderId;
  final int rating;
  final String comment;
  final List<String> tags;
  final DateTime createdAt;
}
