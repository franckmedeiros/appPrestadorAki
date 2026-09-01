import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../../core/app_theme.dart';
import '../../core/date_text_utils.dart';
import '../../widgets/mask_text_input_formatter.dart';
import '../customers/customers_repository.dart';
import '../customers/models/customer.dart';
import 'appointments_repository.dart';
import 'models/appointment.dart';

/// Formulário de compromisso — cria um novo (`appointment == null`) ou
/// edita um já existente (`appointment` preenchido, ver `AgendaScreen`,
/// que agora abre isso ao tocar num compromisso da lista). Visual em
/// cards com ícone, a partir de um mockup que o Franck mandou (mesmo
/// sistema visual do CustomerFormScreen - ver _FieldCard lá, redesenhado
/// aqui localmente porque os dois formulários não compartilham um
/// arquivo comum de widgets de formulário ainda).
class AppointmentFormScreen extends StatefulWidget {
  const AppointmentFormScreen({super.key, this.appointment});

  final Appointment? appointment;

  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  late final _addressController =
      TextEditingController(text: widget.appointment?.addressText ?? '');
  late final _observationsController =
      TextEditingController(text: widget.appointment?.observations ?? '');

  // Digitável em vez de só abrir um seletor (decisão combinada com o
  // Franck: mais rápido pra quem já sabe a data/hora de cor) — ver
  // core/date_text_utils.dart pra formatação/leitura e
  // MaskTextInputFormatter('##/##/####'/'##:##') pra guiar a digitação.
  // O seletor (ícone de calendário/relógio no fim do campo) continua
  // existindo como atalho, não como único jeito de preencher.
  late final DateTime _initialDateTime = widget.appointment?.scheduledAt ?? DateTime.now();
  late final _dateController =
      TextEditingController(text: formatDateDdMmYyyy(_initialDateTime));
  late final _timeController = TextEditingController(
    text: formatTimeHhMm(TimeOfDay(hour: _initialDateTime.hour, minute: _initialDateTime.minute)),
  );
  final _dateMask = MaskTextInputFormatter('##/##/####');
  final _timeMask = MaskTextInputFormatter('##:##');

  late Future<List<Customer>> _customersFuture;
  String? _selectedCustomerId;
  late AppointmentType _type = widget.appointment?.type ?? AppointmentType.visitaTecnica;

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.appointment != null;

  @override
  void initState() {
    super.initState();
    _customersFuture = context.read<CustomersRepository>().list();
    _selectedCustomerId = widget.appointment?.customerId;
  }

  @override
  void dispose() {
    _addressController.dispose();
    _observationsController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final current = tryParseDateDdMmYyyy(_dateController.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dateController.text = formatDateDdMmYyyy(picked));
  }

