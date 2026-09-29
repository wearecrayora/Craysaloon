import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/dashboard/dashboard.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/notifications/push_api.dart';
import '../../domain/privacy/privacy.dart';
import '../../domain/referral/referral.dart';
import '../../domain/records/records.dart';
import '../../domain/wallet/wallet.dart';

/// The only file in the app that talks to Supabase (`RULES.md` 3.7 / GATE-1).
///
/// Two things it deliberately does not do:
///
/// * **It never sends the salon with a verification.** `otp-verify` reads both
///   the phone and the salon from the challenge the server issued, so editing a
///   request cannot move a login to a different salon (ADR-36).
/// * **It never logs a phone number, a code, a challenge id or a token.** The
///   error paths carry a kind, not a payload.
class SupabaseCrayApi
    implements CrayApi, SalonReads, SalonWrites, SalonBookings, PrivacyApi, WalletApi,
        PushApi, ReferralApi, DashboardApi {
  SupabaseCrayApi(this._client);

  final SupabaseClient _client;

  @override
  bool get hasSession => _client.auth.currentSession != null;

  @override
  AppSession? get session {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) return null;
    final claims = _claims(token);
    final role = claims?['app_role'] as String?;
    if (role == null) return null;
    return AppSession(appRole: role, salonId: claims?['salon_id'] as String?);
  }

  /// Reads the payload of a token this app received from our own Edge Function
  /// over TLS. It is NOT verified here, and must not be trusted for anything but
  /// choosing a screen: the signature is checked by the database on every call,
  /// which is where it matters.
  static Map<String, Object?>? _claims(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return _asMap(jsonDecode(payload));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SalonSummary?> resolveJoinCode(String code, {required String deviceKey}) async {
    try {
      final result = await _client.rpc<dynamic>(
        'resolve_join_code',
        params: {'p_code': code, 'p_device_key': deviceKey},
      );
      final row = _asMap(result);
      if (row == null) return null;

      final salonId = row['salon_id'] as String?;
      final displayName = row['display_name'] as String?;
      if (salonId == null || displayName == null) return null;

      return SalonSummary(
        salonId: salonId,
        displayName: displayName,
        brandingVersion: (row['branding_version'] as num?)?.toInt() ?? 0,
        branding: _asMap(row['branding']) ?? const {},
        grievance: GrievanceContact.fromJson(_asMap(row['grievance'])),
      );
    } on PostgrestException catch (e) {
      throw CrayApiException(_postgrestKind(e));
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  @override
  Future<void> startJoin({
    required String code,
    required String phone,
    required String deviceKey,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'start_join',
        params: {'p_code': code, 'p_phone': phone, 'p_device_key': deviceKey},
      );
    } on PostgrestException catch (e) {
      throw CrayApiException(_postgrestKind(e));
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  @override
  Future<OtpChallenge> sendOtp(String phone) async {
    final response = await _invoke('otp-send', {'phone': phone});
    final body = _asMap(response.data) ?? const {};
    final id = body['challenge_id'] as String?;
    if (response.status != 200 || id == null) {
      throw CrayApiException(_functionKind(response.status, body['error']));
    }
    return OtpChallenge(
      challengeId: id,
      expiresIn: (body['expires_in'] as num?)?.toInt() ?? 60,
    );
  }

  @override
  Future<LoginOutcome> verifyOtp({
    required String challengeId,
    required String code,
    bool promotional = false,
    bool whatsapp = false,
  }) async {
    final response = await _invoke('otp-verify', {
      'challenge_id': challengeId,
      'code': code,
      'consents': {'promotional': promotional, 'whatsapp': whatsapp},
    });
    final body = _asMap(response.data) ?? const {};

    if (response.status != 200) {
      throw CrayApiException(
        _functionKind(response.status, body['error']),
        attemptsLeft: (body['attempts_left'] as num?)?.toInt(),
      );
    }

    // The Edge Function returns the session; supabase_flutter is what persists
    // and refreshes it, so hand it over rather than keeping tokens ourselves.
    final access = body['access_token'] as String?;
    final refresh = body['refresh_token'] as String?;
    if (access == null || refresh == null) {
      throw const CrayApiException(CrayErrorKind.server);
    }
    await _client.auth.setSession(refresh);

    return switch (body['outcome']) {
      'bound' => LoginOutcome.bound,
      'staff' => LoginOutcome.staff,
      _ => LoginOutcome.returning,
    };
  }

  Future<FunctionResponse> _invoke(String name, Map<String, Object?> body) async {
    try {
      return await _client.functions.invoke(name, body: body);
    } on FunctionException catch (e) {
      // A non-2xx from an Edge Function arrives as an exception, with the body
      // we deliberately shaped. Treat it as a response, not a crash.
      return FunctionResponse(status: e.status, data: e.details);
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  static CrayErrorKind _functionKind(int status, Object? error) {
    if (status == 429) return CrayErrorKind.rateLimited;
    return switch (error) {
      'salon_unavailable' => CrayErrorKind.salonUnavailable,
      'already_bound' => CrayErrorKind.alreadyBound,
      'account_conflict' => CrayErrorKind.accountConflict,
      'wrong_code' => CrayErrorKind.wrongCode,
      'expired' => CrayErrorKind.otpExpired,
      'too_many_attempts' => CrayErrorKind.rateLimited,
      'invalid_phone' => CrayErrorKind.invalidPhone,
      _ => CrayErrorKind.server,
    };
  }

  static CrayErrorKind _postgrestKind(PostgrestException e) {
    final text = e.message.toLowerCase();
    if (text.contains('rate')) return CrayErrorKind.rateLimited;
    // app.phone_hash raises on anything that is not an Indian mobile number.
    if (text.contains('phone_hash')) return CrayErrorKind.invalidPhone;
    if (text.contains('not active') || text.contains('unavailable')) {
      return CrayErrorKind.salonUnavailable;
    }
    return CrayErrorKind.server;
  }

  static Map<String, Object?>? _asMap(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;

  // -------------------------------------------------------------------------
  // SalonReads (M5). Every one of these is tenant-scoped by RLS, not by a
  // filter written here: a `.eq('salon_id', ...)` would be a courtesy the
  // database already enforces, and writing it invites the belief that it is
  // what protects the data.
  // -------------------------------------------------------------------------

  @override
  Future<List<Service>> services() async {
    final rows = await _rows(
      () => _client
          .from('services')
          .select('id,name,price_paise,duration_minutes,active')
          .order('active', ascending: false)
          .order('name'),
    );
    return rows
        .map((r) => Service(
              id: r['id'] as String,
              name: r['name'] as String? ?? '',
              pricePaise: _int(r['price_paise']),
              durationMinutes: _int(r['duration_minutes']),
              active: r['active'] as bool? ?? true,
            ))
        .toList();
  }

  @override
  Future<List<AddOn>> addOns() async {
    final rows = await _rows(
      () => _client
          .from('add_ons')
          .select('id,name,price_paise,extra_duration_minutes,active')
          .order('active', ascending: false)
          .order('name'),
    );
    return rows
        .map((r) => AddOn(
              id: r['id'] as String,
              name: r['name'] as String? ?? '',
              pricePaise: _int(r['price_paise']),
              extraDurationMinutes: _int(r['extra_duration_minutes']),
              active: r['active'] as bool? ?? true,
            ))
        .toList();
  }

  @override
  Future<List<StaffMember>> staff() async {
    final rows = await _rows(
      () => _client
          .from('staff')
          .select('id,name,active')
          .order('active', ascending: false)
          .order('name'),
    );
    return rows
        .map((r) => StaffMember(
              id: r['id'] as String,
              name: r['name'] as String? ?? '',
              active: r['active'] as bool? ?? true,
            ))
        .toList();
  }

  @override
  Future<CustomerPage> customers({
    String? search,
    CustomerCursor? after,
    int limit = 20,
  }) async {
    // One call for the whole row - name, last visit, balance, visit count -
    // because twenty round trips on salon wi-fi is not a list, it is a wait.
    // The function is SECURITY INVOKER, so RLS still decides what comes back.
    final result = await _client.rpc<dynamic>('list_customers', params: {
      'p_search': (search?.trim().isEmpty ?? true) ? null : search!.trim(),
      'p_cursor_last_visit': after?.lastVisitAt?.toUtc().toIso8601String(),
      'p_cursor_id': after?.id,
      // One more than asked for, so "is there another page" needs no count.
      'p_limit': limit + 1,
    });

    final rows = (result is List ? result : const [])
        .whereType<Map<Object?, Object?>>()
        .map((r) => r.cast<String, Object?>())
        .toList();

    final hasMore = rows.length > limit;
    final page = hasMore ? rows.sublist(0, limit) : rows;

    final customers = page
        .map((r) => CustomerSummary(
              id: r['id'] as String,
              name: r['name'] as String?,
              phone: r['phone'] as String?,
              lastVisitAt: _time(r['last_visit_at']),
              balancePaise: _int(r['balance_paise']),
              visitCount: _int(r['visit_count']),
              loyaltyPoints: _int(r['loyalty_points']),
              tier: r['tier'] as String?,
            ))
        .toList();

    return CustomerPage(
      customers: customers,
      cursor: customers.isEmpty || !hasMore
          ? null
          : CustomerCursor(
              lastVisitAt: customers.last.lastVisitAt,
              id: customers.last.id,
            ),
      hasMore: hasMore,
    );
  }

  @override
  Future<List<Visit>> visits(String customerId, {int limit = 20}) async {
    final rows = await _rows(
      () => _client
          .from('visits')
          .select('id,customer_id,completed_at,final_amount_paise')
          .eq('customer_id', customerId)
          .order('completed_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit),
    );
    return rows
        .map((r) => Visit(
              id: r['id'] as String,
              customerId: r['customer_id'] as String,
              completedAt: _time(r['completed_at']) ?? DateTime.now(),
              finalAmountPaise: _int(r['final_amount_paise']),
            ))
        .toList();
  }

  /// Runs a read and turns transport failures into the app's own error kinds.
  /// A PostgREST refusal is NOT retried and NOT logged with its payload: it
  /// means a policy said no, and the payload would be the thing the policy
  /// protects.
  Future<List<Map<String, Object?>>> _rows(
    Future<List<Map<String, dynamic>>> Function() query,
  ) async {
    try {
      final rows = await query();
      return rows.map((r) => r.cast<String, Object?>()).toList();
    } on PostgrestException catch (e) {
      throw CrayApiException(_postgrestKind(e));
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  // -------------------------------------------------------------------------
  // SalonWrites (M5). The database decides whether these are allowed: the
  // catalogue tables carry a RESTRICTIVE policy admitting only owner and manager
  // (0041). A refusal arrives here as a PostgREST 42501 and is shown as "your
  // account cannot change the catalogue" - never retried, never queued.
  //
  // `salon_id` is not sent. The insert policy's WITH CHECK compares it to the
  // caller's own salon, and the column defaults to it, so naming it here would
  // add a value the client could get wrong and the database would then reject.
  // -------------------------------------------------------------------------

  @override
  Future<String> saveService({
    String? id,
    required String name,
    required int pricePaise,
    required int durationMinutes,
    required bool active,
  }) =>
      _save('services', id, {
        'name': name,
        'price_paise': pricePaise,
        'duration_minutes': durationMinutes,
        'active': active,
      });

  @override
  Future<String> saveAddOn({
    String? id,
    required String name,
    required int pricePaise,
    required int extraDurationMinutes,
    required bool active,
  }) =>
      _save('add_ons', id, {
        'name': name,
        'price_paise': pricePaise,
        'extra_duration_minutes': extraDurationMinutes,
        'active': active,
      });

  @override
  Future<String> saveStaff({String? id, required String name, required bool active}) =>
      _save('staff', id, {'name': name, 'active': active});

  Future<String> _save(String table, String? id, Map<String, Object?> values) async {
    try {
      final row = id == null
          ? await _client.from(table).insert(values).select('id').single()
          : await _client.from(table).update(values).eq('id', id).select('id').single();
      return row['id'] as String;
    } on PostgrestException catch (e) {
      // 42501 is the policy saying no. It is not a bug to retry; it is an answer.
      throw CrayApiException(
        e.code == '42501' ? CrayErrorKind.forbidden : _postgrestKind(e),
      );
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  // -------------------------------------------------------------------------
  // SalonBookings (M6). Every write is one RPC that decides everything: the
  // race, the snapshot, the idempotency. This layer only carries the
  // client_action_id through and turns a refusal into a kind the outbox can
  // tell apart from "no signal".
  // -------------------------------------------------------------------------

  @override
  Future<List<BookingRow>> bookingsOn(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final rows = await _rows(
      () => _client
          .from('bookings')
          .select('id,customer_id,starts_at,ends_at,status,total_paise,'
              'customers(name),staff(name),booking_items(name_snapshot,kind),'
              'visits(payment_status)')
          .gte('starts_at', start.toUtc().toIso8601String())
          .lt('starts_at', end.toUtc().toIso8601String())
          .order('starts_at'),
    );

    return rows.map((r) {
      final items = (r['booking_items'] as List?) ?? const [];
      final services = items
          .whereType<Map<Object?, Object?>>()
          .where((i) => i['kind'] == 'service')
          .map((i) => i['name_snapshot'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .join(', ');
      return BookingRow(
        id: r['id'] as String,
        customerId: r['customer_id'] as String,
        startsAt: _time(r['starts_at']) ?? DateTime.now(),
        endsAt: _time(r['ends_at']) ?? DateTime.now(),
        status: r['status'] as String? ?? 'confirmed',
        totalPaise: _int(r['total_paise']),
        customerName: _asMap(r['customers'])?['name'] as String?,
        staffName: _asMap(r['staff'])?['name'] as String?,
        serviceNames: services,
        // One visit per booking; PostgREST returns the embed as a list.
        paymentStatus: switch (r['visits']) {
          [final Map<Object?, Object?> v, ...] => v['payment_status'] as String?,
          final Map<Object?, Object?> v => v['payment_status'] as String?,
          _ => null,
        },
      );
    }).toList();
  }

  @override
  Future<List<Slot>> slots({
    required String serviceId,
    required DateTime day,
    String? staffId,
    List<String> addOnIds = const [],
  }) async {
    try {
      final result = await _client.rpc<dynamic>('available_slots', params: {
        // The server ignores the salon we name and uses the token's, but the
        // signature keeps it so a mismatch is loud rather than silent.
        'p_salon_id': session?.salonId,
        'p_service_id': serviceId,
        'p_staff_id': staffId,
        'p_date': '${day.year.toString().padLeft(4, '0')}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}',
        'p_add_on_ids': addOnIds,
      });

      return (result is List ? result : const [])
          .whereType<Map<Object?, Object?>>()
          .map((r) => r.cast<String, Object?>())
          .map((r) => Slot(
                staffId: r['staff_id'] as String,
                startsAt: _time(r['starts_at']) ?? DateTime.now(),
                endsAt: _time(r['ends_at']) ?? DateTime.now(),
              ))
          .toList();
    } on PostgrestException catch (e) {
      throw CrayApiException(_postgrestKind(e));
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  @override
  Future<String> createBooking({
    required String clientActionId,
    required String serviceId,
    required DateTime startsAt,
    String? staffId,
    String? customerId,
    List<String> addOnIds = const [],
    String? notes,
  }) async {
    final body = await _call('create_booking', {
      'p_client_action_id': clientActionId,
      'p_service_id': serviceId,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_staff_id': staffId,
      'p_customer_id': customerId,
      'p_add_on_ids': addOnIds,
      'p_notes': notes,
    });
    return body['booking_id'] as String;
  }

  @override
  Future<void> markComplete({
    required String clientActionId,
    required String bookingId,
    int? finalAmountPaise,
    int tipPaise = 0,
  }) async {
    await _call('mark_visit_complete', {
      'p_client_action_id': clientActionId,
      'p_booking_id': bookingId,
      'p_final_amount_paise': finalAmountPaise,
      'p_tip_paise': tipPaise,
    });
  }

  @override
  Future<void> cancelBooking({
    required String clientActionId,
    required String bookingId,
    String? reason,
  }) async {
    await _call('cancel_booking', {
      'p_client_action_id': clientActionId,
      'p_booking_id': bookingId,
      'p_reason': reason,
    });
  }

  @override
  Future<CheckoutQuote> checkoutQuote(String bookingId) async {
    final body = await _call('checkout_quote', {'p_booking_id': bookingId});
    return CheckoutQuote(
      duePaise: _int(body['due_paise']),
      walletAvailablePaise: _int(body['wallet_available_paise']),
      fromWalletPaise: _int(body['from_wallet_paise']),
      fromCounterPaise: _int(body['from_counter_paise']),
    );
  }

  @override
  Future<void> checkout({
    required String clientActionId,
    required String bookingId,
    bool useWallet = true,
    String method = 'cash',
  }) async {
    // By BOOKING: offline, the app has no visit id - the mark-complete that
    // creates one is queued ahead of this in the same outbox (0079).
    await _call('checkout_booking', {
      'p_client_action_id': clientActionId,
      'p_booking_id': bookingId,
      'p_use_wallet': useWallet,
      'p_other_method': method,
    });
  }

  /// Calls one of the booking RPCs and turns `{ok:false, reason}` into an
  /// exception the outbox can classify. A reason is NOT a transport failure:
  /// retrying it would never help, and it belongs in "Needs attention".
  Future<Map<String, Object?>> _call(String fn, Map<String, Object?> params) async {
    try {
      final result = await _client.rpc<dynamic>(fn, params: params);
      final body = _asMap(result) ?? const {};
      if (body['ok'] == true) return body;
      throw CrayApiException(switch (body['reason']) {
        'slot_taken' => CrayErrorKind.slotTaken,
        'salon_unavailable' => CrayErrorKind.salonUnavailable,
        'already_completed' || 'not_completable' || 'not_completed' =>
          CrayErrorKind.notCompletable,
        _ => CrayErrorKind.server,
      });
    } on PostgrestException catch (e) {
      throw CrayApiException(
        e.code == '42501' ? CrayErrorKind.forbidden : _postgrestKind(e),
      );
    } on CrayApiException {
      rethrow;
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  // -------------------------------------------------------------------------
  // PrivacyApi. The rights the DPDP Act gives the customer (0051/0052).
  //
  // All four go through the database's own functions, which check that the
  // caller IS the customer - the app is not trusted to have asked the right
  // person, and a stylist holding someone's phone gets a 42501.
  // -------------------------------------------------------------------------

  @override
  Future<List<ConsentState>> consents() async {
    final rows = await _rows(
      () async => (await _client.rpc<dynamic>('my_consents') as List)
          .cast<Map<String, dynamic>>(),
    );
    return [
      for (final row in rows)
        ConsentState(
          purpose: row['purpose'] as String? ?? '',
          granted: row['granted'] as bool? ?? false,
          occurredAt: _time(row['occurred_at']) ?? DateTime.now(),
        ),
    ];
  }

  @override
  Future<ConsentRefusal?> setConsent(String purpose, bool granted) async {
    try {
      final body = _asMap(await _client.rpc<dynamic>(
            'set_consent',
            params: {'p_purpose': purpose, 'p_granted': granted},
          )) ??
          const {};
      if (body['ok'] == true) return null;
      // One refusal exists, and it is an answer rather than a failure: service
      // messages are the service (RULES 11.6c).
      return body['reason'] == 'service_communication_required'
          ? ConsentRefusal.serviceRequired
          : throw const CrayApiException(CrayErrorKind.server);
    } on PostgrestException catch (e) {
      throw CrayApiException(
        e.code == '42501' ? CrayErrorKind.forbidden : _postgrestKind(e),
      );
    } on CrayApiException {
      rethrow;
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  @override
  Future<DataRightRequest?> requestRight(String kind, {String? detail}) async {
    final body = await _call('request_data_right', {
      'p_kind': kind,
      'p_detail': detail,
    });
    final id = body['request_id'] as String?;
    if (id == null) return null;
    // The function returns the id; the row carries the dates the screen shows,
    // and reading it back is also a check that the customer can see their own
    // request - which is the whole point of the restrictive policy (0038).
    final mine = await myRequests();
    return mine.where((r) => r.id == id).firstOrNull;
  }

  @override
  Future<List<DataRightRequest>> myRequests() async {
    final rows = await _rows(
      () async => await _client
          .from('data_rights_requests')
          .select('id, kind, status, requested_at, due_at, outcome')
          .order('requested_at', ascending: false)
          .limit(20),
    );
    return [
      for (final row in rows)
        DataRightRequest(
          id: row['id'] as String? ?? '',
          kind: row['kind'] as String? ?? '',
          status: row['status'] as String? ?? 'open',
          requestedAt: _time(row['requested_at']) ?? DateTime.now(),
          dueAt: _time(row['due_at']) ?? DateTime.now(),
          outcome: row['outcome'] as String?,
        ),
    ];
  }

  // -------------------------------------------------------------------------
  // WalletApi (M7). Reads come from SECURITY DEFINER functions keyed on the
  // caller's own customer id (0057), so there is no salon filter written here
  // to get wrong - and no table read that a future policy change could widen.
  // -------------------------------------------------------------------------

  @override
  Future<WalletSummary> wallet() async {
    try {
      final row = _asMap(await _client.rpc<dynamic>('my_wallet')) ?? const {};
      return WalletSummary(
        balancePaise: _int(row['balance_paise']),
        paidPaise: _int(row['paid_paise']),
        bonusPaise: _int(row['bonus_paise']),
        nextBonusExpiry: _time(row['next_bonus_expiry']),
        nextBonusPaise: _int(row['next_bonus_paise']),
      );
    } on PostgrestException catch (e) {
      throw CrayApiException(_postgrestKind(e));
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  @override
  Future<List<WalletEntry>> walletHistory({int limit = 20, int? before}) async {
    final rows = await _rows(
      () async => (await _client.rpc<dynamic>(
        'my_wallet_history',
        params: {'p_limit': limit, 'p_before': before},
      ) as List)
          .cast<Map<String, dynamic>>(),
    );
    return [
      for (final row in rows)
        WalletEntry(
          id: _int(row['id']),
          kind: row['kind'] as String? ?? '',
          amountPaise: _int(row['amount_paise']),
          balanceAfter: _int(row['balance_after']),
          createdAt: _time(row['created_at']) ?? DateTime.now(),
          reason: row['reason'] as String?,
        ),
    ];
  }

  @override
  Future<TopupQuote> topupQuote(int amountPaise) async {
    try {
      final row = _asMap(await _client.rpc<dynamic>(
            'topup_quote',
            params: {'p_amount_paise': amountPaise},
          )) ??
          const {};
      return TopupQuote(
        amountPaise: _int(row['amount_paise']),
        bonusPaise: _int(row['bonus_paise']),
        minTopupPaise: _int(row['min_topup_paise']),
        bonusExpiresAt: _time(row['bonus_expires_at']),
      );
    } on PostgrestException catch (e) {
      throw CrayApiException(_postgrestKind(e));
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  @override
  Future<TopupOrder> startTopup({
    required String clientActionId,
    required int amountPaise,
  }) async {
    final response = await _invoke('create-payment-order', {
      'client_action_id': clientActionId,
      'amount_paise': amountPaise,
    });
    final body = _asMap(response.data) ?? const {};

    if (response.status != 200) {
      // Each of these is a different sentence to the customer. "Something went
      // wrong" in front of a pay button is how a salon loses a top-up and never
      // finds out why.
      throw switch (body['error']) {
        'below_minimum' => TopupException(
            TopupProblem.belowMinimum,
            minTopupPaise: _int(body['min_topup_paise']),
          ),
        'invalid_amount' || 'above_maximum' =>
          const TopupException(TopupProblem.invalidAmount),
        'payments_unavailable' =>
          const TopupException(TopupProblem.paymentsUnavailable),
        'salon_unavailable' => const TopupException(TopupProblem.salonUnavailable),
        _ => const TopupException(TopupProblem.network),
      };
    }

    return TopupOrder(
      paymentId: body['payment_id'] as String? ?? '',
      orderId: body['order_id'] as String? ?? '',
      keyId: body['key_id'] as String? ?? '',
      amountPaise: _int(body['amount_paise']),
    );
  }

  // -------------------------------------------------------------------------
  // PushApi (M8). The device's half of the ack protocol.
  // -------------------------------------------------------------------------

  @override
  Future<void> registerPushToken({required String token, required String platform}) async {
    try {
      await _client.rpc<dynamic>(
        'register_push_token',
        params: {'p_token': token, 'p_platform': platform},
      );
    } on PostgrestException catch (e) {
      throw CrayApiException(_postgrestKind(e));
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  @override
  Future<void> ackNotification(String deliveryId) async {
    try {
      await _client.rpc<dynamic>('ack_notification', params: {'p_delivery_id': deliveryId});
    } on PostgrestException catch (e) {
      throw CrayApiException(_postgrestKind(e));
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  // -------------------------------------------------------------------------
  // ReferralApi (M9). Two RPCs, both keyed on the caller's own customer id:
  // the summary deliberately returns counts and no names (0074).
  // -------------------------------------------------------------------------

  @override
  Future<ReferralSummary> referralSummary() async {
    try {
      final code = _asMap(await _client.rpc<dynamic>('my_referral_code')) ?? const {};
      final mine = _asMap(await _client.rpc<dynamic>('my_referrals')) ?? const {};
      return ReferralSummary(
        code: code['code'] as String? ?? '',
        referrerPaise: _int(code['referrer_paise']),
        referredPaise: _int(code['referred_paise']),
        pending: _int(mine['pending']),
        rewarded: _int(mine['rewarded']),
        earnedPaise: _int(mine['earned_paise']),
      );
    } on PostgrestException catch (e) {
      throw CrayApiException(_postgrestKind(e));
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  @override
  Future<ClaimRefusal?> claimReferral(String code) async {
    try {
      final body = _asMap(await _client.rpc<dynamic>(
            'claim_referral',
            params: {'p_code': code},
          )) ??
          const {};
      if (body['ok'] == true) return null;
      return switch (body['reason']) {
        'already_referred' => ClaimRefusal.alreadyReferred,
        'self_referral' => ClaimRefusal.selfReferral,
        'not_a_new_customer' => ClaimRefusal.notNewCustomer,
        _ => ClaimRefusal.unknownCode,
      };
    } on PostgrestException catch (e) {
      throw CrayApiException(_postgrestKind(e));
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  // -------------------------------------------------------------------------
  // DashboardApi (M10). One call; today is computed from source on the server.
  // -------------------------------------------------------------------------

  @override
  Future<Dashboard> dashboard() async {
    try {
      final d = _asMap(await _client.rpc<dynamic>('owner_dashboard')) ?? const {};
      final today = _asMap(d['today']) ?? const {};
      final bookings = _asMap(d['bookings_today']) ?? const {};
      final month = _asMap(d['month']) ?? const {};
      final messaging = _asMap(d['messaging']) ?? const {};
      final spend = _asMap(messaging['spend_by_channel']) ?? const {};

      return Dashboard(
        revenuePaise: _int(today['revenue_paise']),
        completed: _int(today['completed']),
        avgBillPaise: today['avg_bill_paise'] == null ? null : _int(today['avg_bill_paise']),
        bookingsLive: _int(bookings['live']),
        cancelled: _int(bookings['cancelled']),
        noShow: _int(bookings['no_show']),
        newCustomers: _int(month['new_customers']),
        repeatCustomers: _int(month['repeat_customers']),
        walletCollectedPaise: _int(month['wallet_collected_paise']),
        outstandingCreditPaise: _int(d['outstanding_credit_paise']),
        reminderBookings: _int(messaging['reminder_bookings']),
        binds: _int(month['binds']),
        spendByChannel: {for (final e in spend.entries) e.key: _int(e.value)},
        remindersSent: _int(messaging['reminders_sent']),
        ackedPushes: _int(messaging['acked_pushes']),
        cohorts: [
          for (final raw in (d['cohorts'] as List? ?? const []))
            if (_asMap(raw) case final c?)
              CohortRow(
                month: DateTime.tryParse(c['month'] as String? ?? '') ?? DateTime(2000),
                segment: c['segment'] as String? ?? '',
                n: _int(c['n']),
                // null stays null: an unripe cohort has no rate, and 0 would
                // be a lie told in the most readable place on the screen.
                d30: (c['d30'] as num?)?.toDouble(),
                d60: (c['d60'] as num?)?.toDouble(),
                d90: (c['d90'] as num?)?.toDouble(),
              ),
        ],
        driftDays: [
          for (final raw in (d['drift_days'] as List? ?? const []))
            if (_asMap(raw)?['day'] case final String day) day,
        ],
      );
    } on PostgrestException catch (e) {
      throw CrayApiException(
        e.code == '42501' ? CrayErrorKind.forbidden : _postgrestKind(e),
      );
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  static int _int(Object? value) => switch (value) {
        int v => v,
        num v => v.round(),
        String v => int.tryParse(v) ?? 0,
        _ => 0,
      };

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
