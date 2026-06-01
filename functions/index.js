/**
 * Cloud Function template to enforce ride state machine transitions.
 *
 * Sandbox-only Firebase Functions for local M-Pesa testing.
 * This file keeps the payment flow tied to the Safaricom sandbox.
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const https = require('https');
const { URL } = require('url');
const { HttpsError, onCall, onRequest } = require('firebase-functions/v2/https');

admin.initializeApp();
const db = admin.firestore();

const MPESA_SHORTCODE = '174379';
const MPESA_PASSKEY =
  'bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919';
const MPESA_BASE_URL = 'https://sandbox.safaricom.co.ke';
const MPESA_FALLBACK_CONSUMER_KEY =
  'KAT0fSSkv24HA2v1vJQHlNbLN3uY15zspVz0ZAq68HA5B50X';
const MPESA_FALLBACK_CONSUMER_SECRET =
  'TvopOs1TsY7osJm9nfDxSAB4EByhdDa5xDH52oFMxNuxaAA3S1dJkA74NQxaoq86';

function getSandboxMpesaConfig() {
  const mpesa = functions.config().mpesa || {};

  return {
    baseUrl: MPESA_BASE_URL,
    consumerKey: mpesa.consumer_key || process.env.MPESA_CONSUMER_KEY,
    consumerSecret: mpesa.consumer_secret || process.env.MPESA_CONSUMER_SECRET,
    shortcode: mpesa.shortcode || process.env.MPESA_SHORTCODE,
    passkey: mpesa.passkey || process.env.MPESA_PASSKEY,
    callbackUrl: mpesa.callback_url || process.env.MPESA_CALLBACK_URL,
  };
}

function normalizePhoneNumber(phoneNumber) {
  const digits = String(phoneNumber || '').replace(/\D/g, '');
  if (digits.length === 12 && digits.startsWith('254')) return digits;
  if (digits.length === 10 && digits.startsWith('0')) return `254${digits.slice(1)}`;
  if (digits.length === 9) return `254${digits}`;
  return null;
}

function mpesaRequestJson(urlString, options, payload) {
  return new Promise((resolve, reject) => {
    const request = https.request(urlString, options, (response) => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => {
        body += chunk;
      });
      response.on('end', () => {
        try {
          resolve({ statusCode: response.statusCode || 200, body: body ? JSON.parse(body) : {} });
        } catch (error) {
          resolve({ statusCode: response.statusCode || 200, body: { raw: body } });
        }
      });
    });

    request.on('error', reject);

    if (payload) {
      request.write(JSON.stringify(payload));
    }

    request.end();
  });
}

function getTimestamp() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  const hour = String(now.getHours()).padStart(2, '0');
  const minute = String(now.getMinutes()).padStart(2, '0');
  const second = String(now.getSeconds()).padStart(2, '0');
  return `${year}${month}${day}${hour}${minute}${second}`;
}

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  const text = await response.text();

  let body = {};
  if (text) {
    try {
      body = JSON.parse(text);
    } catch (_) {
      body = { raw: text };
    }
  }

  return { ok: response.ok, status: response.status, body };
}

exports.initiateStkPush = onCall({ region: 'us-central1' }, async (request) => {
  const phoneNumber = String(request.data?.phoneNumber || '').trim();
  const amountValue = Number(request.data?.amount);
  const amount = Math.round(amountValue);
  const mpesaConfig = getSandboxMpesaConfig();

  if (!phoneNumber) {
    throw new HttpsError('invalid-argument', 'phoneNumber is required.');
  }

  if (!Number.isFinite(amount) || amount <= 0) {
    throw new HttpsError('invalid-argument', 'amount must be a positive number.');
  }

  const consumerKey = mpesaConfig.consumerKey || MPESA_FALLBACK_CONSUMER_KEY;
  const consumerSecret = mpesaConfig.consumerSecret || MPESA_FALLBACK_CONSUMER_SECRET;

  const tokenResponse = await fetchJson(
    `${mpesaConfig.baseUrl}/oauth/v1/generate?grant_type=client_credentials`,
    {
      method: 'GET',
      headers: {
        Authorization:
          'Basic ' + Buffer.from(`${consumerKey}:${consumerSecret}`).toString('base64'),
      },
    },
  );

  console.log('initiateStkPush: token status', tokenResponse.status);
  console.log('initiateStkPush: token body', tokenResponse.body);

  const accessToken = tokenResponse.body?.access_token;
  if (!tokenResponse.ok || !accessToken) {
    throw new HttpsError('internal', 'Unable to obtain Safaricom access token.', tokenResponse.body);
  }

  const timestamp = getTimestamp();
  const shortcode = mpesaConfig.shortcode || MPESA_SHORTCODE;
  const passkey = mpesaConfig.passkey || MPESA_PASSKEY;
  const callbackUrl = mpesaConfig.callbackUrl || 'https://mydomain.com/mpesa-express-simulate/';
  const password = Buffer.from(`${shortcode}${passkey}${timestamp}`).toString('base64');

  const stkPayload = {
    BusinessShortCode: shortcode,
    Password: password,
    Timestamp: timestamp,
    TransactionType: 'CustomerPayBillOnline',
    
    // TEMPORARY SANDBOX OVERRIDE: 
    // This intercepts your dynamic fare (e.g. 240) and forces it to 1 
    // so Safaricom automatically triggers a successful simulation!
    Amount: 1, 
    
    PartyA: phoneNumber,
    PartyB: shortcode,
    PhoneNumber: phoneNumber,
    CallBackURL: callbackUrl,
    AccountReference: 'AeroRide',
    TransactionDesc: 'AeroRide ride payment',
  };

  const stkResponse = await fetchJson(`${mpesaConfig.baseUrl}/mpesa/stkpush/v1/processrequest`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(stkPayload),
  });

  console.log('initiateStkPush: stk status', stkResponse.status);
  console.log('initiateStkPush: stk body', stkResponse.body);

  if (!stkResponse.ok) {
    throw new HttpsError(
      'internal',
      stkResponse.body?.errorMessage || stkResponse.body?.error_message || 'STK push request failed.',
      stkResponse.body,
    );
  }

  return {
    MerchantRequestID: stkResponse.body?.MerchantRequestID || null,
    CheckoutRequestID: stkResponse.body?.CheckoutRequestID || null,
    ResponseCode: stkResponse.body?.ResponseCode || null,
    ResponseDescription: stkResponse.body?.ResponseDescription || null,
    CustomerMessage: stkResponse.body?.CustomerMessage || null,
  };
});

exports.mpesaCallback = onRequest({ region: 'us-central1', cors: true }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('Method not allowed');
    return;
  }

  let payload = req.body || {};
  if (typeof payload === 'string') {
    try {
      payload = JSON.parse(payload);
    } catch (_) {
      payload = {};
    }
  }

  const callback = payload?.Body?.stkCallback || payload?.stkCallback || payload;
  const resultCode = Number(callback?.ResultCode);
  const resultDesc = callback?.ResultDesc || 'STK callback received';
  const callbackMetadata = callback?.CallbackMetadata?.Item || [];

  const metadata = Array.isArray(callbackMetadata)
    ? callbackMetadata.reduce((accumulator, item) => {
        if (item && item.Name) {
          accumulator[item.Name] = item.Value;
        }
        return accumulator;
      }, {})
    : {};

  if (resultCode === 0) {
    console.log('mpesaCallback: payment successful');
    console.log('mpesaCallback: receipt number:', metadata.MpesaReceiptNumber || null);
  } else {
    console.log('mpesaCallback: payment failed', { resultCode, resultDesc, payload });
  }

  res.status(200).json({ ResultCode: 0, ResultDesc: 'Success' });
});


exports.directionsProxy = functions.https.onRequest((req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  const origin = req.query.origin;
  const destination = req.query.destination;
  const apiKey = req.query.key || functions.config().google?.maps_key || process.env.GOOGLE_MAPS_API_KEY;

  if (!origin || !destination) {
    res.status(400).json({ status: 'INVALID_REQUEST', error_message: 'Missing origin or destination.' });
    return;
  }

  if (!apiKey) {
    res.status(500).json({ status: 'REQUEST_DENIED', error_message: 'Google Maps API key is not configured.' });
    return;
  }

  const directionsUrl = new URL('https://maps.googleapis.com/maps/api/directions/json');
  directionsUrl.searchParams.set('origin', origin);
  directionsUrl.searchParams.set('destination', destination);
  directionsUrl.searchParams.set('key', apiKey);

  https
    .get(directionsUrl, (googleRes) => {
      let body = '';

      googleRes.setEncoding('utf8');
      googleRes.on('data', (chunk) => {
        body += chunk;
      });

      googleRes.on('end', () => {
        res.status(googleRes.statusCode || 200).type('application/json').send(body);
      });
    })
    .on('error', (error) => {
      console.error('directionsProxy failed:', error);
      res.status(500).json({ status: 'ERROR', error_message: error.message });
    });
});

// Allowed transitions map
const ALLOWED = {
  searching: ['accepted', 'cancelled'],
  accepted: ['started', 'cancelled'],
  started: ['completed', 'cancelled'],
  completed: [],
  cancelled: []
};

exports.enforceRideStateMachine = functions.firestore
  .document('rides/{rideId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const rideId = context.params.rideId;

    const prev = before.status || 'searching';
    const next = after.status || 'searching';

    // If status didn't change, nothing to enforce
    if (prev === next) return null;

    const allowedNext = ALLOWED[prev] || [];
    if (!allowedNext.includes(next)) {
      // Revert the status and write an audit field
      await db.collection('rides').doc(rideId).update({
        status: prev,
        stateMachineError: `Invalid transition ${prev} -> ${next}`,
        stateMachineErrorAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.warn(`Reverted invalid transition for ride ${rideId}: ${prev} -> ${next}`);
    }

    return null;
  });
