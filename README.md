# PrestadorAki — Firebase (Firestore + Cloud Functions)

Substitui o backend NestJS + PostgreSQL. Ver `DATA_MODEL.md` pro desenho
completo das coleções do Firestore e o porquê de cada decisão.

## O que já existe

- `firestore.rules` — isolamento multi-tenant (cada prestador só acessa o
  que é dele), com `budgets`/`jobs` bloqueados pro cliente escrever direto
  (só Cloud Functions, via Admin SDK, escrevem esses dois).
- `functions/src/budgets.ts` — todas as regras de negócio de orçamento que
  não davam pra confiar só em regra declarativa do Firestore:
  - `createBudget` (callable) — numeração sequencial atômica
    (`providers/{uid}.nextBudgetNumber`), calcula totais, gera o token
    público.
  - `updateBudget` (callable) — atualiza; se o orçamento já saiu de
    "rascunho", grava uma versão do estado anterior antes de aplicar a
    mudança.
  - `sendBudget` (callable) — marca como enviado, devolve o link público.
  - `rejectBudget` / `requestBudgetChange` (callable).
  - `approveBudget` (callable, o prestador aprovando em nome do cliente) e
    `publicApproveBudget` (HTTPS sem autenticação, o cliente clicando no
    link) — os dois usam a mesma lógica interna, que cria o `job`
    automaticamente e tem uma trava contra aprovar duas vezes (o que
    criaria dois jobs duplicados).
  - `getPublicBudget` (HTTPS sem autenticação) — resolve o token e devolve
    só os campos públicos (nunca o documento inteiro do orçamento).

**Compilação verificada nesta sessão** (`npm run build` limpo, zero
erros de TypeScript). **Execução real não foi possível verificar aqui**:
o emulador do Firestore/Auth precisa baixar um `.jar` de
`storage.googleapis.com`, e esse domínio está bloqueado pela política de
rede deste ambiente sandbox (mesmo bloqueio que já tinha impedido instalar
o Flutter SDK aqui, documentado no README do `mobile/`). Ou seja: a lógica
foi escrita e revisada com cuidado (inclusive corrigi um bug real de
aprovação duplicada durante a revisão manual), mas só será validada de
verdade quando você rodar o emulador ou fizer o primeiro deploy na sua
máquina — que não tem essa restrição de rede.

## O que ainda falta

- CRUD de clientes, visitas técnicas e agenda direto do Firestore no app
  (sem Cloud Function — não tem regra de negócio especial) — ver tarefa
  separada de reescrever os repositórios do Flutter.
- Rastreamento em tempo real de verdade (ingestão de pontos GPS, ETA,
  página pública de rastreamento) — mesma lacuna que já existia antes da
  migração, não é coisa que ficou pior com o Firebase.
- Geração de PDF do orçamento.

## Passo a passo pra você rodar (nada disso dá pra fazer daqui)

1. **Criar o projeto no console do Firebase**: https://console.firebase.google.com
   → "Adicionar projeto" → nome sugerido "PrestadorAki" (projeto novo e
   separado do Resenha, como combinamos).
2. Dentro do projeto: ativar **Firestore Database** (modo produção, escolher
   uma região — `southamerica-east1` fica mais perto do Brasil) e
   **Authentication** → método de login **E-mail/senha**.
3. Ativar o **plano Blaze** (Configurações do projeto → Uso e faturamento) —
   necessário pra rodar Cloud Functions, mesmo que o uso fique dentro da
   cota gratuita.
4. Instalar a CLI e logar (na sua máquina, num terminal comum):
   ```
   npm install -g firebase-tools
   firebase login
   ```
5. Na raiz do projeto (onde está o `firebase.json` — no seu caso é a mesma
   pasta do projeto Flutter, `C:\Projetos\appPrestadorAki`, já que os dois
   zips foram extraídos juntos):
   ```
   firebase use --add        # escolha o projeto que criou no passo 1
   cd functions && npm install && cd ..
   firebase deploy --only firestore:rules,functions
   ```
