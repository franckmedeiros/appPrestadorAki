import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';

/// Contato para denúncias e assuntos dos Termos. É o mesmo endereço que
/// aparece no texto — deixado numa constante pra nunca divergir entre o
/// que o usuário lê e o link em que ele toca.
const String kEmailDeContato = 'opoutsourcingbr@gmail.com';

/// Marca sob a qual o app é oferecido. Igual ao que a tela "Sobre o app"
/// já mostra (ver AboutScreen._nomeEmpresa) — as duas telas falando nomes
/// diferentes da mesma coisa é o tipo de detalhe que um revisor nota.
const String kNomeDaMarca = 'OPOutSourcing Brasil';

/// Quem responde juridicamente hoje.
///
/// A marca aparece em primeiro lugar no texto, mas o nome civil precisa
/// estar lá: [kNomeDaMarca] não é pessoa jurídica registrada, então não
/// pode ser a parte contratante. Um contrato precisa apontar pra alguém
/// que exista de fato — sem isso, o consumidor que quiser reclamar não tem
/// contra quem, e o Código de Defesa do Consumidor exige identificação
/// clara do fornecedor.
///
/// Há ainda uma razão prática: a conta de desenvolvedor nas duas lojas é
/// PESSOAL, então a ficha do app já exibe este nome como vendedor. Termos
/// que só citassem a marca contradiriam a própria loja.
///
/// **Quando o CNPJ existir**, troque as duas constantes por razão social +
/// CNPJ e ajuste a frase da seção 1 — é o único ponto do texto que fala
/// de quem responde.
const String kResponsavelLegal = 'Franck Medeiros Silva';

