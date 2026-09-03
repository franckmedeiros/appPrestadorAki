# Runbook — Assinatura mensal do prestador (Apple/App Store Server API)

Irmão de `RUNBOOK_ASSINATURA.md` (que já existia pro lado Google/Play) —
este é o passo a passo real pro lado Apple/iOS, na ordem em que precisa
ser feito. É citado nos comentários de `functions/src/subscriptionApple.ts`
e `lib/core/subscription_service.dart`. Sem esses passos (todos fora do
código, no App Store Connect), a compra nunca confirma: o app chama
`confirmarAssinaturaPrestadorApple`, que tenta consultar a App Store
Server API e falha porque a chave ainda não existe/não tem permissão, ou
porque o produto ainda não existe.

Nada disso precisa ser refeito depois — é configuração de uma vez só por
projeto (App Store Connect > seu app).

## 1. Criar o produto de assinatura no App Store Connect

1. App Store Connect → seu app → **Recursos do app → Compras no app e
   assinaturas → Assinaturas**.
2. Criar um grupo de assinaturas (se ainda não existir um) e, dentro dele,
   uma assinatura com o Product ID **exatamente** `prestadoraki_assinatura_mensal`
   (tem que bater com `APPLE_SUBSCRIPTION_PRODUCT_ID` em
   `functions/src/subscriptionApple.ts` e
   `SubscriptionService.assinaturaMensalId` no app — é o MESMO texto já
   usado do lado Google; cada loja tem seu próprio catálogo de produtos,
   então não há conflito em reaproveitar o mesmo ID).
3. Definir nome, descrição, duração (mensal) e preço, e submeter pra
   revisão junto com uma versão do app (a Apple exige isso pra aprovar a
   primeira assinatura — não precisa esperar aprovar pra já poder testar
   em Sandbox, só pra vender de verdade).

## 2. Gerar a chave da App Store Server API

1. App Store Connect → **Usuários e acesso → Integrações → Chaves de API
   do App Store Server** (precisa ter o papel de Admin).
2. Criar uma chave nova (ex.: "PrestadorAki - App Store Server API") — a
   Apple mostra o arquivo `.p8` UMA VEZ SÓ pra baixar; se perder, precisa
   gerar outra. **Guardar esse arquivo com cuidado, ele não deve ir pro
   Git.**
3. Anotar, da mesma tela: o **Key ID** (da chave que você acabou de criar)
   e o **Issuer ID** (fica no topo da página, é o mesmo pra todas as
   chaves da conta).

## 3. Guardar a chave no Secret Manager do Firebase

Com o Firebase CLI logado no projeto certo:

```bash
firebase functions:secrets:set APPLE_APP_STORE_CONNECT_KEY
```

Quando pedir o valor, colar um JSON de uma linha só (ou multi-linha, o
comando aceita colar texto multi-linha) no formato:

```json
{"issuerId": "SEU-ISSUER-ID", "keyId": "SEU-KEY-ID", "privateKey": "-----BEGIN PRIVATE KEY-----\nMII...\n-----END PRIVATE KEY-----\n"}
```

O `privateKey` é o CONTEÚDO INTEIRO do arquivo `.p8` baixado no passo 2
(pode colar com quebras de linha de verdade dentro do JSON, ou usar `\n`
— `JSON.parse` aceita os dois, o que importa é que o texto entre
`BEGIN`/`END PRIVATE KEY` venha completo). O nome do secret tem que ser
exatamente `APPLE_APP_STORE_CONNECT_KEY` — é o que
`defineSecret('APPLE_APP_STORE_CONNECT_KEY')` em
`functions/src/subscriptionApple.ts` espera.

## 4. Deploy (primeira vez, pra conseguir a URL da notificação)

```bash
firebase deploy --only functions:confirmarAssinaturaPrestadorApple,functions:processarNotificacaoApple
```

Se o secret do passo 3 ainda não existir, o deploy falha pedindo pra criar
o secret primeiro — é justamente pra evitar functions "meio
configuradas" no ar. Depois do deploy, `firebase functions:list` (ou o
próprio console do Firebase) mostra a URL HTTPS de `processarNotificacaoApple`
— é dela que voce precisa no próximo passo.

## 5. Configurar a App Store Server Notifications V2

1. App Store Connect → seu app → **Informações do app → App Store Server
   Notifications** (ou dentro de Recursos do app, conforme a versão da
   interface).
2. Colar a URL HTTPS de `processarNotificacaoApple` (do passo 4) em
   **Production Server URL** — e, se for testar em Sandbox antes de
   publicar de verdade, na mesma URL em **Sandbox Server URL** também
   (podem ser a mesma URL; a própria notificação já vem marcada com o
   ambiente de origem).
3. Versão V2 é a única que essa função entende — confirme que a versão
   selecionada no App Store Connect é a V2 (a Apple vem descontinuando a
   V1 há um tempo, mas vale conferir).
