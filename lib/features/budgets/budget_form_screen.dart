import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/currency_text_utils.dart';
import '../../core/date_text_utils.dart';
import '../../widgets/mask_text_input_formatter.dart';
import '../customers/customers_repository.dart';
import '../customers/models/customer.dart';
import 'budget_pdf.dart';
import 'budgets_repository.dart';
import 'models/budget.dart';

/// Controllers de uma linha de item — cada linha vira um `BudgetItem` na
/// hora de salvar/gerar o PDF (ver `toItem()`). Ficam num objeto próprio
/// (em vez de 4 listas paralelas de controllers) só pra não perder o
/// vínculo entre os 4 campos de uma mesma linha ao adicionar/remover.
class _ItemRowControllers {
  _ItemRowControllers({
    String description = '',
    double quantity = 1,
    String unit = 'serviço',
    int unitPriceCents = 0,
  })  : descriptionController = TextEditingController(text: description),
        quantityController = TextEditingController(text: _formatQuantity(quantity)),
        unitController = TextEditingController(text: unit),
        unitPriceController = TextEditingController(
          text: unitPriceCents > 0 ? formatCentsBRL(unitPriceCents).replaceAll('R\$ ', '') : '',
        );

  final TextEditingController descriptionController;
  final TextEditingController quantityController;
  final TextEditingController unitController;
  final TextEditingController unitPriceController;

  static String _formatQuantity(double quantity) => quantity == quantity.roundToDouble()
      ? quantity.toInt().toString()
      : quantity.toString().replaceAll('.', ',');

  /// `null` quando a linha está em branco (descrição vazia) — usado tanto
  /// pra montar o orçamento de verdade quanto pro cálculo de subtotal ao
  /// vivo, ignorando linhas que a pessoa ainda não preencheu.
  BudgetItem? toItem() {
    final description = descriptionController.text.trim();
    if (description.isEmpty) return null;
    final quantity = double.tryParse(quantityController.text.trim().replaceAll(',', '.')) ?? 1;
    final unit = unitController.text.trim().isEmpty ? 'serviço' : unitController.text.trim();
    final unitPriceCents = tryParseCentsFromText(unitPriceController.text) ?? 0;
    return BudgetItem(description: description, quantity: quantity, unit: unit, unitPriceCents: unitPriceCents);
  }

  void dispose() {
    descriptionController.dispose();
    quantityController.dispose();
    unitController.dispose();
    unitPriceController.dispose();
  }
}

/// Formulário de orçamento (módulo formal, ligado a Clientes cadastrados
/// — diferente do "Enviar orçamento" simples do marketplace, ver
/// IncomingRequestsScreen). Cria um novo (`budget == null`) ou edita um
/// já existente. Gera o PDF no layout combinado com o Franck a partir
/// dos MESMOS dados do formulário — não precisa salvar antes pra gerar.
class BudgetFormScreen extends StatefulWidget {
  const BudgetFormScreen({super.key, this.budget});

  final Budget? budget;

  @override
  State<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

class _BudgetFormScreenState extends State<BudgetFormScreen> {
  late Future<List<Customer>> _customersFuture;
  String? _selectedCustomerId;

  late final _addressController = TextEditingController(text: widget.budget?.addressText ?? '');
  late final DateTime _initialDate = widget.budget?.date ?? DateTime.now();
  late final _dateController = TextEditingController(text: formatDateDdMmYyyy(_initialDate));
  final _dateMask = MaskTextInputFormatter('##/##/####');
  late final _discountController = TextEditingController(
    text: (widget.budget != null && widget.budget!.discountCents > 0)
        ? formatCentsBRL(widget.budget!.discountCents).replaceAll('R\$ ', '')
        : '',
  );
  late final _observationsController = TextEditingController(text: widget.budget?.observations ?? '');

  late List<_ItemRowControllers> _itemRows;

  bool get _isEditing => widget.budget != null;

  bool _saving = false;
  bool _generatingPdf = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _customersFuture = context.read<CustomersRepository>().list();
    _selectedCustomerId = widget.budget?.customerId;
    final items = widget.budget?.items;
    _itemRows = (items != null && items.isNotEmpty)
        ? items
            .map((item) => _ItemRowControllers(
                  description: item.description,
                  quantity: item.quantity,
                  unit: item.unit,
                  unitPriceCents: item.unitPriceCents,
                ))
            .toList()
        : [_ItemRowControllers()];
  }

