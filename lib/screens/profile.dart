import 'package:flutter/material.dart';
import 'package:user_smartfridge/main.dart';
import 'package:user_smartfridge/screens/notification_settings.dart';
import 'package:user_smartfridge/service/api.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ClientApiService _api = ClientApiService();
  Map<String, dynamic>? _user;
  List<dynamic> _fridges = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final user = await _api.getCurrentUser();
      final fridges = await _api.getFridges();

      setState(() {
        _user = user;
        _fridges = fridges;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);

      if (e.toString().contains('Non autorisé') || e.toString().contains('401')) {
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _buildProfileHeader(),
                  const SizedBox(height: 16),
                  _buildStatsCards(),
                  const SizedBox(height: 16),
                  _buildInfoSection(),
                  const SizedBox(height: 16),
                  _buildPreferencesSection(),
                  const SizedBox(height: 16),
                  _buildSettingsSection(),
                  const SizedBox(height: 16),
                  _buildDangerZone(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      floating: true,
      backgroundColor: Colors.white,
      elevation: 0,
      title: const Text(
        'Profil',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E293B),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: Color(0xFF64748B)),
          onPressed: _showEditProfileDialog,
        ),
      ],
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: CircleAvatar(
              radius: 48,
              backgroundColor: Colors.white,
              child: Text(
                (_user?['name'] ?? 'U')[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3B82F6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _user?['name'] ?? 'Utilisateur',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _user?['email'] ?? '',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Frigos',
              '${_fridges.length}',
              Icons.kitchen_outlined,
              const Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Restrictions',
              '${(_user?['dietary_restrictions'] as List?)?.length ?? 0}',
              Icons.restaurant_outlined,
              const Color(0xFF8B5CF6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Timezone',
              _user?['timezone']?.toString().split('/').last ?? 'UTC',
              Icons.access_time,
              const Color(0xFF10B981),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Informations',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          const Divider(height: 1),
          _buildInfoTile(
            Icons.access_time_outlined,
            'Fuseau horaire',
            _user?['timezone'] ?? 'UTC',
          ),
          if (_user?['preferred_cuisine'] != null)
            _buildInfoTile(
              Icons.restaurant_outlined,
              'Cuisine préférée',
              _user!['preferred_cuisine'],
            ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF64748B), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF64748B),
        ),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }

  Widget _buildPreferencesSection() {
    final restrictions = (_user?['dietary_restrictions'] as List<dynamic>?) ?? [];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Restrictions alimentaires',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Color(0xFF3B82F6)),
                  onPressed: _showAddRestrictionDialog,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: restrictions.isEmpty
                ? const Text(
              'Aucune restriction alimentaire',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontStyle: FontStyle.italic,
              ),
            )
                : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: restrictions
                  .map((r) => Chip(
                label: Text(r.toString()),
                backgroundColor: const Color(0xFF3B82F6).withOpacity(0.1),
                labelStyle: const TextStyle(
                  color: Color(0xFF3B82F6),
                  fontWeight: FontWeight.w500,
                ),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () => _removeRestriction(r.toString()),
              ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          _buildSettingsTile(
            Icons.notifications_outlined,
            'Notifications',
            'Son, vibration, alertes',
                () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationSettingsPage(),
                ),
              );
            },
          ),
          _buildSettingsTile(
            Icons.edit_outlined,
            'Modifier le profil',
            'Nom, email, photo',
            _showEditProfileDialog,
          ),
          const Divider(height: 1, indent: 68),
          _buildSettingsTile(
            Icons.restaurant_outlined,
            'Cuisine préférée',
            _user?['preferred_cuisine'] ?? 'Non définie',
            _showEditCuisineDialog,
          ),
          const Divider(height: 1, indent: 68),
          _buildSettingsTile(
            Icons.access_time_outlined,
            'Fuseau horaire',
            _user?['timezone'] ?? 'UTC',
            _showEditTimezoneDialog,
          ),
          const Divider(height: 1, indent: 68),
          _buildSettingsTile(
            Icons.info_outline,
            'À propos',
            'Version 1.0.0',
                () {
              showAboutDialog(
                context: context,
                applicationName: 'Smart Fridge',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.kitchen, size: 48),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback onTap,
      ) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFF64748B), size: 22),
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

  Widget _buildDangerZone() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: _handleLogout,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.logout,
                color: Color(0xFFEF4444),
                size: 22,
              ),
            ),
            title: const Text(
              'Déconnexion',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: Color(0xFFEF4444),
              ),
            ),
            subtitle: const Text(
              'Se déconnecter de l\'application',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditProfileDialog() async {
    final nameController = TextEditingController(text: _user?['name']);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Modifier le profil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Nom',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _api.updateUser(name: nameController.text);
                Navigator.pop(context);
                _showSuccess('Profil mis à jour');
                _loadData();
              } catch (e) {
                _showError('Erreur: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditCuisineDialog() async {
    final cuisines = ['Française', 'Italienne', 'Asiatique', 'Méditerranéenne', 'Mexicaine', 'Autre'];
    String? selected = _user?['preferred_cuisine'];

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cuisine préférée'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: cuisines.map((cuisine) => RadioListTile<String>(
            title: Text(cuisine),
            value: cuisine,
            groupValue: selected,
            onChanged: (value) async {
              try {
                await _api.updateUser(preferredCuisine: value);
                Navigator.pop(context);
                _showSuccess('Cuisine mise à jour');
                _loadData();
              } catch (e) {
                _showError('Erreur: $e');
              }
            },
          )).toList(),
        ),
      ),
    );
  }

  Future<void> _showEditTimezoneDialog() async {
    final timezones = ['UTC', 'Europe/Paris', 'America/New_York', 'Asia/Tokyo', 'Australia/Sydney'];
    String? selected = _user?['timezone'];

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Fuseau horaire'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: timezones.map((tz) => RadioListTile<String>(
            title: Text(tz),
            value: tz,
            groupValue: selected,
            onChanged: (value) async {
              try {
                await _api.updateUser(timezone: value);
                Navigator.pop(context);
                _showSuccess('Fuseau horaire mis à jour');
                _loadData();
              } catch (e) {
                _showError('Erreur: $e');
              }
            },
          )).toList(),
        ),
      ),
    );
  }

  Future<void> _showAddRestrictionDialog() async {
    final controller = TextEditingController();
    final commonRestrictions = ['lactose', 'gluten', 'nuts', 'shellfish', 'vegan', 'vegetarian'];

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Ajouter une restriction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Restriction',
                hintText: 'Ex: lactose, gluten',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Suggestions:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: commonRestrictions.map((r) => ActionChip(
                label: Text(r),
                onPressed: () => controller.text = r,
              )).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isEmpty) return;

              try {
                final current = List<String>.from(_user?['dietary_restrictions'] ?? []);
                if (!current.contains(controller.text)) {
                  current.add(controller.text);
                  await _api.updateUser(dietaryRestrictions: current);
                  Navigator.pop(context);
                  _showSuccess('Restriction ajoutée');
                  _loadData();
                }
              } catch (e) {
                _showError('Erreur: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeRestriction(String restriction) async {
    try {
      final current = List<String>.from(_user?['dietary_restrictions'] ?? []);
      current.remove(restriction);
      await _api.updateUser(dietaryRestrictions: current);
      _showSuccess('Restriction supprimée');
      _loadData();
    } catch (e) {
      _showError('Erreur: $e');
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Déconnexion'),
        content: const Text(
          'Êtes-vous sûr de vouloir vous déconnecter ?',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _api.logout();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    }
  }
}