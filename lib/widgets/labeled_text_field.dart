import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';

/// Campo de texto com o rótulo acima (fora da caixa) — mesmo padrão
/// visual do CustomTextField do app Resenha, usado nas telas de Login e
/// Cadastro reestilizadas. Só cuida da aparência: validação/controller
/// continuam do jeito que cada tela já usava com TextFormField.
class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.keyboardType,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.inputFormatters,
    this.textInputAction,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          validator: validator,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          style: const TextStyle(fontSize: 15, color: AppColors.ink),
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: AppColors.muted, size: 21) : null,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}
