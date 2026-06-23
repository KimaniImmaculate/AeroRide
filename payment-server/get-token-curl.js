/**
 * Generates a Firebase access token using the service account JSON.
 * Creates and signs the JWT locally, then exchanges it via curl (which handles
 * the corporate SSL inspection proxy correctly).
 * 
 * Usage: node payment-server/get-token-curl.js
 * Output: Access token printed to stdout (copy for use with FIREBASE_TOKEN)
 */
const { execSync } = require('child_process');
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');

// Load service account
const keyFile = path.join(__dirname, '..', 'service-account.json');
const sa = JSON.parse(fs.readFileSync(keyFile, 'utf8'));

// Build JWT header + payload
const now = Math.floor(Date.now() / 1000);
const header = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).toString('base64url');
const payload = Buffer.from(JSON.stringify({
  iss: sa.client_email,
  scope: 'https://www.googleapis.com/auth/firebase https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/cloudplatformprojects.readonly',
  aud: 'https://oauth2.googleapis.com/token',
  exp: now + 3600,
  iat: now,
})).toString('base64url');

// Sign with private key
const sign = crypto.createSign('RSA-SHA256');
sign.update(`${header}.${payload}`);
sign.end();
const signature = sign.sign(sa.private_key).toString('base64url');
const jwt = `${header}.${payload}.${signature}`;

// Exchange JWT for access token using curl (bypasses Node.js TLS issues)
const curlCmd = [
  'curl', '-s', '-k',   // -k = insecure (corporate SSL proxy)
  '-X', 'POST',
  '"https://oauth2.googleapis.com/token"',
  '-H', '"Content-Type: application/x-www-form-urlencoded"',
  '-d', `"grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}"`
].join(' ');

try {
  const result = execSync(`cmd /c ${curlCmd}`, { encoding: 'utf8' });
  const json = JSON.parse(result);
  if (json.access_token) {
    console.log(json.access_token);
  } else {
    console.error('ERROR: No access_token in response:', JSON.stringify(json, null, 2));
    process.exit(1);
  }
} catch (err) {
  console.error('ERROR:', err.message);
  process.exit(1);
}
