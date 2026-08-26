import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../../core/app_theme.dart';
import '../../widgets/app_list_card.dart';
import 'customers_repository.dart';
import 'models/customer.dart';

class CustomersListScreen extends StatefulWidget {
  const CustomersListScreen({super.key});

  @override
  State<CustomersListScreen> createState() => _CustomersListScreenState();
}

class _CustomersListScreenState extends State<CustomersListScreen> {
  final _searchController = TextEditingController();
  late Future<List<Customer>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Customer>> _load({String? search}) {
    return context.read<CustomersRepository>().list(search: search);
  }

  Future<void> _reload() async {
    setState(() => _future = _load(search: _searchController.text.trim()));
    await _future;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await context.push<bool>('/clientes/novo');
          if (created == true) _reload();
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Buscar por nome ou telefone',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => _reload(),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: FutureBuilder<List<Customer>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    final message = snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : 'Não foi possível carregar os clientes.';
                    return _ErrorState(message: message, onRetry: _reload);
                  }
                  final customers = snapshot.data ?? [];
                  if (customers.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 80),
                        Icon(Icons.people_outline, size: 48, color: AppColors.muted),
                        SizedBox(height: 12),
                        Text(
                          'Nenhum cliente cadastrado ainda.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: customers.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return AppListCard(
                        leading: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppColors.primary, AppColors.primaryDark],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
                          ),
                        ),
                        title: customer.name,
                        subtitle: [customer.phone, customer.locationLabel]
                            .where((value) => value != null && value.isNotEmpty)
                            .join(' · '),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton(onPressed: onRetry, child: const Text('Tentar de novo')),
        ),
      ],
    );
  }
}
