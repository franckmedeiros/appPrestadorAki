# Runbook — Assinatura mensal do prestador (Google Play Billing)

Este arquivo é citado em vários comentários de `functions/src/subscription.ts`
e `lib/core/subscription_service.dart`, mas nunca tinha sido escrito de
verdade — este é o passo a passo real, na ordem em que precisa ser feito.
Sem esses passos (todos fora do código, no Play Console/Google Cloud), a
compra nunca confirma: o app chama `confirmarAssinaturaPrestador`, que
tenta consultar a Play Developer API e falha porque a service account
ainda não existe/não tem permissão, ou porque o produto ainda não existe.

Nada disso precisa ser refeito depois — é configuração de uma vez só por
projeto.

## 1. Criar o produto de assinatura no Play Console

1. Play Console → seu app → **Monetizar → Produtos → Assinaturas**.
2. Criar uma assinatura com o ID **exatamente** `prestadoraki_assinatura_mensal`
   (tem que bater com `SUBSCRIPTION_PRODUCT_ID` em `functions/src/subscription.ts`
   e `SubscriptionService.assinaturaMensalId` no app — mudar um sem mudar o
   outro quebra tudo).
3. Definir nome, descrição, preço (base plan mensal) e ativar.
4. Um produto recém-criado pode levar algumas horas pra ficar
   "comprável" de verdade — não é bug se o app não achar o produto logo
   depois de criar.

## 2. Criar a service account e dar permissão no Play Console

1. Google Cloud Console → **IAM e administrador → Contas de serviço**, no
   MESMO projeto do Firebase deste app.
2. Criar uma conta de serviço nova (ex.: `play-billing-verifier`), sem
   precisar dar nenhum papel de IAM no Cloud (a permissão que importa é a
   do Play Console, no próximo passo).
3. Gerar uma chave JSON pra essa conta de serviço e baixar o arquivo —
   **guardar esse arquivo com cuidado, ele não deve ir pro Git**.
4. Play Console → **Usuários e permissões → Convidar novos usuários**,
   convidar o e-mail da service account (algo como
   `play-billing-verifier@SEU-PROJETO.iam.gserviceaccount.com`) com:
   - **Ver dados financeiros, pedidos e cancelamentos**
   - **Gerenciar pedidos e assinaturas**

## 3. Guardar a chave no Secret Manager do Firebase

Com o Firebase CLI logado no projeto certo:

```bash
firebase functions:secrets:set PLAY_SERVICE_ACCOUNT_KEY
```

Quando pedir o valor, colar o CONTEÚDO INTEIRO do arquivo JSON baixado no
passo 2 (o comando aceita colar texto multi-linha). O nome do secret tem
que ser exatamente `PLAY_SERVICE_ACCOUNT_KEY` — é o que
`defineSecret('PLAY_SERVICE_ACCOUNT_KEY')` em `functions/src/subscription.ts`
espera.

## 4. Configurar a notificação em tempo real (RTDN)

1. Play Console → seu app → **Monetizar → Configuração de monetização →
   Notificações em tempo real do desenvolvedor**.
2. Nome do tópico Pub/Sub: **`play-subscriptions`** (tem que bater com
   `RTDN_TOPIC` em `functions/src/subscription.ts`).
3. Esse tópico precisa existir no Pub/Sub do projeto ANTES de configurar
   aqui — o primeiro `firebase deploy --only functions` depois de existir
   o export `processarNotificacaoPlay` já cria o tópico sozinho (gatilho
   `onMessagePublished`); se der erro de "tópico não encontrado" ao
   configurar no Play Console, faça o deploy das functions primeiro e
   tente de novo.
4. Depois de configurar, o Play Console dá a opção de mandar uma
   notificação de teste — vale mandar uma e conferir no
   `firebase functions:log` que `processarNotificacaoPlay` recebeu algo
   (mesmo que ignore por não ter `subscriptionNotification` — só confirma
   que o cano está ligado).

