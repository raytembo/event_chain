// lib/features/scanner/verifier_assigned_events_provider.dart
//
// Resolves which events the *signed-in verifier* is authorized to scan
// tickets for, by reading gate_verifiers rows where verifier_id == auth.uid().
//
//   • event_id != null  → that single event.
//   • event_id == null  → "All Events" scope for that row's owner, expanded
//                          into every event belonging to that owner.
//
// Requires an RLS policy on gate_verifiers letting a verifier read their own
// rows, e.g.:
//   create policy "verifiers can read their own assignments"
//   on gate_verifiers for select
//   using (verifier_id = auth.uid());
// and a policy on events allowing those rows to be read (a public-read
// policy, or one scoped to owner_id IN (select owner_id from gate_verifiers
// where verifier_id = auth.uid())).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/supabase_service.dart';

final verifierAssignedEventsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = SupabaseService.instance;
  final uid = svc.currentUserId;
  if (uid == null) return [];

  final rows = await svc.client
      .from('gate_verifiers')
      .select(
          'event_id, owner_id, status, events(id, event_name, event_date, venue)')
      .eq('verifier_id', uid)
      .eq('status', 'active');

  final assignments = List<Map<String, dynamic>>.from(rows);
  if (assignments.isEmpty) return [];

  final specific = <Map<String, dynamic>>[];
  final allEventsOwnerIds = <String>{};

  for (final a in assignments) {
    if (a['event_id'] == null) {
      final ownerId = a['owner_id'] as String?;
      if (ownerId != null) allEventsOwnerIds.add(ownerId);
    } else {
      final ev = a['events'] as Map<String, dynamic>?;
      if (ev != null) specific.add(ev);
    }
  }

  var combined = specific;

  if (allEventsOwnerIds.isNotEmpty) {
    final allEventsRows = await svc.client
        .from('events')
        .select('id, event_name, event_date, venue')
        .inFilter('owner_id', allEventsOwnerIds.toList());

    combined = [...combined, ...List<Map<String, dynamic>>.from(allEventsRows)];
  }

  // De-dupe by event id (possible overlap between a specific-event row and
  // an "All Events" row from the same owner).
  final byId = <String, Map<String, dynamic>>{};
  for (final e in combined) {
    final id = e['id'] as String?;
    if (id != null) byId[id] = e;
  }
  return byId.values.toList();
});
