import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:user_smartfridge/screens/auth.dart';
import 'package:user_smartfridge/service/api.dart';
import 'package:user_smartfridge/service/fridge.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  final ClientApiService _api = ClientApiService();
  List<dynamic> _alerts = [];
  bool _isLoading = true;
  String _filter = 'pending';
  int? _selectedFridgeId;
  String _sortOrder = 'desc';

  final _fridgeService = FridgeService();
  StreamSubscription<int?>? _fridgeSubscription;

  @override
  void initState() {
    super.initState();

    _fridgeSubscription = _fridgeService.fridgeStream.listen((fridgeId) {
      if (fridgeId != null && fridgeId != _selectedFridgeId) {
        _selectedFridgeId = fridgeId;
        _loadAlerts();
      }
    });
    _loadAlerts();
  }

  @override
  void dispose() {
    _fridgeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);

    try {
      final fridges = await _api.getFridges();

      if (fridges.isEmpty) {
        setState(() {
          _alerts = [];
          _selectedFridgeId = null;
          _isLoading = false;
        });
        return;
      }

      int? savedFridgeId = await _fridgeService.getSelectedFridge();

      if (savedFridgeId != null &&
          fridges.any((f) => f['id'] == savedFridgeId)) {
        _selectedFridgeId = savedFridgeId;
      } else {
        _selectedFridgeId = fridges[0]['id'];
        await _fridgeService.setSelectedFridge(_selectedFridgeId!);
      }

      if (kDebugMode) {
        print('🔔 AlertsPage: Loading alerts for fridge $_selectedFridgeId');
      }

      final alerts = await _api.getAlerts(
        _selectedFridgeId!,
        status: _filter == 'all' ? null : _filter,
      );

      final sortedAlerts = List<dynamic>.from(alerts);
      sortedAlerts.sort((a, b) {
        final dateA =
            DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.now();
        final dateB =
            DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();

        return _sortOrder == 'desc'
            ? dateB.compareTo(dateA)
            : dateA.compareTo(dateB);
      });

      setState(() {
        _alerts = sortedAlerts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);

      if (e.toString().contains('Non autorisé') ||
          e.toString().contains('401')) {
        await _api.logout();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
      } else {
        _showError('Erreur: $e');
      }
    }
  }

  // 🆕 Fonction pour extraire la date d'expiration du message d'origine
  DateTime? _extractExpiryDateFromAlert(Map<String, dynamic> alert) {
    try {
      final message = alert['message'] ?? '';

      // Rechercher un pattern de date dans le message
      final dateMatch = RegExp(
        r'(\d{1,2})/(\d{1,2})/(\d{4})',
      ).firstMatch(message);
      if (dateMatch != null) {
        final day = int.parse(dateMatch.group(1)!);
        final month = int.parse(dateMatch.group(2)!);
        final year = int.parse(dateMatch.group(3)!);
        return DateTime(year, month, day);
      }

      // Si pas de date trouvée, essayer avec expiry_date si présent
      if (alert['expiry_date'] != null) {
        return DateTime.parse(alert['expiry_date']);
      }
    } catch (e) {
      if (kDebugMode) print('Erreur extraction date: $e');
    }
    return null;
  }

  // 🆕 Fonction pour recalculer le message dynamiquement
  String _getDynamicAlertMessage(Map<String, dynamic> alert) {
    final type = alert['type'] ?? '';
    final isResolved = alert['status'] == 'resolved';

    if (type == 'EXPIRY_SOON' || type == 'EXPIRED') {
      final expiryDate = _extractExpiryDateFromAlert(alert);

      if (expiryDate != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final expiry = DateTime(
          expiryDate.year,
          expiryDate.month,
          expiryDate.day,
        );
        final diff = expiry.difference(today).inDays;

        // Extraire le nom du produit du message original
        final originalMessage = alert['message'] ?? '';
        String productName = 'Un produit';

        // Essayer d'extraire le nom (format: "Le produit X expire...")
        final nameMatch = RegExp(
          r'Le produit (.+?) expire',
        ).firstMatch(originalMessage);
        if (nameMatch != null) {
          productName = nameMatch.group(1)!;
        }

        // 🆕 Si l'alerte est résolue, afficher la date exacte
        if (isResolved) {
          if (diff < 0) {
            return 'Le produit $productName a expiré le ${expiryDate.day.toString().padLeft(2, '0')}/${expiryDate.month.toString().padLeft(2, '0')}/${expiryDate.year}';
          } else {
            return 'Le produit $productName expire le ${expiryDate.day.toString().padLeft(2, '0')}/${expiryDate.month.toString().padLeft(2, '0')}/${expiryDate.year}';
          }
        }

        // Pour les alertes actives, message relatif
        if (diff < 0) {
          final daysExpired = diff.abs();
          if (daysExpired == 1) {
            return 'Le produit $productName a expiré hier';
          } else {
            return 'Le produit $productName a expiré il y a $daysExpired jours';
          }
        } else if (diff == 0) {
          return 'Le produit $productName expire AUJOURD\'HUI !';
        } else if (diff == 1) {
          return 'Le produit $productName expire demain';
        } else if (diff <= 3) {
          return 'Le produit $productName expire dans $diff jours';
        } else {
          return 'Le produit $productName expire le ${expiryDate.day}/${expiryDate.month}/${expiryDate.year}';
        }
      }
    }

    // Pour les autres types d'alertes, garder le message original
    return alert['message'] ?? '';
  }

  // 🆕 Fonction pour déterminer le statut d'expiration actuel
  String _getCurrentExpiryStatus(Map<String, dynamic> alert) {
    final type = alert['type'] ?? '';

    if (type == 'EXPIRY_SOON' || type == 'EXPIRED') {
      final expiryDate = _extractExpiryDateFromAlert(alert);

      if (expiryDate != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final expiry = DateTime(
          expiryDate.year,
          expiryDate.month,
          expiryDate.day,
        );
        final diff = expiry.difference(today).inDays;

        if (diff < 0) return 'expired';
        if (diff == 0) return 'expires_today';
        if (diff <= 3) return 'expiring_soon';
        return 'fresh';
      }
    }

    return type.toLowerCase();
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sort, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Trier par date',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.arrow_downward),
              title: const Text('Plus récent d\'abord'),
              subtitle: const Text('Alertes récentes en premier'),
              trailing: _sortOrder == 'desc' ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _sortOrder = 'desc');
                Navigator.pop(context);
                _loadAlerts();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('Plus ancien d\'abord'),
              subtitle: const Text('Alertes anciennes en premier'),
              trailing: _sortOrder == 'asc' ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _sortOrder = 'asc');
                Navigator.pop(context);
                _loadAlerts();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildAppBar(),
          _buildFilterChips(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _selectedFridgeId == null
                ? _buildNoFridgeState()
                : _alerts.isEmpty
                ? _buildEmptyState()
                : _buildAlertsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNoFridgeState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.kitchen_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Aucun frigo connecté',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connectez un frigo depuis le tableau de bord\npour voir les alertes',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alertes',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${_alerts.length} notification(s)',
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                        fontSize: 14,
                      ),
                    ),
                    if (_selectedFridgeId != null) ...[
                      Text(
                        ' • Frigo #$_selectedFridgeId',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              _sortOrder == 'desc' ? Icons.arrow_downward : Icons.arrow_upward,
              color: Theme.of(context).iconTheme.color,
            ),
            onPressed: _showSortOptions,
            tooltip: 'Trier',
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
            onPressed: _loadAlerts,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final pendingCount = _alerts.where((a) => a['status'] == 'pending').length;
    final resolvedCount = _alerts
        .where((a) => a['status'] == 'resolved')
        .length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip(
              'En attente',
              'pending',
              Icons.pending_outlined,
              count: pendingCount,
            ),
            const SizedBox(width: 8),
            _buildFilterChip('Toutes', 'all', Icons.list_alt),
            const SizedBox(width: 8),
            _buildFilterChip(
              'Résolues',
              'resolved',
              Icons.check_circle_outline,
              count: resolvedCount,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    String value,
    IconData icon, {
    int? count,
  }) {
    final isSelected = _filter == value;

    return InkWell(
      onTap: () {
        setState(() => _filter = value);
        _loadAlerts();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).textTheme.bodyMedium?.color,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).textTheme.bodyMedium?.color,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.3)
                      : const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    // ✅ Utiliser le statut recalculé dynamiquement
    final currentStatus = _getCurrentExpiryStatus(alert);
    final dynamicMessage = _getDynamicAlertMessage(alert);
    final isResolved = alert['status'] == 'resolved';

    // 🆕 Si résolu, forcer la couleur verte
    final color = isResolved
        ? const Color(0xFF10B981)
        : _getAlertColor(alert['type'], currentStatus);
    final icon = isResolved
        ? Icons.check_circle_outline
        : _getAlertIcon(alert['type'], currentStatus);
    final title = _getAlertTitle(alert['type'], currentStatus, alert['status']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showAlertDetails(alert),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dynamicMessage,
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                          fontSize: 13,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (alert['created_at'] != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatTime(alert['created_at']),
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(alert['status']).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getStatusText(alert['status']),
                    style: TextStyle(
                      color: _getStatusColor(alert['status']),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAlertDetails(Map<String, dynamic> alert) {
    final currentStatus = _getCurrentExpiryStatus(alert);
    final dynamicMessage = _getDynamicAlertMessage(alert);
    final isResolved = alert['status'] == 'resolved';

    // 🆕 Si résolu, forcer la couleur verte
    final color = isResolved
        ? const Color(0xFF10B981)
        : _getAlertColor(alert['type'], currentStatus);
    final icon = isResolved
        ? Icons.check_circle_outline
        : _getAlertIcon(alert['type'], currentStatus);
    final title = _getAlertTitle(alert['type'], currentStatus, alert['status']);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      if (alert['created_at'] != null)
                        Text(
                          _formatTime(alert['created_at']),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              dynamicMessage,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).textTheme.bodyMedium?.color,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 32),
            if (alert['status'] != 'resolved') ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (_selectedFridgeId == null) {
                      _showError('Aucun frigo sélectionné');
                      return;
                    }
                    try {
                      await _api.updateAlertStatus(
                        fridgeId: _selectedFridgeId!,
                        alertId: alert['id'],
                        status: 'resolved',
                      );
                      Navigator.pop(context);
                      _showSuccess('Alerte résolue');
                      _loadAlerts();
                    } catch (e) {
                      _showError('Erreur: $e');
                    }
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Marquer comme résolue'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                label: const Text('Fermer'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color,
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _filter == 'pending'
                    ? Icons.notifications_off_outlined
                    : Icons.check_circle_outline,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _filter == 'pending' ? 'Aucune alerte' : 'Aucune alerte résolue',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _filter == 'pending'
                  ? 'Tout va bien ! 👍\nVous n\'avez aucune alerte en attente'
                  : 'Vous n\'avez pas encore\nrésolu d\'alertes',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsList() {
    final criticalAlerts = _alerts
        .where((a) => _getCurrentExpiryStatus(a) == 'expired')
        .toList();
    final warningAlerts = _alerts.where((a) {
      final status = _getCurrentExpiryStatus(a);
      return status == 'expires_today' || status == 'expiring_soon';
    }).toList();
    final infoAlerts = _alerts.where((a) {
      final status = _getCurrentExpiryStatus(a);
      return !['expired', 'expires_today', 'expiring_soon'].contains(status);
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadAlerts,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (criticalAlerts.isNotEmpty) ...[
            _buildSectionHeader(
              'Critique',
              criticalAlerts.length,
              const Color(0xFFEF4444),
            ),
            ...criticalAlerts.map((alert) => _buildAlertCard(alert)),
            const SizedBox(height: 16),
          ],
          if (warningAlerts.isNotEmpty) ...[
            _buildSectionHeader(
              'Avertissement',
              warningAlerts.length,
              const Color(0xFFF59E0B),
            ),
            ...warningAlerts.map((alert) => _buildAlertCard(alert)),
            const SizedBox(height: 16),
          ],
          if (infoAlerts.isNotEmpty) ...[
            _buildSectionHeader(
              'Information',
              infoAlerts.length,
              const Color(0xFF3B82F6),
            ),
            ...infoAlerts.map((alert) => _buildAlertCard(alert)),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getAlertColor(String type, String currentStatus) {
    if (type == 'EXPIRY_SOON' || type == 'EXPIRED') {
      switch (currentStatus) {
        case 'expired':
          return const Color(0xFFEF4444); // Rouge
        case 'expires_today':
          return const Color(0xFFEF4444); // Rouge aussi
        case 'expiring_soon':
          return const Color(0xFFF59E0B); // Orange
        default:
          return const Color(0xFF10B981); // Vert (si frais)
      }
    }

    switch (type) {
      case 'LOST_ITEM':
        return const Color(0xFFF59E0B);
      case 'LOW_STOCK':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF64748B);
    }
  }

  IconData _getAlertIcon(String type, String currentStatus) {
    if (type == 'EXPIRY_SOON' || type == 'EXPIRED') {
      switch (currentStatus) {
        case 'expired':
          return Icons.dangerous_outlined; // Danger pour expiré
        case 'expires_today':
          return Icons.warning_outlined; // Avertissement urgent
        case 'expiring_soon':
          return Icons.schedule_outlined; // Horloge pour bientôt
        default:
          return Icons.check_circle_outline;
      }
    }

    switch (type) {
      case 'LOST_ITEM':
        return Icons.search_off_outlined;
      case 'LOW_STOCK':
        return Icons.trending_down;
      default:
        return Icons.notification_important_outlined;
    }
  }

  String _getAlertTitle(
    String type,
    String currentStatus,
    String? alertStatus,
  ) {
    // 🆕 Si l'alerte est résolue, afficher un message approprié
    if (alertStatus == 'resolved') {
      if (type == 'EXPIRY_SOON' || type == 'EXPIRED') {
        switch (currentStatus) {
          case 'expired':
            return 'Produit expiré (résolu)';
          case 'expires_today':
            return 'Expiration (résolu)';
          case 'expiring_soon':
            return 'Alerte traitée';
          default:
            return 'Alerte résolue';
        }
      }
      return 'Alerte résolue';
    }

    // Pour les alertes non résolues, afficher le statut actuel
    if (type == 'EXPIRY_SOON' || type == 'EXPIRED') {
      switch (currentStatus) {
        case 'expired':
          return 'Produit expiré';
        case 'expires_today':
          return 'Expire aujourd\'hui !';
        case 'expiring_soon':
          return 'Expiration proche';
        default:
          return 'Alerte produit';
      }
    }

    switch (type) {
      case 'LOST_ITEM':
        return 'Objet non détecté';
      case 'LOW_STOCK':
        return 'Stock faible';
      default:
        return 'Alerte';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'resolved':
        return const Color(0xFF10B981);
      case 'acknowledged':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'resolved':
        return 'Résolue';
      case 'acknowledged':
        return 'Vue';
      default:
        return 'En attente';
    }
  }

  String _formatTime(String dateStr) {
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays}j';
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }
}
