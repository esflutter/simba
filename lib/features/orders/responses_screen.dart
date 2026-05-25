import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/backend_error.dart';
import '../../core/utils/date_time_formatters.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/order_responses_repository.dart';
import '../../data/remote/orders_repository.dart';
import '../../data/remote/pocketbase_client.dart' show pocketbaseProvider;
import '../../data/remote/users_repository.dart' show publicUserProvider;
import 'order_details_screen.dart' show orderByIdProvider;

/// Future-провайдер: список id исполнителей с pending-откликом на заказ.
/// На моках берётся из `state.myOrders[i].responses`, на live — из коллекции
/// `order_responses` через PB-репозиторий.
final pendingExecutorIdsProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, orderId) async {
  return ref.read(orderResponsesRepositoryProvider).pendingExecutorIds(orderId);
});

/// Сообщение, когда отклик уже не существует (исполнитель отозвал в момент
/// accept/decline). Одна константа, чтобы accept- и decline-ветки точно
/// показывали один и тот же текст.
const _kResponseGoneMessage = 'Этот отклик уже недоступен';

/// Возвращает AppUser для отображения карточки отклика.
/// Для seed-id из MockData используем готового мок-юзера (с фото/рейтингом).
/// Для PB-id формируем placeholder с укороченным id вместо «Иван Иванов»,
/// чтобы исполнители визуально различались в списке откликов.
AppUser _userForResponder(String id) {
  final known = userById(id);
  if (known != null) return known;
  final shortId = id.substring(0, math.min(6, id.length));
  return AppUser(
    id: id,
    name: 'Исполнитель $shortId',
    phone: '',
  );
}

class ResponsesScreen extends ConsumerStatefulWidget {
  const ResponsesScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<ResponsesScreen> createState() => _ResponsesScreenState();
}

class _ResponsesScreenState extends ConsumerState<ResponsesScreen> {
  /// Screen-level лок: пока одна карточка обрабатывает accept/decline,
  /// все остальные кнопки на экране заблокированы. Без этого юзер,
  /// пока крутится «Принять» на одной карточке, мог тапнуть «Отклонить»
  /// на другой — и реально отклонить того, кого только что приняли,
  /// потому что второй PATCH успешно проходит до того, как первый
  /// инвалидирует providers.
  bool _busy = false;

