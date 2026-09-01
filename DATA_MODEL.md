# PrestadorAki — Modelo de dados no Firestore

Substitui `database/schema.sql` (Postgres) depois da migração pra Firebase.
Convenção: nomes de campo em camelCase (igual ao contrato de API que já
existia), datas como `Timestamp` do Firestore exceto onde o valor precisa
ser comparável como string (ex.: `scheduledDate`).

## Por que subcoleções de `/providers/{uid}` em vez de coleções no topo

Isolamento multi-tenant (cada prestador só vê os próprios dados) fica
trivial de garantir via `firestore.rules` quando o caminho já carrega o
dono: `/providers/{uid}/customers/{id}` só precisa checar
`request.auth.uid == uid`. Numa coleção no topo (`/customers/{id}` com um
campo `providerId`), a regra teria que ler o próprio documento pra decidir
se libera o acesso — funciona, mas é mais fácil de errar.

## `providers/{uid}`

`{uid}` é o UID do Firebase Auth do dono da conta — 1 prestador = 1 conta
(o mesmo desenho de MVP que já existia; suporte a múltiplos usuários por
prestador, "staff", fica pra uma próxima etapa, viraria uma subcoleção
`providers/{uid}/staff/{staffUid}`).

```
name                string   — nome do responsável (dono da conta)
email               string
companyName         string?
tradeName           string?
cpfCnpj             string?
whatsapp            string?  — opcional, editável em "Meu perfil"
contactEmail        string?
addressZipCode      string?  — opcional, editável em "Meu perfil"
addressStreet       string?  — opcional, editável em "Meu perfil" (rua e número)
addressNeighborhood string?  — opcional, editável em "Meu perfil"
addressCity         string?  — opcional, editável em "Meu perfil"
addressState        string?  — opcional, editável em "Meu perfil"
category            string?  — área de atuação (ServiceCategory.wireValue) — ver abaixo
city                string?  — cidade de atuação (diferente de addressCity: endereço pessoal)
state               string?  — UF de atuação
listingStatus       string?  — 'pending' | 'active' (ver nota abaixo); ausente = ativo (contas antigas)
subscriptionState      string?  — último estado bruto devolvido pela Play Developer API
                                   (ex.: SUBSCRIPTION_STATE_ACTIVE) — só informativo/debug
subscriptionExpiresAt  Timestamp? — quando a assinatura atual vence, segundo a Play Store
logoUrl             string?
description         string?
nextBudgetNumber    number   — incrementado pela Cloud Function createBudget
createdAt           Timestamp
updatedAt           Timestamp
```

Criado pela Cloud Function `confirmarAssinaturaPrestador` (ver
`functions/src/subscription.ts` e a seção "Gate de pagamento" abaixo) na
primeira vez que a assinatura mensal do prestador é confirmada — nunca
mais é o próprio app/cliente quem grava este documento diretamente (só o
Admin SDK, que ignora o `firestore.rules`). `AuthController.becomeProvider`
ainda existe no código, mas não é mais chamado por nenhuma tela — a UI
sempre passa pela `ProviderPaywallScreen` primeiro.

**Conta unificada** (decisão combinada com o Franck): ter um documento
aqui NUNCA significa que a conta deixou de ser cliente — toda conta
autenticada também tem (ou ganha, na primeira ação de cliente) um
`clients/{uid}` (ver abaixo). As duas coisas coexistem sempre.

**Gate de pagamento — assinatura mensal via Google Play Billing**
(decisão combinada com o Franck, substituindo um plano anterior de
ativação manual): "virar prestador" só acontece de verdade depois de uma
assinatura mensal confirmada — nunca há cobrança avulsa via Pix/cartão
nem corte manual por falta de pagamento. O app usa `in_app_purchase`
(Google Play Billing) pra comprar/restaurar a assinatura
(`lib/core/subscription_service.dart`,
`lib/features/profile/provider_paywall_screen.dart`), e quem confirma de
verdade (batendo o token de compra contra a Google Play Developer API,
nunca confiando no que o app diz sozinho) é a Cloud Function
`confirmarAssinaturaPrestador` (`functions/src/subscription.ts`) — é ela
quem cria `providers/{uid}` na primeira vez e liga `listingStatus` pra
`'active'`, além de criar/atualizar `providerDirectory/{uid}` com
`visible: true` (ver seção `providerDirectory` abaixo).

