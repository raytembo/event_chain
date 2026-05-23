// lib/core/services/supabase_service.dart
//
// Singleton wrapper around the Supabase client.
// Covers: Auth, Profiles, Events, Event Ticket Types, Tickets, Payments.
//
// Call SupabaseService.init() once from main() before runApp().

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_model.dart';
import '../models/ticket_record.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  // ── Initialise — call once in main() ──────────────────────────────────────

  static Future<void> init({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(url: url, anonKey: anonKey);
  }

  // ── Client / Auth accessors ────────────────────────────────────────────────

  SupabaseClient get client => Supabase.instance.client;
  GoTrueClient get auth => client.auth;

  /// The currently signed-in user's UUID, or null if not authenticated.
  String? get currentUserId => auth.currentUser?.id;

  // ── Table / view query builders ────────────────────────────────────────────

  SupabaseQueryBuilder get profiles => client.from('profiles');
  SupabaseQueryBuilder get events => client.from('events');
  SupabaseQueryBuilder get eventTicketTypes =>
      client.from('event_ticket_types');
  SupabaseQueryBuilder get tickets => client.from('tickets');
  SupabaseQueryBuilder get payments => client.from('payments');

  /// Full ticket rows joined with event columns.
  /// Use this everywhere you need eventName / venue / eventDate / posterUrl
  /// on a ticket — avoids duplicating event columns in the tickets table.
  SupabaseQueryBuilder get ticketDetail => client.from('v_ticket_detail');

  /// Per-event sold / available summary — useful for owner dashboards.
  SupabaseQueryBuilder get eventTicketSummary =>
      client.from('v_event_ticket_summary');

  // ══════════════════════════════════════════════════════════════════════════
  // AUTH
  // ══════════════════════════════════════════════════════════════════════════

  /// Sign up a new user.  [role] is stored in raw_user_meta_data so the
  /// handle_new_user trigger can write the correct role into profiles.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String displayName,
    UserRole role = UserRole.customer,
  }) =>
      auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': displayName,
          'role': role.name, // 'owner' | 'customer'
        },
      );

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) =>
      auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => auth.signOut();

  // ══════════════════════════════════════════════════════════════════════════
  // PROFILES
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetch the profile for the currently signed-in user.
  Future<AppUser?> fetchCurrentUser() async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final row = await profiles.select().eq('id', uid).single();
      return AppUser.fromMap(row);
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchCurrentUser: ${e.message}');
      return null;
    }
  }

  /// Fetch any user's public profile by UUID.
  Future<AppUser?> fetchUserById(String userId) async {
    try {
      final row = await profiles.select().eq('id', userId).single();
      return AppUser.fromMap(row);
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchUserById($userId): ${e.message}');
      return null;
    }
  }

  /// Update mutable profile fields for the current user.
  /// Only pass the fields you want to change.
  Future<bool> updateProfile({
    String? displayName,
    String? phone,
    String? avatarUrl,
    String? bio,
  }) async {
    final uid = currentUserId;
    if (uid == null) return false;

    final updates = <String, dynamic>{
      if (displayName != null) 'display_name': displayName,
      if (phone != null) 'phone': phone,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (bio != null) 'bio': bio,
      // updated_at is handled automatically by the trg_profiles_updated_at trigger
    };
    if (updates.isEmpty) return true;

    try {
      await profiles.update(updates).eq('id', uid);
      return true;
    } on PostgrestException catch (e) {
      debugPrint('❌ updateProfile: ${e.message}');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EVENTS
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetch all public events (or all events the current user owns).
  Future<List<Map<String, dynamic>>> fetchPublicEvents() async {
    try {
      return await events
          .select()
          .eq('is_public', true)
          .order('event_date', ascending: true);
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchPublicEvents: ${e.message}');
      return [];
    }
  }

  /// Fetch events owned by the current user.
  Future<List<Map<String, dynamic>>> fetchMyEvents() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      return await events
          .select()
          .eq('owner_id', uid)
          .order('event_date', ascending: true);
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchMyEvents: ${e.message}');
      return [];
    }
  }

  /// Fetch a single event by its UUID.
  Future<Map<String, dynamic>?> fetchEventById(String eventId) async {
    try {
      return await events.select().eq('id', eventId).single();
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchEventById($eventId): ${e.message}');
      return null;
    }
  }

  /// Create a new event.  Returns the new row (including the generated id),
  /// or null on failure.
  Future<Map<String, dynamic>?> createEvent({
    required String eventName,
    String? description,
    DateTime? eventDate,
    String? venue,
    double? latitude,
    double? longitude,
    bool isPublic = true,
    String? posterUrl,
    int? maxTickets,
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final row = await events
          .insert({
            'owner_id': uid,
            'event_name': eventName,
            if (description != null) 'description': description,
            if (eventDate != null) 'event_date': eventDate.toIso8601String(),
            if (venue != null) 'venue': venue,
            if (latitude != null) 'latitude': latitude,
            if (longitude != null) 'longitude': longitude,
            'is_public': isPublic,
            if (posterUrl != null) 'poster_url': posterUrl,
            if (maxTickets != null) 'max_tickets': maxTickets,
          })
          .select()
          .single();
      return row;
    } on PostgrestException catch (e) {
      debugPrint('❌ createEvent: ${e.message}');
      return null;
    }
  }

  /// Update mutable event fields.  Only pass the fields you want to change.
  Future<bool> updateEvent(
    String eventId, {
    String? eventName,
    String? description,
    DateTime? eventDate,
    String? venue,
    double? latitude,
    double? longitude,
    bool? isPublic,
    String? posterUrl,
    int? maxTickets,
  }) async {
    final updates = <String, dynamic>{
      if (eventName != null) 'event_name': eventName,
      if (description != null) 'description': description,
      if (eventDate != null) 'event_date': eventDate.toIso8601String(),
      if (venue != null) 'venue': venue,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (isPublic != null) 'is_public': isPublic,
      if (posterUrl != null) 'poster_url': posterUrl,
      if (maxTickets != null) 'max_tickets': maxTickets,
    };
    if (updates.isEmpty) return true;
    try {
      await events.update(updates).eq('id', eventId);
      return true;
    } on PostgrestException catch (e) {
      debugPrint('❌ updateEvent($eventId): ${e.message}');
      return false;
    }
  }

  Future<bool> deleteEvent(String eventId) async {
    try {
      await events.delete().eq('id', eventId);
      return true;
    } on PostgrestException catch (e) {
      debugPrint('❌ deleteEvent($eventId): ${e.message}');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EVENT TICKET TYPES
  // Prices and capacities per ticket category per event.
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetch all ticket-type rows for a given event.
  Future<List<Map<String, dynamic>>> fetchTicketTypes(String eventId) async {
    try {
      return await eventTicketTypes.select().eq('event_id', eventId);
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchTicketTypes($eventId): ${e.message}');
      return [];
    }
  }

  /// Upsert a ticket-type row.
  /// Uses the (event_id, ticket_type) unique constraint for the upsert target.
  Future<bool> upsertTicketType({
    required String eventId,
    required TicketType ticketType,
    required double price,
    required int quantityAvailable,
  }) async {
    try {
      await eventTicketTypes.upsert(
        {
          'event_id': eventId,
          'ticket_type': ticketType.dbValue,
          'price': price,
          'quantity_available': quantityAvailable,
        },
        onConflict: 'event_id,ticket_type',
      );
      return true;
    } on PostgrestException catch (e) {
      debugPrint('❌ upsertTicketType: ${e.message}');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TICKETS
  // ══════════════════════════════════════════════════════════════════════════

  /// Insert a new ticket row after the blockchain block has been added.
  ///
  /// [blockIndex] is the 0-based index from the C++ chain.
  /// The quantity_sold counter is updated automatically by the
  /// trg_ticket_quantity trigger — do NOT increment it manually.
  Future<TicketRecord?> insertTicket({
    required String ticketId,
    required int blockIndex,
    required String eventId,
    required String ownerName,
    required TicketType ticketType,
    required double price,
    String? stegoUrl,
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final row = await tickets
          .insert({
            'ticket_id': ticketId,
            'block_index': blockIndex,
            'event_id': eventId,
            'owner_id': uid,
            'owner_name': ownerName,
            'ticket_type': ticketType.dbValue,
            'price': price,
            'is_sold': false,
            if (stegoUrl != null) 'stego_url': stegoUrl,
          })
          .select()
          .single();
      return TicketRecord.fromMap(row);
    } on PostgrestException catch (e) {
      debugPrint('❌ insertTicket: ${e.message}');
      return null;
    }
  }

  /// Attach (or update) the stego_url on an existing ticket after the PNG has
  /// been uploaded to Storage.
  Future<bool> updateStegoUrl({
    required String ticketId, // the UUID primary key (tickets.id)
    required String stegoUrl,
  }) async {
    try {
      await tickets.update({'stego_url': stegoUrl}).eq('id', ticketId);
      return true;
    } on PostgrestException catch (e) {
      debugPrint('❌ updateStegoUrl($ticketId): ${e.message}');
      return false;
    }
  }

  /// Fetch all active (non-deleted) tickets owned by the current user,
  /// with event fields joined via v_ticket_detail.
  Future<List<TicketRecord>> fetchMyTickets() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final rows = await ticketDetail.select().eq('owner_id', uid);
      return rows.map(TicketRecord.fromMap).toList();
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchMyTickets: ${e.message}');
      return [];
    }
  }

  /// Fetch all active tickets for an event (event-owner view).
  Future<List<TicketRecord>> fetchTicketsForEvent(String eventId) async {
    try {
      final rows = await ticketDetail.select().eq('event_id', eventId);
      return rows.map(TicketRecord.fromMap).toList();
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchTicketsForEvent($eventId): ${e.message}');
      return [];
    }
  }

  /// Fetch a single ticket by its Supabase UUID, with event fields joined.
  Future<TicketRecord?> fetchTicketById(String id) async {
    try {
      final row = await ticketDetail.select().eq('id', id).single();
      return TicketRecord.fromMap(row);
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchTicketById($id): ${e.message}');
      return null;
    }
  }

  /// Transfer a ticket to a new owner.
  ///
  /// Call AFTER EventChainFFI.transferOwnership() has succeeded so the
  /// blockchain and database stay in sync.
  Future<bool> transferTicket({
    required String ticketId, // UUID primary key (tickets.id)
    required String newOwnerId, // auth.users UUID of the buyer
    required String newOwnerName,
    String? buyerEmail,
    String? buyerPhone,
  }) async {
    try {
      await tickets.update({
        'owner_id': newOwnerId,
        'owner_name': newOwnerName,
        'is_sold': true,
        'sold_to': newOwnerId,
        'sold_at': DateTime.now().toIso8601String(),
        if (buyerEmail != null) 'buyer_email': buyerEmail,
        if (buyerPhone != null) 'buyer_phone': buyerPhone,
      }).eq('id', ticketId);
      return true;
    } on PostgrestException catch (e) {
      debugPrint('❌ transferTicket($ticketId): ${e.message}');
      return false;
    }
  }

  /// Soft-delete a ticket (cancelled / refunded).
  ///
  /// Sets deleted_at — the trg_ticket_quantity trigger automatically
  /// decrements quantity_sold on event_ticket_types.
  Future<bool> softDeleteTicket(String ticketId) async {
    try {
      await tickets.update({'deleted_at': DateTime.now().toIso8601String()}).eq(
          'id', ticketId);
      return true;
    } on PostgrestException catch (e) {
      debugPrint('❌ softDeleteTicket($ticketId): ${e.message}');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAYMENTS
  // ══════════════════════════════════════════════════════════════════════════

  /// Record a new payment for a ticket purchase.
  Future<Map<String, dynamic>?> insertPayment({
    required String ticketId,
    required String eventId,
    required double amount,
    required String buyerName,
    required String buyerEmail,
    String? buyerPhone,
    String? paymentMethod, // matches payment_method enum values
    String? cardLastFour,
    String? cardBrand,
    String? transactionReference,
    String currency = 'MWK',
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final row = await payments
          .insert({
            'ticket_id': ticketId,
            'event_id': eventId,
            'buyer_id': uid,
            'amount': amount,
            'currency': currency,
            'buyer_name': buyerName,
            'buyer_email': buyerEmail,
            if (buyerPhone != null) 'buyer_phone': buyerPhone,
            if (paymentMethod != null) 'payment_method': paymentMethod,
            if (cardLastFour != null) 'card_last_four': cardLastFour,
            if (cardBrand != null) 'card_brand': cardBrand,
            if (transactionReference != null)
              'transaction_reference': transactionReference,
          })
          .select()
          .single();
      return row;
    } on PostgrestException catch (e) {
      debugPrint('❌ insertPayment: ${e.message}');
      return null;
    }
  }

  /// Update a payment's status (e.g. pending → completed).
  Future<bool> updatePaymentStatus({
    required String paymentId,
    required String
        status, // 'pending' | 'processing' | 'completed' | 'failed' | 'refunded'
    String? failureReason,
  }) async {
    try {
      await payments.update({
        'status': status,
        'processed_at': DateTime.now().toIso8601String(),
        if (failureReason != null) 'failure_reason': failureReason,
      }).eq('id', paymentId);
      return true;
    } on PostgrestException catch (e) {
      debugPrint('❌ updatePaymentStatus($paymentId): ${e.message}');
      return false;
    }
  }

  /// Fetch all payments made by the current user.
  Future<List<Map<String, dynamic>>> fetchMyPayments() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      return await payments
          .select()
          .eq('buyer_id', uid)
          .order('created_at', ascending: false);
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchMyPayments: ${e.message}');
      return [];
    }
  }

  /// Fetch all payments for an event (event-owner view).
  Future<List<Map<String, dynamic>>> fetchPaymentsForEvent(
      String eventId) async {
    try {
      return await payments
          .select()
          .eq('event_id', eventId)
          .order('created_at', ascending: false);
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchPaymentsForEvent($eventId): ${e.message}');
      return [];
    }
  }
}
