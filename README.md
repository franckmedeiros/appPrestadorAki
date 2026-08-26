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
  acontece através de "Solicitar orçamento" (`serviceRequests`), nunca de
  um número exposto.
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
- Cadastro de prestador (`RegisterScreen`, chegando por `/welcome`) pede
  categoria e cidade, que já criam a entrada pública no diretório
  (`providerDirectory`).
- Lado prestador: aba "Pedidos" (`IncomingRequestsScreen`) — recebe os
  pedidos do marketplace e responde com um valor + mensagem simples (bem
  mais simples que o módulo formal de Orçamentos, que continua existindo
  separado, para clientes já cadastrados manualmente).
- `firestore.rules` e `firestore.indexes.json` atualizados com as novas
  coleções (`clients`, `providerDirectory`, `serviceRequests`) —
  `providerDirectory` agora tem **leitura pública** (`allow read: if
  true`), de propósito, pra busca funcionar sem sessão nenhuma. Depois de
  puxar essas mudanças, rode de novo, na raiz do projeto:
  ```
  firebase deploy --only firestore:rules,firestore:indexes
  ```

**Lacuna consciente**: uma conta hoje só é OU cliente OU prestador, nunca
as duas ao mesmo tempo (`AuthController._resolveRole`). Se alguém já
logado como cliente tocar em "Sou prestador", a tela de boas-vindas
manda de volta pra busca em vez de oferecer um jeito de virar prestador
com a mesma conta — não é o fim do mundo (a pessoa pode sair e criar uma
segunda conta), mas é uma aresta que ainda não foi resolvida.

**O que ainda falta** (próximos passos naturais, não escondidos):

- Tela de "editar perfil público" pro prestador (hoje só é criado uma vez
  no cadastro).
- Aceitar um orçamento do marketplace não fecha o laço sozinho ainda (não
  cria job nem cadastra o cliente automaticamente pro prestador) — isso
  fica pra quando o fluxo básico estiver validado em uso real.
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
