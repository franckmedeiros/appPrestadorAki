import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../widgets/app_list_card.dart';
import '../../widgets/botao_com_seta.dart';
import '../../widgets/cabecalho_de_tela.dart';
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

  /// Tocar num cliente agora abre a PÁGINA dele (contato, próximo
  /// compromisso, quanto pagou e deve, histórico), não o formulário de
  /// edição. Editar virou uma ação dentro dela.
  ///
  /// A razão: na esmagadora maioria das vezes que alguém toca num cliente,
  /// quer VER alguma coisa sobre ele — não corrigir o cadastro. O caminho
  /// antigo tratava o caso raro como se fosse o comum.
  void _abrirCliente(Customer customer) {
    context.push('/clientes/detalhe', extra: customer);
  }

  /// Só pro botão "+": cliente novo não tem página pra ver ainda.
  Future<void> _novoCliente() async {
    await context.push<bool>('/clientes/editar');
    // Não precisa recarregar nada manualmente — a stream já reflete a
    // escrita sozinha (ver `_stream` acima).
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: CabecalhoDeTela(
              titulo: 'Clientes',
              area: AreaDoApp.prestador,
              aoVoltar: Navigator.of(context).canPop()
                  ? () => Navigator.of(context).maybePop()
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.margemLateral,
              0,
              AppMetrics.margemLateral,
              16,
            ),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Buscar por nome ou telefone',
                // A lupa passou pra DIREITA. À esquerda ela empurrava o
                // texto pra dentro e desalinhava o campo das listas logo
                // abaixo, onde o nome começa na margem.
                suffixIcon: Icon(Icons.search, color: AppColors.muted),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppMetrics.margemLateral,
                      ),
                      children: const [
                        SizedBox(height: 60),
                        Icon(Icons.people_outline, size: 40, color: AppColors.muted),
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
                    padding: const EdgeInsets.fromLTRB(
                      AppMetrics.margemLateral,
                      0,
                      AppMetrics.margemLateral,
                      8,
                    ),
                    itemCount: customers.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return AppListCard(
                        onTap: () => _abrirCliente(customer),
                        // Era um quadrado laranja chapado com a inicial
                        // em branco. Numa agenda de cinquenta clientes
                        // isso vira uma coluna de blocos de cor que não
                        // distingue ninguém de ninguém. Agora é um disco
                        // laranja claro com a inicial em laranja — a mesma
                        // informação, sem a mancha.
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: AppColors.primarySuave,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            customer.name.isNotEmpty
                                ? customer.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        title: customer.name,
                        subtitle: [customer.phone, customer.locationLabel]
                            .where((value) => value != null && value.isNotEmpty)
                            .join(' · '),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: AppColors.muted,
                          size: 22,
                        ),
                      );
                    },
                  );
                },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.margemLateral,
                8,
                AppMetrics.margemLateral,
                10,
              ),
              child: BotaoComSeta(
                rotulo: 'Novo cliente',
                icone: Icons.add,
                comCaixa: false,
                aoTocar: _novoCliente,
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppMetrics.margemLateral,
      ),
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.error_outline, size: 40, color: AppColors.danger),
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
