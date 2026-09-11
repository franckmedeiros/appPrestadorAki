import 'package:flutter/material.dart';

import 'models/job.dart';

/// Selo compacto (bolinha colorida + texto) com a etapa atual de um Job —
/// mesma paleta de `JobStatusWire.color` usada no cabeçalho de cada seção
/// do Kanban de Serviços. Criado pro pedido do Franck de dar pra ver (e,
/// tocando, mudar) a etapa de um serviço direto no card de "Compromissos
/// de hoje" do Dashboard, sem precisar entrar em Serviços.
class JobStatusChip extends StatelessWidget {
  const JobStatusChip({super.key, required this.status, this.paraCliente = false});

  final JobStatus status;

  /// Troca o texto pelo vocabulário do CLIENTE.
  ///
  /// Os rótulos padrão (`JobStatus.label`) são do Kanban do prestador, e
  /// ali fazem sentido: "Novo" é uma raia de trabalho a fazer. Do outro
  /// lado do balcão, "Novo" não diz nada — o Franck reparou que o cliente
  /// ficava vendo só "Aceito" e não entendia que o serviço ainda nem
  /// começou. Aqui os mesmos estados viram uma frase que responde à
  /// pergunta que o cliente realmente tem: e agora, o que acontece?
  final bool paraCliente;

  String get _texto => paraCliente
      ? switch (status) {
          JobStatus.novo => 'Aguardando o prestador iniciar',
          JobStatus.emAndamento => 'Serviço em andamento',
          JobStatus.interrompido => 'Serviço pausado',
          JobStatus.aguardandoPagamento => 'Aguardando pagamento',
          JobStatus.concluido => 'Serviço concluído',
        }
      : status.label;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            _texto,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
