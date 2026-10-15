const fs = require('fs');
const crypto = require('crypto');
const [, , arquivo, issuerId, keyId] = process.argv;
if (!arquivo || !issuerId || !keyId) {
  console.error('Uso: node gerar-segredo-apple.js <AuthKey.p8> <issuerId> <keyId>');
  process.exit(1);
}
const privateKey = fs.readFileSync(arquivo, 'utf8').replace(/\r\n/g, '\n').trim();
const k = crypto.createPrivateKey(privateKey);
if (k.asymmetricKeyType !== 'ec') {
  console.error('A chave não é EC. Use a chave .p8 de "In-App Purchase" do App Store Connect.');
  process.exit(1);
}
fs.writeFileSync('apple-secret.json', JSON.stringify({ issuerId, keyId, privateKey }));
console.log('OK: apple-secret.json gerado (chave EC válida).');