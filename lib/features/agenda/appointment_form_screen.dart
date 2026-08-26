import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../customers/customers_repository.dart';
import '../customers/models/customer.dart';
import 'appointments_repository.dart';
import 'models/appointment.dart';

class AppointmentFormScreen extends StatefulWidget {
  const AppointmentFormScreen({super.key});

  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  final _addressController = TextEditingController();
  final _observationsController = TextEditingController();

  late Future<List<Customer>> _customersFuture;
  String? _selectedCustomerId;
  AppointmentType _type = AppointmentType.visitaTecnica;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _customersFuture = context.read<CustomersRepository>().list();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _observationsController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final scheduledAt = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
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
      await context.read<AppointmentsRepository>().create(
            customerId: _selectedCustomerId,
            customerName: customerName,
            type: _type,
            scheduledAt: scheduledAt,
            addressText: _addressController.text.trim(),
            observations: _observationsController.text.trim(),
          );
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
      appBar: AppBar(title: const Text('Novo compromisso')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FutureBuilder<List<Customer>>(
              future: _customersFuture,
              builder: (context, snapshot) {
                final customers = snapshot.data ?? [];
                return DropdownButtonFormField<String>(
                  initialValue: _selectedCustomerId,
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
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                      '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_outlined, size: 18),
                    label: Text(_time.format(context)),
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
                  : const Text('Salvar compromisso'),
            ),
          ],
        ),
      ),
    );
  }
}
