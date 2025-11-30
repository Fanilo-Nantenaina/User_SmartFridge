// ============================================================================
// lib/screens/search_inventory_page.dart
// ============================================================================
// ✅ Recherche intelligente avec fuzzy matching
// ✅ Commande vocale (Speech-to-Text)
// ✅ Réponse vocale (Text-to-Speech)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:user_smartfridge/service/api_service.dart';
import 'package:intl/intl.dart';

class SearchInventoryPage extends StatefulWidget {
  const SearchInventoryPage({Key? key}) : super(key: key);

  @override
  State<SearchInventoryPage> createState() => _SearchInventoryPageState();
}

class _SearchInventoryPageState extends State<SearchInventoryPage>
    with SingleTickerProviderStateMixin {
  final ClientApiService _api = ClientApiService();
  final TextEditingController _searchController = TextEditingController();

  // Reconnaissance vocale
  late stt.SpeechToText _speech;
  late FlutterTts _tts;
  bool _isListening = false;

  // Résultats
  List<dynamic> _allInventory = [];
  List<dynamic> _filteredResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  // Animation
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _tts = FlutterTts();
    _loadInventory();
    _configureTts();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _configureTts() async {
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);

    try {
      final fridges = await _api.getFridges();
      if (fridges.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final inventory = await _api.getInventory(fridges[0]['id']);

      setState(() {
        _allInventory = inventory;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Erreur: $e');
    }
  }

  // ==========================================
  // RECHERCHE INTELLIGENTE
  // ==========================================
  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredResults = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() => _hasSearched = true);

    // Normaliser la requête
    final normalizedQuery = _normalizeQuery(query.toLowerCase());

    // Recherche intelligente
    final results = _allInventory.where((item) {
      final productName = (item['product']?['name'] ?? '').toLowerCase();
      final category = (item['product']?['category'] ?? '').toLowerCase();

      // Correspondance exacte ou partielle
      return productName.contains(normalizedQuery) ||
          category.contains(normalizedQuery) ||
          _fuzzyMatch(productName, normalizedQuery);
    }).toList();

    // Trier par pertinence
    results.sort((a, b) {
      final nameA = (a['product']?['name'] ?? '').toLowerCase();
      final nameB = (b['product']?['name'] ?? '').toLowerCase();

      // Exact match en premier
      if (nameA.startsWith(normalizedQuery)) return -1;
      if (nameB.startsWith(normalizedQuery)) return 1;

      // Puis contains
      if (nameA.contains(normalizedQuery) && !nameB.contains(normalizedQuery)) return -1;
      if (!nameA.contains(normalizedQuery) && nameB.contains(normalizedQuery)) return 1;

      return 0;
    });

    setState(() => _filteredResults = results);

    // Si un seul résultat, annoncer vocalement
    if (results.length == 1) {
      _announceResult(results[0]);
    } else if (results.isEmpty) {
      _speak('Aucun produit trouvé pour $query');
    } else {
      _speak('J\'ai trouvé ${results.length} produits');
    }
  }

  String _normalizeQuery(String query) {
    // Supprimer les mots courants
    final stopWords = [
      'combien', 'reste', 'il', 'de', 'me', 'ai', 'je',
      'dans', 'mon', 'le', 'la', 'les', 'un', 'une', 'des',
      'frigo', 'réfrigérateur', 'congélateur',
      'y', 'a', 't', 'il',
    ];

    var normalized = query;
    for (var word in stopWords) {
      normalized = normalized.replaceAll(RegExp('\\b$word\\b'), '');
    }

    return normalized.trim();
  }

  bool _fuzzyMatch(String text, String query) {
    if (text.length < query.length) return false;

    var queryIndex = 0;
    for (var i = 0; i < text.length && queryIndex < query.length; i++) {
      if (text[i] == query[queryIndex]) {
        queryIndex++;
      }
    }

    return queryIndex == query.length;
  }

  // ==========================================
  // RECONNAISSANCE VOCALE
  // ==========================================
  Future<void> _startListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        print('Speech status: $status');
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        print('Speech error: $error');
        setState(() => _isListening = false);
        _showError('Erreur: ${error.errorMsg}');
      },
    );

    if (available) {
      setState(() => _isListening = true);
      _speak('Je vous écoute');

      _speech.listen(
        onResult: (result) {
          setState(() {
            _searchController.text = result.recognizedWords;
          });

          if (result.finalResult) {
            _performSearch(result.recognizedWords);
            _stopListening();
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        localeId: 'fr_FR',
      );
    } else {
      _showError('Reconnaissance vocale non disponible');
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  // ==========================================
  // ANNONCE VOCALE
  // ==========================================
  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  void _announceResult(Map<String, dynamic> item) {
    final quantity = item['quantity'];
    final unit = item['unit'];
    final productName = item['product']?['name'] ?? 'produit';

    final message = 'Il vous reste $quantity $unit de $productName';
    _speak(message);

    _showSuccess(message);
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

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================================
  // UI
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildSearchHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildResultsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Text(
                  'Interroger mon frigo',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Barre de recherche
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _performSearch,
                  decoration: InputDecoration(
                    hintText: 'Ex: Combien d\'œufs ?',
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear, color: Color(0xFF94A3B8)),
                      onPressed: () {
                        _searchController.clear();
                        _performSearch('');
                      },
                    )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Bouton microphone
              ScaleTransition(
                scale: _isListening ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isListening
                          ? [Colors.red.shade400, Colors.red.shade600]
                          : [const Color(0xFF3B82F6), const Color(0xFF2563EB)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: (_isListening ? Colors.red : const Color(0xFF3B82F6))
                            .withOpacity(0.3),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: Colors.white,
                    ),
                    onPressed: _isListening ? _stopListening : _startListening,
                  ),
                ),
              ),
            ],
          ),

          // Suggestions de recherche
          if (!_hasSearched) ...[
            const SizedBox(height: 16),
            const Text(
              'Essayez par exemple:',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildSuggestionChip('Combien d\'œufs ?'),
                _buildSuggestionChip('Reste-t-il du lait ?'),
                _buildSuggestionChip('Tomates'),
                _buildSuggestionChip('Produits laitiers'),
              ],
            ),
          ],

          // Indicateur vocal
          if (_isListening) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.mic, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'En écoute... Posez votre question',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String text) {
    return ActionChip(
      label: Text(text),
      onPressed: () {
        _searchController.text = text;
        _performSearch(text);
      },
      backgroundColor: const Color(0xFF3B82F6).withOpacity(0.1),
      labelStyle: const TextStyle(
        color: Color(0xFF3B82F6),
        fontWeight: FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: const Color(0xFF3B82F6).withOpacity(0.3)),
      ),
    );
  }

  Widget _buildResultsList() {
    if (!_hasSearched) {
      return _buildEmptyState();
    }

    if (_filteredResults.isEmpty) {
      return _buildNoResultsState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredResults.length,
      itemBuilder: (context, index) => _buildResultCard(_filteredResults[index]),
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
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search,
                size: 64,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Interrogez votre frigo',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tapez ou parlez pour rechercher un produit',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade500,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startListening,
              icon: const Icon(Icons.mic),
              label: const Text('Commencer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 100, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Aucun résultat',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Essayez avec un autre terme',
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                _searchController.clear();
                _performSearch('');
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Nouvelle recherche'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3B82F6),
                side: const BorderSide(color: Color(0xFF3B82F6)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> item) {
    final quantity = item['quantity'];
    final unit = item['unit'];
    final productName = item['product']?['name'] ?? 'Produit inconnu';
    final category = item['product']?['category'] ?? '';
    final expiryDate = item['expiry_date'] != null
        ? DateTime.parse(item['expiry_date'])
        : null;

    Color statusColor = const Color(0xFF10B981);
    String statusText = 'Disponible';
    IconData statusIcon = Icons.check_circle_outline;

    if (expiryDate != null) {
      final daysUntilExpiry = expiryDate.difference(DateTime.now()).inDays;
      if (daysUntilExpiry < 0) {
        statusColor = const Color(0xFFEF4444);
        statusText = 'Expiré';
        statusIcon = Icons.dangerous_outlined;
      } else if (daysUntilExpiry <= 3) {
        statusColor = const Color(0xFFF59E0B);
        statusText = 'À consommer rapidement';
        statusIcon = Icons.warning_outlined;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _announceResult(item),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.shopping_basket,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            productName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          if (category.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              category,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.volume_up, color: Color(0xFF3B82F6)),
                      onPressed: () => _announceResult(item),
                      tooltip: 'Lire à voix haute',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.inventory_2,
                        color: Color(0xFF3B82F6),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Il vous reste',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$quantity $unit',
                        style: const TextStyle(
                          color: Color(0xFF3B82F6),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (expiryDate != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 16, color: statusColor),
                        const SizedBox(width: 8),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '• ${_formatDate(expiryDate)}',
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('d MMM yyyy', 'fr_FR').format(date);
  }
}