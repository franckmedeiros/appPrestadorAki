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
whatsapp            string?
contactEmail        string?
addressCity         string?
addressState        string?
logoUrl             string?
description         string?
nextBudgetNumber    number   — incrementado pela Cloud Function createBudget
createdAt           Timestamp
updatedAt           Timestamp
```

Criado direto pelo app, uma única vez, logo após
`createUserWithEmailAndPassword` ter sucesso (o próprio usuário recém-criado
grava seu próprio documento — permitido pela regra `isOwner`).

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
customerId, customerName
technicalVisitId?
number              number  — sequencial por prestador (providers.nextBudgetNumber)
status              enum (rascunho | enviado | visualizado | aguardando_aprovacao |
                          aprovado | recusado | alteracao_solicitada | expirado | cancelado)
issueDate, validUntil?
items               array<{ description, quantity, unit, unitPriceCents, totalCents, sortOrder }>
subtotalCents, discountCents, additionCents, totalCents
executionDeadline?, paymentTerms?, notes?
publicToken         string  — gerado na criação (usado no link público)
sentAt?, viewedAt?, decidedAt?, decidedByIp?
createdAt, updatedAt
```

`items` fica embutido como array no próprio documento (não uma
subcoleção) — sempre é lido/escrito junto com o orçamento, e a lista é
pequena o bastante pra nunca chegar perto do limite de 1MB por documento.

Criação, atualização (com versionamento), envio e decisão (aprovar/
recusar) só acontecem via Cloud Functions callable — ver
`functions/src/budgets.ts`. O app nunca escreve num `budget` diretamente.

### `providers/{uid}/budgets/{budgetId}/versions/{versionId}`

```
versionNumber
snapshot       map   — cópia do orçamento (itens + valores + status) no
                        momento da versão anterior
changeReason?
createdAt
```

Só escrito pela Cloud Function `updateBudget` quando o orçamento já tinha
sido enviado (mesma regra que existia no Postgres: "gera nova versão se já
enviado").

### `providers/{uid}/budgets/{budgetId}/changeRequests/{requestId}`

`message`, `createdAt`, `resolvedAt?` — só escrito pela Cloud Function
`requestBudgetChange`.

## `publicBudgetTokens/{token}` (coleção no topo, fora de `/providers`)

```
providerId
budgetId
```

Ponteiro simples token → (providerId, budgetId). Nunca acessado pelo app
nem por regra do Firestore — só as Cloud Functions HTTPS (`getPublicBudget`,
`publicApproveBudget`) leem essa coleção via Admin SDK, que ignora
`firestore.rules`. Isso evita ter que "vazar" uma regra pública em cima da
coleção de orçamentos de verdade.

## `providers/{uid}/jobs/{jobId}`

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

Só nasce automaticamente via Cloud Function `approveBudget`/
`publicApproveBudget` (regra: `allow create: if false` no Firestore). O
prestador só lê e atualiza o status de execução — endpoints próprios de
Jobs (iniciar/chegar/concluir, como em TechnicalVisits) ainda não existem;
é a mesma lacuna que já existia na versão Postgres.

**Ressalva honesta, carregada da versão anterior**: como um orçamento não
tem data/hora de execução própria, o job criado automaticamente usa a data
da visita técnica vinculada quando existe; se não existir, usa um
placeholder (data de hoje, horário "09:00") que o prestador precisa
confirmar/reagendar manualmente. Isso é uma lacuna do contrato original,
não algo que a migração pra Firebase resolveu ou piorou.

## Marketplace (cliente ↔ prestador) — pivot de produto

A partir daqui o PrestadorAki passa a ter dois lados: o prestador (tudo
acima) e o cliente final, que busca, favorita e solicita orçamento a
prestadores — inclusive os que ainda não têm conta (perfis "não
reivindicados", carregados manualmente pra o app não abrir vazio). Ver
`README.md` pro raciocínio completo por trás dessa mudança (inclusive a
preocupação com LGPD sobre a carga inicial).

### `clients/{uid}`

`{uid}` é o UID do Firebase Auth do cliente — mesmo desenho de
`providers/{uid}`, mas para o outro lado do marketplace.

```
name        string
email       string
createdAt, updatedAt   Timestamp
```

Criado direto pelo app, uma única vez, logo após o cadastro (quando a
pessoa escolhe "Sou cliente" na tela de criar conta).

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
ratingAverage number?  — média 0-5, agregada a partir da subcoleção ratings
ratingCount   number?  — quantidade de avaliações
featured      bool?    — selo "Destaque" (plano pago mensal, ver abaixo)
featuredUntil Timestamp? — validade do Destaque; expirado = não conta mais
createdAt, updatedAt   Timestamp
```

**Perfil reivindicado** (`claimed: true`): o id do documento é sempre
igual ao `providerUid` — criado automaticamente quando um prestador se
cadastra escolhendo categoria/cidade (`AuthController.register`), e pode
ser atualizado depois via `ProviderDirectoryRepository.upsertOwnListing`
(hoje só chamado no cadastro; ainda não existe uma tela de "editar perfil
público" separada — é o próximo passo natural).

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

#### Selo "Destaque" (`featured`/`featuredUntil`)

Plano pago do prestador — por decisão do Franck, a cobrança é uma
assinatura MENSAL feita por fora do app (sem checkout integrado ainda);
quem liga/desliga o selo é só o script administrativo
`scripts/set_provider_plan.js` (Admin SDK, ignora firestore.rules). O
`firestore.rules` bloqueia explicitamente o próprio prestador de gravar
esses dois campos no perfil dele mesmo. Efeito no app: prestadores com
Destaque em dia (`featured: true` e `featuredUntil` no futuro) aparecem
com um selo e sempre no topo dos resultados de busca, antes dos demais
(ver `ProviderListing.isFeatured`, `ProviderDirectoryRepository.search`).
Se a assinatura vencer, o selo some sozinho no próximo app aberto — não
depende de nenhum job/Cloud Function rodando pra "desligar" nada.

### `serviceRequests/{requestId}` (coleção no topo, fora de `/providers`)

O pedido de orçamento do cliente pra um prestador do diretório — o
primeiro contato do fluxo do marketplace, deliberadamente mais simples que
o módulo formal de Orçamentos acima (que é pra prestador × cliente já
cadastrado manualmente, com numeração e versionamento via Cloud Function).

```
clientUid, clientName
providerDirectoryId       — aponta pro providerDirectory
providerUid?              — só se o perfil já era reivindicado no momento do pedido
providerName, category
description, addressText, preferredDate?
status                    enum (aguardando_prestador | orcamento_enviado | aceito | recusado)
quoteAmountCents?, quoteMessage?
createdAt                 Timestamp
```

CRUD direto do app (sem Cloud Function) — ver a ressalva sobre validação
de transição de status em `firestore.rules`. **Lacuna consciente**: aceitar
um orçamento aqui não cria nada automaticamente (nem `job`, nem cliente
cadastrado do prestador) — fechar esse laço de verdade é o próximo passo
depois que esse fluxo básico for validado em uso real.