**Revogação automática, sem intervenção manual** (decisão combinada com o
Franck: "pra mim ficar cuidando disso não fica bom" → RTDN): a Play Store
avisa a própria Cloud Function (`processarNotificacaoPlay`, via Pub/Sub —
Real-time Developer Notifications) toda vez que o estado de uma
assinatura muda — renovou, atrasou o pagamento, cancelou, expirou. Cada
notificação faz a função reconsultar o estado real na Developer API (a
notificação em si só avisa "algo mudou", nunca diz qual é o estado atual)
e aplicar o resultado: assinatura fora dos estados ativos
(`SUBSCRIPTION_STATE_ACTIVE`/`SUBSCRIPTION_STATE_IN_GRACE_PERIOD`) →
`listingStatus` volta pra `'pending'` e `providerDirectory/{uid}.visible`
vira `false` — o prestador some da busca sozinho, sem o Franck precisar
olhar nada. Se a pessoa assinar de novo depois, tudo volta ao normal
automaticamente, com a mesma reputação (`ratingAverage`/`ratingCount`) de
antes — ver a nota sobre isso na seção `providerDirectory`.

Contas de prestador criadas ANTES dessa mudança (ativação manual, direto
no Firebase Console) não têm os campos `subscriptionState`/
`subscriptionExpiresAt` — `listingStatus` continua valendo do jeito que
foi deixado manualmente até a primeira vez que essa conta passar por
`confirmarAssinaturaPrestador`/`processarNotificacaoPlay`. A ausência
completa do campo `listingStatus` continua tratada como "ativo" (contas
bem antigas, de antes de qualquer gate de pagamento existir).

## `providers/{uid}/customers/{customerId}`

Mesmos campos do `CreateCustomerDto` que já existia: `name`, `cpfCnpj`,
`phone`, `whatsapp`, `email`, `addressStreet`, `addressNumber`,
`addressDistrict`, `addressCity`, `addressState`, `addressZip`,
`observations`, `createdAt`, `updatedAt`. CRUD direto do app (sem Cloud
Function — não tem regra de negócio especial aqui).

## `providers/{uid}/technicalVisits/{visitId}`

```
customerId, customerName   — customerName denormalizado (Firestore não faz
                              join; evita 1 leitura extra só pra mostrar o
                              nome na lista)
addressText
scheduledDate    string "YYYY-MM-DD"
scheduledTime    string "HH:mm"
visitType        enum (visita_tecnica | servico | retorno | reuniao | pagamento | outro)
description, observations
status           enum (agendada | confirmada | prestador_a_caminho |
                       prestador_chegou | em_atendimento | concluida | cancelada)
createdAt, updatedAt
```

CRUD + transições de status (`start-trip`/`arrived`/`complete`) direto do
app via `runTransaction` (atualiza o status da visita e cria/fecha um doc
em `locationSessions` atomicamente) — não precisa de Cloud Function porque
não envolve numeração nem outro documento fora do controle do prestador.

## `providers/{uid}/appointments/{appointmentId}`

Espelha o antigo endpoint `/appointments`: `customerId?`, `customerName?`,
`type`, `scheduledAt` (Timestamp), `durationMinutes`, `addressText?`,
`observations?`, `status`, `relatedVisitId?`, `createdAt`. CRUD direto do
app.

## `providers/{uid}/locationSessions/{sessionId}`

```
ownerType   'technical_visit' | 'job'
ownerId
status      'active' | 'ended'
startedAt, endedAt
lastUpdatedAt, etaSeconds, distanceMeters
```

Só o ciclo de vida (abrir/fechar) está implementado — a ingestão de pontos
de GPS em si, cálculo de ETA/distância e a página pública de rastreamento
**ainda não existem** (mesma ressalva que já valia na versão Postgres:
é uma etapa maior, separada, de rastreamento em tempo real).

## `providers/{uid}/budgets/{budgetId}`

```
customerId?, customerName
addressText?
date                Timestamp — data do orçamento/serviço
items               array<{ description, quantity, unit, unitPriceCents }>
discountCents, observations?
status?             enum (pendente | enviado | aprovado | aceito | recusado)
clientUid?, providerDirectoryId?, providerName?, category?
requestDescription?, preferredDate?
rejectedBy?         'prestador' | 'cliente'
serviceScheduledAt?, serviceDurationMinutes?, appointmentId?
createdAt, updatedAt
```

CRUD direto do app (`BudgetsRepository`/`BudgetRequestsRepository`), sem
Cloud Function — versão simples implementada em 2026-08. `items` fica
embutido como array no próprio documento (não uma subcoleção): sempre é
lido/escrito junto com o orçamento, e a lista é pequena o bastante pra
nunca chegar perto do limite de 1MB por documento.

