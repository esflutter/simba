import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/local/preferences_store.dart';

@immutable
class OrderDraft {
  const OrderDraft({
    this.categoryId,
    this.title = '',
    this.description = '',
    this.address = '',
    this.location,
    this.priceRub = 0,
    this.scheduledAt,
    this.asap = true,
    this.photoPaths = const [],
    this.forOtherPhone,
    this.paymentMethod,
  });

  final String? categoryId;
  final String title;
  final String description;
  final String address;
  final LatLng? location;
  final int priceRub;
  final DateTime? scheduledAt;
  final bool asap;
  final List<String> photoPaths;
  final String? forOtherPhone;
  final String? paymentMethod;

  Map<String, dynamic> toJson() => {
        if (categoryId != null) 'categoryId': categoryId,
        'title': title,
        'description': description,
        'address': address,
        if (location != null) 'lat': location!.latitude,
        if (location != null) 'lng': location!.longitude,
        'priceRub': priceRub,
        if (scheduledAt != null) 'scheduledAt': scheduledAt!.toIso8601String(),
        'asap': asap,
        'photoPaths': photoPaths,
        if (forOtherPhone != null) 'forOtherPhone': forOtherPhone,
        if (paymentMethod != null) 'paymentMethod': paymentMethod,
      };

  static OrderDraft fromJson(Map<String, dynamic> j) {
    final lat = j['lat'];
    final lng = j['lng'];
    final scheduled = j['scheduledAt'];
    // Файлы из image_picker лежат в кэше — после рестарта могут быть стёрты.
    // Отфильтровываем несуществующие, чтобы Image.file не показывал пустые тайлы.
    final rawPhotos = (j['photoPaths'] as List?)?.cast<String>() ?? const [];
    final photos = rawPhotos.where((p) => File(p).existsSync()).toList();
    return OrderDraft(
      categoryId: j['categoryId'] as String?,
      title: (j['title'] as String?) ?? '',
      description: (j['description'] as String?) ?? '',
      address: (j['address'] as String?) ?? '',
      location: (lat is num && lng is num) ? LatLng(lat.toDouble(), lng.toDouble()) : null,
      priceRub: (j['priceRub'] as num?)?.toInt() ?? 0,
      scheduledAt: scheduled is String ? DateTime.tryParse(scheduled) : null,
      asap: (j['asap'] as bool?) ?? true,
      photoPaths: photos,
      forOtherPhone: j['forOtherPhone'] as String?,
      paymentMethod: j['paymentMethod'] as String?,
    );
  }

  bool get isEmpty =>
      categoryId == null &&
      title.isEmpty &&
      description.isEmpty &&
      address.isEmpty &&
      location == null &&
      priceRub == 0 &&
      scheduledAt == null &&
      asap == true &&
      photoPaths.isEmpty &&
      forOtherPhone == null &&
      paymentMethod == null;

  bool get isReady =>
      categoryId != null &&
      title.trim().isNotEmpty &&
      address.trim().isNotEmpty &&
      location != null &&
      priceRub >= 100;

  OrderDraft copyWith({
    String? categoryId,
    String? title,
    String? description,
    String? address,
    LatLng? location,
    int? priceRub,
    DateTime? scheduledAt,
    bool? asap,
    List<String>? photoPaths,
    String? forOtherPhone,
    String? paymentMethod,
    bool clearScheduled = false,
    bool clearForOther = false,
  }) =>
      OrderDraft(
        categoryId: categoryId ?? this.categoryId,
        title: title ?? this.title,
        description: description ?? this.description,
        address: address ?? this.address,
        location: location ?? this.location,
        priceRub: priceRub ?? this.priceRub,
        scheduledAt: clearScheduled ? null : scheduledAt ?? this.scheduledAt,
        asap: asap ?? this.asap,
        photoPaths: photoPaths ?? this.photoPaths,
        forOtherPhone: clearForOther ? null : forOtherPhone ?? this.forOtherPhone,
        paymentMethod: paymentMethod ?? this.paymentMethod,
      );
}

class OrderDraftController extends Notifier<OrderDraft> {
  PreferencesStore? get _prefs {
    try {
      return ref.read(preferencesProvider);
    } catch (_) {
      return null; // тесты могут не подменять prefs — это допустимо
    }
  }

  @override
  OrderDraft build() {
    final raw = _prefs?.draftJson;
    if (raw == null || raw.isEmpty) return const OrderDraft();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return OrderDraft.fromJson(map);
    } catch (_) {
      return const OrderDraft();
    }
  }

  void _persist(OrderDraft d) {
    final p = _prefs;
    if (p == null) return;
    if (d.isEmpty) {
      p.clearDraft();
    } else {
      p.saveDraftJson(jsonEncode(d.toJson()));
    }
  }

  void update({
    String? categoryId,
    String? title,
    String? description,
    String? address,
    LatLng? location,
    int? priceRub,
    DateTime? scheduledAt,
    bool? asap,
    List<String>? photoPaths,
    String? forOtherPhone,
    String? paymentMethod,
    bool clearScheduled = false,
    bool clearForOther = false,
  }) {
    state = state.copyWith(
      categoryId: categoryId,
      title: title,
      description: description,
      address: address,
      location: location,
      priceRub: priceRub,
      scheduledAt: scheduledAt,
      asap: asap,
      photoPaths: photoPaths,
      forOtherPhone: forOtherPhone,
      paymentMethod: paymentMethod,
      clearScheduled: clearScheduled,
      clearForOther: clearForOther,
    );
    _persist(state);
  }

  void reset() {
    state = const OrderDraft();
    _prefs?.clearDraft();
  }
}

final orderDraftProvider =
    NotifierProvider<OrderDraftController, OrderDraft>(OrderDraftController.new);
