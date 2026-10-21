import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/content.dart';
import '../models/product.dart';
import '../services/store_repository.dart';
import '../widgets/product_grid.dart';
import 'product_screen.dart';

/// فيديوهات عمودية مثل الريلز. الفيديو الظاهر بس يشتغل.
class ReelsScreen extends StatefulWidget {
  /// false لما المستخدم بتبويب ثاني، حتى يوكف الفيديو.
  final bool visible;

  const ReelsScreen({super.key, this.visible = true});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  late final _repo = context.read<StoreRepository>();
  late final Stream<List<Reel>> _reels = _repo.watchReels();
  late final Stream<List<Product>> _products = _repo.watchProducts();
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<List<Reel>>(
        stream: _reels,
        builder: (context, snapshot) {
          final reels = snapshot.data;
          if (reels == null) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          if (reels.isEmpty) {
            return Theme(
              data: Theme.of(context).copyWith(
                textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white70),
              ),
              child: const EmptyMessage(icon: Icons.play_circle_outline, text: 'ماكو فيديوهات بعد'),
            );
          }
          return StreamBuilder<List<Product>>(
            stream: _products,
            builder: (context, productsSnap) {
              final products = productsSnap.data ?? const <Product>[];
              return PageView.builder(
                scrollDirection: Axis.vertical,
                itemCount: reels.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final reel = reels[i];
                  return _ReelPage(
                    key: ValueKey(reel.id),
                    reel: reel,
                    product: products.where((p) => p.id == reel.productId).firstOrNull,
                    playing: widget.visible && i == _page,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  final Reel reel;
  final Product? product;
  final bool playing;

  const _ReelPage({super.key, required this.reel, required this.product, required this.playing});

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _pausedByUser = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uri = Uri.tryParse(widget.reel.videoUrl);
    if (uri == null || !uri.hasScheme) {
      setState(() => _failed = true);
      return;
    }
    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) return;
      setState(() {});
      _syncPlayback();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _syncPlayback() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (widget.playing && !_pausedByUser) {
      c.play();
    } else {
      c.pause();
    }
  }

  @override
  void didUpdateWidget(_ReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) {
      _pausedByUser = false;
      _syncPlayback();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePause() {
    setState(() => _pausedByUser = !_pausedByUser);
    _syncPlayback();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: ready ? _togglePause : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            )
          else if (_failed)
            const Center(
              child: Text('ما كدرنا نشغل الفيديو', style: TextStyle(color: Colors.white70)),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (ready && _pausedByUser)
            const Center(child: Icon(Icons.play_arrow_rounded, size: 84, color: Colors.white70)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.reel.caption.isNotEmpty)
                    Text(
                      widget.reel.caption,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
                    ),
                  if (widget.product != null) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.secondary,
                        minimumSize: const Size(0, 44),
                      ),
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: Text('${widget.product!.name} • ${formatPrice(widget.product!.price)}'),
                      onPressed: () {
                        c?.pause();
                        Navigator.of(context)
                            .push(MaterialPageRoute(
                              builder: (_) => ProductScreen(product: widget.product!),
                            ))
                            .then((_) => _syncPlayback());
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
