import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../theme/app_theme.dart';

/// Where menu photos are kept, so the menu has them without a connection. The package's default
/// cache holds only 200, fewer than a large menu.
final CacheManager menuImageCache = CacheManager(
  Config('menu_images', stalePeriod: const Duration(days: 30), maxNrOfCacheObjects: 1000),
);

/// A product image, cached. Shops with no photos are common, so the fallback is a plain tile
/// rather than a broken-image icon.
class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, required this.imageUrl, this.size = 56, this.radius = 10});

  final String? imageUrl;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryTint,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.restaurant_rounded, size: size * 0.45, color: MeedColors.inkSoft),
    );
    final url = imageUrl;
    if (url == null || url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url,
        cacheManager: menuImageCache,
        // Decoded near the size shown, not at the photo's own: a list of full-size decodes is
        // what makes scrolling stutter. The margin keeps wide photos sharp once cropped.
        memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context) * 1.5).round(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      ),
    );
  }
}
