import 'package:flutter/material.dart';
import 'package:user_smartfridge/main.dart';

class RecipesPage extends StatefulWidget {
  const RecipesPage({Key? key}) : super(key: key);

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> with SingleTickerProviderStateMixin {
  final ClientApiService _api = ClientApiService();
  late TabController _tabController;
  List<dynamic> _allRecipes = [];
  List<dynamic> _feasibleRecipes = [];
  List<dynamic> _favoriteRecipes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRecipes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipes() async {
    setState(() => _isLoading = true);

    try {
      final fridges = await _api.getFridges();
      final allRecipes = await _api.getRecipes();

      List<dynamic> feasible = [];
      if (fridges.isNotEmpty) {
        feasible = await _api.getFeasibleRecipes(fridges[0]['id']);
      }

      setState(() {
        _allRecipes = allRecipes;
        _feasibleRecipes = feasible;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Erreur: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Recettes'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          tabs: const [
            Tab(text: 'Réalisables'),
            Tab(text: 'Toutes'),
            Tab(text: 'Favorites'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildFeasibleRecipes(),
          _buildAllRecipes(),
          _buildFavoriteRecipes(),
        ],
      ),
    );
  }

  Widget _buildFeasibleRecipes() {
    if (_feasibleRecipes.isEmpty) {
      return _buildEmptyState(
        'Aucune recette réalisable',
        'Ajoutez des produits à votre frigo',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRecipes,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _feasibleRecipes.length,
        itemBuilder: (context, index) {
          final item = _feasibleRecipes[index];
          final recipe = item['recipe'];
          final canMake = item['can_make'] ?? false;
          final matchPercentage = (item['match_percentage'] ?? 0.0).toDouble();

          return _buildRecipeCard(
            recipe,
            canMake: canMake,
            matchPercentage: matchPercentage,
            missingIngredients: item['missing_ingredients'] ?? [],
          );
        },
      ),
    );
  }

  Widget _buildAllRecipes() {
    if (_allRecipes.isEmpty) {
      return _buildEmptyState(
        'Aucune recette',
        'Les recettes seront bientôt disponibles',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _allRecipes.length,
      itemBuilder: (context, index) => _buildRecipeCard(_allRecipes[index]),
    );
  }

  Widget _buildFavoriteRecipes() {
    if (_favoriteRecipes.isEmpty) {
      return _buildEmptyState(
        'Aucune recette favorite',
        'Ajoutez vos recettes préférées',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _favoriteRecipes.length,
      itemBuilder: (context, index) => _buildRecipeCard(_favoriteRecipes[index]),
    );
  }

  Widget _buildRecipeCard(
      Map<String, dynamic> recipe, {
        bool? canMake,
        double? matchPercentage,
        List<dynamic>? missingIngredients,
      }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showRecipeDetails(recipe),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder
            Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.deepPurple.shade300, Colors.purple.shade500],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Center(
                child: Icon(
                  Icons.restaurant,
                  size: 64,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          recipe['title'] ?? 'Recette',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (canMake != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: canMake
                                ? Colors.green.withOpacity(0.2)
                                : Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            canMake ? 'Réalisable' : 'Incomplet',
                            style: TextStyle(
                              color: canMake ? Colors.green : Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (recipe['description'] != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      recipe['description'],
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (recipe['preparation_time'] != null) ...[
                        Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          '${recipe['preparation_time']} min',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                        const SizedBox(width: 16),
                      ],
                      if (recipe['difficulty'] != null) ...[
                        Icon(Icons.signal_cellular_alt, size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          recipe['difficulty'],
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                      const Spacer(),
                      if (matchPercentage != null)
                        Text(
                          '${matchPercentage.toInt()}% disponible',
                          style: TextStyle(
                            color: Colors.deepPurple.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  if (missingIngredients != null && missingIngredients.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${missingIngredients.length} ingrédient(s) manquant(s)',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.restaurant_menu, size: 100, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  void _showRecipeDetails(Map<String, dynamic> recipe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                recipe['title'] ?? 'Recette',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (recipe['description'] != null) ...[
                Text(
                  recipe['description'],
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              const Text(
                'Étapes de préparation',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                recipe['steps'] ?? 'Pas d\'instructions disponibles',
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Generate shopping list for this recipe
                  },
                  icon: const Icon(Icons.shopping_cart),
                  label: const Text('Générer liste de courses'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
