import 'package:flutter/material.dart';

import '../../widgets/selo_de_estado.dart';
import 'models/job.dart';

/// Selo com a etapa atual de um Job. Criado pro pedido do Franck de dar
/// pra ver (e, tocando, mudar) a etapa de um serviço direto no card de
/// "Compromissos de hoje" do Dashboard, sem precisar entrar em Serviços.
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

  /// A etapa do serviço traduzida nos cinco tons do app.
  ///
  /// Era uma cor por etapa, tirada de `JobStatus.color`, mais uma
  /// bolinha colorida do lado do texto. Duas marcas de cor pro mesmo
  /// dado — e num card que já tem o selo do orçamento logo acima, viravam
  /// quatro manchas coloridas disputando o olho. Agora é a mesma regra do
  /// resto do app: ou a bola está com você, ou está com o cliente, ou
  /// acabou.
  TomDoSelo get _tom => switch (status) {
        // "Novo" é neutro, não laranja: é o estado em que o serviço
        // nasce, e numa lista recém-aberta quase tudo estaria laranja —
        // a cor pararia de significar "olhe aqui".
        JobStatus.novo => TomDoSelo.neutro,
        JobStatus.emAndamento => TomDoSelo.marca,
        JobStatus.interrompido => TomDoSelo.espera,
        JobStatus.aguardandoPagamento => TomDoSelo.espera,
        JobStatus.concluido => TomDoSelo.positivo,
      };

  @override
  Widget build(BuildContext context) {
    return SeloDeEstado(_texto, tom: _tom);
  }
}
