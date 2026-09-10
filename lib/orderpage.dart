import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/inventory_provider.dart';
import 'providers/cart_provider.dart';
import 'utils/globalData.dart';

class ShoppingPage extends ConsumerStatefulWidget {
  const ShoppingPage({super.key});

  @override
  ConsumerState<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends ConsumerState<ShoppingPage> {
  String? userName;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      userName = prefs.getString('userName') ?? 'Guest';
    });
  }

  int _getGridColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 700) return 1;
    if (width < 1000) return 2;
    if (width < 1400) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(inventoryProvider);
    final query = _searchController.text.toLowerCase();
    final cartItems = ref.watch(cartProvider);

    final filteredItems = items.where((item) =>
        item.itemName.toLowerCase().contains(query) ||
        item.itemCode.toLowerCase().contains(query)).toList();

    bool isMobile = MediaQuery.of(context).size.width < 900;
    int gridColumns = _getGridColumns(context);

    return Scaffold(
      backgroundColor: AppColors.onyx,
      body: CustomScrollView(
        slivers: [
          /// Header Section
          SliverAppBar(
            expandedHeight: 50,
            floating: true,
            pinned: true,
            backgroundColor: AppColors.onyx,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              title: ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [AppColors.peach, Color(0xFFFF9968)],
                ).createShader(bounds),
                child: Text(
                  'Shop Products',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                  ),
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.onyx,
                      AppColors.onyx.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
            ),
          ),

          /// Search Bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _SearchBar(controller: _searchController),
            ),
          ),

          /// Content Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: isMobile
                  ? Column(
                      children: [
                        _ProductsGrid(
                          items: filteredItems,
                          gridColumns: gridColumns,
                          ref: ref,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 400,
                          child: _CartSidebar(
                            cartItems: cartItems,
                            ref: ref,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: _ProductsGrid(
                            items: filteredItems,
                            gridColumns: gridColumns,
                            ref: ref,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 3,
                          child: SizedBox(
                            height: 500,
                            child: _CartSidebar(
                              cartItems: cartItems,
                              ref: ref,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 40),
          ),
        ],
      ),
    );
  }
}

/// Search Bar Component
class _SearchBar extends StatefulWidget {
  final TextEditingController controller;

  const _SearchBar({required this.controller});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isFocused
              ? AppColors.peach.withValues(alpha: 0.6)
              : AppColors.oatmilk.withValues(alpha: 0.15),
          width: 2,
        ),
        gradient: LinearGradient(
          colors: _isFocused
              ? [
                  AppColors.onyxCard,
                  AppColors.onyxCard.withValues(alpha: 0.7),
                ]
              : [AppColors.onyxCard, AppColors.onyxCard],
        ),
      ),
      child: TextField(
        controller: widget.controller,
        onChanged: (_) => setState(() {}),
        onTap: () => setState(() => _isFocused = true),
        style: const TextStyle(
          color: AppColors.oatmilk,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          hintText: 'Search products by name or code...',
          hintStyle: TextStyle(
            color: AppColors.oatmilk.withValues(alpha: 0.4),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: AppColors.peach.withValues(alpha: 0.7),
          ),
          suffixIcon: widget.controller.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    widget.controller.clear();
                    setState(() {});
                  },
                  child: Icon(
                    Icons.clear,
                    color: AppColors.peach.withValues(alpha: 0.5),
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        ),
      ),
    );
  }
}

/// Products Grid Component
class _ProductsGrid extends StatelessWidget {
  final List items;
  final int gridColumns;
  final WidgetRef ref;

  const _ProductsGrid({
    required this.items,
    required this.gridColumns,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 64,
                color: AppColors.peach.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No products found',
                style: TextStyle(
                  color: AppColors.oatmilk.withValues(alpha: 0.5),
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridColumns,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: 0.78,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _ProductCard(
        item: items[index],
        ref: ref,
      ),
    );
  }
}

/// Product Card with Hover Effects
class _ProductCard extends StatefulWidget {
  final dynamic item;
  final WidgetRef ref;

