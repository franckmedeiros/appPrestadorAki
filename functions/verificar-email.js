/**
 * Mostra se o e-mail de um usuário consta como confirmado no Firebase e,
 * se você pedir, marca como confirmado.
 *
 * Usa as credenciais da sua conta Google (sem arquivo de chave):
 *   gcloud auth application-default login
 *
 * Rode dentro da pasta `functions` do projeto (lá o firebase-admin já está instalado):
 *
 *   node verificar-email.js cliente@email.com              -> só mostra
 *   node verificar-email.js cliente@email.com --confirmar  -> marca como confirmado
 */

const admin = require('firebase-admin');

const [, , email, flag] = process.argv;
if (!email) {
  console.error('Uso: node verificar-email.js <email> [--confirmar]');
  process.exit(1);
}

admin.initializeApp({ projectId: 'prestadoraki' });

(async () => {
  let user;
  try {
    user = await admin.auth().getUserByEmail(email.trim().toLowerCase());
  } catch (e) {
    console.error(`Nenhum usuário com o e-mail ${email} no Authentication.`);
    process.exit(1);
  }

  console.log('UID ............', user.uid);
  console.log('E-mail .........', user.email);
  console.log('Confirmado .....', user.emailVerified ? 'SIM' : 'NÃO');
  console.log('Login por ......', user.providerData.map((p) => p.providerId).join(', ') || '-');
  console.log('Criado em ......', user.metadata.creationTime);
  console.log('Último login ...', user.metadata.lastSignInTime);

  if (flag === '--confirmar') {
    if (user.emailVerified) {
      console.log('\nJá estava confirmado. Nada foi alterado.');
    } else {
      await admin.auth().updateUser(user.uid, { emailVerified: true });
      console.log('\nPronto: e-mail marcado como confirmado.');
    }
    console.log('Peça para a pessoa SAIR da conta no app e ENTRAR de novo.');
  }
  process.exit(0);
})().catch((e) => {
  console.error('Erro:', e.message);
  process.exit(1);
});
