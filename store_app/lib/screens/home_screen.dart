import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/content.dart';
import '../models/product.dart';
import '../services/store_repository.dart';
import '../widgets/banner_carousel.dart';
import '../widgets/brand_logo.dart';
import '../widgets/product_grid.dart';
import '../widgets/product_image.dart';
import '../widgets/smart_offers.dart';
import 'categories_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final _repo = context.read<StoreRepository>();
  late final Stream<List<Product>> _products = _repo.watchProducts();
  late final Stream<List<PromoBanner>> _banners = _repo.watchBanners();

  void _openCategory(Category category) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CategoryProductsScreen(category: category)),
      );

  void _openBanner(PromoBanner banner) {
    final category =
        context.read<List<Category>>().where((c) => c.id == banner.categoryId).firstOrNull;
    if (category != null) _openCategory(category);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = context.watch<List<Category>>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const BrandLogo(height: 34),
                    const Spacer(),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SearchField()),
            SliverToBoxAdapter(
              child: StreamBuilder<List<PromoBanner>>(
                stream: _banners,
                builder: (context, snapshot) {
                  final banners = snapshot.data ?? const [];
                  if (banners.isEmpty) return const SizedBox(height: 8);
                  return Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: BannerCarousel(banners: banners, onTap: _openBanner),
                  );
                },
              ),
            ),
            if (categories.isNotEmpty) ...[
              _SectionTitle(title: 'الأقسام'),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, i) {
                      final category = categories[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openCategory(category),
                        child: SizedBox(
                          width: 68,
                          child: Column(
                            children: [
                              CategoryAvatar(category: category),
                              const SizedBox(height: 6),
                              Text(
                                category.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            // عروض ذكية حسب مشتريات الزبون وسلته (ما تبين إذا ماكو شي يناسب).
            const SliverToBoxAdapter(child: SmartOffers()),
            _SectionTitle(title: 'كل المنتجات'),
            StreamBuilder<List<Product>>(
              stream: _products,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyMessage(
                      icon: Icons.wifi_off,
                      text: 'ما كدرنا نحمل المنتجات. تأكد من الإنترنت.',
                    ),
                  );
                }
                final products = snapshot.data;
                if (products == null) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (products.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyMessage(icon: Icons.inventory_2_outlined, text: 'ماكو منتجات هنا'),
                  );
                }
                return SliverProductGrid(products: products);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// مستطيل البحث. ينضغط ويفتح صفحة البحث.
class SearchField extends StatelessWidget {
  const SearchField({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: Theme.of(context).cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.search, color: colors.outline),
                const SizedBox(width: 10),
                Text('ابحث في كل المنتجات', style: TextStyle(color: colors.outline, fontSize: 15)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
