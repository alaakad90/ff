import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/content.dart';
import '../services/contact.dart';
import '../services/order_service.dart';
import '../widgets/brand_logo.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final info = context.watch<StoreInfo>();
    final theme = Theme.of(context);

    Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.secondary),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('عن المتجر')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const BrandLogo(height: 110),
          const SizedBox(height: 24),
          if (info.about.isNotEmpty) ...[
            Text(info.about, style: theme.textTheme.bodyLarge?.copyWith(height: 1.7)),
            const SizedBox(height: 16),
          ],
          if (info.address.isNotEmpty) row(Icons.location_on_outlined, info.address),
          if (info.hours.isNotEmpty) row(Icons.schedule, info.hours),
          if (info.phone.isNotEmpty) row(Icons.phone_outlined, info.phone),
          const SizedBox(height: 20),
          if (info.whatsapp.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                icon: const Icon(Icons.chat),
                label: const Text('راسلنا على واتساب'),
                onPressed: () => openWhatsapp(info.whatsapp),
              ),
            ),
          if (info.phone.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.call),
                label: const Text('اتصل بينا'),
                onPressed: () => callPhone(info.phone),
              ),
            ),
          if (info.facebook.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: const Color(0xFF1877F2),
                ),
                icon: const Icon(Icons.facebook),
                label: const Text('تابعنا على فيسبوك'),
                onPressed: () => openLink(facebookUrl(info.facebook)),
              ),
            ),
          if (info.instagram.isNotEmpty)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('تابعنا على إنستغرام'),
              onPressed: () => openLink(info.instagram.startsWith('http')
                  ? info.instagram
                  : 'https://instagram.com/${info.instagram.replaceAll('@', '')}'),
            ),
          if (privacyPolicyUrl.isNotEmpty)
            TextButton(
              onPressed: () => openLink(privacyPolicyUrl),
              child: const Text('سياسة الخصوصية'),
            ),
        ],
      ),
    );
  }
}
