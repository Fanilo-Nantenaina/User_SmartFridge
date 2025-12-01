import 'package:flutter/material.dart';
import 'package:user_smartfridge/service/notification.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final NotificationService _notificationService = NotificationService();

  bool _expiryNotifications = true;
  bool _lostItemNotifications = true;
  bool _lowStockNotifications = true;
  bool _inventoryUpdates = true;

  bool _vibration = true;
  bool _sound = true;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _expiryNotifications = prefs.getBool('notif_expiry') ?? true;
      _lostItemNotifications = prefs.getBool('notif_lost') ?? true;
      _lowStockNotifications = prefs.getBool('notif_stock') ?? true;
      _inventoryUpdates = prefs.getBool('notif_inventory') ?? true;

      _vibration = _notificationService.vibrationEnabled;
      _sound = _notificationService.soundEnabled;

      _isLoading = false;
    });
  }

  Future<void> _savePreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        children: [
          _buildSection(
            title: 'Types d\'alertes',
            icon: Icons.notifications_active_outlined,
            children: [
              _buildSwitchTile(
                title: 'Produits expirant bientôt',
                subtitle: 'Alertes 3 jours avant expiration',
                icon: Icons.schedule_outlined,
                iconColor: const Color(0xFFF59E0B),
                value: _expiryNotifications,
                onChanged: (value) {
                  setState(() => _expiryNotifications = value);
                  _savePreference('notif_expiry', value);
                },
              ),
              _buildSwitchTile(
                title: 'Produits expirés',
                subtitle: 'Alertes produits périmés',
                icon: Icons.dangerous_outlined,
                iconColor: const Color(0xFFEF4444),
                value: _expiryNotifications,
                onChanged: (value) {
                  setState(() => _expiryNotifications = value);
                  _savePreference('notif_expiry', value);
                },
              ),
              _buildSwitchTile(
                title: 'Objets perdus',
                subtitle: 'Produits non détectés',
                icon: Icons.search_off_outlined,
                iconColor: const Color(0xFFF59E0B),
                value: _lostItemNotifications,
                onChanged: (value) {
                  setState(() => _lostItemNotifications = value);
                  _savePreference('notif_lost', value);
                },
              ),
              _buildSwitchTile(
                title: 'Stock faible',
                subtitle: 'Produits en rupture',
                icon: Icons.trending_down,
                iconColor: const Color(0xFF3B82F6),
                value: _lowStockNotifications,
                onChanged: (value) {
                  setState(() => _lowStockNotifications = value);
                  _savePreference('notif_stock', value);
                },
              ),
              _buildSwitchTile(
                title: 'Mises à jour inventaire',
                subtitle: 'Scan kiosk, consommations',
                icon: Icons.inventory_2_outlined,
                iconColor: const Color(0xFF10B981),
                value: _inventoryUpdates,
                onChanged: (value) {
                  setState(() => _inventoryUpdates = value);
                  _savePreference('notif_inventory', value);
                },
              ),
            ],
          ),

          _buildSection(
            title: 'Son et vibration',
            icon: Icons.volume_up_outlined,
            children: [
              _buildSwitchTile(
                title: 'Vibration',
                subtitle: 'Faire vibrer le téléphone',
                icon: Icons.vibration,
                iconColor: const Color(0xFF8B5CF6),
                value: _vibration,
                onChanged: (value) async {
                  setState(() => _vibration = value);
                  await _notificationService.setVibrationEnabled(value);
                },
              ),
              _buildSwitchTile(
                title: 'Son',
                subtitle: 'Jouer un son de notification',
                icon: Icons.music_note,
                iconColor: const Color(0xFF8B5CF6),
                value: _sound,
                onChanged: (value) async {
                  setState(() => _sound = value);
                  await _notificationService.setSoundEnabled(value);
                },
              ),
            ],
          ),

          _buildSection(
            title: 'Test',
            icon: Icons.bug_report_outlined,
            children: [
              _buildActionTile(
                title: 'Tester les notifications',
                subtitle: 'Envoyer une notification de test',
                icon: Icons.send_outlined,
                iconColor: const Color(0xFF3B82F6),
                onTap: () async {
                  await _notificationService.showNotification(
                    title: '🧪 Test de notification',
                    body: 'Les notifications fonctionnent correctement !',
                    alertType: 'EXPIRY_SOON',
                  );
                  _showSuccess('Notification envoyée');
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 20,
                          color: Color(0xFF64748B)
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'À propos',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Les notifications vous permettent de rester informé '
                        'de l\'état de votre frigo en temps réel.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF64748B)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      value: value,
      onChanged: onChanged,
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: Color(0xFF1E293B),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF64748B),
        ),
      ),
      activeColor: const Color(0xFF3B82F6),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: Color(0xFF1E293B),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF64748B),
        ),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Color(0xFF94A3B8),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}