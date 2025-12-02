import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FridgeSelector extends StatefulWidget {
  final List<dynamic> fridges;
  final int? selectedFridgeId;
  final Function(int) onFridgeChanged;

  const FridgeSelector({
    super.key,
    required this.fridges,
    required this.selectedFridgeId,
    required this.onFridgeChanged,
  });

  @override
  State<FridgeSelector> createState() => _FridgeSelectorState();
}

class _FridgeSelectorState extends State<FridgeSelector> {
  Future<void> _selectFridge(int fridgeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_fridge_id', fridgeId);
    widget.onFridgeChanged(fridgeId);
  }

  void _showFridgePickerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.kitchen,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Sélectionner un frigo')),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.fridges.length,
            itemBuilder: (context, index) {
              final fridge = widget.fridges[index];
              final isSelected = fridge['id'] == widget.selectedFridgeId;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.kitchen_outlined,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).iconTheme.color,
                  ),
                ),
                title: Text(
                  fridge['name'] ?? 'Mon Frigo',
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                subtitle: fridge['location'] != null
                    ? Text(
                  fridge['location'],
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                )
                    : null,
                trailing: isSelected
                    ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                )
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _selectFridge(fridge['id']);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fridges.isEmpty) return const SizedBox.shrink();

    final selectedFridge = widget.fridges.firstWhere(
          (f) => f['id'] == widget.selectedFridgeId,
      orElse: () => widget.fridges.first,
    );

    return InkWell(
      onTap: widget.fridges.length > 1 ? _showFridgePickerDialog : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.kitchen,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                selectedFridge['name'] ?? 'Mon Frigo',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.fridges.length > 1) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 20,
                color: Theme.of(context).iconTheme.color,
              ),
            ],
          ],
        ),
      ),
    );
  }
}