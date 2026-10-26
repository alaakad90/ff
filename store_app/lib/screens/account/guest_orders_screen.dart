import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order.dart';
import '../../services/device_history.dart';
import '../../services/store_api.dart';
import '../../widgets/product_grid.dart';
import 'my_orders_screen.dart';

/// طلبات الزائر (بدون حساب) من هذا الجهاز: السيرفر يرجع حالتها بمفتاح المتابعة.
class GuestOrdersScreen extends StatefulWidget {
  const GuestOrdersScreen({super.key});

  @override
  State<GuestOrdersScreen> createState() => _GuestOrdersScreenState();
}

class _GuestOrdersScreenState extends State<GuestOrdersScreen> {
  late Future<List<StoreOrder>> _orders = _load();

  Future<List<StoreOrder>> _load() async {
    final api = context.read<StoreApi>();
    final refs = await context.read<DeviceHistory>().guestOrders();
    final results = await Future.wait(refs.map((r) async {
      try {
        return await api.track(r.id, r.key);
      } catch (_) {
        return null;
      }
    }));
    if (refs.isNotEmpty && results.every((o) => o == null)) {
      throw StoreApiException('ما كدرنا نجيب طلباتك');
    }
    return results.whereType<StoreOrder>().toList();
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _orders = next);
    await next.catchError((_) => <StoreOrder>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تتبع طلباتي')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<StoreOrder>>(
          future: _orders,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListView(children: const [
                SizedBox(height: 120),
                EmptyMessage(icon: Icons.wifi_off, text: 'ما كدرنا نجيب طلباتك. اسحب لتحت حتى تعيد المحاولة.'),
              ]);
            }
            final orders = snapshot.data;
            if (orders == null) return const Center(child: CircularProgressIndicator());
            if (orders.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                EmptyMessage(
                  icon: Icons.receipt_long_outlined,
                  text: 'ماكو طلبات من هذا الجهاز بعد.\nسجل دخول حتى تشوف طلباتك من أي جهاز.',
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => OrderSummaryCard(order: orders[i]),
            );
          },
        ),
      ),
    );
  }
}
