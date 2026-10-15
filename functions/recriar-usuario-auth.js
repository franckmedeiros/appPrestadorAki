/**
 * Recria um usuário no Firebase Authentication COM UM UID ESPECÍFICO.
 *
 * Serve pro caso em que o documento `providers/{uid}` (ou `clients/{uid}`)
 * continua no Firestore mas o usuário correspondente no Authentication foi
 * apagado. Criar a conta de novo pelo console do Firebase não resolve: o
 * console sorteia um UID novo, e o perfil antigo fica órfão. Só o Admin
 * SDK aceita escolher o UID.
 *
 * NÃO precisa de arquivo de chave. Ele usa as credenciais da sua própria
 * conta Google (Application Default Credentials), então nada sensível
 * passa por lugar nenhum:
 *
 *   gcloud auth application-default login
 *
 * Uso:
 *
 *   node recriar-usuario-auth.js <uid> <email> <senha> [nome]
 *
 * Exemplo:
 *
 *   node recriar-usuario-auth.js aBcD123... demo@prestadoraki.app umaSenha123 "Demo PrestadorAki"
 *
 * O script confere antes se o UID ou o e-mail já existem, e não sobrescreve
 * nada — se já houver conta, ele diz e para.
 */

const admin = require('firebase-admin');

const PROJECT_ID = 'prestadoraki';

const [, , uid, email, senha, ...restoDoNome] = process.argv;
const nome = restoDoNome.join(' ').trim() || undefined;

if (!uid || !email || !senha) {
  console.error('Uso: node recriar-usuario-auth.js <uid> <email> <senha> [nome]');
  process.exit(1);
}
if (senha.length < 6) {
  console.error('A senha precisa ter pelo menos 6 caracteres (exigência do Firebase).');
  process.exit(1);
}

admin.initializeApp({ projectId: PROJECT_ID });

async function main() {
  const auth = admin.auth();

  // 1. O UID já está em uso?
  try {
    const existente = await auth.getUser(uid);
    console.error(
      `Já existe um usuário com esse UID (${existente.email ?? 'sem e-mail'}). ` +
        'Nada foi alterado.',
    );
    process.exit(1);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }

  // 2. O e-mail já está em uso por outro UID?
  try {
    const porEmail = await auth.getUserByEmail(email);
    console.error(
      `Esse e-mail já pertence ao usuário ${porEmail.uid}, que é diferente do UID pedido. ` +
        'Apague esse usuário primeiro, ou use o UID dele. Nada foi alterado.',
    );
    process.exit(1);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }

  // 3. Cria.
  await auth.createUser({
    uid,
    email,
    password: senha,
    emailVerified: true,
    ...(nome ? { displayName: nome } : {}),
  });

  console.log(`Usuário criado: ${email} com UID ${uid}`);

  // 4. Confere que o perfil antigo realmente casa com esse UID.
  const db = admin.firestore();
  const [provider, client] = await Promise.all([
    db.collection('providers').doc(uid).get(),
    db.collection('clients').doc(uid).get(),
  ]);
  console.log(`providers/${uid}: ${provider.exists ? 'encontrado' : 'NÃO existe'}`);
  console.log(`clients/${uid}:   ${client.exists ? 'encontrado' : 'NÃO existe'}`);
  if (!provider.exists && !client.exists) {
    console.log(
      'Aviso: nenhum perfil achado para esse UID. Confira se o UID está certo — ' +
        'ele é o NOME do documento em providers/, não um campo dentro dele.',
    );
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