6. Ainda na raiz do projeto, instalar a CLI do FlutterFire e configurar
   (mesmo processo que você já fez no Resenha):
   ```
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   Isso gera `lib/firebase_options.dart` e registra o app Android/iOS
   nesse projeto Firebase novo.
7. Testar localmente antes de depender só do deploy — de dentro da
   raiz do projeto:
   ```
   firebase emulators:start
   ```
   Abre uma UI em `http://localhost:4000` com Firestore/Auth/Functions
   rodando local, sem gastar nada nem depender do deploy.

Qualquer erro nesses passos (principalmente no `flutterfire configure` ou
no primeiro `firebase deploy`), me manda a mensagem exata que eu te ajudo
a resolver.

## App Flutter — autenticação e dados

O app (`lib/`) foi reescrito para falar direto com Firebase Auth e
Firestore, no lugar do login customizado (JWT) e da API REST em NestJS que
existiam antes:

- `core/auth_controller.dart` — login, cadastro e logout agora usam
  `FirebaseAuth` (`signInWithEmailAndPassword`,
  `createUserWithEmailAndPassword`, `signOut`). O cadastro também cria o
  documento `providers/{uid}` no Firestore logo depois da conta ser criada
  (ver `firebase/DATA_MODEL.md`). A biometria continua sendo só um cadeado
  local por cima da sessão do Firebase Auth — não mudou de comportamento
  pro usuário.
- `features/customers/customers_repository.dart` e
  `features/agenda/appointments_repository.dart` — CRUD direto em
  `providers/{uid}/customers` e `providers/{uid}/appointments` no
  Firestore, sem passar mais por nenhuma API própria.
- `core/api_client.dart` e `core/token_storage.dart` (a parte de tokens)
  ficaram sem uso — não foram apagados pra não mexer em mais arquivos do
  que o necessário, mas podem ser removidos com segurança.

**Nota honesta**: a busca de clientes (`CustomersRepository.list(search:
...)`) hoje filtra no próprio aparelho, depois de baixar a lista inteira
do Firestore — não existe busca de texto parcial nativa no Firestore.
Funciona bem pra quantidade de clientes de um prestador autônomo; não é a
solução certa se a base crescer muito (nesse caso entra uma ferramenta de
busca de verdade, tipo Algolia/Typesense, via Cloud Function).

### Rodando contra o emulador local

Antes de testar, é preciso ter rodado `flutterfire configure` (gera
`lib/firebase_options.dart` e registra o app no projeto Firebase — ver
passo 6 acima) e ter o emulador do Firebase rodando (`firebase
emulators:start`, na raiz do projeto).

Pra apontar o app pros emuladores locais em vez do projeto real:
```
flutter run --dart-define=USE_FIREBASE_EMULATOR=true
```
Sem essa flag, o app fala direto com o Firebase de produção (o padrão,
pra não ter risco de esquecer isso ligado num build de verdade). No
emulador Android, `10.0.2.2` (usado por padrão) já aponta pro localhost
da máquina host; num aparelho físico, use
`--dart-define=FIREBASE_EMULATOR_HOST=<IP da sua máquina na rede>`.

Também foi preciso adicionar um `network_security_config.xml`
(`android/app/src/main/res/xml/`) liberando tráfego HTTP não criptografado
só para `10.0.2.2`/`localhost` — o Android bloqueia isso por padrão a
partir da API 28, e o SDK do Firebase fala HTTP puro (não HTTPS) com o
emulador local. Isso não afeta a comunicação com o Firebase de produção,
que sempre usa HTTPS.

## Marketplace: cliente + prestador (pivot de produto)

Mudança de escopo combinada: o PrestadorAki deixa de ser só um app pro
prestador organizar o próprio negócio e passa a ter um segundo lado —
o cliente final busca, favorita e solicita orçamento a prestadores,
inclusive os que ainda não usam o app (perfis "não reivindicados",
carregados manualmente pra o app não abrir vazio na primeira região).
Ver `firebase/DATA_MODEL.md`, seção "Marketplace", pro modelo de dados
completo.