  /// PB realtime-подписка на order_responses. Без неё новые отклики
  /// (другой исполнитель только что нажал «Откликнуться») не появляются
  /// в списке, пока юзер сам не сделает pull-to-refresh; точно так же
  /// отозванные отклики продолжают висеть как «активные».
  Future<void> Function()? _responsesUnsub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribeResponses());
  }

  Future<void> _subscribeResponses() async {
    if (!mounted) return;
    final pb = ref.read(pocketbaseProvider);
    if (pb == null) return;
    try {
      final unsub = await pb.collection('order_responses').subscribe('*', (e) {
        if (!mounted) return;
        // Фильтр по orderId на клиенте: WS-канал даёт события по всей
        // коллекции (PB-правила всё равно отсечут чужие записи на
        // сервере), мы дополнительно отбрасываем отклики на другие
        // заказы, чтобы не дёргать запрос лишний раз.
        final rec = e.record;
        if (rec == null) {
          ref.invalidate(pendingExecutorIdsProvider(widget.orderId));
          return;
        }
        if (rec.getStringValue('order_ref') == widget.orderId) {
          ref.invalidate(pendingExecutorIdsProvider(widget.orderId));
        }
      });
      if (!mounted) {
        await unsub();
        return;
      }
      _responsesUnsub = unsub;
    } catch (_) {/* WebSocket недоступен — pull-to-refresh всё ещё работает */}
  }

  @override
  void dispose() {
    final unsub = _responsesUnsub;
    _responsesUnsub = null;
    if (unsub != null) {
      // ignore: discarded_futures
      unsub();
    }
    super.dispose();
  }

  Future<void> _withLock(Future<void> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get orderId => widget.orderId;

  @override
  Widget build(BuildContext context) {
    final asyncIds = ref.watch(pendingExecutorIdsProvider(orderId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                child: const AppBackButton(),
              ),
            ),
            Expanded(
              child: asyncIds.when(
                data: (executorIds) {
                  Future<void> doRefresh() async {
                    ref.invalidate(pendingExecutorIdsProvider(orderId));
                    try {
                      await ref.read(
                          pendingExecutorIdsProvider(orderId).future);
                    } catch (e) {
                      if (!context.mounted) return;
                      AppToast.error(context, humanizeBackendError(e));
                    }
                  }

                  if (executorIds.isEmpty) {
                    return RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: doRefresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: 120.h),
                          Center(
                            child: Text(
                              'Откликов пока нет',
                              style: AppText.body(
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  // userById даёт мок-данные только для seed-id из MockData;
                  // для PB-id оно подставило бы demoCurrentUser (Иван Иванов),
                  // и все исполнители выглядели бы одинаково. Делаем явный
                  // placeholder по id-шорту. TODO(users-repo): когда появится
                  // usersRepository.getById — перейти на async с подгрузкой
                  // реального имени/фото.
                  final users = executorIds.map(_userForResponder).toList(
                        growable: false,
                      );
                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: doRefresh,
                    child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                    itemCount: users.length,
                    separatorBuilder: (_, _) => SizedBox(height: 16.h),
                    itemBuilder: (_, i) {
                      final u = users[i];
                      return _ResponseCard(
                        user: u,
                        // Если на экране уже крутится accept/decline другой
                        // карточки — все остальные кнопки заблокированы.
                        // Без этого юзер мог отклонить только что принятого
                        // исполнителя за полсекунды до того, как accept
                        // успеет вернуться.
                        screenBusy: _busy,
                        onTap: () =>
                            context.push('/order/$orderId/user/${u.id}'),
                        onDecline: () => _withLock(() async {
                          final isLast = users.length == 1;
                          try {
                            await ref
                                .read(orderResponsesRepositoryProvider)
                                .decline(orderId, u.id);
                            if (!context.mounted) return;
                            ref.invalidate(myOrdersStreamProvider);
                            ref.invalidate(myExecutorOrdersProvider);
                            ref.invalidate(feedOrdersProvider);
                            ref.invalidate(
                                pendingExecutorIdsProvider(orderId));
                            ref.invalidate(orderByIdProvider(orderId));
                            AppToast.show(context, 'Исполнитель отклонён');
                            if (isLast) context.pop();
                          } on OrderResponseGoneException {
                            // Исполнитель отозвал отклик параллельно — это не
                            // ошибка, просто перерисуем экран.
                            if (!context.mounted) return;
                            ref.invalidate(
                                pendingExecutorIdsProvider(orderId));
                            AppToast.show(context, _kResponseGoneMessage);
                          } catch (e) {
                            if (!context.mounted) return;
                            AppToast.show(context, humanizeBackendError(e));
                          }
                        }),
                        onAccept: () => _withLock(() async {
                          try {
                            await ref
                                .read(orderResponsesRepositoryProvider)
                                .accept(orderId, u.id);
                            if (!context.mounted) return;
                            ref.invalidate(myOrdersStreamProvider);
                            ref.invalidate(myExecutorOrdersProvider);
                            // После accept заказ становится "не open"
                            // → должен исчезнуть из фида у других исполнителей.
                            ref.invalidate(feedOrdersProvider);
                            ref.invalidate(
                                pendingExecutorIdsProvider(orderId));
                            ref.invalidate(orderByIdProvider(orderId));
                            AppToast.show(context, 'Исполнитель принят');
                            // pushReplacement, а не go: go сбрасывает стек
                            // и /home/orders уходит — потом back из заказа
                            // не работает. Заменяем responses на профиль,
                            // сохраняя [home, order, profile] в стеке.
                            context.pushReplacement(
                              '/order/$orderId/user/${u.id}',
                            );
                          } on OrderResponseGoneException {
                            // Исполнитель отозвал отклик прямо в момент
                            // принятия. Раньше клиент молча уходил «успешно»,
                            // а на сервере ничего не менялось. Теперь честно
                            // сообщаем и перезагружаем список откликов.
                            if (!context.mounted) return;
                            ref.invalidate(
                                pendingExecutorIdsProvider(orderId));
                            ref.invalidate(orderByIdProvider(orderId));
                            AppToast.show(context, _kResponseGoneMessage);
                          } on ClientException catch (e) {
                            if (!context.mounted) return;
                            // 409 = unique index `idx_resp_single_accepted`:
                            // на этом заказе уже есть один accepted-отклик
                            // (открыты две вкладки, кто-то успел раньше).
                            // Перезагружаем экран — заказ уже не open.
                            if (e.statusCode == 409) {
                              ref.invalidate(
                                  pendingExecutorIdsProvider(orderId));
                              ref.invalidate(orderByIdProvider(orderId));
                              AppToast.show(
                                context,
                                'Заказ уже принят другим исполнителем',
                              );
                            } else {
                              AppToast.show(context, humanizeBackendError(e));
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            AppToast.show(context, humanizeBackendError(e));
                          }
                        }),
                      );
                    },
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (_, _) => Center(
                  child: Text(
                    'Не удалось загрузить отклики',
                    style: AppText.body(color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponseCard extends ConsumerStatefulWidget {
  const _ResponseCard({
    required this.user,
    required this.onTap,
    required this.onDecline,
    required this.onAccept,
    this.screenBusy = false,
  });

  /// Базовый AppUser (placeholder с id-шортом для PB-юзеров без
  /// подгруженного публичного профиля). Реальные имя/фото/рейтинг
  /// подтягиваются через `publicUserProvider` в build — fallback
  /// на `user` пока запрос грузится / при ошибке.
  final AppUser user;
  final VoidCallback onTap;
  final Future<void> Function() onDecline;
  final Future<void> Function() onAccept;
  /// Экран-уровневый лок: другая карточка сейчас обрабатывает
  /// accept/decline. Все кнопки на этой тоже дизейблятся, чтобы юзер
  /// не отклонил только что принятого исполнителя на параллельной
  /// карточке быстрым тапом.
  final bool screenBusy;

  @override
  ConsumerState<_ResponseCard> createState() => _ResponseCardState();
}

class _ResponseCardState extends ConsumerState<_ResponseCard> {
  bool _busy = false;

  Future<void> _handleAccept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onAccept();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleDecline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onDecline();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Подтягиваем публичный профиль из PB. Пока запрос грузится / при
    // ошибке — fallback на переданного `widget.user` (placeholder
    // «Исполнитель xxxxxx», ★ 0,0). Это устраняет «нулевую» карточку
    // отклика, которую заказчик видел до фикса.
    final publicAsync = ref.watch(publicUserProvider(widget.user.id));
    final user = publicAsync.maybeWhen(
      data: (u) => u ?? widget.user,
      orElse: () => widget.user,
    );
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _busy ? null : widget.onTap,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16.r),
              topRight: Radius.circular(16.r),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
              child: Row(
                children: [
                  Container(
                    width: 56.r,
                    height: 56.r,
                    decoration: const BoxDecoration(
                      color: AppColors.background,
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Builder(builder: (_) {
                      final fallback = Icon(
                        IconsaxPlusLinear.user,
                        color: AppColors.primary,
                        size: 32.r,
                      );
                      final p = user.photoPath;
                      if (p == null) return fallback;
                      if (p.startsWith('http')) {
                        return AppNetworkImage(
                          url: p,
                          width: 56.r,
                          height: 56.r,
                          fallback: fallback,
                        );
                      }
                      return Image.file(
                        File(p),
                        fit: BoxFit.cover,
                        // 56r-кружок ≈ 168px; полный 1024-аватар бы декодился
                        // в RAM (~4МБ × 50 откликов = 200МБ на пустом месте).
                        cacheWidth: 168,
                        cacheHeight: 168,
                        errorBuilder: (_, _, _) => fallback,
                      );
                    }),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                            height: 1.50,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Image.asset(
                              'assets/images/icon_ranking.webp',
                              width: 16.r,
                              height: 16.r,
                            ),
                            SizedBox(width: 4.w),
                            Text(
                              formatRating(user.rating),
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w400,
                                height: 1.50,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Image.asset(
                    'assets/images/icon_chevron_right.webp',
                    width: 24.r,
                    height: 24.r,
                  ),
                ],
              ),
            ),
          ),
          Container(
            height: 1,
            margin: EdgeInsets.symmetric(horizontal: 16.w),
            color: const Color(0x33787878),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
            child: Row(
              children: [
                Expanded(
                  child: _ResponseAction(
                    label: 'Отклонить',
                    background: AppColors.surfaceVariant,
                    color: AppColors.error,
                    onTap: (_busy || widget.screenBusy)
                        ? null
                        : _handleDecline,
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: _ResponseAction(
                    label: 'Принять',
                    background: AppColors.primary,
                    // Белый текст на синем — нормальный контраст.
                    // Раньше был серый F5F5F5 на синем, плохо читался.
                    color: AppColors.surface,
                    onTap: (_busy || widget.screenBusy)
                        ? null
                        : _handleAccept,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponseAction extends StatelessWidget {
  const _ResponseAction({
    required this.label,
    required this.background,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: disabled ? AppColors.surfaceVariant : background,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: SizedBox(
          // 48dp — Material/Android минимум touch-target. Раньше было
          // 36, пальцем на iPhone было сложно попасть.
          height: 48.h,
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: disabled ? AppColors.textTertiary : color,
                fontSize: 17.sp,
                fontWeight: FontWeight.w600,
                height: 1.29,
                letterSpacing: -0.40,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
