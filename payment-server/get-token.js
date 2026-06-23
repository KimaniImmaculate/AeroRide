/**
 * Custom access token generator to handle corporate proxy, clock skew, and fetch library issues.
 * Uses native Node.js 'crypto' and 'https' modules.
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const https = require('https');

process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

// 1. Load service account
const saPath = path.join(__dirname, '..', 'service-account.json');
let sa;
try {
  sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
} catch (e) {
  console.error('ERROR reading service account:', e.message);
  process.exit(1);
}

// Helper for Base64URL encoding
const b64url = (obj) => 
  Buffer.from(JSON.stringify(obj))
    .toString("base64")
    .replace(/=+$/, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

// 2. Fetch server time to calculate offset
function getServerTimeOffset() {
  return new Promise((resolve) => {
    const req = https.request({
      hostname: 'www.googleapis.com',
      method: 'HEAD',
      timeout: 10000,
    }, (res) => {
      const serverDateStr = res.headers.date;
      if (serverDateStr) {
        const serverTime = Date.parse(serverDateStr);
        const localTime = Date.now();
        const offsetMs = serverTime - localTime;
        console.warn('Clock sync: server time =', new Date(serverTime).toISOString(), 'local time =', new Date(localTime).toISOString(), 'offset =', offsetMs / 1000, 'seconds');
        resolve(offsetMs);
      } else {
        console.warn('Clock sync: Date header not found, using 0 offset');
        resolve(0);
      }
    });
    req.on('error', (e) => {
      console.warn('Clock sync: request failed, using 0 offset:', e.message);
      resolve(0);
    });
    req.on('timeout', () => {
      console.warn('Clock sync: timeout, using 0 offset');
      req.destroy();
      resolve(0);
    });
    req.end();
  });
}

async function run() {
  const offsetMs = await getServerTimeOffset();
  const nowSec = Math.floor((Date.now() + offsetMs) / 1000);
  
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: [
      'https://www.googleapis.com/auth/firebase',
      'https://www.googleapis.com/auth/cloud-platform',
      'https://www.googleapis.com/auth/cloudplatformprojects.readonly'
    ].join(' '),
    aud: sa.token_uri || "https://oauth2.googleapis.com/token",
    iat: nowSec - 10, // Go slightly in past to be safe
    exp: nowSec + 3600,
  };

  const unsigned = `${b64url(header)}.${b64url(claims)}`;

  let signature;
  try {
    const signer = crypto.createSign("RSA-SHA256");
    signer.update(unsigned);
    signer.end();
    signature = signer
      .sign(sa.private_key)
      .toString("base64")
      .replace(/=+$/, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");
  } catch (err) {
    console.error('ERROR signing JWT:', err.message);
    process.exit(1);
  }

  const jwt = `${unsigned}.${signature}`;

  const tokenUri = sa.token_uri || "https://oauth2.googleapis.com/token";
  const url = new URL(tokenUri);

  const postData = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion: jwt,
  }).toString();

  const req = https.request({
    hostname: url.hostname,
    path: url.pathname,
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Content-Length': Buffer.byteLength(postData)
    }
  }, r => {
    let body = '';
    r.on('data', d => body += d);
    r.on('end', () => {
      if (r.statusCode === 200) {
        try {
          const data = JSON.parse(body);
          if (!data.access_token) {
            console.error('ERROR: no access_token in response:', body);
            process.exit(1);
          }
          console.log(data.access_token);
        } catch (err) {
          console.error('ERROR parsing response:', err.message, body);
          process.exit(1);
        }
      } else {
        console.error('ERROR status code:', r.statusCode, body);
        process.exit(1);
      }
    });
  });

  req.on('error', e => {
    console.error('ERROR requesting token:', e.message);
    process.exit(1);
  });

  req.write(postData);
  req.end();
}

run();