**O risco que motivou o desenho**: se o cliente conseguisse pegar o
contato do prestador direto na lista, o resto do serviço (orçamento,
combinação, pagamento) aconteceria fora do app, e o PrestadorAki viraria
só uma lista telefônica gratuita. Por isso:

- Nenhuma tela mostra telefone/WhatsApp de um prestador — o contato
  acontece através de "Solicitar orçamento", que vira um orçamento
  (`Budget`, ver mais abaixo), nunca de um número exposto.
- Perfis "não reivindicados" (carga inicial) guardam só nome, categoria e
  cidade — nunca um contato direto que a pessoa não deu permissão de usar
  no PrestadorAki. Isso não é só cautela de produto: usar um dado de
  contato de alguém pra criar um perfil comercial em outro serviço sem
  consentimento esbarra na LGPD, mesmo quando a fonte original era
  pública (ex.: um catálogo do Google Maps). Fica valendo pra quando essa
  carga inicial for feita de verdade — os próprios dados de nome/
  categoria/cidade já dão pra alimentar a busca sem esse risco.
- Se o cliente quiser convidar um profissional "não reivindicado" por
  fora do app, é ele quem escolhe compartilhar — o app monta um texto
  pronto (`RequestQuoteFormScreen`) que a pessoa copia e manda por
  WhatsApp/SMS/o que preferir, mas nunca guarda nem descobre esse contato
  sozinho.

### Quem precisa de conta — mudança de ideia

Depois de rever com o Franck, o cadastro deixou de ser a porta de entrada
do lado do cliente: **buscar e ver o perfil público de um prestador nunca
exige conta** — é a primeira coisa que qualquer pessoa vê ao abrir o app
(`/buscar` virou a home padrão de quem não está logado). Só ações que
realmente precisam saber quem é a pessoa pedem login/cadastro, e pedem
**na hora**, sem tirar ninguém da tela onde estava: favoritar um
prestador, solicitar orçamento, ou abrir as abas "Favoritos"/"Minhas
solicitações" (que mostram um convite pra criar conta no lugar do
conteúdo, em vez de sumir ou travar a navegação). Isso é o
`ensureClientAccount` (`lib/features/marketplace/client_auth_gate.dart`)
— um modal simples de entrar/criar conta que aparece só quando necessário
e devolve `true`/`false` pra ação continuar ou não.

O lado do prestador **não mudou**: continua exigindo conta desde o
início, porque aparecer no diretório e responder pedidos já pressupõe uma
identidade real por trás. A porta de entrada dele agora é um link "Sou
prestador" na busca (`ClientHomeScreen`), que leva pra `/welcome` — a
mesma tela de sempre, só que agora é exclusiva desse fluxo (tem um link
"Só quero buscar um prestador" pra quem chegou lá por engano).

**O que já está implementado** (mobile, `lib/features/marketplace/`):

- Busca por categoria/cidade (`ClientHomeScreen`) e perfil público do
  prestador (`ProviderPublicProfileScreen`) são a home do app pra quem
  não tem conta — nenhuma das duas pede login.
- Favoritar, solicitar orçamento (`RequestQuoteFormScreen`, com o fluxo de
  convite pra não reivindicados) e ver o histórico
  (`MyFavoritesScreen`/`MyRequestsScreen`) pedem conta na hora, via
  `client_auth_gate.dart` — nunca antes disso.
- Cadastro (`RegisterScreen`) é sempre de cliente — virar prestador
  acontece depois, em "Meu perfil", passando pela assinatura mensal (ver
  seção "Assinatura mensal do prestador" mais abaixo).
