import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// Service global pour gérer la sélection de frigo
/// Utilise un Stream pour notifier tous les widgets du changement
class FridgeService {
  // Singleton
  static final FridgeService _instance = FridgeService._internal();
  factory FridgeService() => _instance;
  FridgeService._internal();

  // StreamController pour diffuser les changements
  final _fridgeController = StreamController<int?>.broadcast();

  // Stream public pour écouter les changements
  Stream<int?> get fridgeStream => _fridgeController.stream;

  // Frigo actuellement sélectionné
  int? _currentFridgeId;
  int? get currentFridgeId => _currentFridgeId;

  /// Initialiser le service au démarrage
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _currentFridgeId = prefs.getInt('selected_fridge_id');
  }

  /// Changer le frigo sélectionné
  Future<void> setSelectedFridge(int fridgeId) async {
    if (_currentFridgeId == fridgeId) return; // Pas de changement

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_fridge_id', fridgeId);

    _currentFridgeId = fridgeId;

    // Notifier tous les listeners
    _fridgeController.add(fridgeId);
  }

  /// Obtenir le frigo sélectionné depuis SharedPreferences
  Future<int?> getSelectedFridge() async {
    if (_currentFridgeId != null) return _currentFridgeId;

    final prefs = await SharedPreferences.getInstance();
    _currentFridgeId = prefs.getInt('selected_fridge_id');
    return _currentFridgeId;
  }

  /// Nettoyer les ressources
  void dispose() {
    _fridgeController.close();
  }
}
