// lib/features/customer/providers/events_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fetches all public events with their ticket types in a single query.
final publicEventsProvider =
FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await Supabase.instance.client
      .from('events')
      .select(
    '*, owner:profiles(display_name), ticket_types:event_ticket_types(*)',
  )
      .eq('is_public', true)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(res);
});