  @override
  void dispose() {
    _addressController.dispose();
    _dateController.dispose();
    _discountController.dispose();
    _observationsController.dispose();
    for (final row in _itemRows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addItemRow() => setState(() => _itemRows.add(_ItemRowControllers()));

  void _removeItemRow(int index) {
    setState(() {
      _itemRows.removeAt(index).dispose();
      if (_itemRows.isEmpty) _itemRows.add(_ItemRowControllers());
    });
  }

  List<BudgetItem> _currentItems() =>
      _itemRows.map((row) => row.toItem()).whereType<BudgetItem>().toList();

  Future<void> _pickDate() async {
    final current = tryParseDateDdMmYyyy(_dateController.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 2),
      lastDate: DateTime(current.year + 2),
    );
    if (picked != null) setState(() => _dateController.text = formatDateDdMmYyyy(picked));
  }

  /// Monta o `Budget` a partir do estado atual do formulário — usado
  /// tanto por `_save` quanto por `_generatePdf`, pra nunca ficarem
  /// divergentes sobre o que vale como orçamento válido.
  Future<Budget?> _buildBudgetFromForm() async {
    final items = _currentItems();
    if (items.isEmpty) {
      setState(() => _error = 'Adicione pelo menos um item com descrição.');
      return null;
    }
    if (_selectedCustomerId == null) {
      setState(() => _error = 'Selecione um cliente.');
      return null;
    }
    final date = tryParseDateDdMmYyyy(_dateController.text.trim());
    if (date == null) {
      setState(() => _error = 'Data inválida.');
      return null;
    }
    final customers = await _customersFuture;
    Customer? customer;
    for (final c in customers) {
      if (c.id == _selectedCustomerId) {
        customer = c;
        break;
      }
    }
    if (customer == null) {
      setState(() => _error = 'Cliente selecionado não encontrado — escolha de novo.');
      return null;
    }
    return Budget(
      id: widget.budget?.id ?? '',
      customerId: _selectedCustomerId,
      customerName: customer.name,
      addressText: _addressController.text.trim(),
      date: date,
      items: items,
      discountCents: tryParseCentsFromText(_discountController.text) ?? 0,
      observations: _observationsController.text.trim(),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final budget = await _buildBudgetFromForm();
      if (budget == null) return;
      final repository = context.read<BudgetsRepository>();
      // `_buildBudgetFromForm` já preenche `id` com `widget.budget!.id`
      // quando `_isEditing` — só falta escolher qual método do
      // repositório usar (update ignora o id passado em `create`, e
      // vice-versa não faria sentido).
      if (_isEditing) {
        await repository.update(budget);
      } else {
        await repository.create(budget);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar o orçamento.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generatePdf() async {
    setState(() {
      _generatingPdf = true;
      _error = null;
    });
    try {
      final budget = await _buildBudgetFromForm();
      if (budget == null) return;
      final auth = context.read<AuthController>();
      final profileData = await auth.fetchOwnProfileData();
      final bytes = await buildBudgetPdf(
        budget,
        BudgetPdfProvider(
          name: auth.displayName,
          logoUrl: profileData['logoUrl'] as String?,
          pixKey: profileData['pixKey'] as String?,
        ),
      );
      if (!mounted) return;
      await Printing.sharePdf(bytes: bytes, filename: 'orcamento_${budget.customerName}.pdf');
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível gerar o PDF. Tenta de novo.');
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Widget _buildItemRow(int index) {
    final row = _itemRows[index];
    final item = row.toItem();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.descriptionController,
                    decoration: const InputDecoration(labelText: 'Descrição do item'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  onPressed: () => _removeItemRow(index),
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  tooltip: 'Remover item',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.quantityController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Qtd'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: row.unitController,
                    decoration: const InputDecoration(labelText: 'Unidade', hintText: 'serviço, m², ...'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: row.unitPriceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Preço unitário (R\$)'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (item != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Total do item: ${formatCentsBRL(item.totalCents)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _currentItems();
    final subtotalCents = items.fold<int>(0, (sum, item) => sum + item.totalCents);
    final discountCents = tryParseCentsFromText(_discountController.text) ?? 0;
    final totalCents = (subtotalCents - discountCents).clamp(0, 1 << 62);
    final busy = _saving || _generatingPdf;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar orçamento' : 'Novo orçamento')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FutureBuilder<List<Customer>>(
              future: _customersFuture,
              builder: (context, snapshot) {
                final customers = snapshot.data ?? [];
                final hasSelected =
                    _selectedCustomerId == null || customers.any((c) => c.id == _selectedCustomerId);
                return DropdownButtonFormField<String>(
                  initialValue: hasSelected ? _selectedCustomerId : null,
                  decoration: const InputDecoration(labelText: 'Cliente'),
                  items: customers
                      .map((c) => DropdownMenuItem<String>(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (value) => setState(() => _selectedCustomerId = value),
                );
              },
            ),
            const SizedBox(height: 4),
            const Text(
              'Não achou o cliente? Cadastre primeiro na aba Clientes.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Endereço (opcional, aparece no PDF)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dateController,
              keyboardType: TextInputType.datetime,
              inputFormatters: [_dateMask],
              decoration: InputDecoration(
                labelText: 'Data',
                suffixIcon: IconButton(
                  tooltip: 'Escolher no calendário',
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  onPressed: _pickDate,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Itens', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (var i = 0; i < _itemRows.length; i++) _buildItemRow(i),
            OutlinedButton.icon(
              onPressed: _addItemRow,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar item'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _discountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Desconto (opcional, em R\$)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _observationsController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Observações (opcional)'),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.muted.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _totalsRow('Subtotal', formatCentsBRL(subtotalCents)),
                  if (discountCents > 0) ...[
                    const SizedBox(height: 4),
                    _totalsRow('Desconto', formatCentsBRL(discountCents)),
                  ],
                  const Divider(height: 20),
                  _totalsRow('Total', formatCentsBRL(totalCents.toInt()), bold: true),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: busy ? null : _save,
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salvar orçamento'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: busy ? null : _generatePdf,
              icon: _generatingPdf
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Gerar e compartilhar PDF'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalsRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 16 : 14,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}