## 5. Deploy

```bash
firebase deploy --only functions:confirmarAssinaturaPrestador,functions:processarNotificacaoPlay
```

(ou o deploy completo de functions). Se o secret do passo 3 ainda não
existir, o deploy falha pedindo pra criar o secret primeiro — é
justamente pra evitar functions "meio configuradas" no ar.

## 6. Preparar um jeito de comprar de teste

Compra de assinatura de verdade pelo Google Play **não funciona** com um
APK instalado direto (sideload) nem com `flutter run` num build debug — o
Play Billing só "vê" a compra quando o app foi baixado através da própria
Play Store. Dois jeitos de testar sem cobrar cartão de verdade:

- **Testadores de licença** (mais simples pra começar): Play Console →
  **Configuração → Testes de licença**, adicionar o e-mail Google da
  conta que vai testar. Contas de teste de licença podem "comprar" e a
  cobrança não é feita de verdade (ou é reembolsada automaticamente,
  dependendo do tipo de teste), mas o fluxo de confirmação roda igual ao
  de produção.
- Subir um build assinado (`flutter build appbundle`) numa faixa de teste
  (**Teste interno** é a mais rápida de configurar) em Play Console →
  **Testar e lançar → Testes → Teste interno**, adicionar o e-mail
  testador na lista de testadores dessa faixa, aceitar o link de opt-in
  que o Play Console gera, e instalar o app a partir do link da Play
  Store (não do APK solto).

## 7. Roteiro do teste de verdade

Com tudo acima pronto:

1. Abrir o app (instalado via Play Store, testador logado), ir em
   "Virar prestador", preencher categoria/cidade e chegar na tela de
   assinatura (`ProviderPaywallScreen`).
2. Tocar **Assinar** → completar a compra de teste.
3. Esperado: `onAtivada` dispara, `AuthController.refreshProviderStatus()`
   roda, a tela fecha sozinha (`Navigator.pop(true)`), e a conta passa a
   ver a área de prestador.
4. Conferir no Firestore Console: `providers/{uid}.listingStatus` deve
   virar `active`, com `subscriptionState` e `subscriptionExpiresAt`
   preenchidos; `providerDirectory/{uid}` deve existir com `visible: true`.
5. Conferir `firebase functions:log` (função `confirmarAssinaturaPrestador`)
   sem erros.
6. Testar **cancelamento**: cancelar a assinatura de teste no próprio
   Play Store (Assinaturas da conta Google) e, depois de alguns minutos,
   conferir se a RTDN chegou (`processarNotificacaoPlay` no log) e se
   `listingStatus` voltou pra `pending` e `providerDirectory/{uid}.visible`
   virou `false` — sem precisar abrir o app de novo (é o ponto principal
   de ter a RTDN, não só a confirmação na hora da compra).
7. Testar **restaurar compra**: em outro aparelho/reinstalação, logar com
   a mesma conta e tocar "Já assinei, restaurar compra" na tela de
   assinatura — deve reconfirmar sem cobrar de novo.

## Onde olhar quando algo não bate

- `firebase functions:log --only confirmarAssinaturaPrestador,processarNotificacaoPlay`
  — toda consulta à Play Developer API e todo erro passam por aqui
  (`logger.error`/`logger.warn` em `functions/src/subscription.ts`).
- Firestore `assinaturasVerificadas/{purchaseToken}` — criado na primeira
  confirmação, guarda o `uid` dono do token e o último `subscriptionState`
  visto; se a RTDN chega com um token que não está aqui ainda, ela é
  ignorada de propósito (comentário "Lacuna consciente" no código) até a
  primeira confirmação acontecer.
- Erro `failed-precondition` no app ("Sua assinatura ainda não está
  ativa...") logo depois de pagar geralmente é só a Play Store levando
  alguns segundos pra propagar o estado — o botão "restaurar compra"
  resolve.
