// lib/features/customer/customer_discover_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import './providers/event_providers_customer.dart';
import 'widgets/event_card_customer.dart';
import 'widgets/shared_widgets.dart';

class CustomerDiscoverScreen extends ConsumerWidget {
  const CustomerDiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(publicEventsProvider);

    return Scaffold(
      backgroundColor: AppTheme.cardColor,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(ref),
          eventsAsync.when(
            loading: _buildLoading,
            error: (e, _) => _buildError(e.toString()),
            data: _buildEventList,
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(WidgetRef ref) {
    return SliverAppBar(
      floating: true,
      snap: true,
      backgroundColor: AppTheme.cardColor,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Discover Events', style: AppTheme.merri(fontSize: 22)),
          Text(
            'Find & purchase tickets',
            style:
            AppTheme.sans(fontSize: 11, color: AppTheme.subTextColor),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded,
              color: AppTheme.primaryColor),
          onPressed: () => ref.invalidate(publicEventsProvider),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildLoading() => const SliverFillRemaining(
    child: Center(
      child: CircularProgressIndicator(
          color: AppTheme.primaryColor, strokeWidth: 2),
    ),
  );

  Widget _buildError(String message) => SliverFillRemaining(
    child: ErrorState(message: message),
  );

  Widget _buildEventList(List<Map<String, dynamic>> events) {
    if (events.isEmpty) {
      return const SliverFillRemaining(child: EmptyState());
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
              (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: EventCard(event: events[i]),
          ),
          childCount: events.length,
        ),
      ),
    );
  }
}