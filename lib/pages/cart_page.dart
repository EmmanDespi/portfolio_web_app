import 'dart:math';
import 'package:flutter/material.dart';
import 'package:portfolio/utils/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';


class GroceryCartPage extends StatefulWidget {
  const GroceryCartPage({super.key});

  @override
  State<GroceryCartPage> createState() => _GroceryCartPageState();
}

class _GroceryCartPageState extends State<GroceryCartPage> {
  bool _isDark = false;
  bool _showOptions = false;

  // ── Theme (app_theme.dart) ─────────────────────────────
  static final ThemeData _lightTheme = AppTheme.portfolio(isDark: false);
  static final ThemeData _darkTheme = AppTheme.portfolio(isDark: true);

  ThemeData get _theme => _isDark ? _darkTheme : _lightTheme;

  AppPalette get _p => _theme.extension<AppPalette>()!;
  TextTheme get _text => _theme.textTheme;

  Color get _bg => _p.background;
  Color get _shell => _p.shell;
  Color get _card => _p.card;
  Color get _ink => _p.ink;
  Color get _shadow => _p.shadow;

  Border _border(Color color) => Border.all(color: _ink, width: 3);

  BoxShadow _hardShadow(double offset) =>
      BoxShadow(color: _shadow, offset: Offset(offset, offset), blurRadius: 0);

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _isDark = prefs.getBool('isDark') ?? false);
  }

  final _rng = Random();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  final List<String> _saved = []; // the cart
  final List<String> _items = []; // random picks

   @override
  void initState() {
    super.initState();
    _loadThemePreference();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showGenericDialog(
        context,
        title: 'Welcome',
        message: "Having trouble what to buy from your grocery list? \n\nAdd Items on the cart below and let the randomized pick for you",
      );
    });
  }

   void showGenericDialog(BuildContext context,
    {required String title, required String message}) {
    showDialog(
      context: context,
      barrierDismissible: true, // Allow dismiss by tapping outside
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }


  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // setDialogState rebuilds the dialog; setState rebuilds the page (count).
  void _save(StateSetter setDialogState) {
    final name = _input.text.trim();
    final exists = _saved.any((s) => s.toLowerCase() == name.toLowerCase());

    if (name.isNotEmpty && !exists) {
      setState(() => _saved.add(name));
      setDialogState(() {});
    }
    _input.clear();

    // Keep the cursor in the box so the user can keep typing.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _inputFocus.requestFocus());
  }

  void _removeSaved(String name, StateSetter setDialogState) {
    setState(() => _saved.remove(name));
    setDialogState(() {});
  }

  // Moves a random item from the cart to the picks list.
  void _addItem() {
    if (_saved.isEmpty) return;

    setState(() {
      final picked = _saved.removeAt(_rng.nextInt(_saved.length));
      _items.add(picked);
    });
  }

  void _deleteAll() => setState(() => _items.clear());

  void _openCart() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: AppResponsive.dialogWidth(ctx, 480),
              maxHeight: AppResponsive.dialogHeight(ctx, 0.7),
            ),
            child: WireFrame(
              color: _shell,
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(AppSpacing.sm),
              border: _border(AppColors.oatmilk),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Cart', style: _text.titleLarge),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(),
                        child: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: WireFrame(
                          color: AppColors.white,
                          margin: EdgeInsets.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: TextField(
                            controller: _input,
                            focusNode: _inputFocus,
                            autofocus: true,
                            style: _text.bodyMedium,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _save(setDialogState),
                            decoration: const InputDecoration(
                              hintText: 'Item name',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                      NeoButton(
                        label: 'Save',
                        height: 48,
                        onPressed: () => _save(setDialogState),
                      ),
                    ],
                  ),
                  if (_saved.isEmpty)
                    Text('Your cart is empty.', style: _text.bodyMedium)
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(right: 4, bottom: 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final name in _saved)
                              WireFrame(
                                color: AppColors.white,
                                margin: EdgeInsets.zero,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                boxShadow: AppResponsive.hardShadow(2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(name, style: _text.bodyMedium),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () =>
                                          _removeSaved(name, setDialogState),
                                      child: const Icon(Icons.close, size: 16),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
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

  @override
  Widget build(BuildContext context) {
    final w = context.screenWidth;
    final h = context.screenHeight;

    return Theme(
      data: _theme,
        child:Scaffold(
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: NeoButton(
          width: context.isDesktop ? w * 0.3 : w * 0.5,
          label: 'Items (${_saved.length})',
          fontSize: 18,
          icon: Icons.shopping_cart,
          height: 52,
          onPressed: _openCart,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Center(
              child: Column(
                spacing: context.isDesktop ? 12 : 8,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 12,),
                  Text('Grocery Randomizer', style: _text.headlineLarge),
                  WireFrame(
                    width: context.isDesktop ? w * 0.5 : w,
                    minHeight: h * 0.1,
                    color: _shell,
                    border: _border(AppColors.oatmilk),
                    child: Column(
                      spacing: 12,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          spacing: 8,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            NeoButton(
                              label: '+',
                              fontSize: 24,
                              width: 110,
                              height: 55,
                              onPressed: _saved.isEmpty ? null : _addItem,
                            ),
                            NeoButton(
                              label: 'Delete',
                              width: 110,
                              height: 55,
                              color: AppColors.coral,
                              onPressed: _items.isEmpty ? null : _deleteAll,
                            ),
                          ],
                        ),
                        const Divider(),
                        Column(
                          spacing: 8,
                          children: [
                            if (_items.isEmpty)
                              WireFrame(
                                color: AppColors.muted,
                                width: w,
                                height: 55,
                                child: Text(
                                  _saved.isEmpty
                                      ? 'Open the cart to add items'
                                      : 'Click + to pick a random item',
                                  style: _text.headlineSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            else
                              for (final name in _items)
                                WireFrame(
                                  width: w,
                                  height: 55,
                                  child: Text(
                                    name,
                                    style: _text.bodyMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Keeps the last item clear of the floating button.
                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
        ),
      )
    );
  }
}