  const _ProductCard({
    required this.item,
    required this.ref,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onHoverChange(bool isHovered) {
    setState(() => _isHovered = isHovered);
    if (isHovered) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        'https://picsum.photos/seed/${widget.item.itemCode}/800/600';
    final isOutOfStock = widget.item.itemCount <= 0;

    return MouseRegion(
      onEnter: (_) => _onHoverChange(true),
      onExit: (_) => _onHoverChange(false),
      child: GestureDetector(
        onTap: isOutOfStock ? null : () {},
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            );
          },
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            color: AppColors.onyxCard,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _isHovered
                      ? AppColors.peach.withValues(alpha: 0.5)
                      : AppColors.oatmilk.withValues(alpha: 0.1),
                  width: 2,
                ),
              ),
              child: Stack(
                children: [
                  /// Background Accent
                  Positioned(
                    right: -25,
                    top: -25,
                    child: AnimatedOpacity(
                      opacity: _isHovered ? 0.12 : 0.04,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.peach,
                        ),
                      ),
                    ),
                  ),

                  /// Out of Stock Overlay
                  if (isOutOfStock)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: AppColors.onyx.withValues(alpha: 0.6),
                        ),
                        child: Center(
                          child: Text(
                            'Out of Stock',
                            style: TextStyle(
                              color: AppColors.peach,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),

                  /// Content
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// Product Image
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.onyxCard,
                                AppColors.onyxCard.withValues(alpha: 0.5),
                              ],
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                            child: CachedNetworkImage(
                              key: ValueKey('product-image-${widget.item.itemCode}'),
                              imageUrl: imageUrl,
                              cacheKey: 'product-${widget.item.itemCode}',
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: AppColors.onyx.withValues(alpha: 0.5),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.peach,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: AppColors.onyx.withValues(alpha: 0.5),
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: AppColors.peach.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      /// Product Details
                      Expanded(
                        flex: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              /// Product Name
                              Text(
                                widget.item.itemName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.oatmilk,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),

                              const SizedBox(height: 6),

                              /// Code and Price
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Code: ${widget.item.itemCode}",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.oatmilk
                                          .withValues(alpha: 0.5),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    "\$${widget.item.itemPrice.toStringAsFixed(2)}",
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.peach,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 6),

                              /// Stock and Add Button
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Stock: ${widget.item.itemCount}",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: widget.item.itemCount > 0
                                          ? AppColors.oatmilk
                                              .withValues(alpha: 0.7)
                                          : AppColors.peach,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (!isOutOfStock)
                                    GestureDetector(
                                      onTap: () {
                                        widget.ref
                                            .read(cartProvider.notifier)
                                            .addToCart(widget.item);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            backgroundColor:
                                                AppColors.peach,
                                            content: Text(
                                              '${widget.item.itemName} added to cart',
                                              style: const TextStyle(
                                                color: AppColors.onyx,
                                              ),
                                            ),
                                            duration:
                                                const Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: _isHovered
                                                  ? [
                                                      AppColors.peach,
                                                      AppColors.peach
                                                          .withValues(
                                                              alpha: 0.8),
                                                    ]
                                                  : [
                                                      AppColors.peach
                                                          .withValues(
                                                              alpha: 0.7),
                                                      AppColors.peach
                                                          .withValues(
                                                              alpha: 0.5),
                                                    ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: const Icon(
                                            Icons.add_shopping_cart,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cart Sidebar Component
class _CartSidebar extends StatelessWidget {
  final List cartItems;
  final WidgetRef ref;

  const _CartSidebar({
    required this.cartItems,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final totalQty = cartItems.fold<int>(
        0, (sum, item) => sum + (item.itemCount as int));
    final totalPrice = cartItems.fold<double>(
      0,
      (sum, item) => sum + (item.itemPrice * item.itemCount as double),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.oatmilk.withValues(alpha: 0.15),
          width: 2,
        ),
        color: AppColors.onyxCard,
      ),
      child: Column(
        children: [
          /// Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              gradient: LinearGradient(
                colors: [
                  AppColors.onyxCard,
                  AppColors.onyxCard.withValues(alpha: 0.6),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.shopping_cart_outlined,
                      color: AppColors.peach,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Your Cart',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.oatmilk,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$totalQty item${totalQty != 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.oatmilk.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),

          /// Cart Items or Empty State
          if (cartItems.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shopping_bag_outlined,
                      size: 48,
                      color: AppColors.peach.withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Cart is empty',
                      style: TextStyle(
                        color: AppColors.oatmilk.withValues(alpha: 0.5),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: cartItems.length,
                itemBuilder: (context, index) {
                  final item = cartItems[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.oatmilk.withValues(alpha: 0.1),
                          width: 1,
                        ),
                        color: AppColors.onyx.withValues(alpha: 0.3),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item.itemName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.oatmilk,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  ref
                                      .read(inventoryProvider.notifier)
                                      .updateItemCount(
                                        item.itemCode,
                                        ref
                                            .read(inventoryProvider)
                                            .firstWhere((inv) =>
                                                inv.itemCode ==
                                                item.itemCode)
                                            .itemCount +
                                            (item.itemCount as int),
                                      );

                                  ref
                                      .read(cartProvider.notifier)
                                      .removeFromCart(item.itemCode);
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: AppColors.peach.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Qty: ${item.itemCount}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.oatmilk
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                              Text(
                                '\$${(item.itemPrice * (item.itemCount as int)).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.peach,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          /// Footer with Total
          if (cartItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border(
                  top: BorderSide(
                    color: AppColors.oatmilk.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total:',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.oatmilk.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '\$${totalPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.peach,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.peach, Color(0xFFFF9968)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'Checkout',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
