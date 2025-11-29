import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_smartfridge/screens/alerts_page.dart';
import 'package:user_smartfridge/screens/dashboard_page.dart';
import 'package:user_smartfridge/screens/inventory_page.dart';
import 'package:user_smartfridge/screens/profile_page.dart';
import 'package:user_smartfridge/screens/recipes_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SmartFridgeClientApp());
}

class SmartFridgeClientApp extends StatelessWidget {
  const SmartFridgeClientApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Fridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        useMaterial3: true,
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1E293B),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.white,
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

// Auth Wrapper
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    setState(() {
      _isAuthenticated = token != null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _isAuthenticated ? const HomePage() : const LoginPage();
  }
}

// ============= LOGIN PAGE =============
class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isRegisterMode = false;
  bool _obscurePassword = true;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final api = ClientApiService();
      if (_isRegisterMode) {
        await api.register(
          email: _emailController.text,
          password: _passwordController.text,
          name: _nameController.text,
        );
      } else {
        await api.login(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isLoading = false);
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
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
                    child: const Icon(Icons.kitchen, size: 48, color: Colors.white),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Smart Fridge',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isRegisterMode ? 'Créez votre compte' : 'Bon retour !',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Form fields
                  if (_isRegisterMode) ...[
                    _buildTextField(
                      controller: _nameController,
                      label: 'Nom complet',
                      icon: Icons.person_outline,
                      validator: (v) => v?.isEmpty ?? true ? 'Requis' : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildTextField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v?.isEmpty ?? true || !v!.contains('@')
                        ? 'Email invalide' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _passwordController,
                    label: 'Mot de passe',
                    icon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (v) => v?.isEmpty ?? true || v!.length < 6
                        ? 'Min. 6 caractères' : null,
                  ),
                  const SizedBox(height: 32),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                          : Text(
                        _isRegisterMode ? 'Créer mon compte' : 'Se connecter',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Toggle mode
                  TextButton(
                    onPressed: () => setState(() => _isRegisterMode = !_isRegisterMode),
                    child: Text(
                      _isRegisterMode
                          ? 'Déjà inscrit ? Se connecter'
                          : 'Pas de compte ? S\'inscrire',
                      style: const TextStyle(color: Color(0xFF3B82F6)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF64748B)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
      ),
    );
  }
}

// ============= HOME PAGE WITH NAVIGATION =============
class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const DashboardPage(),
    const InventoryPage(),
    const RecipesPage(),
    const AlertsPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_outlined, Icons.home, 'Accueil'),
                _buildNavItem(1, Icons.inventory_2_outlined, Icons.inventory_2, 'Stock'),
                _buildNavItem(2, Icons.restaurant_menu_outlined, Icons.restaurant_menu, 'Recettes'),
                _buildNavItem(3, Icons.notifications_outlined, Icons.notifications, 'Alertes'),
                _buildNavItem(4, Icons.person_outline, Icons.person, 'Profil'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _currentIndex = index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8),
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============= API SERVICE COMPLET =============
class ClientApiService {
  static const String baseUrl = 'http://localhost:8000/api/v1';
  String? _accessToken;
  String? _refreshToken;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
  }

  Future<void> login({required String email, required String password}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _accessToken = data['access_token'];
      _refreshToken = data['refresh_token'];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', _accessToken!);
      await prefs.setString('refresh_token', _refreshToken!);
    } else {
      throw Exception('Connexion échouée: ${response.body}');
    }
  }

  Future<void> register({required String email, required String password, required String name}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password, 'name': name}),
    );

    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      _accessToken = data['access_token'];
      _refreshToken = data['refresh_token'];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', _accessToken!);
      await prefs.setString('refresh_token', _refreshToken!);
    } else {
      throw Exception('Inscription échouée: ${response.body}');
    }
  }

  Future<String> _getToken() async {
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      return _accessToken!;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    if (token == null || token.isEmpty) {
      throw Exception('Non authentifié - Token manquant');
    }

    _accessToken = token;
    return token;
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ===== USER =====
  Future<Map<String, dynamic>> getCurrentUser() async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/me'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 401) {
      throw Exception('Token invalide ou expiré');
    } else {
      throw Exception('Erreur ${response.statusCode}: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updateUser({
    String? name,
    String? preferredCuisine,
    List<String>? dietaryRestrictions,
    String? timezone,
    Map<String, dynamic>? prefs,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (preferredCuisine != null) body['preferred_cuisine'] = preferredCuisine;
    if (dietaryRestrictions != null) body['dietary_restrictions'] = dietaryRestrictions;
    if (timezone != null) body['timezone'] = timezone;
    if (prefs != null) body['prefs'] = prefs;

    final response = await http.put(
      Uri.parse('$baseUrl/users/me'),
      headers: await _getAuthHeaders(),
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Échec de mise à jour: ${response.body}');
  }

  // ===== FRIDGES =====
  Future<List<dynamic>> getFridges() async {
    final response = await http.get(
      Uri.parse('$baseUrl/fridges'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 401) {
      throw Exception('Non autorisé - Reconnectez-vous');
    } else {
      throw Exception('Erreur ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> createFridge({required String name, String? location}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/fridges'),
      headers: await _getAuthHeaders(),
      body: json.encode({'name': name, 'location': location}),
    );
    if (response.statusCode == 201) return json.decode(response.body);
    throw Exception('Failed to create fridge: ${response.body}');
  }

  Future<void> deleteFridge(int fridgeId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/fridges/$fridgeId'),
      headers: await _getAuthHeaders(),
    );
    if (response.statusCode != 204) {
      throw Exception('Failed to delete fridge');
    }
  }

  // ===== INVENTORY =====
  Future<List<dynamic>> getInventory(int fridgeId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/fridges/$fridgeId/inventory'),
      headers: await _getAuthHeaders(),
    );
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Failed to load inventory');
  }

  Future<Map<String, dynamic>> addInventoryItem({
    required int fridgeId,
    required int productId,
    required double quantity,
    String? unit,
    String? expiryDate,
  }) async {
    final body = {
      'product_id': productId,
      'quantity': quantity,
    };
    if (unit != null) body['unit'] = unit as num;
    if (expiryDate != null) body['expiry_date'] = expiryDate as num;

    final response = await http.post(
      Uri.parse('$baseUrl/fridges/$fridgeId/inventory'),
      headers: await _getAuthHeaders(),
      body: json.encode(body),
    );

    if (response.statusCode == 201) {
      return json.decode(response.body);
    }
    throw Exception('Failed to add item: ${response.body}');
  }

  Future<void> consumeItem({required int fridgeId, required int itemId, required double quantityConsumed}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/fridges/$fridgeId/inventory/$itemId/consume'),
      headers: await _getAuthHeaders(),
      body: json.encode({'quantity_consumed': quantityConsumed}),
    );
    if (response.statusCode != 200) throw Exception('Failed to consume item');
  }

  Future<void> deleteInventoryItem({required int fridgeId, required int itemId}) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/fridges/$fridgeId/inventory/$itemId'),
      headers: await _getAuthHeaders(),
    );
    if (response.statusCode != 204) {
      throw Exception('Failed to delete item');
    }
  }

  // ===== PRODUCTS =====
  Future<List<dynamic>> getProducts({String? search, int limit = 50}) async {
    var url = '$baseUrl/products?limit=$limit';
    if (search != null && search.isNotEmpty) {
      url += '&search=$search';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load products');
  }

  // ===== ALERTS =====
  Future<List<dynamic>> getAlerts(int fridgeId, {String? status}) async {
    var url = '$baseUrl/fridges/$fridgeId/alerts';
    if (status != null) url += '?status=$status';
    final response = await http.get(Uri.parse(url), headers: await _getAuthHeaders());
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Failed to load alerts');
  }

  Future<void> updateAlertStatus({
    required int fridgeId,
    required int alertId,
    required String status,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/fridges/$fridgeId/alerts/$alertId'),
      headers: await _getAuthHeaders(),
      body: json.encode({'status': status}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update alert');
    }
  }

  // ===== RECIPES =====
  Future<List<dynamic>> getRecipes() async {
    final response = await http.get(Uri.parse('$baseUrl/recipes'), headers: await _getAuthHeaders());
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Failed to load recipes');
  }

  Future<List<dynamic>> getFeasibleRecipes(int fridgeId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/fridges/$fridgeId/feasible'),
      headers: await _getAuthHeaders(),
    );
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Failed to load feasible recipes');
  }

  Future<void> addRecipeToFavorites(int recipeId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/recipes/$recipeId/favorite'),
      headers: await _getAuthHeaders(),
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to add favorite');
    }
  }

  Future<void> removeRecipeFromFavorites(int recipeId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/recipes/$recipeId/favorite'),
      headers: await _getAuthHeaders(),
    );
    if (response.statusCode != 204) {
      throw Exception('Failed to remove favorite');
    }
  }

  Future<List<dynamic>> getFavoriteRecipes() async {
    final response = await http.get(
      Uri.parse('$baseUrl/recipes/favorites/mine'),
      headers: await _getAuthHeaders(),
    );
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Failed to load favorites');
  }

  // ===== SHOPPING LISTS =====
  Future<Map<String, dynamic>> generateShoppingList({
    required int fridgeId,
    List<int>? recipeIds,
  }) async {
    final body = {'fridge_id': fridgeId};
    if (recipeIds != null) body['recipe_ids'] = recipeIds as int;

    final response = await http.post(
      Uri.parse('$baseUrl/shopping-lists/generate'),
      headers: await _getAuthHeaders(),
      body: json.encode(body),
    );

    if (response.statusCode == 201) {
      return json.decode(response.body);
    }
    throw Exception('Failed to generate shopping list');
  }

  // ===== DEVICES =====
  Future<Map<String, dynamic>> pairDevice(String pairingCode) async {
    final fridges = await getFridges();
    if (fridges.isEmpty) throw Exception('Aucun frigo disponible');

    final response = await http.post(
      Uri.parse('$baseUrl/fridges/${fridges[0]['id']}/devices/pair'),
      headers: await _getAuthHeaders(),
      body: json.encode({
        'pairing_code': pairingCode,
        'device_type': 'mobile',
        'device_name': 'Mon téléphone',
      }),
    );
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Failed to pair device');
  }

  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }
}