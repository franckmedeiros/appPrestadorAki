# Pré-cadastro com consentimento (atual — 14/10)

Fluxo completo em `functions/src/convites.ts`. Resumo: você pergunta no
WhatsApp se pode incluir a empresa; quem disser SIM entra na busca e passa
a receber AVISO DE PEDIDO no WhatsApp (sem dados do cliente). O prestador
baixa o app e ativa o perfil com o código do aviso; o contato do cliente
só é liberado com a assinatura.

## 1. Mensagem de convite (manual, pelo seu WhatsApp)

> Olá! Tudo bem? Sou o Franck, do PrestadorAki, um app que conecta clientes
> a prestadores de serviço aqui da região. Vi que vocês trabalham com
> {serviço} em {cidade}. Posso incluir a empresa de vocês no app, sem custo?
> Quando algum cliente pedir esse serviço, aviso vocês aqui pelo WhatsApp.

Uns 20 a 30 por dia, à mão. **Só registre quem responder SIM.**

## 2. Registrar quem aceitou

Monte um CSV `nome,categoria,cidade,uf,whatsapp` e rode:

    node scripts/registrar_convites.js C:\caminho\chave.json aceitaram.csv
    node scripts/registrar_convites.js C:\caminho\chave.json aceitaram.csv --gravar

Pediu pra sair: mesma linha num CSV e `--remover --gravar`.

## 3. Modelo do aviso (aprovar no WhatsApp Manager da conta do EstiloAki)

- Nome: `prestadoraki_novo_pedido`
- Categoria: **Utilidade** · Idioma: Português (BR)
- Corpo:

> Olá, {{1}}! Um cliente pediu orçamento de {{2}} em {{3}} pelo
> PrestadorAki. Número do pedido: {{4}}. Para ver e responder, baixe o app
> PrestadorAki, crie sua conta e toque em "Recebi um aviso de pedido no
> WhatsApp".

(Enviado para análise em 14/10. Não use a palavra "código": a Meta trata
como modelo de Autenticação e recusa como Utilidade.)

Exemplo pros campos (a Meta pede): `João`, `instalação elétrica`,
`Pinheirinho, Criciúma`, `482913`.

---

# (Histórico) Modelo antigo de consentimento

# Modelo de mensagem pra pedir consentimento

Mensagem curta pra mandar por WhatsApp/telefone pros nomes da lista de
`leads_para_contato.csv`, antes de colocar qualquer um deles no
`providers_seed.csv`. Ajuste o [nome do app]/link conforme o momento do
projeto (hoje ainda não tem link de loja publicado).

---

Oi, [nome]! Tudo bem? Meu nome é [seu nome], sou de [Criciúma/Sertãozinho].

Estou lançando um aplicativo chamado PrestadorAki, pra ajudar quem precisa
de um profissional (eletricista, encanador, pedreiro, pintor, etc.) a
encontrar alguém de confiança na região.

Vi que você trabalha com [categoria] aqui em [cidade] e queria saber se
posso colocar seu nome, categoria e cidade no diretório do app — só isso,
sem telefone nem endereço público. Quem quiser te chamar, pede um
orçamento pelo próprio app e você recebe o contato normalmente. É de
graça, e se um dia você quiser tirar seu nome de lá, é só avisar.

Posso incluir?

---

**Depois que a pessoa responder "sim"**: adiciona uma linha nova em
`providers_seed.csv` com `name,category,city,state` (sem telefone) e roda
o script normalmente — ver `README.md` desta pasta.

**Se a pessoa não responder ou disser "não"**: não inclui. Sem exceção,
mesmo que o número esteja público em algum guia comercial.
