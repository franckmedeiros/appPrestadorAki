import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/validators.dart';

/// Checklist ao vivo dos requisitos da senha forte (ver
/// core/validators.dart) — mostrado embaixo do campo de senha nas telas
/// de cadastro. Sem isso, o usuário só descobre o que falta um requisito
/// de cada vez, a cada tentativa de "Cadastrar" (o `validator:` do
/// TextFormField só aponta o PRIMEIRO requisito que falta).
///
/// Ouve o `controller` diretamente (ValueListenableBuilder) em vez de
/// depender de um `onChanged` que cada tela precisaria fiar certinho —
/// funciona sozinho só recebendo o mesmo controller do campo de senha.
class PasswordRequirementsHint extends StatelessWidget {
  const PasswordRequirementsHint({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final password = value.text;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _Requirement(
                label: '$passwordMinLength+ caracteres',
                met: password.length >= passwordMinLength,
              ),
              _Requirement(label: 'Maiúscula', met: passwordHasUppercase(password)),
              _Requirement(label: 'Minúscula', met: passwordHasLowercase(password)),
              _Requirement(label: 'Número', met: passwordHasDigit(password)),
              _Requirement(label: 'Especial (!@#...)', met: passwordHasSpecialChar(password)),
            ],
          ),
        );
      },
    );
  }
}

class _Requirement extends StatelessWidget {
  const _Requirement({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final color = met ? AppColors.success : AppColors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(met ? Icons.check_circle : Icons.circle_outlined, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11.5, color: color)),
      ],
    );
  }
}
