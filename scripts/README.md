# Scripts administrativos do PrestadorAki

Scripts que rodam fora do app e das Cloud Functions — usam a chave de
administrador do Firebase (Admin SDK), que **ignora o `firestore.rules`**.
Rodam só na sua máquina, nunca daqui do assistente.

## Carga inicial do diretório de prestadores (`seed_provider_directory.js`)

Isso alimenta a busca do lado do cliente com entradas "não reivindicadas"
(prestadores que ainda não têm conta no PrestadorAki) — ver a seção
"Marketplace" do `README.md` da raiz do projeto pro raciocínio completo.

**Antes de rodar com nomes de verdade**: só entram aqui prestadores que
você já tem consentimento pra listar publicamente — nunca telefone,
WhatsApp ou e-mail, só nome, categoria e cidade. Ver a ressalva de LGPD no
`README.md` da raiz.

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
   limpeza, marceneiro, serralheiro, climatizacao, vidraceiro, azulejista, outro`.

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

## Selo "Destaque" / plano pago (`set_provider_plan.js`)

Liga ou desliga o selo "Destaque" de um prestador — hoje é sempre uma
assinatura MENSAL cobrada por fora do app (você combina o pagamento direto
com o prestador; não existe checkout dentro do PrestadorAki ainda). O
`firestore.rules` bloqueia o próprio prestador de gravar isso no perfil
dele, então esse script (Admin SDK) é a única forma de marcar quem pagou.

Busca pelo **nome do prestador** (não precisa achar nenhum id no Console
do Firebase — troque `NOME_DO_PRESTADOR` abaixo pelo nome de verdade,
entre aspas se tiver espaço):

```
node set_provider_plan.js caminho/pra/service-account.json "NOME_DO_PRESTADOR" ativar [dias]
node set_provider_plan.js caminho/pra/service-account.json "NOME_DO_PRESTADOR" desativar
```

Por exemplo:

```
node set_provider_plan.js caminho/pra/service-account.json "William Pizzetti" ativar
```

Se o nome bater com mais de um prestador, o script lista todos (com
categoria e cidade) e pede pra você digitar o número do certo — nunca
precisa copiar um id manualmente. `dias` é opcional (padrão 30). Como é
uma assinatura mensal de verdade, `ativar` sempre grava uma data de
validade; se o prestador não renovar, o selo some sozinho no app quando a
data passar — não precisa rodar `desativar` todo mês, só rodar `ativar` de
novo quando ele pagar a próxima mensalidade.

**Nota pra quem usa Windows (cmd/PowerShell)**: nunca copie comandos de
exemplo com `<` e `>` — nesses terminais esses dois caracteres são
"redirecionamento de arquivo", não um espaço reservado pra você substituir
(foi exatamente o que deu o erro "não pode encontrar o arquivo
especificado" da primeira vez). Os exemplos aqui usam aspas em vez disso —
troque só o texto de dentro.
