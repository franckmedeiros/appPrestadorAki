import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../../widgets/mask_text_input_formatter.dart';
import '../../widgets/state_city_fields.dart';
import 'customers_repository.dart';
import 'models/customer.dart';

/// Formulário de cliente — cria um novo (`customer == null`) ou edita um
/// já existente (`customer` preenchido, ver `CustomersListScreen`, que
/// agora abre isso ao tocar num card da lista).
class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key, this.customer});

  final Customer? customer;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.customer?.name ?? '');
  late final _phoneController =
      TextEditingController(text: widget.customer?.phone ?? widget.customer?.whatsapp ?? '');
  late String? _city = widget.customer?.addressCity;
  late String? _uf = widget.customer?.addressState;

  final _phoneMask = MaskTextInputFormatter('(##) #####-####');

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.customer != null;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = context.read<CustomersRepository>();
      if (_isEditing) {
        await repository.update(
          widget.customer!.id,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          addressCity: (_city ?? '').trim(),
          addressState: (_uf ?? '').trim().toUpperCase(),
        );
      } else {
        await repository.create(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          addressCity: (_city ?? '').trim(),
          addressState: (_uf ?? '').trim().toUpperCase(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar o cliente.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar cliente' : 'Novo cliente')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome completo'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Informe o nome' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [_phoneMask],
                decoration: const InputDecoration(labelText: 'Telefone / WhatsApp'),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: StateSelectorField(
                      key: ValueKey('customer-uf-$_uf'),
                      initialValue: _uf,
                      onChanged: (uf) => setState(() {
                        _uf = uf;
                        _city = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: CitySelectorField(
                      key: ValueKey('customer-city-$_uf-$_city'),
                      uf: _uf,
                      initialValue: _city,
                      onChanged: (city) => setState(() => _city = city),
                    ),
                  ),
                ],
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
                    : Text(_isEditing ? 'Salvar alterações' : 'Salvar cliente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