/// Termos de Uso do PrestadorAki.
///
/// Existe por exigência da Apple (App Store Review Guideline 1.2): um app
/// com conteúdo publicado por usuários precisa ter termos aceitos no
/// cadastro, deixando claro que conteúdo ofensivo não é tolerado. Por isso
/// a seção "Conduta e conteúdo" é explícita a ponto de listar o que é
/// proibido, em vez de dizer "use com bom senso" — a Apple procura a regra
/// escrita, e o usuário só consegue cumprir o que consegue ler.
///
/// Texto em português simples, de propósito. Termos que ninguém entende
/// são termos que ninguém leu, e um aceite sem leitura não protege nem o
/// usuário nem você.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Termos de Uso')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          const _Atualizacao('Última atualização: 18 de setembro de 2026'),
          const SizedBox(height: 18),

          const _Secao('1. Quem oferece o PrestadorAki'),
          const _Paragrafo(
            'O PrestadorAki é um produto da $kNomeDaMarca, marca sob a qual '
            '$kResponsavelLegal, pessoa física, opera e responde pelo app.',
          ),
          const _Paragrafo(
            'Para falar sobre estes Termos, denunciar conteúdo ou pedir a '
            'remoção de algo publicado, use o e-mail abaixo.',
          ),
          const SizedBox(height: 8),
          const _BotaoDeEmail(),

          const _Secao('2. O que o app faz — e o que não faz'),
          const _Paragrafo(
            'O PrestadorAki conecta quem precisa de um serviço a '
            'profissionais da região. Nós não prestamos os serviços, não '
            'somos parte do contrato entre cliente e prestador e não '
            'garantimos preço, prazo ou qualidade do que for combinado '
            'entre vocês.',
          ),
          const _Paragrafo(
            'Quem contrata e quem executa respondem pelo que combinaram. '
            'Confira as informações do profissional antes de fechar '
            'qualquer serviço.',
          ),

          const _Secao('3. Sua conta'),
          const _Paragrafo(
            'Você precisa ter 18 anos ou mais e informar dados verdadeiros. '
            'A conta é sua e intransferível: o que for feito por ela é de '
            'sua responsabilidade, então guarde bem a sua senha.',
          ),
          const _Paragrafo(
            'Você pode excluir sua conta a qualquer momento, em '
            'Meu perfil, e seus dados são apagados junto.',
          ),

          const _Secao('4. Conduta e conteúdo'),
          const _Paragrafo(
            'Avaliações e comentários são escritos pelos próprios usuários. '
            'Você é responsável pelo que publica, e não toleramos conteúdo '
            'ofensivo. É proibido publicar:',
          ),
          const _Item('ofensa, xingamento, ameaça ou discurso de ódio — '
              'inclusive por raça, cor, religião, origem, deficiência, '
              'idade, gênero ou orientação sexual;'),
          const _Item('assédio, perseguição ou incentivo à violência contra '
              'qualquer pessoa;'),
          const _Item('conteúdo sexual, obsceno ou impróprio;'),
          const _Item('acusação que você sabe ser falsa sobre um '
              'profissional ou cliente;'),
          const _Item('dados pessoais de terceiros — telefone, endereço, '
              'documento — sem autorização;'),
          const _Item('spam, propaganda ou avaliação comprada, trocada ou '
              'escrita por quem não contratou o serviço.'),
          const _Paragrafo(
            'Não há tolerância para conteúdo ofensivo e para usuários '
            'abusivos. Publicar algo da lista acima pode levar à remoção do '
            'conteúdo e ao encerramento da sua conta, sem aviso prévio e '
            'sem devolução de valores de assinatura.',
          ),

          const _Secao('5. Denúncia, bloqueio e remoção'),
          const _Paragrafo(
            'Toda avaliação tem, no menu de três pontinhos, as opções '
            'Denunciar e Bloquear este usuário. Ao bloquear, você deixa de '
            'ver o conteúdo daquela pessoa; é possível desfazer em '
            'Meu perfil, na lista de usuários bloqueados.',
          ),
          const _Paragrafo(
            'Analisamos toda denúncia em até 24 horas. Se o conteúdo violar '
            'estes Termos, ele é removido e podemos suspender ou encerrar a '
            'conta de quem publicou. Você também pode denunciar pelo e-mail '
            'de contato, se preferir.',
          ),

          const _Secao('6. Avaliações'),
          const _Paragrafo(
            'Avalie apenas serviços que você realmente contratou, e '
            'descreva a sua experiência. A nota fica visível no perfil '
            'público do profissional junto com o seu nome. Não removemos '
            'uma avaliação só por ser negativa — só quando ela viola estes '
            'Termos.',
          ),

          const _Secao('7. Assinatura do profissional'),
          const _Paragrafo(
            'Para aparecer na busca, o profissional assina um plano mensal. '
            'A cobrança, a renovação automática e os reembolsos são feitos '
            'pela App Store ou pelo Google Play, conforme a loja em que a '
            'compra foi realizada, e seguem as regras dessas lojas.',
          ),
          const _Paragrafo(
            'O cancelamento é feito na própria loja, nas configurações de '
            'assinatura da sua conta. Ao cancelar, o perfil deixa de '
            'aparecer na busca ao fim do período já pago.',
          ),

          const _Secao('8. Seus dados'),
          const _Paragrafo(
            'Coletamos o que é necessário para o app funcionar: nome, '
            'e-mail, telefone, cidade e os dados dos serviços que você '
            'contrata ou presta. Não vendemos seus dados.',
          ),
          const _Paragrafo(
            'Conforme a LGPD, você pode pedir acesso, correção ou exclusão '
            'dos seus dados pelo e-mail de contato. A exclusão da conta no '
            'app já faz isso automaticamente.',
          ),

          const _Secao('9. Mudanças nestes Termos'),
          const _Paragrafo(
            'Podemos atualizar estes Termos. Se a mudança for relevante, '
            'avisamos no app. Continuar usando depois do aviso significa '
            'que você aceitou a nova versão.',
          ),

          const _Secao('10. Foro'),
          const _Paragrafo(
            'Aplica-se a lei brasileira. Questões que envolvam relação de '
            'consumo podem ser levadas ao foro do domicílio do consumidor, '
            'como prevê o Código de Defesa do Consumidor.',
          ),

          const SizedBox(height: 28),
          const Text(
            'Dúvida sobre qualquer ponto? Escreva para o e-mail acima.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _BotaoDeEmail extends StatelessWidget {
  const _BotaoDeEmail();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () async {
          final uri = Uri(scheme: 'mailto', path: kEmailDeContato);
          final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!abriu && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Não foi possível abrir um app de e-mail.')),
            );
          }
        },
        icon: const Icon(Icons.mail_outline, size: 18),
        label: const Text(kEmailDeContato),
        style: TextButton.styleFrom(padding: EdgeInsets.zero),
      ),
    );
  }
}

class _Atualizacao extends StatelessWidget {
  const _Atualizacao(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(fontSize: 12, color: AppColors.muted, fontStyle: FontStyle.italic),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao(this.titulo);

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        titulo,
        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink),
      ),
    );
  }
}

class _Paragrafo extends StatelessWidget {
  const _Paragrafo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        texto,
        style: const TextStyle(fontSize: 13.5, height: 1.55, color: AppColors.ink),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Icon(Icons.circle, size: 5, color: AppColors.primary),
          ),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
