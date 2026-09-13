# Scripts administrativos do PrestadorAki

Scripts que rodam fora do app e das Cloud Functions — usam a chave de
administrador do Firebase (Admin SDK), que **ignora o `firestore.rules`**.
Rodam só na sua máquina, nunca daqui do assistente.

## A decisão que manda hoje: convidar primeiro, publicar depois

**13/09 — o diretório de curadoria saiu da busca.** O `providerDirectory`
tinha ~9.700 entradas raspadas e nenhuma delas usava o app. Na prática,
todo pedido de orçamento feito pra uma delas morria: o cliente escrevia o
pedido e recebia "esse profissional ainda não usa o PrestadorAki, copie a
mensagem e mande você mesmo". Trabalho perdido e primeira impressão
queimada — num mercado do tamanho de Criciúma, isso circula rápido.

O gargalo de um marketplace não é cliente, é prestador que responde.
Cinquenta que atendem valem mais que dez mil nomes de catálogo.

Então a ordem se inverteu:

1. `prospeccao_criciuma.csv` — a lista de contato, ordenada com as
   categorias que sustentam a busca de uma cidade primeiro (eletricista,
   encanador, pedreiro, pintor, limpeza...). Tem link `wa.me` pronto e
   coluna `status` pra você marcar quem respondeu.
2. Convite por WhatsApp — ver `modelo_mensagem_convite.md`.
3. **Só depois do "sim"**, o perfil vai ao ar.

`ocultar_prospeccao.js` é o que tirou as 9.700 da busca (`visible:
false`), preservando as exceções passadas em `--manter` e nunca tocando
em quem tem `claimed: true`. É reversível: `--reverter` traz de volta.

O `importar_prestadores.js` continua aqui e funcionando, mas **não é o
caminho atual** — ele publica direto na vitrine, que é justamente o que
a gente deixou de fazer.

## Dois caminhos de carga inicial — e por que o telefone mudou de lado

| caminho | entrada | grava telefone? | reivindicável? |
| --- | --- | --- | --- |
| `seed_provider_directory.js` | `providers_seed.csv` (`name,category,city,state`) | não | não |
| `converter_prospeccao.js` + `importar_prestadores.js` | CSV de prospecção com WhatsApp | sim | sim |

O primeiro é o original, de quando a regra era "nenhum contato na carga
inicial". **Essa regra mudou**, e o motivo está em
`functions/src/subscription.ts`: a função `reivindicarListagemPorTelefone`
casa a entrada não reivindicada com a conta recém-criada **pelo
telefone** — é o único dado que sobrevive entre o convite e o cadastro (o
nome a pessoa digita diferente). Sem `phoneNormalized` gravado, a entrada
nunca é encontrada: quando o prestador se cadastra nasce um perfil
duplicado e o antigo fica órfão, exigindo limpeza manual.

Daí também a regra **sem telefone não entra**: uma linha sem telefone só
geraria uma entrada impossível de reivindicar depois.

O que continua valendo, e é decisão consciente:

- Só entram prestadores que você tenha base pra listar publicamente. A
  ressalva de LGPD no `README.md` da raiz segue de pé — mudou o campo, não
  o cuidado.
- `providerDirectory` tem `allow read: if true` no `firestore.rules`:
  **tudo que é gravado ali é público**, `phoneNormalized` inclusive. Não
  existe campo "guardado mas escondido" nessa coleção.
- A descrição e os metadados da fonte externa (place_id, endereço, site,
  link do Maps) **não** são importados. O perfil fica com nome,
  categoria, cidade e contato; a bio quem escreve é a própria pessoa,
  quando assumir o perfil.

### Carga de prospecção, passo a passo

```
cd scripts && npm install          # uma vez só
node converter_prospeccao.js caminho/pra/prospeccao_resultados.csv
node importar_prestadores.js caminho/pra/chave.json            # simula
node importar_prestadores.js caminho/pra/chave.json --gravar   # grava
```

O conversor valida as categorias contra
`assets/data/service_categories.json` e avisa quais não reconheceu (uma
categoria errada faz o prestador nunca aparecer na busca — é erro
silencioso). Ele também tira o código do país `55` do telefone: o app
normaliza o que a pessoa digita na máscara `(00) 00000-0000` e chega em 11
dígitos sem o 55; gravar com o 55 faria nenhuma entrada ser reivindicada.

**Como a importação evita duplicata.** Os dois caminhos usam esquemas de
id diferentes (`nome-cidade` no antigo, `imp_<telefone>` no novo), então o
mesmo prestador carregado pelos dois viraria dois cards na busca. Antes de
escrever, o importador lê a coleção inteira e decide: mesmo telefone →
escreve por cima daquele documento; id igual ao slug `nome-cidade` →
escreve por cima da entrada antiga (e de quebra adiciona o telefone que
faltava nela); nome parecido na mesma cidade → **não decide sozinho**,
reporta como suspeito e pula. Fusão errada junta dois profissionais
diferentes, o que é pior que a duplicata.

Para confirmar um suspeito, crie `scripts/fusoes.json` mapeando o telefone
da linha nova para o id do documento que já existe:

```json
{ "48999361869": "william-pizzetti-criciuma" }
```

Entradas já reivindicadas (`claimed: true`) são sempre puladas — uma
reimportação não pode sobrescrever com dados da prospecção o perfil que a
pessoa escreveu.

## Carga inicial sem contato (`seed_provider_directory.js`)

Alimenta a busca usando só nome, categoria e cidade — ver a seção
"Marketplace" do `README.md` da raiz pro raciocínio completo. Continua
servindo pra quando você não tiver o telefone; só lembre que essas
entradas não são reivindicáveis automaticamente.

### Passo a passo

1. Pegar a chave de administrador do projeto:
   Console do Firebase → ⚙️ Configurações do projeto → Contas de serviço
   → "Gerar nova chave privada". Salva esse `.json` em algum lugar fora do
   controle de versão (o `.gitignore` da raiz já bloqueia qualquer
   `*serviceAccount*.json` dentro desta pasta, mas não custa ter cuidado
   redobrado — essa chave dá acesso total ao projeto).

2. Instalar a dependência (só precisa fazer uma vez):
   ```
   cd scripts
   npm install
   ```

3. Copiar `providers_seed.example.csv` pra `providers_seed.csv` e
   preencher com os prestadores de verdade (mesma pasta `scripts/`):
   ```
   cp providers_seed.example.csv providers_seed.csv
   ```
   Formato (cabeçalho obrigatório, nessa ordem): `name,category,city,state`
   — `state` é opcional. `category` precisa ser um destes valores (iguais
   ao app): `eletricista, encanador, pedreiro, pintor, jardineiro,
   limpeza, marceneiro, serralheiro, climatizacao, vidraceiro, outro`.

4. Rodar (o script mostra tudo que vai gravar e pede confirmação antes de
   tocar no banco de verdade):
   ```
   node seed_provider_directory.js caminho/pra/service-account.json providers_seed.csv
   ```

Rodar de novo com o mesmo CSV atualiza as mesmas entradas em vez de
duplicar (o id de cada documento é gerado a partir de nome+cidade).

### O que fica de fora, de propósito

- Nenhum campo de contato (telefone/WhatsApp/e-mail) — só nome, categoria
  e cidade.
- Nenhuma validação de duplicata "parecida" (dois nomes escritos
  diferente pra o mesmo prestador viram duas entradas) — revisão manual
  do CSV antes de rodar é o que evita isso, por enquanto.
