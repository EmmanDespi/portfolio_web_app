import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/inventory.dart';

final inventoryProvider = StateNotifierProvider<InventoryNotifier, List<Item>>((ref) {
  return InventoryNotifier([
    Item(itemName: "Wooden Lamp", itemCode: "WL001", itemPrice: 45.00, itemCount: 50),
    Item(itemName: "Handmade Necklace", itemCode: "HN002", itemPrice: 30.00, itemCount: 50),
    Item(itemName: "Ceramic Vase", itemCode: "CV003", itemPrice: 25.00, itemCount: 50),
    Item(itemName: "Knitted Bag", itemCode: "KB004", itemPrice: 40.00, itemCount: 50),
  ]);
});

class InventoryNotifier extends StateNotifier<List<Item>> {
  InventoryNotifier(super.state);

  void updateItemCount(String code, int newCount) {
    state = [
      for (final item in state)
        if (item.itemCode == code)
          Item(
            itemName: item.itemName,
            itemCode: item.itemCode,
            itemPrice: item.itemPrice,
            itemCount: newCount,
          )
        else
          item
    ];
  }
}
