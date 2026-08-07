import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';

class PosPage extends StatelessWidget {
  const PosPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final total = store.cart.fold(0.0, (sum, line) => sum + line.total);
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: SectionCard(
                  title: 'Sell Products',
                  child: Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final p in store.products.where((p) => p.active))
                      SizedBox(
                        width: 210,
                        child: Card(
                          color: Colors.grey.shade50,
                          child: InkWell(
                            onTap: p.stock > 0 ? () => store.addToCart(p) : null,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name, style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 8),
                                Text(p.sku),
                                Text('Stock: ${p.stock.toStringAsFixed(0)}'),
                                Text(AppFormatters.currency(p.sellingPrice), style: Theme.of(context).textTheme.titleLarge),
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: SectionCard(
                  title: 'Cart',
                  actions: [Text(AppFormatters.currency(total), style: Theme.of(context).textTheme.titleLarge)],
                  child: Column(children: [
                    for (final line in store.cart)
                      ListTile(
                        title: Text(line.product.name),
                        subtitle: Text('${line.quantity} × ${AppFormatters.currency(line.product.sellingPrice)}'),
                        trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => store.removeFromCart(line)),
                      ),
                    const Divider(),
                    SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: store.cart.isEmpty ? null : () async => store.checkout(customer: store.customers.isEmpty ? null : store.customers.first, paid: total), icon: const Icon(Icons.receipt), label: const Text('Checkout cash sale'))),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
