// lib/core/services/supabase_service.dart
//
// Singleton wrapper around the Supabase client.
// Covers: Auth, Profiles, Events, Event Ticket Types, Tickets, Payments, Gate Verifiers.
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
  SupabaseQueryBuilder get gateVerifiers => client.from('gate_verifiers');

  /// Full ticket rows joined with event columns.
  SupabaseQueryBuilder get ticketDetail => client.from('v_ticket_detail');

  /// Per-event sold / available summary — useful for owner dashboards.
  SupabaseQueryBuilder get eventTicketSummary =>
      client.from('v_event_ticket_summary');

  // ══════════════════════════════════════════════════════════════════════════
  // AUTH
  // ══════════════════════════════════════════════════════════════════════════

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
          'role': role.name, // 'owner' | 'customer' | 'verifier'
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

  Future<AppUser?> fetchUserById(String userId) async {
    try {
      final row = await profiles.select().eq('id', userId).single();
      return AppUser.fromMap(row);
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchUserById($userId): ${e.message}');
      return null;
    }
  }

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

  Future<Map<String, dynamic>?> fetchEventById(String eventId) async {
    try {
      return await events.select().eq('id', eventId).single();
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchEventById($eventId): ${e.message}');
      return null;
    }
  }

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

  /// Deletes an event and everything that depends on it — ticket types,
  /// tickets, payments, and gate verifier assignments scoped to that event —
  /// via the delete_event_cascade RPC (SECURITY DEFINER, so it bypasses RLS
  /// on the child tables it touches).
  ///
  /// A plain `.delete()` here would throw a foreign key violation the moment
  /// the event has any ticket types, tickets, or payments attached, since
  /// none of the schema's FKs are declared ON DELETE CASCADE. This method
  /// only touches rows scoped to this one event_id — other events, their
  /// tickets/payments, and the owner's profile are left untouched.
  ///
  /// Requires the following to exist in Supabase (SQL Editor / migration):
  ///
  ///   CREATE OR REPLACE FUNCTION public.delete_event_cascade(p_event_id uuid)
  ///   RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
  ///   BEGIN
  ///     DELETE FROM public.payments WHERE event_id = p_event_id;
  ///     DELETE FROM public.tickets WHERE event_id = p_event_id;
  ///     DELETE FROM public.event_ticket_types WHERE event_id = p_event_id;
  ///     DELETE FROM public.gate_verifiers WHERE event_id = p_event_id;
  ///     DELETE FROM public.events WHERE id = p_event_id;
  ///   END; $$;
  Future<bool> deleteEvent(String eventId) async {
    try {
      await client.rpc('delete_event_cascade', params: {'p_event_id': eventId});
      return true;
    } on PostgrestException catch (e) {
      debugPrint('❌ deleteEvent($eventId): ${e.message}');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EVENT TICKET TYPES
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> fetchTicketTypes(String eventId) async {
    try {
      return await eventTicketTypes.select().eq('event_id', eventId);
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchTicketTypes($eventId): ${e.message}');
      return [];
    }
  }

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

  Future<bool> updateStegoUrl({
    required String ticketId,
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

  /// Fetches the current user's tickets, excluding any that have been
  /// soft-deleted via [softDeleteTicket]. deleted_at is left on the row
  /// (not hard-deleted) to preserve block_index continuity and payment
  /// audit trail, so every read path needs this filter.
  Future<List<TicketRecord>> fetchMyTickets() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final rows = await ticketDetail
          .select()
          .eq('owner_id', uid)
          .filter('deleted_at', 'is', null);
      return rows.map(TicketRecord.fromMap).toList();
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchMyTickets: ${e.message}');
      return [];
    }
  }

  /// Fetches all tickets for an event, excluding soft-deleted ones.
  /// See fetchMyTickets for why the deleted_at filter is required here.
  Future<List<TicketRecord>> fetchTicketsForEvent(String eventId) async {
    try {
      final rows = await ticketDetail
          .select()
          .eq('event_id', eventId)
          .filter('deleted_at', 'is', null);
      return rows.map(TicketRecord.fromMap).toList();
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchTicketsForEvent($eventId): ${e.message}');
      return [];
    }
  }

  Future<TicketRecord?> fetchTicketById(String id) async {
    try {
      final row = await ticketDetail.select().eq('id', id).single();
      return TicketRecord.fromMap(row);
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchTicketById($id): ${e.message}');
      return null;
    }
  }

  Future<bool> transferTicket({
    required String ticketId,
    required String newOwnerId,
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

  /// Soft-deletes a ticket by stamping deleted_at, instead of removing the
  /// row. Preferred over a hard delete for tickets specifically: it keeps
  /// block_index history intact for blockchain integrity, and preserves the
  /// payment audit trail (payments.ticket_id still resolves). Every read
  /// path (fetchMyTickets, fetchTicketsForEvent, etc.) must filter
  /// deleted_at IS NULL to hide these from view.
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

  Future<Map<String, dynamic>?> insertPayment({
    required String ticketId,
    required String eventId,
    required double amount,
    required String buyerName,
    required String buyerEmail,
    String? buyerPhone,
    String? paymentMethod,
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

  Future<bool> updatePaymentStatus({
    required String paymentId,
    required String status,
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

  // ══════════════════════════════════════════════════════════════════════════
  // GATE VERIFIERS
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetch all verifiers invited by the current owner, joining event names.
  Future<List<Map<String, dynamic>>> fetchAllGateVerifiers() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      return await client
          .from('gate_verifiers')
          .select('*, events(event_name)')
          .eq('owner_id', uid);
    } on PostgrestException catch (e) {
      debugPrint('❌ fetchAllGateVerifiers: ${e.message}');
      return [];
    }
  }

  /// Invite (create) a gate verifier account on the owner's behalf.
  ///
  /// This actually provisions a Supabase Auth user with role = 'verifier'
  /// — the previous version only staged a row in gate_verifiers and never
  /// created real credentials, so invited verifiers had nothing to log in
  /// with. [displayName], [phone], [bio], and [avatarUrl] mirror the
  /// optional profile fields on the public register screen.
  ///
  /// auth.signUp() switches the client's active session to the newly
  /// created verifier, so the owner's session is snapshotted first and
  /// restored in `finally`, before gate_verifiers is touched (its RLS
  /// policy expects owner_id == auth.uid()).
  ///
  /// Limitation: this blocks re-inviting an email that's already on this
  /// owner's gate_verifiers list (see the pre-check below), but doesn't yet
  /// support attaching an *existing* verifier account to a second event —
  /// that needs a lookup that isn't blocked by profiles RLS (e.g. a small
  /// Postgres function), which isn't wired up here.
  Future<Map<String, dynamic>?> inviteGateVerifier({
    required String verifierEmail,
    required String password,
    String? eventId,
    String? displayName,
    String? phone,
    String? bio,
    String? avatarUrl,
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;

    final normalisedEmail = verifierEmail.trim().toLowerCase();
    final ownerSession = auth.currentSession;

    // Block duplicate invites for this owner + email before creating any
    // Auth account.
    final existingInvite = await client
        .from('gate_verifiers')
        .select('id')
        .eq('owner_id', uid)
        .eq('verifier_email', normalisedEmail)
        .maybeSingle();
    if (existingInvite != null) {
      debugPrint('❌ inviteGateVerifier: $normalisedEmail already invited');
      return null;
    }

    String? verifierId;
    try {
      final response = await signUp(
        email: normalisedEmail,
        password: password,
        displayName: (displayName != null && displayName.trim().isNotEmpty)
            ? displayName.trim()
            : normalisedEmail,
        role: UserRole.verifier,
      );

      verifierId = response.user?.id;
      if (verifierId == null) {
        debugPrint('❌ inviteGateVerifier: signUp returned no user');
        return null;
      }

      // Still signed in as the new verifier here, so this is just like the
      // follow-up update in AuthNotifier.register().
      final extras = <String, dynamic>{
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (bio != null && bio.trim().isNotEmpty) 'bio': bio.trim(),
        if (avatarUrl != null && avatarUrl.trim().isNotEmpty)
          'avatar_url': avatarUrl.trim(),
      };
      if (extras.isNotEmpty) {
        await profiles.update(extras).eq('id', verifierId);
      }
    } on AuthException catch (e) {
      debugPrint('❌ inviteGateVerifier auth error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('❌ inviteGateVerifier unexpected error: $e');
      return null;
    } finally {
      // Always hand the session back to the owner, success or failure.
      if (ownerSession != null) {
        await auth.setSession(ownerSession.refreshToken!);
      }
    }

    try {
      final row = await client
          .from('gate_verifiers')
          .insert({
            'owner_id': uid,
            'verifier_id': verifierId,
            'verifier_email': normalisedEmail,
            'setup_password': password,
            'event_id': eventId,
            'status': 'active',
            if (displayName != null) 'verifier_name': displayName,
            if (phone != null) 'verifier_phone': phone,
            if (bio != null) 'verifier_bio': bio,
            if (avatarUrl != null) 'verifier_avatar_url': avatarUrl,
          })
          .select()
          .single();
      return row;
    } on PostgrestException catch (e) {
      debugPrint(
          '❌ inviteGateVerifier database error: ${e.message} | Details: ${e.details}');
      return null;
    }
  }

  Future<bool> revokeGateVerifier(String id) async {
    try {
      await client
          .from('gate_verifiers')
          .update({'status': 'revoked'}).eq('id', id);
      return true;
    } on PostgrestException catch (e) {
      debugPrint('❌ revokeGateVerifier: ${e.message}');
      return false;
    }
  }

  Future<bool> reactivateGateVerifier(String id) async {
    try {
      await client
          .from('gate_verifiers')
          .update({'status': 'active'}).eq('id', id);
      return true;
    } on PostgrestException catch (e) {
      debugPrint('❌ reactivateGateVerifier: ${e.message}');
      return false;
    }
  }

  /// Removes a gate verifier assignment. Safe as a plain hard delete —
  /// gate_verifiers is a leaf table (nothing else has a FK pointing at it),
  /// so this never touches events, tickets, or payments.
  Future<bool> deleteGateVerifier(String id) async {
    try {
      await client.from('gate_verifiers').delete().eq('id', id);
      return true;
    } on PostgrestException catch (e) {
      debugPrint('❌ deleteGateVerifier: ${e.message}');
      return false;
    }
  }
}
