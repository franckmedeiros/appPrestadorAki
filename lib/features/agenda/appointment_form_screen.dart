import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../../core/date_text_utils.dart';
import '../../widgets/mask_text_input_formatter.dart';
import '../customers/customers_repository.dart';
import '../customers/models/customer.dart';
import 'appointments_repository.dart';
import 'models/appointment.dart';

/// Formulário de compromisso — cria um novo (`appointment == null`) ou
/// edita um já existente (`appointment` preenchido, ver `AgendaScreen`,
/// que agora abre isso ao tocar num compromisso da lista).
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
      appBar: AppBar(title: Text(_isEditing ? 'Editar compromisso' : 'Novo compromisso')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
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
                return DropdownButtonFormField<String>(
                  initialValue: hasSelected ? _selectedCustomerId : null,
                  decoration: const InputDecoration(labelText: 'Cliente (opcional)'),
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('Sem cliente vinculado')),
                    ...customers.map(
                      (c) => DropdownMenuItem<String>(value: c.id, child: Text(c.name)),
                    ),
                  ],
                  onChanged: (value) => setState(() => _selectedCustomerId = value),
                );
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AppointmentType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: AppointmentType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _dateController,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: [_dateMask],
                    decoration: InputDecoration(
                      labelText: 'Data',
                      hintText: 'DD/MM/AAAA',
                      suffixIcon: IconButton(
                        tooltip: 'Escolher no calendário',
                        icon: const Icon(Icons.calendar_today_outlined, size: 18),
                        onPressed: _pickDate,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _timeController,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: [_timeMask],
                    decoration: InputDecoration(
                      labelText: 'Hora',
                      hintText: 'HH:MM',
                      suffixIcon: IconButton(
                        tooltip: 'Escolher no relógio',
                        icon: const Icon(Icons.schedule_outlined, size: 18),
                        onPressed: _pickTime,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Endereço (opcional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _observationsController,
              decoration: const InputDecoration(labelText: 'Observações (opcional)'),
              maxLines: 3,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_isEditing ? 'Salvar alterações' : 'Salvar compromisso'),
            ),
          ],
        ),
      ),
    );
  }
}