Um orçamento criado manualmente pelo prestador (cliente já cadastrado,
fora do marketplace) não tem `status` nenhum — os campos de `status` em
diante só existem pra orçamentos que nasceram de um pedido de cliente
pelo marketplace (pedido do Franck, 2026-09: eliminar o "Pedido" como
etapa separada, o pedido do cliente já nasce direto como orçamento
`pendente`). O fluxo desses:

```
pendente  → cliente pediu (RequestQuoteFormScreen/BudgetRequestsRepository.create,
            escreve na subcoleção do prestador escolhido). Cliente auto-
            cadastrado como Customer (CustomersRepository.findOrCreateForClient).
enviado   → prestador terminou de preencher itens/preço e mandou pro
            cliente (BudgetsRepository.sendToClient).
aprovado  → cliente aprovou (BudgetRequestsRepository.approve) — falta o
            aceite final do prestador.
aceito    → prestador deu o aceite final (BudgetsRepository.acceptFinal):
            SÓ AQUI a data/hora do serviço é definida, com checagem de
            conflito na agenda (AppointmentsRepository.hasConflict,
            bloqueia e pede outro horário) — e o compromisso já nasce
            sozinho em providers/{uid}/appointments.
recusado  → prestador ou cliente recusou (ver `rejectedBy`) — fluxo
            encerrado, pode acontecer a partir de pendente/enviado
            (prestador) ou enviado (cliente).
```

`firestore.rules` autoriza um cliente autenticado a criar (só `pendente`,
só com o próprio uid, sem itens/preço) e atualizar (só de `enviado` pra
`aprovado`/`recusado`, só mexendo em `status`/`rejectedBy`) um documento
na subcoleção de OUTRO prestador — é a mesma coleção, só que escrita por
uma conta diferente da dona. Uma consulta `collectionGroup('budgets')`
filtrando por `clientUid` (usada por `BudgetRequestsRepository.watchMine`,
"Meus orçamentos") junta os pedidos de um cliente em vários prestadores.

**Nota histórica**: existe um desenho bem mais ambicioso em
`functions/src/budgets.ts` — Cloud Functions callable, numeração
sequencial, versionamento (`versions`/`changeRequests` abaixo), aprovação
por link público (`publicBudgetTokens`) e criação automática de um `job`
(`providers/{uid}/jobs/{jobId}`). Esse desenho nunca foi ligado ao app
(nenhuma tela chama essas Functions) — é código morto, mantido só porque
ainda pode servir de referência se um fluxo mais formal (contrato, link
público pra cliente sem conta) virar prioridade de verdade. As
subcoleções abaixo e a coleção `jobs` só existem nesse desenho legado.

### `providers/{uid}/budgets/{budgetId}/versions/{versionId}` (código morto — ver nota acima)

```
versionNumber
snapshot       map   — cópia do orçamento (itens + valores + status) no
                        momento da versão anterior
changeReason?
createdAt
```

### `providers/{uid}/budgets/{budgetId}/changeRequests/{requestId}` (código morto)

`message`, `createdAt`, `resolvedAt?` — só escrito pela Cloud Function
`requestBudgetChange`, que nunca é chamada pelo app.

## `publicBudgetTokens/{token}` (coleção no topo, fora de `/providers`) — código morto

```
providerId
budgetId
```

Ponteiro simples token → (providerId, budgetId), parte do desenho legado
de `functions/src/budgets.ts` (ver nota acima) — nunca acessado pelo app.

## `providers/{uid}/jobs/{jobId}` (código morto — ver nota acima)

```
customerId, customerName
budgetId?, technicalVisitId?, appointmentId?
addressText
scheduledDate string "YYYY-MM-DD", scheduledTime string "HH:mm"
totalCents
status        enum (agendado | confirmado | prestador_a_caminho |
                    prestador_chegou | em_execucao | pausado | concluido | cancelado)
startedAt?, arrivedAt?, completedAt?
notes?
createdAt, updatedAt
```

Só nasceria automaticamente via Cloud Function `approveBudget`/
`publicApproveBudget` — nunca chamadas pelo app; o fluxo de verdade que
lança um compromisso na agenda automaticamente é o `aceito` do `budgets`
acima, que cria um `providers/{uid}/appointments/{appointmentId}`, não um
`job`.

## Marketplace (cliente ↔ prestador) — pivot de produto

