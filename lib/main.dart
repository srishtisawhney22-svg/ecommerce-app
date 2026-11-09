import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() { runApp(const ShopApp());
}

class Product {
  const Product({required this.id, required this.title, required this.price,
    required this.description, required this.category, required this.image,
    required this.rating, required this.ratingCount});

  final int id;
  final String title, description, category, image;
  final double price, rating;
  final int ratingCount;

  factory Product.fromJson(Map<String, dynamic> json) {
    final rating = json['rating'] as Map<String, dynamic>? ?? {};
    return Product(id: json['id'] as int, title: json['title'] as String,
      price: (json['price'] as num).toDouble(),
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'Other',
      image: json['image'] as String? ?? '',
      rating: (rating['rate'] as num?)?.toDouble() ?? 0,
      ratingCount: rating['count'] as int? ?? 0);
  }
}

class ShopApp extends StatefulWidget {
  const ShopApp({super.key});
  @override
  State<ShopApp> createState() => _ShopAppState();
}

class _ShopAppState extends State<ShopApp> {
  final Map<int, int> _cart = {};
  final Set<int> _favourites = {};
  List<Product> _products = [];
  String _category = 'All';
  String _sort = 'Featured';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
    _loadProducts();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final rawCart = prefs.getString('cart');
    if (rawCart != null) {
      final decoded = jsonDecode(rawCart) as Map<String, dynamic>;
      _cart.addAll(decoded.map((key, value) => MapEntry(int.parse(key), value as int)));
    }
    _favourites.addAll((prefs.getStringList('favourites') ?? []).map(int.parse));
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cart', jsonEncode(_cart.map((k, v) => MapEntry('$k', v))));
    await prefs.setStringList('favourites', _favourites.map((id) => '$id').toList());
  }

  Future<void> _loadProducts() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await http.get(Uri.parse('https://fakestoreapi.com/products'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('Server returned ${response.statusCode}');
      final list = jsonDecode(response.body) as List<dynamic>;
      _products = list.map((item) => Product.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      _error = 'Could not load products. Check your internet connection and try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _categories {
    final categories = _products.map((p) => p.category).toSet().toList()..sort();
    return ['All', ...categories];
  }
  List<Product> get _visibleProducts {
    final result = _products.where((p) => _category == 'All' || p.category == _category).toList();
    if (_sort == 'Price: low to high') result.sort((a, b) => a.price.compareTo(b.price));
    if (_sort == 'Price: high to low') result.sort((a, b) => b.price.compareTo(a.price));
    if (_sort == 'Top rated') result.sort((a, b) => b.rating.compareTo(a.rating));
    return result;
  }
  int get _cartCount => _cart.values.fold(0, (sum, quantity) => sum + quantity);
  double get _total => _cart.entries.fold(0, (sum, entry) {
    final product = _products.where((p) => p.id == entry.key).firstOrNull;
    return sum + (product == null ? 0 : product.price * entry.value);
  });

  void _add(Product product) { setState(() => _cart.update(product.id, (n) => n + 1, ifAbsent: () => 1)); _save(); }
  void _change(Product product, int delta) {
    setState(() { final next = (_cart[product.id] ?? 0) + delta; if (next <= 0) { _cart.remove(product.id); } else { _cart[product.id] = next; } });
    _save();
  }
  void _toggleFavourite(Product product) {
    setState(() { _favourites.contains(product.id) ? _favourites.remove(product.id) : _favourites.add(product.id); });
    _save();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Everyday Shop', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b57)), useMaterial3: true),
      home: DefaultTabController(length: 2, child: Builder(builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Everyday Shop', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [IconButton(tooltip: 'Cart total', onPressed: () => _showCart(context), icon: Badge(label: Text('$_cartCount'), child: const Icon(Icons.shopping_bag_outlined)))],
          bottom: const TabBar(tabs: [Tab(icon: Icon(Icons.storefront_outlined), text: 'Shop'), Tab(icon: Icon(Icons.favorite_border), text: 'Favourites')])),
        body: TabBarView(children: [_shopView(context), _favouritesView(context)]),
        floatingActionButton: _cartCount == 0 ? null : FloatingActionButton.extended(onPressed: () => _showCart(context), icon: const Icon(Icons.shopping_cart), label: Text('Cart · $_cartCount  ·  \$${_total.toStringAsFixed(2)}')),
      ))),
  );

  Widget _shopView(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _message(_error!, onRetry: _loadProducts);
    final products = _visibleProducts;
    return Column(children: [
      SizedBox(height: 58, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: _categories.map((c) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(c), selected: c == _category, onSelected: (_) => setState(() => _category = c)))).toList())),
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Row(children: [Text('${products.length} products', style: Theme.of(context).textTheme.bodySmall), const Spacer(), const Text('Sort: '), DropdownButton<String>(value: _sort, underline: const SizedBox(), items: const ['Featured', 'Price: low to high', 'Price: high to low', 'Top rated'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => _sort = v!))])),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth > 850 ? 4 : constraints.maxWidth > 580 ? 3 : 2;
        return GridView.builder(padding: const EdgeInsets.fromLTRB(12, 4, 12, 90), itemCount: products.length, gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, childAspectRatio: .66, crossAxisSpacing: 12, mainAxisSpacing: 12), itemBuilder: (context, index) => _productCard(context, products[index]));
      })),
    ]);
  }

  Widget _favouritesView(BuildContext context) {
    final products = _products.where((p) => _favourites.contains(p.id)).toList();
    if (_loading && _products.isEmpty) return const Center(child: CircularProgressIndicator());
    if (products.isEmpty) return _message('Your favourites will appear here. Tap the heart on a product to save it.');
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth > 850 ? 4 : constraints.maxWidth > 580 ? 3 : 2;
      return GridView.builder(padding: const EdgeInsets.all(12), itemCount: products.length, gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, childAspectRatio: .66, crossAxisSpacing: 12, mainAxisSpacing: 12), itemBuilder: (context, index) => _productCard(context, products[index]));
    });
  }

  Widget _productCard(BuildContext context, Product product) => Card(clipBehavior: Clip.antiAlias, child: InkWell(onTap: () => _showDetails(context, product), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: Stack(fit: StackFit.expand, children: [Padding(padding: const EdgeInsets.all(16), child: Image.network(product.image, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, size: 44))), Positioned(right: 4, top: 4, child: IconButton(onPressed: () => _toggleFavourite(product), icon: Icon(_favourites.contains(product.id) ? Icons.favorite : Icons.favorite_border, color: Colors.red)))])),
    Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(product.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 5), Row(children: [const Icon(Icons.star, size: 16, color: Colors.amber), Text(' ${product.rating.toStringAsFixed(1)}'), const Spacer(), Text('\$${product.price.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))]), const SizedBox(height: 8), SizedBox(width: double.infinity, child: FilledButton.tonal(onPressed: () => _add(product), child: const Text('Add to cart')))])),
  ])));

  Widget _message(String message, {VoidCallback? onRetry}) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(onRetry == null ? Icons.shopping_bag_outlined : Icons.wifi_off, size: 48, color: Colors.grey), const SizedBox(height: 12), Text(message, textAlign: TextAlign.center), if (onRetry != null) ...[const SizedBox(height: 12), FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again'))]])));

  void _showDetails(BuildContext context, Product product) => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (context) => SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Center(child: Image.network(product.image, height: 210, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 80))), const SizedBox(height: 12), Text(product.category.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(product.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 8), Row(children: [const Icon(Icons.star, color: Colors.amber), Text(' ${product.rating} (${product.ratingCount} reviews)'), const Spacer(), Text('\$${product.price.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleLarge)]), const SizedBox(height: 12), Text(product.description), const SizedBox(height: 16), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () { _add(product); Navigator.pop(context); }, icon: const Icon(Icons.add_shopping_cart), label: const Text('Add to cart')))])))));

  void _showCart(BuildContext context) => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (context) => StatefulBuilder(builder: (context, refresh) => SafeArea(child: SizedBox(height: MediaQuery.of(context).size.height * .75, child: Column(children: [Padding(padding: const EdgeInsets.all(20), child: Row(children: [Text('Your cart', style: Theme.of(context).textTheme.headlineSmall), const Spacer(), Text('\$${_total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))])), const Divider(height: 1), Expanded(child: _cart.isEmpty ? const Center(child: Text('Your cart is empty. Add a product to get started.')) : ListView(children: _cart.entries.map((entry) {
      final product = _products.where((p) => p.id == entry.key).firstOrNull;
      if (product == null) return const SizedBox.shrink();
      return ListTile(leading: Image.network(product.image, width: 44, errorBuilder: (_, __, ___) => const Icon(Icons.image)), title: Text(product.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text('\$${product.price.toStringAsFixed(2)} each'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(onPressed: () { _change(product, -1); refresh(() {}); }, icon: const Icon(Icons.remove_circle_outline)), Text('${entry.value}'), IconButton(onPressed: () { _change(product, 1); refresh(() {}); }, icon: const Icon(Icons.add_circle_outline)), IconButton(onPressed: () { setState(() => _cart.remove(product.id)); _save(); refresh(() {}); }, icon: const Icon(Icons.delete_outline))]));
    }).toList())), Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: FilledButton(onPressed: _cart.isEmpty ? null : () { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demo only: no payment is collected.'))); }, child: const Text('Review order (demo)'))))])))));
}

extension FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
