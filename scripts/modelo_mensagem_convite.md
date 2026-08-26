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