A partir daqui o PrestadorAki passa a ter dois lados: o prestador (tudo
acima) e o cliente final, que busca, favorita e solicita orçamento a
prestadores — inclusive os que ainda não têm conta (perfis "não
reivindicados", carregados manualmente pra o app não abrir vazio). Ver
`README.md` pro raciocínio completo por trás dessa mudança (inclusive a
preocupação com LGPD sobre a carga inicial).

### `clients/{uid}`

`{uid}` é o UID do Firebase Auth da conta — mesmo desenho de
`providers/{uid}`, mas com os dados "de cliente". **Conta unificada**
(decisão combinada com o Franck, substitui o desenho anterior de "conta é
OU prestador OU cliente"): TODA conta autenticada tem um documento aqui,
seja ela também prestador ou não — é a identidade base. Um prestador que
também quer favoritar/pedir orçamento como cliente usa o mesmo uid, sem
precisar de uma segunda conta (ver `AuthController.isProvider` e
`ensureClientDocument`).

```
name                 string
email                string
whatsapp             string?  — opcional, editável em "Meu perfil"
addressZipCode       string?  — opcional, editável em "Meu perfil"
addressStreet        string?  — opcional, editável em "Meu perfil" (rua e número)
addressNeighborhood  string?  — opcional, editável em "Meu perfil"
addressCity          string?  — opcional, editável em "Meu perfil"
addressState         string?  — opcional, editável em "Meu perfil"
createdAt, updatedAt Timestamp
```

`whatsapp` e os campos `address*` do lado do cliente existem só pra dar
paridade com "Meu perfil" do prestador (mesma tela, UserProfileScreen/
EditProfileScreen) — nenhum deles aparece em nenhuma busca ou perfil
público, ficam só no documento raiz do próprio dono. O e-mail também é
editável em "Meu perfil", mas não é um campo do Firestore — é o e-mail de
login do Firebase Auth, trocado via `AuthController.updateEmailAddress`
(exige confirmar a senha atual e clicar num link enviado pro e-mail
novo).

Criado direto pelo app, uma única vez: no cadastro (sempre, pra toda
conta nova — ver `AuthController.register`) ou, pra uma conta de
prestador que já existia antes desse documento ser garantido sempre, na
primeira vez que ela tenta uma ação de cliente (favoritar, pedir
orçamento — ver `ClientAuthGate.ensureClientAccount` ->
`AuthController.ensureClientDocument`).

#### `clients/{uid}/favorites/{listingId}`

```
addedAt   Timestamp
```

Só um ponteiro pro id do `providerDirectory` favoritado — não duplica os
dados do prestador, pra não ficar desatualizado se ele mudar nome/cidade.

### `providerDirectory/{listingId}` (coleção no topo, fora de `/providers`)

O catálogo público que alimenta a busca do cliente. Duas origens
possíveis pro mesmo formato de documento:

```
name          string
category      string   — um dos valores de ServiceCategory (eletricista, encanador, ...)
city          string
state         string?
claimed       bool     — true se tem conta de verdade no PrestadorAki
providerUid   string?  — só quando claimed == true
visible       bool?    — false enquanto a assinatura mensal não está ativa (ver
                          `providers/{uid}`); ausente = visível (padrão de sempre,
                          inclusive nas entradas não reivindicadas abaixo)
ratingAverage number?  — média 0-5, agregada a partir da subcoleção ratings
ratingCount   number?  — quantidade de avaliações
createdAt, updatedAt   Timestamp
```

**Perfil reivindicado** (`claimed: true`): o id do documento é sempre
igual ao `providerUid`. Desde o gate de pagamento por assinatura (ver
`providers/{uid}`), este documento é criado/atualizado principalmente
pela Cloud Function `confirmarAssinaturaPrestador`/`processarNotificacaoPlay`
(`functions/src/subscription.ts`), com `visible: true` só enquanto a
assinatura estiver ativa. `ProviderDirectoryRepository.upsertOwnListing`
(chamado pela tela "Editar perfil") continua existindo pra atualizar
nome/categoria/cidade depois — mas nunca mexe em `visible`, então nunca
reativa por engano uma entrada que a Cloud Function marcou como
invisível por falta de pagamento.

**Por que soft-hide (`visible: false`) em vez de apagar o documento**: se
o prestador reativar a assinatura depois de um período sem pagar, ele
recupera exatamente a mesma reputação (`ratingAverage`/`ratingCount`) de
antes — apagar o documento perderia isso (a subcoleção `ratings` em si
não seria apagada em cascata pelo Firestore, ficaria órfã sem o pai).
`ProviderDirectoryRepository.search`/`listCities` filtram
`visible == false` no próprio app (mesma filosofia de ordenar/filtrar no
Dart em vez de criar mais um índice composto, já usada aqui — ver a nota
logo acima sobre a ordenação por nome).

**Leitura pública, de propósito**: buscar e ver um perfil nunca exige
conta (ver `README.md`, "Quem precisa de conta — mudança de ideia") —
por isso `allow read: if true` no `firestore.rules`, sem checar
`request.auth`. Não é um risco, porque este documento nunca guarda nada
além de nome/categoria/cidade — o mesmo dado que já apareceria numa lista
telefônica ou num catálogo do Google Maps.

**Perfil não reivindicado** (`claimed: false`, sem `providerUid`): carga
inicial ou curadoria manual, feita fora do app (Admin SDK/console, nunca
pelo cliente). **Ressalva importante**: por decisão deliberada, essas
entradas não guardam telefone/WhatsApp nem qualquer contato direto do
prestador — só nome, categoria e cidade, que são os dados mínimos pra
aparecer numa busca. Isso evita expor um contato que a pessoa nunca deu
permissão de usar no PrestadorAki (ver a discussão de LGPD no
`mobile/README.md`). O contato de verdade só acontece depois que o
próprio prestador cria a conta — até lá, o cliente pode registrar um
pedido e, se quiser, convidar o profissional por fora do app usando texto
que ele mesmo escolhe compartilhar (`RequestQuoteFormScreen`).

Busca por proximidade real ainda não existe (os filtros são por
igualdade exata de categoria/cidade, não geolocalização).

#### `providerDirectory/{listingId}/ratings/{clientUid}`

```
stars       number   — 1 a 5
comment     string?
createdAt, updatedAt   Timestamp
```

Id do documento é o uid de quem avaliou — um cliente só tem uma avaliação
por prestador (avaliar de novo edita, nunca duplica). Só pode avaliar quem
já teve um pedido com status `aceito` com esse prestador (checado no app,
ver `ServiceRequestsRepository.hasAcceptedRequestWith` — **lacuna
consciente**: não é validado no firestore.rules, ver a ressalva lá).
`ratingAverage`/`ratingCount` no documento pai são recalculados numa
transação a cada avaliação nova ou editada (ver
`ProviderDirectoryRepository.rate`).


### `assinaturasVerificadas/{purchaseToken}` (coleção no topo, fora de `/providers`)

```
uid                string   — dono dessa compra
productId          string   — sempre 'prestadoraki_assinatura_mensal' hoje
subscriptionState  string?  — último estado bruto da Play Developer API
atualizadoEm       Timestamp
```

Só escrito pelas Cloud Functions (`functions/src/subscription.ts`), via
Admin SDK — não existe regra em `firestore.rules` pra isso porque o
cliente nunca lê nem escreve aqui diretamente. Duas finalidades: (1)
antifraude — impede que o mesmo `purchaseToken` seja reaproveitado por
outra conta Firebase (`confirmarAssinaturaPrestador` recusa com
`permission-denied` se o uid não bater); (2) é como
`processarNotificacaoPlay` (a notificação RTDN da Play Store, que só traz
o `purchaseToken`) descobre a qual `uid` aplicar a mudança de estado —
por isso uma notificação que chega ANTES da primeira confirmação de
compra pra aquele token é ignorada (ainda não tem o que fazer com ela; a
própria confirmação, quando chegar, já busca o estado atual na API na
hora). Mesmo padrão do `comprasVerificadas` do app Resenha.

### Não existe mais uma coleção `serviceRequests` separada

Até 2026-09 o primeiro contato do fluxo do marketplace (cliente →
prestador do diretório) vivia numa coleção própria, `serviceRequests`,
que só depois virava um orçamento de verdade quando o prestador
respondia. Pedido do Franck: tirar essa etapa do meio — o pedido do
cliente já nasce direto como um orçamento `pendente` em
`providers/{uid}/budgets` (ver a seção `budgets` acima, que documenta o
fluxo completo `pendente → enviado → aprovado → aceito`/`recusado`).
`serviceRequests` foi apagada (dados de teste incluídos, a pedido do
Franck) e o código que a usava (`ServiceRequest`,
`ServiceRequestsRepository`, `IncomingRequestsScreen`, rota `/pedidos`)
foi removido.
