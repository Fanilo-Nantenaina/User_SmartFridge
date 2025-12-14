import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:user_smartfridge/service/api.dart';

class FridgeStatisticsPage extends StatefulWidget {
  final int fridgeId;
  final int initialTab;

  const FridgeStatisticsPage({
    super.key,
    required this.fridgeId,
    this.initialTab = 0,
  });

  @override
  State<FridgeStatisticsPage> createState() => _FridgeStatisticsPageState();
}

class _FridgeStatisticsPageState extends State<FridgeStatisticsPage>
    with SingleTickerProviderStateMixin {
  final ClientApiService _api = ClientApiService();
  late TabController _tabController;

  Map<String, dynamic> _statistics = {};
  Map<String, dynamic> _eventStats = {};
  List<dynamic> _allEvents = [];
  bool _isLoading = true;
  int _selectedDays = 30;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _api.getFridgeStatistics(widget.fridgeId),
        _api.getEventStatistics(fridgeId: widget.fridgeId, days: _selectedDays),
        _api.getEvents(fridgeId: widget.fridgeId, pageSize: 100),
      ]);

      setState(() {
        _statistics = results[0] as Map<String, dynamic>;
        _eventStats = results[1] as Map<String, dynamic>;
        _allEvents = (results[2] as Map<String, dynamic>)['items'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Erreur de chargement: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Statistiques'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Vue d\'ensemble', icon: Icon(Icons.insights, size: 20)),
            Tab(text: 'Événements', icon: Icon(Icons.timeline, size: 20)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildOverviewTab(), _buildEventsTab()],
            ),
    );
  }

  // ==================== ONGLET VUE D'ENSEMBLE ====================
  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMainStatsCard(),
            const SizedBox(height: 16),
            _buildTopConsumedProducts(),
            const SizedBox(height: 16),
            _buildActivityByDayChart(),
            const SizedBox(height: 16),
            _buildSourceDistribution(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainStatsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vue d\'ensemble',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Articles actifs',
                  _statistics['active_items']?.toString() ?? '0',
                  Icons.inventory_2,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Alertes',
                  _statistics['pending_alerts']?.toString() ?? '0',
                  Icons.notifications,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Événements (30j)',
                  _statistics['recent_events']?.toString() ?? '0',
                  Icons.history,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Valeur estimée',
                  '${_statistics['estimated_value'] ?? 0}€',
                  Icons.euro,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTopConsumedProducts() {
    final topProducts = _eventStats['top_consumed_products'] as List? ?? [];

    if (topProducts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.trending_up,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Produits les plus consommés',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...topProducts
              .take(5)
              .map(
                (product) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.shopping_basket_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product['product_name'],
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                            ),
                            Text(
                              '${product['consumption_count']} fois',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${product['total_quantity']} ${product['unit']}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
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

  Widget _buildActivityByDayChart() {
    final activityByDay = _eventStats['activity_by_day'] as List? ?? [];

    if (activityByDay.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Activité par jour',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY:
                    activityByDay
                        .map((e) => (e['count'] as num).toDouble())
                        .reduce((a, b) => a > b ? a : b) *
                    1.2,
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= activityByDay.length)
                          return const Text('');
                        final day =
                            activityByDay[value.toInt()]['day'] as String;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            day.substring(0, 3),
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(
                  activityByDay.length,
                  (index) => BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: (activityByDay[index]['count'] as num).toDouble(),
                        color: Theme.of(context).colorScheme.primary,
                        width: 16,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceDistribution() {
    final sources =
        _eventStats['source_distribution'] as Map<String, dynamic>? ?? {};

    if (sources.isEmpty) {
      return const SizedBox.shrink();
    }

    final total = sources.values.fold<int>(0, (sum, val) => sum + (val as int));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pie_chart,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Source des ajouts',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...sources.entries.map((entry) {
            final percentage = total > 0
                ? (entry.value / total * 100).round()
                : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatSourceName(entry.key),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      Text(
                        '$percentage%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: percentage / 100,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    color: Theme.of(context).colorScheme.primary,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatSourceName(String source) {
    switch (source) {
      case 'manual':
        return '📱 Manuel';
      case 'vision':
        return '📷 Vision IA';
      case 'scan':
        return '🔍 Scan';
      default:
        return source;
    }
  }

  // ==================== ONGLET ÉVÉNEMENTS ====================
  Widget _buildEventsTab() {
    return Column(
      children: [
        _buildDaysFilter(),
        Expanded(
          child: _allEvents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucun événement',
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAllData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _allEvents.length,
                    itemBuilder: (context, index) {
                      final event = _allEvents[index];
                      return _buildEventCard(event);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildDaysFilter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Période :',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(width: 12),
          ...[7, 30, 90].map(
            (days) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('$days jours'),
                selected: _selectedDays == days,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedDays = days);
                    _loadAllData();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final type = event['type'] as String;
    final payload = event['payload'] as Map<String, dynamic>? ?? {};
    final createdAt = DateTime.parse(event['created_at']);

    IconData icon;
    Color color;
    String title;
    String subtitle = '';

    switch (type) {
      case 'ITEM_ADDED':
        icon = Icons.add_circle;
        color = const Color(0xFF10B981);
        title = 'Produit ajouté';
        subtitle = payload['product_name'] ?? '';
        break;
      case 'ITEM_CONSUMED':
        icon = Icons.remove_circle;
        color = const Color(0xFF3B82F6);
        title = 'Produit consommé';
        subtitle = payload['product_name'] ?? '';
        break;
      case 'ITEM_DETECTED':
        icon = Icons.camera_alt;
        color = const Color(0xFF8B5CF6);
        title = 'Scan IA';
        subtitle = '${payload['detected_items'] ?? 0} produits détectés';
        break;
      case 'QUANTITY_UPDATED':
        icon = Icons.edit;
        color = const Color(0xFFF59E0B);
        title = 'Quantité modifiée';
        subtitle = payload['product_name'] ?? '';
        break;
      case 'ALERT_CREATED':
        icon = Icons.warning_amber;
        color = const Color(0xFFEF4444);
        title = 'Alerte créée';
        subtitle = payload['alert_type'] ?? '';
        break;
      default:
        icon = Icons.circle;
        color = Theme.of(context).colorScheme.onSurfaceVariant;
        title = type.replaceAll('_', ' ');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
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
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              Text(
                '${createdAt.day}/${createdAt.month}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
