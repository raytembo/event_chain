// lib/features/owner/gate_verifier_patch.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/supabase_service.dart';

final ownerEventOptionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = SupabaseService.instance;
  final userId = svc.currentUserId;
  if (userId == null) return [];

  final res = await svc.events
      .select('id, event_name')
      .eq('owner_id', userId)
      .order('event_date', ascending: true);

  return List<Map<String, dynamic>>.from(res);
});

class GateVerifiersState {
  final List<Map<String, dynamic>> verifiers;
  final bool loading;
  final bool submitting;
  final String? error;

  const GateVerifiersState({
    this.verifiers = const [],
    this.loading = false,
    this.submitting = false,
    this.error,
  });

  GateVerifiersState copyWith({
    List<Map<String, dynamic>>? verifiers,
    bool? loading,
    bool? submitting,
    String? error,
    bool clearError = false,
  }) =>
      GateVerifiersState(
        verifiers: verifiers ?? this.verifiers,
        loading: loading ?? this.loading,
        submitting: submitting ?? this.submitting,
        error: clearError ? null : error ?? this.error,
      );
}

class GateVerifiersNotifier extends Notifier<GateVerifiersState> {
  SupabaseService get _svc => SupabaseService.instance;

  @override
  GateVerifiersState build() {
    Future.microtask(refresh);
    return const GateVerifiersState(loading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final rows = await _svc.fetchAllGateVerifiers();
      state = state.copyWith(verifiers: rows, loading: false);
    } catch (e) {
      debugPrint('❌ GateVerifiersNotifier.refresh: $e');
      state = state.copyWith(
        loading: false,
        error: 'Could not load your verifiers. Please try again.',
      );
    }
  }

  /// [eventId] == null means "All Events".
  ///
  /// Mirrors the fields collected on the owner/customer register screen so
  /// the owner can fully provision a verifier's profile in one step:
  /// [displayName] + [password] are required; [phone], [bio], and
  /// [avatarUrl] are optional follow-up profile fields (avatarUrl is the
  /// public storage URL after the image has already been uploaded by the
  /// caller, same pattern as AuthNotifier.register()).
  Future<bool> invite({
    required String email,
    required String password,
    required String displayName,
    String? phone,
    String? bio,
    String? avatarUrl,
    String? eventId,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final row = await _svc.inviteGateVerifier(
        verifierEmail: email,
        password: password,
        displayName: displayName,
        phone: phone,
        bio: bio,
        avatarUrl: avatarUrl,
        eventId: eventId,
      );
      if (row == null) {
        state = state.copyWith(
          submitting: false,
          error:
              'Could not send the invite — they may already be authorized for this event.',
        );
        return false;
      }
      await refresh();
      state = state.copyWith(submitting: false);
      return true;
    } catch (e) {
      debugPrint('❌ GateVerifiersNotifier.invite: $e');
      state = state.copyWith(
        submitting: false,
        error: 'Could not send the invite. Please try again.',
      );
      return false;
    }
  }

  Future<bool> revoke(String gateVerifierId) async {
    final ok = await _svc.revokeGateVerifier(gateVerifierId);
    if (ok) {
      await refresh();
    } else {
      state =
          state.copyWith(error: 'Could not revoke access. Please try again.');
    }
    return ok;
  }

  Future<bool> reactivate(String gateVerifierId) async {
    final ok = await _svc.reactivateGateVerifier(gateVerifierId);
    if (ok) {
      await refresh();
    } else {
      state = state.copyWith(
          error: 'Could not reactivate access. Please try again.');
    }
    return ok;
  }

  Future<bool> remove(String gateVerifierId) async {
    final ok = await _svc.deleteGateVerifier(gateVerifierId);
    if (ok) {
      await refresh();
    } else {
      state = state.copyWith(
          error: 'Could not remove this entry. Please try again.');
    }
    return ok;
  }
}

final gateVerifiersProvider =
    NotifierProvider<GateVerifiersNotifier, GateVerifiersState>(
  GateVerifiersNotifier.new,
);
