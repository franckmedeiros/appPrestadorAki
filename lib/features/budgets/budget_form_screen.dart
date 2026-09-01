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
///
/// Visual em cards com ícone, a partir de um mockup que o Franck mandou.
/// O mockup só mostrava "Salvar orçamento" e "Cancelar", mas "Gerar e
/// compartilhar PDF" é uma funcionalidade de verdade que já existia
/// (não dava pra simplesmente tirar) - virou um terceiro botão
/// secundário entre os outros dois, em vez de sumir.
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: row.descriptionController,
                  decoration: const InputDecoration(hintText: 'Descrição do item'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: () => _removeItemRow(index),
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  tooltip: 'Remover item',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MiniField(
                  badge: const Text('#', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  label: 'Qtd',
                  child: TextField(
                    controller: row.quantityController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniField(
                  badge: const Icon(Icons.sell_outlined, size: 16, color: AppColors.primary),
                  label: 'Unidade',
                  child: TextField(
                    controller: row.unitController,
                    decoration: const InputDecoration(hintText: 'Serviço'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniField(
                  badge: const Text('R\$', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                  label: 'Preço unitário',
                  child: TextField(
                    controller: row.unitPriceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: '0,00'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ],
          ),
          if (item != null) ...[
            const SizedBox(height: 8),
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 76,
        title: Text(_isEditing ? 'Editar orçamento' : 'Novo orçamento'),
        titleTextStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _isEditing
                    ? 'Atualize os dados e os itens do orçamento'
                    : 'Preencha os dados e adicione os itens do orçamento',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<List<Customer>>(
                    future: _customersFuture,
                    builder: (context, snapshot) {
                      final customers = snapshot.data ?? [];
                      final hasSelected = _selectedCustomerId == null ||
                          customers.any((c) => c.id == _selectedCustomerId);
                      return _FieldRow(
                        icon: Icons.person_outline,
                        label: 'Cliente',
                        helperText: 'Não achou o cliente? Cadastre primeiro na aba Clientes.',
                        child: DropdownButtonFormField<String>(
                          initialValue: hasSelected ? _selectedCustomerId : null,
                          decoration: const InputDecoration(hintText: 'Selecione o cliente'),
                          items: customers
                              .map((c) => DropdownMenuItem<String>(value: c.id, child: Text(c.name)))
                              .toList(),
                          onChanged: (value) => setState(() => _selectedCustomerId = value),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _FieldRow(
                    icon: Icons.location_on_outlined,
                    label: 'Endereço (opcional, aparece no PDF)',
                    child: TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(hintText: 'Digite o endereço'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FieldRow(
                    icon: Icons.calendar_month_outlined,
                    label: 'Data',
                    child: TextField(
                      controller: _dateController,
                      keyboardType: TextInputType.datetime,
                      inputFormatters: [_dateMask],
                      decoration: InputDecoration(
                        suffixIcon: IconButton(
                          tooltip: 'Escolher no calendário',
                          icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                          onPressed: _pickDate,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Itens', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 10),
            for (var i = 0; i < _itemRows.length; i++) _buildItemRow(i),
            _DottedActionButton(onTap: _addItemRow, label: 'Adicionar item'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldRow(
                    icon: Icons.percent_rounded,
                    label: 'Desconto (opcional, em R\$)',
                    child: TextField(
                      controller: _discountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(hintText: '0,00'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FieldRow(
                    icon: Icons.description_outlined,
                    label: 'Observações (opcional)',
                    child: TextField(
                      controller: _observationsController,
                      maxLines: 3,
                      decoration: const InputDecoration(hintText: 'Adicione observações sobre o orçamento'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
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
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: busy ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined, size: 20),
              label: const Text('Salvar orçamento'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : _generatePdf,
              icon: _generatingPdf
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined, size: 20),
              label: const Text('Gerar e compartilhar PDF'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.close, size: 20),
              label: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalsRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 18 : 14,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: bold ? AppColors.primary : AppColors.ink,
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

/// Linha de campo — ícone num círculo à esquerda, rótulo acima do campo
/// de verdade, e um texto de ajuda opcional embaixo. Igual ao _FieldCard
/// de CustomerFormScreen/AppointmentFormScreen, só que SEM o Container
/// próprio (aqui várias linhas dividem um único cartão externo — ver o
/// mockup, que agrupa Cliente/Endereço/Data e Desconto/Observações cada
/// um dentro de um cartão só, em vez de um cartão por campo).
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.icon, required this.label, required this.child, this.helperText});

  final IconData icon;
  final String label;
  final Widget child;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              child,
              if (helperText != null) ...[
                const SizedBox(height: 6),
                Text(helperText!, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Campo miúdo (Qtd/Unidade/Preço unitário de um item) — rótulo acima,
/// e um selo pequeno (ícone ou texto curto tipo "#"/"R\$") à esquerda do
/// campo em vez de um círculo grande, já que os três dividem a largura
/// do cartão do item.
class _MiniField extends StatelessWidget {
  const _MiniField({required this.badge, required this.label, required this.child});

  final Widget badge;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: badge,
            ),
            const SizedBox(width: 6),
            Expanded(child: child),
          ],
        ),
      ],
    );
  }
}

/// Botão "Adicionar item" com borda pontilhada, igual ao mockup. O
/// Flutter não tem uma borda tracejada pronta sem depender de outro
/// pacote só pra isso — em vez de adicionar uma dependência nova pra um
/// detalhe puramente decorativo, a borda vira uma linha tracejada
/// desenhada à mão com CustomPainter (mais barato que trazer um pacote
/// inteiro pra um traço).
class _DottedActionButton extends StatelessWidget {
  const _DottedActionButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: CustomPaint(
        painter: _DashedBorderPainter(color: AppColors.primary, radius: 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