  Future<void> _pickTime() async {
    final current = tryParseTimeHhMm(_timeController.text) ?? TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked != null) setState(() => _timeController.text = formatTimeHhMm(picked));
  }

  Future<void> _save() async {
    final date = tryParseDateDdMmYyyy(_dateController.text);
    final time = tryParseTimeHhMm(_timeController.text);
    if (date == null || time == null) {
      setState(() => _error = 'Informe uma data e hora válidas (ex.: 15/03/2027 e 09:00).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      // O Firestore não faz join — o nome do cliente é denormalizado no
      // próprio compromisso (ver firebase/DATA_MODEL.md) pra não precisar
      // de uma leitura extra só pra mostrar o nome na lista da Agenda.
      String? customerName;
      if (_selectedCustomerId != null) {
        final customers = await _customersFuture;
        for (final c in customers) {
          if (c.id == _selectedCustomerId) {
            customerName = c.name;
            break;
          }
        }
      }
      final repository = context.read<AppointmentsRepository>();
      if (_isEditing) {
        await repository.update(
          widget.appointment!.id,
          customerId: _selectedCustomerId,
          customerName: customerName,
          type: _type,
          scheduledAt: scheduledAt,
          durationMinutes: widget.appointment!.durationMinutes,
          addressText: _addressController.text.trim(),
          observations: _observationsController.text.trim(),
        );
      } else {
        await repository.create(
          customerId: _selectedCustomerId,
          customerName: customerName,
          type: _type,
          scheduledAt: scheduledAt,
          addressText: _addressController.text.trim(),
          observations: _observationsController.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar o compromisso.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(_isEditing ? 'Editar compromisso' : 'Novo compromisso'),
        titleTextStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.calendar_month_outlined, color: Colors.white),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _isEditing ? 'Atualize os dados do compromisso' : 'Agende uma visita técnica ou serviço',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        // `stretch`: sem isso, o Column usa o alinhamento padrão (centro)
        // no eixo horizontal, e tanto o SingleChildScrollView quanto a
        // barra de botões abaixo encolhem pro tamanho do próprio conteúdo
        // em vez de ocupar a largura da tela — foi isso que deixou a tela
        // toda pequena e flutuando no meio, em vez de preencher direito.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                FutureBuilder<List<Customer>>(
                  future: _customersFuture,
                  builder: (context, snapshot) {
                    final customers = snapshot.data ?? [];
                    // Garante que o cliente já vinculado (modo de edição)
                    // sempre exista como opção, mesmo que a lista de clientes
                    // ainda não tenha carregado ou ele tenha sido removido.
                    final hasSelected =
                        _selectedCustomerId == null || customers.any((c) => c.id == _selectedCustomerId);
                    return _FieldCard(
                      icon: Icons.person_outline,
                      label: 'Cliente (opcional)',
                      helperText: 'Selecione um cliente para este compromisso (opcional)',
                      child: DropdownButtonFormField<String>(
                        initialValue: hasSelected ? _selectedCustomerId : null,
                        decoration: const InputDecoration(),
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text('Sem cliente vinculado')),
                          ...customers.map(
                            (c) => DropdownMenuItem<String>(value: c.id, child: Text(c.name)),
                          ),
                        ],
                        onChanged: (value) => setState(() => _selectedCustomerId = value),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _FieldCard(
                  icon: Icons.medical_services_outlined,
                  label: 'Tipo',
                  child: DropdownButtonFormField<AppointmentType>(
                    initialValue: _type,
                    decoration: const InputDecoration(),
                    items: AppointmentType.values
                        .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                        .toList(),
                    onChanged: (value) => setState(() => _type = value ?? _type),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _FieldCard(
                        icon: Icons.calendar_month_outlined,
                        label: 'Data',
                        compact: true,
                        child: TextFormField(
                          controller: _dateController,
                          keyboardType: TextInputType.datetime,
                          inputFormatters: [_dateMask],
                          decoration: InputDecoration(
                            hintText: 'DD/MM/AAAA',
                            suffixIcon: IconButton(
                              tooltip: 'Escolher no calendário',
                              icon: const Icon(Icons.keyboard_arrow_down_rounded),
                              onPressed: _pickDate,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FieldCard(
                        icon: Icons.schedule_outlined,
                        label: 'Hora',
                        compact: true,
                        child: TextFormField(
                          controller: _timeController,
                          keyboardType: TextInputType.datetime,
                          inputFormatters: [_timeMask],
                          decoration: InputDecoration(
                            hintText: 'HH:MM',
                            suffixIcon: IconButton(
                              tooltip: 'Escolher no relógio',
                              icon: const Icon(Icons.keyboard_arrow_down_rounded),
                              onPressed: _pickTime,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _FieldCard(
                  icon: Icons.location_on_outlined,
                  label: 'Endereço (opcional)',
                  child: TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(hintText: 'Digite o endereço'),
                  ),
                ),
                const SizedBox(height: 14),
                _FieldCard(
                  icon: Icons.description_outlined,
                  label: 'Observações (opcional)',
                  child: TextFormField(
                    controller: _observationsController,
                    decoration: const InputDecoration(hintText: 'Adicione observações sobre o compromisso'),
                    maxLines: 3,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                ],
              ),
            ),
          ),
          // Botões fixos no rodapé (fora do SingleChildScrollView) — antes
          // ficavam soltos no fim do conteúdo, o que em telas com poucos
          // campos (esse formulário é curto) deixava uma sobra grande de
          // espaço em branco abaixo deles. Assim eles sempre grudam no
          // fundo de verdade, e o formulário rola só na área acima.
          Container(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 8 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -4)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_outlined, size: 20),
                  label: Text(_isEditing ? 'Salvar alterações' : 'Salvar compromisso'),
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.close, size: 20),
                  label: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo compacto — layout vertical para preservar a largura útil em telas
/// estreitas. Evita que o ícone lateral consuma espaço dos Dropdowns e inputs.
class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.icon,
    required this.label,
    required this.child,
    this.helperText,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final String? helperText;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final padding = compact ? 12.0 : 14.0;
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.muted.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 26 : 30,
                height: compact ? 26 : 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  color: AppColors.primary,
                  size: compact ? 15 : 17,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 12 : 13,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 7 : 9),
          child,
          if (helperText != null) ...[
            const SizedBox(height: 6),
            Text(
              helperText!,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
