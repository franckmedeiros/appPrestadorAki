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
logoUrl             string?
description         string?
nextBudgetNumber    number   — incrementado pela Cloud Function createBudget
createdAt           Timestamp
updatedAt           Timestamp
```

Criado direto pelo app, logo após `createUserWithEmailAndPassword` ter
sucesso, OU depois — quando uma conta que já era só cliente decide
"também quero oferecer serviços" pela tela de perfil (ver
`AuthController.becomeProvider`) — o próprio usuário grava seu próprio
documento nos dois casos (permitido pela regra `isOwner`).

**Conta unificada** (decisão combinada com o Franck): ter um documento
aqui NUNCA significa que a conta deixou de ser cliente — toda conta
autenticada também tem (ou ganha, na primeira ação de cliente) um
`clients/{uid}` (ver abaixo). As duas coisas coexistem sempre.

**Gate de pagamento — "só preparar o terreno"** (decisão combinada com o
Franck, sem pagamento de verdade integrado ainda): um prestador recém-
criado (seja no cadastro ou virando prestador depois) nasce com
`listingStatus: 'pending'` e o app NÃO cria a entrada correspondente em
`providerDirectory` automaticamente — ou seja, ele não aparece de graça
na busca do cliente. A ativação hoje é manual, direto no Firebase
Console: (1) mudar `listingStatus` pra `'active'` no documento de
`providers/{uid}`, e (2) o próprio prestador precisa salvar o perfil uma
vez (`EditProfileScreen` -> "Salvar alterações") depois disso pra
`providerDirectory/{uid}` ser criado/atualizado — ou, mais direto, criar
esse documento manualmente também. Contas de prestador criadas ANTES
dessa mudança não têm o campo `listingStatus` — a ausência do campo é
tratada como "ativo" (nunca tira alguém que já estava aparecendo do ar).

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
ratingAverage number?  — média 0-5, agregada a partir da subcoleção ratings
ratingCount   number?  — quantidade de avaliações
createdAt, updatedAt   Timestamp
```

**Perfil reivindicado** (`claimed: true`): o id do documento é sempre
igual ao `providerUid`. Desde o gate de pagamento ("só preparar o
terreno" — ver `providers/{uid}`), este documento NÃO nasce mais junto
com o cadastro/`becomeProvider` — só é criado (ou atualizado) via
`ProviderDirectoryRepository.upsertOwnListing`, chamado pela tela
"Editar perfil" (EditProfileScreen), e só quando
`providers/{uid}.listingStatus != 'pending'`. Ou seja, um prestador
recém-cadastrado só ganha entrada aqui depois de ser ativado manualmente
E salvar o perfil de novo uma vez.

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
