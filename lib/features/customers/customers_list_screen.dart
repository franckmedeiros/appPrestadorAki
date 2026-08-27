import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
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
  // Stream ao vivo (ver CustomersRepository.watchAll) em vez de um
  // Future recarregado manualmente depois de criar/editar um cliente —
  // resolve "salvei e não apareceu, precisei sair e entrar de novo". A
  // busca por texto continua sendo feita no app, agora filtrando a lista
  // que a stream já entregou, em vez de refazer a consulta no Firestore.
  late Stream<List<Customer>> _stream = context.read<CustomersRepository>().watchAll();
  String _query = '';

  Future<void> _retry() async {
    setState(() => _stream = context.read<CustomersRepository>().watchAll());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Customer> _filter(List<Customer> customers) {
    if (_query.isEmpty) return customers;
    final query = _query.toLowerCase();
    return customers
        .where((c) =>
            c.name.toLowerCase().contains(query) || (c.phone?.contains(query) ?? false))
        .toList();
  }

  Future<void> _openCustomer(Customer? customer) async {
    final saved = await context.push<bool>('/clientes/editar', extra: customer);
    // Não precisa recarregar nada manualmente — a stream já reflete a
    // escrita sozinha (ver `_stream` acima). O retorno só importa se um
    // dia isso precisar de outro efeito colateral aqui.
    if (saved != true) return;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openCustomer(null),
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
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Customer>>(
              stream: _stream,
              builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(
                      message: 'Não foi possível carregar os clientes.',
                      onRetry: _retry,
                    );
                  }
                  final customers = _filter(snapshot.data ?? []);
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
                        onTap: () => _openCustomer(customer),
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
