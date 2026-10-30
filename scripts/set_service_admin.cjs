'use strict';
// Grants or revokes the service admin claim (Auth custom claim admin: true) that the learning
// screen, /learning/* on the formation server and approveModel/activateModel require.
//
//   node scripts/set_service_admin.cjs --project teamix-309c0 --email you@example.com
//   node scripts/set_service_admin.cjs --project teamix-309c0 --email you@example.com --revoke
//   node scripts/set_service_admin.cjs --project teamix-309c0 --email admin@teamix.app --create
//     (creates the account if missing; its random password goes to scripts/service_admin.local.txt)
// Uses Application Default Credentials. The user must sign out and in again (or wait up to
// an hour) for the new claim to reach the app.

function arg(name) {
  const i = process.argv.indexOf(name);
  return i < 0 ? null : process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[i + 1] : true;
}

async function main() {
  const project = arg('--project'), email = arg('--email');
  if (typeof project !== 'string' || typeof email !== 'string') throw new Error('--project and --email are required');
  const admin = require('../functions/node_modules/firebase-admin');
  admin.initializeApp({projectId: project});
  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch (e) {
    if (e.code !== 'auth/user-not-found' || !arg('--create')) throw e;
    // New demo admin: random password kept only in a git-ignored local file.
    const password = require('crypto').randomBytes(12).toString('base64url');
    user = await admin.auth().createUser({email, password, displayName: '서비스 관리자'});
    const file = require('path').join(__dirname, 'service_admin.local.txt');
    require('fs').writeFileSync(file, `email: ${email}\npassword: ${password}\n`);
    console.log(`created ${email}; password saved to ${file}`);
  }
  const claims = {...(user.customClaims || {})};
  if (arg('--revoke')) delete claims.admin;
  else claims.admin = true;
  await admin.auth().setCustomUserClaims(user.uid, claims);
  console.log(`${email}: admin=${claims.admin === true}`);
}

main().catch(e => { console.error(e.message); process.exit(1); });