- ~~Lado prestador: aba "Pedidos" (`IncomingRequestsScreen`) — recebe os
  pedidos do marketplace e responde com um valor + mensagem simples~~ —
  removido (ver "Atualização (pedido vira orçamento direto)" abaixo): o
  pedido do cliente já nasce como um orçamento no módulo formal de
  Orçamentos, não existe mais uma aba/tela separada pra isso.
- `firestore.rules` e `firestore.indexes.json` atualizados com as novas
  coleções (`clients`, `providerDirectory`, `budgets` acessível também
  pelo cliente que pediu) — `providerDirectory` tem **leitura pública**
  (`allow read: if true`), de propósito, pra busca funcionar sem sessão
  nenhuma. Depois de puxar essas mudanças, rode de novo, na raiz do
  projeto:
  ```
  firebase deploy --only firestore:rules,firestore:indexes,functions
  ```

**Atualização (pedido vira orçamento direto)**: mudança combinada com o
Franck em 2026-09 — não existe mais um "Pedido" como etapa separada do
Orçamento. Quando o cliente pede um orçamento pelo marketplace, ele já
nasce como um orçamento `pendente` (mesmo módulo formal de Orçamentos, só
que com um `status` — ver `Budget`/`BudgetStatus` e a seção "Marketplace"
do `DATA_MODEL.md`), o cliente é cadastrado automaticamente como Customer
do prestador (cadastro manual continua existindo, pra cliente fora do
app), e o fluxo tramita `pendente → enviado → aprovado → aceito`/
`recusado` entre prestador e cliente. No aceite final o prestador escolhe
a data/hora do serviço e o compromisso já nasce sozinho na Agenda, com
checagem de conflito de horário. A antiga coleção `serviceRequests` e a
aba "Pedidos" foram removidas.

**Atualização (conta unificada)**: a lacuna que existia aqui (conta só
podia ser OU cliente OU prestador) foi resolvida — toda conta autenticada
tem uma identidade base de cliente e PODE, além disso, ter a capacidade
de prestador (`AuthController.isProvider`, ver `DATA_MODEL.md`). Quem já
tem conta e quer virar prestador faz isso em "Meu perfil" → "Também
quero oferecer serviços" — sem precisar de uma segunda conta. Ver a
seção "Assinatura mensal do prestador" mais abaixo pra como isso
funciona hoje (gate por assinatura, não mais de graça).

**O que ainda falta** (próximos passos naturais, não escondidos):

- ~~Tela de "editar perfil público" pro prestador (hoje só é criado uma
  vez no cadastro)~~ — já existe (`UserProfileScreen`/`EditProfileScreen`,
  aba "Perfil" nos dois lados do app), incluindo editar nome/categoria/
  cidade/UF, ativar biometria e sair da conta.
- ~~Aceitar um orçamento do marketplace não fecha o laço sozinho ainda
  (não cria job nem cadastra o cliente automaticamente pro prestador)~~ —
  já fecha: o aceite final do prestador cria o compromisso na agenda
  sozinho (com checagem de conflito de horário) e o cliente é cadastrado
  automaticamente (ver "Atualização (pedido vira orçamento direto)"
  acima).
- ~~A curadoria/carga inicial de prestadores por região não foi feita~~ —
  já existe um script pra isso (`scripts/seed_provider_directory.js`, ver
  `scripts/README.md`). A curadoria em si — decidir quais prestadores
  entram e conseguir o consentimento deles — continua sendo trabalho
  manual de vocês, o script só faz a parte de escrever no Firestore.
- ~~Nota média (`ratingAverage`) ainda não existe~~ — já existe avaliação
  por estrelas (1 a 5, só quem teve um pedido aceito com o prestador pode
  avaliar — ver `ProviderDirectoryRepository.rate` e a subcoleção
  `ratings` no `DATA_MODEL.md`). Busca por proximidade real
  (geolocalização de verdade, não só preencher a cidade pelo GPS) ainda
  não existe — a busca continua sendo por igualdade exata de
  categoria/cidade.