4. A própria tela tem uma opção de mandar uma notificação de teste — vale
   usar (ou chamar `requestTestNotification` da biblioteca depois, se
   precisar de novo) e conferir no `firebase functions:log` que
   `processarNotificacaoApple` recebeu algo.

## 6. Deploy completo

```bash
firebase deploy --only functions
```

(ou só as duas functions do passo 4, se preferir deploys menores).

## 7. Preparar um jeito de comprar de teste (Sandbox)

Compra de assinatura de verdade pela App Store **não funciona** com
`flutter run` puro sem estar logado com uma conta certa. Dois jeitos:

- **Testador do Sandbox** (mais simples pra começar): App Store Connect →
  **Testar → Sandbox → Testadores**, criar uma conta de teste (e-mail
  fictício, não precisa ser real de verdade — só não pode já ter sido
  usado numa conta Apple de verdade). No **aparelho de teste**: Ajustes →
  App Store → rolar até **CONTA SANDBOX** (embaixo, separado da conta
  Apple normal do aparelho) → logar com essa conta de teste. Assim o app
  instalado via Xcode/TestFlight já compra em modo sandbox, sem cobrar
  cartão de verdade.
- Subir um build via **TestFlight** (App Store Connect → **TestFlight** →
  criar um grupo interno/externo, adicionar o e-mail testador) — mesma
  ideia do "Teste interno" do Play Console, mas a compra em si ainda
  passa pela conta Sandbox configurada no aparelho, não pelo TestFlight
  em si.

## 8. Roteiro do teste de verdade

Com tudo acima pronto:

1. Abrir o app (aparelho logado com a conta Sandbox), ir em "Virar
   prestador", preencher categoria/cidade e chegar na tela de assinatura
   (`ProviderPaywallScreen`).
2. Tocar **Assinar** → completar a compra (Face ID/senha da conta
   Sandbox, sem cobrança de verdade).
3. Esperado: `onAtivada` dispara, `AuthController.refreshProviderStatus()`
   roda, a tela fecha sozinha (`Navigator.pop(true)`), e a conta passa a
   ver a área de prestador — mesmo comportamento do lado Google.
4. Conferir no Firestore Console: `providers/{uid}.listingStatus` deve
   virar `active`, com `subscriptionStore: 'apple'`, `subscriptionState`
   e `subscriptionExpiresAt` preenchidos; `providerDirectory/{uid}` deve
   existir com `visible: true`.
5. Conferir `firebase functions:log` (função
   `confirmarAssinaturaPrestadorApple`) sem erros.
6. Testar **cancelamento**: no aparelho de teste, Ajustes → conta
   Sandbox → Assinaturas → cancelar. Assinaturas de Sandbox renovam MUITO
   mais rápido que o mundo real (minutos, não um mês) — dá pra ver o
   ciclo de renovação/expiração se repetir sozinho sem esperar 30 dias de
   verdade. Depois de expirar, conferir se a notificação chegou
   (`processarNotificacaoApple` no log) e se `listingStatus` voltou pra
   `pending` e `providerDirectory/{uid}.visible` virou `false`.
7. Testar **restaurar compra**: em outro aparelho/reinstalação, logar com
   a mesma conta Sandbox e tocar "Já assinei, restaurar compra" na tela
   de assinatura — deve reconfirmar sem cobrar de novo.

## Onde olhar quando algo não bate

- `firebase functions:log --only confirmarAssinaturaPrestadorApple,processarNotificacaoApple`
  — toda consulta à App Store Server API e todo erro passam por aqui
  (`logger.error`/`logger.warn` em `functions/src/subscriptionApple.ts`).
- Firestore `assinaturasVerificadas/{apple:transactionId}` — criado na
  primeira confirmação (prefixo `apple:` só pra nunca colidir com um
  purchaseToken do Google), guarda o `uid` dono da transação e o último
  `subscriptionState` visto; se a notificação chega com uma transação que
  não está aqui ainda, ela é ignorada de propósito (mesma "lacuna
  consciente" do lado Google) até a primeira confirmação acontecer.
- Erro `failed-precondition` no app ("Sua assinatura ainda não está
  ativa...") logo depois de pagar geralmente é só a App Store levando
  alguns segundos pra propagar o estado — o botão "restaurar compra"
  resolve.
- Nota honesta sobre segurança (ver comentário completo no topo de
  `subscriptionApple.ts`): este runbook NÃO inclui baixar os
  certificados-raiz da Apple pra verificar a assinatura criptográfica dos
  JWS recebidos — o código confia na resposta autenticada da própria App
  Store Server API como fonte de verdade (mesmo modelo já usado do lado
  Google), e usa o conteúdo do JWS recebido só pra saber QUAL transação
  perguntar pra Apple. Isso é seguro pelo motivo explicado lá, mas se um
  dia quiser fechar essa lacuna por completo, os certificados ficam em
  https://www.apple.com/certificateauthority/.
