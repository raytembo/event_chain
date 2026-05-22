// lib/features/events/events_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:latlong2/latlong.dart';

import '../../core/ffi_bridge/eventchain_ffi.dart';
import '../../core/services/supabase_storage_service.dart';
import '../../shared/theme/app_theme.dart';
import 'events_provider.dart';
import 'event_detail_screen.dart';
import 'event_location_picker.dart';

final ownerEventsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];
  final res = await supabase
      .from('events')
      .select()
      .eq('owner_id', userId)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(res);
});

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(eventsProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(ownerEventsProvider);
    return Scaffold(
      backgroundColor: AppTheme.cardColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: AppTheme.cardColor,
            elevation: 0,
            title: Text('My Events', style: AppTheme.merri(fontSize: 22)),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    color: AppTheme.primaryColor),
                onPressed: () {
                  ref.invalidate(ownerEventsProvider);
                  ref.read(eventsProvider.notifier).refresh();
                },
              ),
            ],
          ),
          eventsAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.primaryColor,
                  strokeWidth: 2,
                ),
              ),
            ),
            error: (err, _) => SliverFillRemaining(
              child: _ErrorState(message: err.toString()),
            ),
            data: (events) => events.isEmpty
                ? SliverFillRemaining(
                    child: _EmptyState(
                      onCreateTapped: () => _showFormSheet(context),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _EventCard(
                            event: events[i],
                            onTap: () => _openEvent(events[i]),
                            onEdit: () =>
                                _showFormSheet(context, eventToEdit: events[i]),
                            onDelete: () => _confirmDelete(events[i]),
                          ),
                        ),
                        childCount: events.length,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.black,
        onPressed: () => _showFormSheet(context),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(
          'New Event',
          style: AppTheme.sans(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  Future<void> _openEvent(Map<String, dynamic> ev) async {
    final eventName = ev['event_name'] as String;
    final loaded = ref.read(eventsProvider).eventNames.contains(eventName);
    if (!loaded) {
      await ref.read(eventsProvider.notifier).loadRemoteChain(eventName);
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          eventName: eventName,
          eventId: ev['id'] as String,
          posterUrl: ev['poster_url'] as String? ?? '',
          venue: ev['venue'] as String?,
          eventDate: _formatDate(ev['event_date']),
        ),
      ),
    ).then((_) {
      ref.invalidate(ownerEventsProvider);
      ref.read(eventsProvider.notifier).refresh();
    });
  }

  void _showFormSheet(BuildContext context,
      {Map<String, dynamic>? eventToEdit}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EventFormSheet(eventToEdit: eventToEdit),
    ).then((_) {
      ref.invalidate(ownerEventsProvider);
      ref.read(eventsProvider.notifier).refresh();
    });
  }

  Future<void> _confirmDelete(Map<String, dynamic> event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Event?', style: AppTheme.merri(fontSize: 18)),
        content: Text(
          'This will permanently remove the event, all tickets, payments, '
          'blockchain file, and uploaded images.\n\nThis cannot be undone.',
          style: AppTheme.sans(fontSize: 14, color: AppTheme.subTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: AppTheme.sans(color: AppTheme.subTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.tamperedColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: AppTheme.sans(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final scaffold = ScaffoldMessenger.of(context);
    final supabase = Supabase.instance.client;
    final eventId = event['id'] as String;
    final eventName = event['event_name'] as String;
    try {
      scaffold.showSnackBar(const SnackBar(
        content: Text('Deleting event…'),
        duration: Duration(seconds: 2),
      ));
      await supabase.from('events').delete().eq('id', eventId);

      // Delegate storage cleanup to the service so bucket names stay in one place.
      final storage = SupabaseStorageService.instance;
      await storage.deleteBlockchainFile(eventName);
      await storage.deleteEventPoster(eventId);
      ref.invalidate(ownerEventsProvider);
      ref.read(eventsProvider.notifier).refresh();
      scaffold.showSnackBar(SnackBar(
        content:
            Text('Event deleted.', style: AppTheme.sans(color: Colors.black)),
        backgroundColor: AppTheme.authenticColor,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      scaffold.showSnackBar(SnackBar(
        content: Text('Error: $e', style: AppTheme.sans()),
        backgroundColor: AppTheme.tamperedColor,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  static String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.day.toString().padLeft(2, '0')} '
          '${_month(dt.month)} ${dt.year}';
    } catch (_) {
      return raw.toString();
    }
  }

  static String _month(int m) => const [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][m];
}

class _EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EventCard({
    required this.event,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  static String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.day.toString().padLeft(2, '0')} '
          '${const [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][dt.month]}'
          ' ${dt.year}';
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final posterUrl = event['poster_url'] as String?;
    final name = event['event_name'] as String? ?? '';
    final date = _formatDate(event['event_date']);
    final venue = event['venue'] as String? ?? '';
    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                if (posterUrl != null && posterUrl.isNotEmpty)
                  Image.network(
                    posterUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _posterPlaceholder(),
                  )
                else
                  _posterPlaceholder(),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 80,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xCC1A1A1A)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: AppTheme.merri(fontSize: 16)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded,
                                size: 11, color: AppTheme.subTextColor),
                            const SizedBox(width: 5),
                            Text(
                              date,
                              style: AppTheme.sans(
                                fontSize: 11,
                                color: AppTheme.subTextColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.location_on_outlined,
                                size: 11, color: AppTheme.subTextColor),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                venue,
                                style: AppTheme.sans(
                                  fontSize: 11,
                                  color: AppTheme.subTextColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      _IconBtn(
                        icon: Icons.edit_outlined,
                        color: AppTheme.primaryColor,
                        onTap: onEdit,
                        tooltip: 'Edit',
                      ),
                      const SizedBox(width: 4),
                      _IconBtn(
                        icon: Icons.delete_outline_rounded,
                        color: AppTheme.tamperedColor,
                        onTap: onDelete,
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _posterPlaceholder() => Container(
        height: 180,
        width: double.infinity,
        color: const Color(0xFF252525),
        child: const Center(
          child: Icon(Icons.event_rounded, color: Color(0xFF3A3A3A), size: 48),
        ),
      );
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      );
}

class _TicketEntry {
  final String type;
  final TextEditingController priceCtrl;
  final TextEditingController qtyCtrl;

  _TicketEntry({
    required this.type,
    double price = 0,
    int qty = 0,
  })  : priceCtrl = TextEditingController(
          text: price > 0 ? price.toStringAsFixed(2) : '',
        ),
        qtyCtrl = TextEditingController(
          text: qty > 0 ? qty.toString() : '',
        );

  double get price => double.tryParse(priceCtrl.text) ?? 0.0;
  int get qty => int.tryParse(qtyCtrl.text) ?? 0;

  void dispose() {
    priceCtrl.dispose();
    qtyCtrl.dispose();
  }
}

class _EventFormSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? eventToEdit;
  const _EventFormSheet({this.eventToEdit});

  @override
  ConsumerState<_EventFormSheet> createState() => _EventFormSheetState();
}

class _EventFormSheetState extends ConsumerState<_EventFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _venueCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime? _eventDate;
  File? _posterFile;
  LatLng? _selectedLocation;
  bool _submitting = false;
  bool _triedSubmit = false;

  late final List<_TicketEntry> _entries;

  bool get _isEdit => widget.eventToEdit != null;

  @override
  void initState() {
    super.initState();
    _entries = [
      _TicketEntry(type: 'General'),
      _TicketEntry(type: 'VIP'),
      _TicketEntry(type: 'Backstage'),
      _TicketEntry(type: 'Student'),
    ];
    if (_isEdit) {
      final e = widget.eventToEdit!;
      _nameCtrl.text = e['event_name'] ?? '';
      _venueCtrl.text = e['venue'] ?? '';
      _descCtrl.text = e['description'] ?? '';
      final dateRaw = e['event_date'];
      if (dateRaw != null) {
        try {
          _eventDate = DateTime.parse(dateRaw.toString()).toLocal();
        } catch (_) {}
      }
      if (e['latitude'] != null && e['longitude'] != null) {
        _selectedLocation = LatLng(
          (e['latitude'] as num).toDouble(),
          (e['longitude'] as num).toDouble(),
        );
      }
      _loadExistingPrices(e['id'] as String);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _venueCtrl.dispose();
    _descCtrl.dispose();
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExistingPrices(String eventId) async {
    try {
      final rows = await Supabase.instance.client
          .from('event_ticket_types')
          .select()
          .eq('event_id', eventId);
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final type = row['ticket_type'] as String;
        final entry = _entries.firstWhere(
          (e) => e.type == type,
          orElse: () => _TicketEntry(type: type),
        );
        entry.priceCtrl.text =
            (row['price'] as num).toDouble().toStringAsFixed(2);
        entry.qtyCtrl.text = (row['quantity_available'] as int).toString();
      }
      setState(() {});
    } catch (e) {
      debugPrint('_loadExistingPrices: $e');
    }
  }

  Future<void> _pickPoster() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked != null) setState(() => _posterFile = File(picked.path));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _eventDate = picked);
  }

  Future<void> _pickLocation() async {
    final picked = await Navigator.push<LatLng?>(
      context,
      MaterialPageRoute(
        builder: (_) => EventLocationPickerScreen(
          initialLocation: _selectedLocation,
        ),
      ),
    );
    if (picked != null) {
      setState(() => _selectedLocation = picked);
    }
  }

  Future<void> _submit() async {
    setState(() => _triedSubmit = true);
    if (!_formKey.currentState!.validate()) return;
    if (_eventDate == null) {
      _snack('Please select an event date', error: true);
      return;
    }
    if (!_isEdit && _posterFile == null) {
      _snack('Please select an event poster', error: true);
      return;
    }
    final activeEntries =
        _entries.where((e) => e.price > 0 && e.qty > 0).toList();
    if (activeEntries.isEmpty) {
      _snack('Set price & quantity for at least one ticket type', error: true);
      return;
    }
    setState(() => _submitting = true);
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    try {
      final dateIso = _eventDate!.toUtc().toIso8601String();
      if (_isEdit) {
        final eventId = widget.eventToEdit!['id'] as String;
        await supabase.from('events').update({
          'event_name': _nameCtrl.text.trim(),
          'event_date': dateIso,
          'venue': _venueCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'latitude': _selectedLocation?.latitude,
          'longitude': _selectedLocation?.longitude,
        }).eq('id', eventId);
        for (final entry in activeEntries) {
          await supabase.from('event_ticket_types').upsert(
            {
              'event_id': eventId,
              'ticket_type': entry.type,
              'price': entry.price,
              'quantity_available': entry.qty,
            },
            onConflict: 'event_id,ticket_type',
          );
        }
      } else {
        final eventId = const Uuid().v4();
        final posterUrl =
            await SupabaseStorageService.instance.uploadEventPoster(
          eventId: eventId,
          imageFile: _posterFile!,
        );
        if (posterUrl == null || (posterUrl).isEmpty) {
          throw Exception('Poster upload failed');
        }
        await supabase.from('events').insert({
          'id': eventId,
          'owner_id': userId,
          'event_name': _nameCtrl.text.trim(),
          'event_date': dateIso,
          'venue': _venueCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'poster_url': posterUrl,
          'latitude': _selectedLocation?.latitude,
          'longitude': _selectedLocation?.longitude,
          'is_public': true,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        for (final entry in activeEntries) {
          await supabase.from('event_ticket_types').insert({
            'event_id': eventId,
            'ticket_type': entry.type,
            'price': entry.price,
            'quantity_available': entry.qty,
          });
        }
      }
      if (mounted) {
        Navigator.pop(context);
        _snack(_isEdit ? 'Event updated.' : 'Event created!');
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        msg,
        style: AppTheme.sans(
          color: error ? Colors.white : Colors.black,
        ),
      ),
      backgroundColor: error ? AppTheme.tamperedColor : AppTheme.primaryColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: _triedSubmit
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3A3A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _isEdit ? 'Edit Event' : 'New Event',
                style: AppTheme.merri(fontSize: 22),
              ),
              const SizedBox(height: 4),
              Text(
                _isEdit
                    ? 'Update event info and ticket pricing.'
                    : 'Fill in the details to publish your event.',
                style:
                    AppTheme.sans(fontSize: 12, color: AppTheme.subTextColor),
              ),
              const SizedBox(height: 24),
              if (!_isEdit) ...[
                const _Label('Event Poster'),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickPoster,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _posterFile != null
                            ? AppTheme.primaryColor
                            : const Color(0xFF2A2A2A),
                        width: _posterFile != null ? 1.5 : 1,
                      ),
                    ),
                    child: _posterFile != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(_posterFile!, fit: BoxFit.cover),
                                Positioned(
                                  bottom: 10,
                                  right: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Change',
                                      style: AppTheme.sans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor
                                      .withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                  color: AppTheme.primaryColor,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Tap to upload event poster',
                                style: AppTheme.sans(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'JPG or PNG recommended',
                                style: AppTheme.sans(
                                  fontSize: 11,
                                  color: AppTheme.subTextColor,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              const _Label('Event Name'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameCtrl,
                style: AppTheme.sans(),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'e.g. Blantyre Jazz Night',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Event name is required';
                  }
                  if (v.trim().length < 3) {
                    return 'Name must be at least 3 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const _Label('Event Date'),
              const SizedBox(height: 8),
              _DateField(date: _eventDate, onTap: _pickDate),
              const SizedBox(height: 16),
              const _Label('Venue'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _venueCtrl,
                style: AppTheme.sans(),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'e.g. Kamuzu Stadium',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Venue is required';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const _Label('Event Location'),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickLocation,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardMidColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedLocation != null
                          ? AppTheme.primaryColor
                          : AppTheme.dividerColor,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.map_outlined,
                          color: AppTheme.primaryColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedLocation != null
                              ? '${_selectedLocation!.latitude.toStringAsFixed(5)}, '
                                  '${_selectedLocation!.longitude.toStringAsFixed(5)}'
                              : 'Tap to choose location on map',
                          style: AppTheme.sans(
                            fontSize: 14,
                            color: _selectedLocation != null
                                ? Colors.white
                                : AppTheme.subTextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _Label('Description (optional)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descCtrl,
                style: AppTheme.sans(),
                maxLines: 3,
                maxLength: 400,
                decoration: const InputDecoration(
                  hintText: 'Short event description…',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Ticket Pricing', style: AppTheme.merri(fontSize: 14)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: const Color(0xFF2A2A2A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Set price 0 or qty 0 to disable a ticket type.',
                style: AppTheme.sans(
                  fontSize: 11,
                  color: AppTheme.subTextColor,
                ),
              ),
              const SizedBox(height: 12),
              ..._entries.map((entry) => _TicketPriceRow(entry: entry)),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          _isEdit ? 'Update Event' : 'Create Event',
                          style: AppTheme.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketPriceRow extends StatelessWidget {
  final _TicketEntry entry;
  const _TicketPriceRow({required this.entry});

  Color _color(String type) {
    switch (type.toLowerCase()) {
      case 'vip':
        return const Color(0xFFFFD700);
      case 'backstage':
        return const Color(0xFFFF6D00);
      case 'student':
        return const Color(0xFF69F0AE);
      default:
        return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(entry.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardMidColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (entry.price > 0 && entry.qty > 0)
              ? color.withValues(alpha: 0.4)
              : AppTheme.dividerColor,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                entry.type.toUpperCase(),
                style: AppTheme.sans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: entry.priceCtrl,
              style: AppTheme.sans(fontSize: 14),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
              ],
              decoration: InputDecoration(
                hintText: 'Price',
                prefixText: 'MWK ',
                hintStyle:
                    AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                filled: true,
                fillColor: const Color(0xFF252525),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: TextField(
              controller: entry.qtyCtrl,
              style: AppTheme.sans(fontSize: 14),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'Qty',
                hintStyle:
                    AppTheme.sans(fontSize: 13, color: AppTheme.subTextColor),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                filled: true,
                fillColor: const Color(0xFF252525),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTheme.sans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.subTextColor,
        ),
      );
}

class _DateField extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onTap;

  const _DateField({required this.date, required this.onTap});

  static String _fmt(DateTime dt) {
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final has = date != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.cardMidColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: has ? AppTheme.primaryColor : AppTheme.dividerColor,
            width: has ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: has ? AppTheme.primaryColor : AppTheme.subTextColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                has ? _fmt(date!) : 'Select a date',
                style: AppTheme.sans(
                  fontSize: 14,
                  fontWeight: has ? FontWeight.w600 : FontWeight.normal,
                  color: has ? Colors.white : AppTheme.subTextColor,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppTheme.subTextColor, size: 18),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTapped;
  const _EmptyState({required this.onCreateTapped});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.event_rounded,
                  size: 52,
                  color: AppTheme.primaryColor.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              Text('No Events Yet', style: AppTheme.merri(fontSize: 22)),
              const SizedBox(height: 8),
              Text(
                'Create your first event and start\nissuing on-chain tickets.',
                textAlign: TextAlign.center,
                style: AppTheme.sans(color: AppTheme.subTextColor),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 200,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onCreateTapped,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    'Create Event',
                    style: AppTheme.sans(
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: AppTheme.tamperedColor),
              const SizedBox(height: 16),
              Text('Something went wrong', style: AppTheme.merri(fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTheme.sans(color: AppTheme.subTextColor),
              ),
            ],
          ),
        ),
      );
}