- O link de convite pro profissional "não reivindicado" ainda é um
  placeholder (`[link do app aqui]`) — só vira um link de verdade quando
  o app for publicado numa loja ou tiver uma página própria pra apontar.

## Assinatura mensal do prestador (Google Play Billing + RTDN)

Decisão combinada com o Franck: nada de cobrar Pix/cartão na mão nem
tirar prestador da busca manualmente todo mês ("pra mim ficar cuidando
disso não fica bom"). "Virar prestador" agora é sempre uma assinatura
mensal comprada dentro do próprio app, pela Google Play — o mesmo desenho
já usado no app Resenha pra "criar uma resenha" (`in_app_purchase`), só
que aqui com um reforço a mais: a Play Store avisa a própria Cloud
Function automaticamente quando alguém para de pagar (RTDN), então o
prestador some da busca sozinho, sem ninguém precisar olhar nada.

**O que já está implementado** (código escrito e verificado nesta
sessão — `npm run build` das Functions limpo, zero erros de TypeScript;
o lado Flutter não pôde ser compilado aqui pela mesma restrição de rede
que já impede instalar o Flutter SDK neste sandbox, ver nota mais acima):

- `functions/src/subscription.ts` — `confirmarAssinaturaPrestador`
  (callable, chamada pelo app assim que uma compra/restauração é
  concluída) e `processarNotificacaoPlay` (Pub/Sub, disparada sozinha
  pela Play Store a cada mudança de estado da assinatura). As duas SEMPRE
  reconsultam o estado real na Google Play Developer API antes de agir —
  nunca confiam só no que o app ou a notificação dizem.
- `lib/core/subscription_service.dart` — ponte com o `in_app_purchase`.
- `lib/features/profile/provider_paywall_screen.dart` — tela de venda da
  assinatura, aberta a partir de "Meu perfil" → "Também quero oferecer
  serviços" (`UserProfileScreen`/`_BecomeProviderSheet`), depois de
  escolher categoria/cidade/UF.
- `lib/features/marketplace/provider_directory_repository.dart` — busca e
  lista de cidades agora ignoram entradas com `visible == false`
  (assinatura inativa) — ver `DATA_MODEL.md`.
- `lib/features/auth/register_screen.dart` — voltou a ser só cadastro de
  cliente (a compra do Play Billing não dá pra encaixar no meio da
  criação da conta).

**O que só você consegue fazer** (acesso ao Play Console/GCP, que eu não
tenho aqui):

1. **Cadastrar o produto da assinatura** — Play Console → seu app →
   Monetizar → Assinaturas → criar uma assinatura com o ID EXATO
   `prestadoraki_assinatura_mensal` (esse valor já está fixado no código,
   em `SubscriptionService.assinaturaMensalId` e
   `subscription.ts:SUBSCRIPTION_PRODUCT_ID` — se usar outro ID lá, tem
   que trocar aqui também), período mensal, e o preço que você quiser
   cobrar.
2. **Criar a service account que a Cloud Function vai usar pra falar com
   a Play Developer API**:
   - Google Cloud Console → seu projeto Firebase (mesmo projeto do
     PrestadorAki) → IAM e administrador → Contas de serviço → Criar
     conta de serviço (ex.: `prestadoraki-play-billing`). Não precisa dar
     nenhum papel do IAM na hora de criar — a permissão de verdade vem do
     passo seguinte, dentro do Play Console.
   - Nessa conta de serviço recém-criada → aba "Chaves" → Adicionar
     chave → Criar nova chave → JSON. Isso baixa um arquivo `.json` —
     guarde ele, é a chave que vai pro Secret Manager no passo 4.
   - Play Console → Configurações da conta → Usuários e permissões →
     Convidar novos usuários → cole o e-mail da service account (o mesmo
     formato de sempre, tipo
     `prestadoraki-play-billing@SEU-PROJETO.iam.gserviceaccount.com`).
   - Nas permissões dessa convite, marque pelo menos: **"Ver dados
     financeiros, pedidos e histórico de cancelamento"** e **"Gerenciar
     pedidos e assinaturas"**. Sem essas duas, a Cloud Function recebe erro
     de permissão da Play Developer API.
3. **Ativar as Real-time Developer Notifications (RTDN)** — é o que faz o
   corte/reativação automáticos funcionarem, sem isso a assinatura só
   seria checada quando o app abrisse de novo:
   - Google Cloud Console (mesmo projeto) → Pub/Sub → Tópicos → Criar
     tópico → nome EXATO `play-subscriptions` (já fixado em
     `subscription.ts:RTDN_TOPIC` — trocar os dois juntos se usar outro
     nome).
   - Nesse tópico → Permissões → Adicionar principal → cole
     `google-play-developer-notifications@system.gserviceaccount.com`
     com o papel **Pub/Sub Publisher** (é a conta de serviço da própria
     Google que publica as notificações — não é a sua service account do
     passo 2).
   - Play Console → seu app → Monetizar → Configuração de monetização →
     "Notificações em tempo real do desenvolvedor" → cole o nome completo
     do tópico (algo como
     `projects/SEU-PROJETO/topics/play-subscriptions`) → Salvar.
4. **Guardar a chave da service account no Secret Manager do Firebase**
   (na sua máquina, dentro da pasta do projeto):
   ```
   firebase functions:secrets:set PLAY_SERVICE_ACCOUNT_KEY < caminho\para\a\chave.json
   ```
   Isso pede confirmação e já deixa disponível pro próximo deploy — não
   precisa (nem deve) colar o conteúdo da chave em nenhum arquivo do
   repositório.
5. **Instalar a dependência nova e implantar** (na raiz do projeto):
   ```
   cd functions && npm install && cd ..
   firebase deploy --only functions:confirmarAssinaturaPrestador,functions:processarNotificacaoPlay
   ```
6. **No app Flutter**: `flutter pub get` (pra baixar `in_app_purchase` e
   `cloud_functions`, adicionados no `pubspec.yaml`), depois gerar um
   build assinado e subir num "faixa de teste interno" da Play Store —
   compra de assinatura só funciona em app publicado numa faixa de teste
   ou produção, nunca rodando direto do `flutter run` num aparelho sem
   passar pela loja.

Qualquer erro de permissão nesses passos (o mais comum costuma ser
esquecer de convidar a service account com as duas permissões certas no
passo 2, ou errar o nome do tópico no passo 3), me manda a mensagem exata
que eu ajudo a diagnosticar.

## Descrição do prestador com IA (Gemini)

Na tela "Editar perfil", o prestador pode gerar ou melhorar, com IA, a
descrição curta que aparece no perfil público (ver
`functions/src/bio.ts:gerarDescricaoPrestador`). Usa a Gemini Developer
API (pacote `@google/genai`), com a chave guardada no Secret Manager —
mesmo esquema da chave da service account do Google Play acima.

1. **Gerar uma chave de API** em https://aistudio.google.com/apikey
   (Google AI Studio — pode ser vinculada ao mesmo projeto Firebase, não
   precisa de outra conta nem cartão de crédito pra começar; a Gemini
   Developer API tem uma cota gratuita).
2. **Guardar no Secret Manager** (na sua máquina, dentro da pasta do
   projeto):
   ```
   firebase functions:secrets:set GEMINI_API_KEY
   ```
   Cola a chave quando pedir (sem colar em nenhum arquivo do
   repositório).
3. **Instalar a dependência nova e implantar**:
   ```
   cd functions && npm install && cd ..
   firebase deploy --only functions:gerarDescricaoPrestador
   ```

Sem essa chave configurada, os botões "Gerar com IA"/"Melhorar com IA"
aparecem normalmente no app, mas dão erro ao tocar — o campo de texto
continua funcionando manualmente (escrever/editar na mão) mesmo sem a IA.
