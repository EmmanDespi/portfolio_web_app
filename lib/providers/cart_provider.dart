import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/inventory.dart';
import 'inventory_provider.dart';

final cartProvider = StateNotifierProvider<CartNotifier, List<Item>>((ref) {
  return CartNotifier(ref);
});

class CartNotifier extends StateNotifier<List<Item>> {
  final Ref ref;
  CartNotifier(this.ref) : super([]);

  void addToCart(Item item) {
    // Add item to cart
    final index = state.indexWhere((i) => i.itemCode == item.itemCode);
    if (index != -1) {
      final updated = [...state];
      updated[index] = Item(
        itemName: item.itemName,
        itemCode: item.itemCode,
        itemPrice: item.itemPrice,
        itemCount: updated[index].itemCount + 1,
      );
      state = updated;
    } else {
      state = [...state, Item(
        itemName: item.itemName,
        itemCode: item.itemCode,
        itemPrice: item.itemPrice,
        itemCount: 1,
      )];
    }

    // Decrement inventory
    ref.read(inventoryProvider.notifier).updateItemCount(
      item.itemCode,
      ref.read(inventoryProvider)
         .firstWhere((inv) => inv.itemCode == item.itemCode).itemCount - 1,
    );
  }

  void removeFromCart(String code) {
    final item = state.firstWhere((i) => i.itemCode == code);

    // Return stock to inventory
    ref.read(inventoryProvider.notifier).updateItemCount(
      code,
      ref.read(inventoryProvider)
         .firstWhere((inv) => inv.itemCode == code).itemCount + item.itemCount,
    );

    // Remove from cart
    state = state.where((i) => i.itemCode != code).toList();
  }
}
