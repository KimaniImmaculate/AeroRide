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
const { HttpsError, onRequest } = require('firebase-functions/v2/https');

admin.initializeApp();
const db = admin.firestore();

const MPESA_SHORTCODE = '174379';
const MPESA_PASSKEY = 'bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919';
const MPESA_BASE_URL = 'https://sandbox.safaricom.co.ke';
const MPESA_FALLBACK_CONSUMER_KEY = 'KAT0fSSkv24HA2v1vJQHlNbLN3uY15zspVz0ZAq68HA5B50X';
const MPESA_FALLBACK_CONSUMER_SECRET = 'TvopOs1TsY7osJm9nfDxSAB4EByhdDa5xDH52oFMxNuxaAA3S1dJkA74NQxaoq86';

// ==========================================
// FIXING THE VARIABLE TYPO HERE 🛠️
// ==========================================
function getSandboxMpesaConfig() {
  return {
    // ✅ FIXED: Changed MP_BASE_URL to MPESA_BASE_URL
    baseUrl: process.env.MPESA_BASE_URL || MPESA_BASE_URL, 
    consumerKey: process.env.MPESA_CONSUMER_KEY || MPESA_FALLBACK_CONSUMER_KEY,
    consumerSecret: process.env.MPESA_CONSUMER_SECRET || MPESA_FALLBACK_CONSUMER_SECRET,
    shortcode: process.env.MPESA_SHORTCODE || MPESA_SHORTCODE,
    passkey: process.env.MPESA_PASSKEY || MPESA_PASSKEY,
    callbackUrl: process.env.MPESA_CALLBACK_URL || "https://us-central1-aeroride-1.cloudfunctions.net/mpesaCallback",
  };
}

function normalizePhoneNumber(phoneNumber) {
  const digits = String(phoneNumber || '').replace(/\D/g, '');
  if (digits.length === 12 && digits.startsWith('254')) return digits;
  if (digits.length === 10 && digits.startsWith('0')) return `254${digits.slice(1)}`;
  if (digits.length === 9) return `254${digits}`;
  return null;
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

// ==========================================
// 1. INITIATE STK PUSH FUNCTION (onRequest version for direct Flutter calls)
// ==========================================
exports.initiateStkPush = onRequest({ region: 'us-central1', cors: true }, async (req, res) => {
  try {
    // 1. Accept data from body (POST) or query params (GET/Testing)
    const rawPhoneNumber = req.body?.data?.phoneNumber || req.query?.phoneNumber || '';
    const phoneNumber = normalizePhoneNumber(rawPhoneNumber);
    const mpesaConfig = getSandboxMpesaConfig();

    if (!phoneNumber) {
      res.status(400).json({ data: { success: false, error: 'Valid Kenyan phoneNumber is required.' } });
      return;
    }

    const consumerKey = mpesaConfig.consumerKey || MPESA_FALLBACK_CONSUMER_KEY;
    const consumerSecret = mpesaConfig.consumerSecret || MPESA_FALLBACK_CONSUMER_SECRET;

    // 2. Fetch Safaricom OAuth Token
    const tokenResponse = await fetchJson(
      `${mpesaConfig.baseUrl}/oauth/v1/generate?grant_type=client_credentials`,
      {
        method: 'GET',
        headers: {
          Authorization: 'Basic ' + Buffer.from(`${consumerKey}:${consumerSecret}`).toString('base64'),
        },
      },
    );

    console.log('initiateStkPush: token status', tokenResponse.status);
    const accessToken = tokenResponse.body?.access_token;
    if (!tokenResponse.ok || !accessToken) {
      res.status(500).json({ data: { success: false, error: 'Unable to obtain Safaricom access token.' } });
      return;
    }

    // 3. Build the STK Payload
    const timestamp = getTimestamp();
    const shortcode = mpesaConfig.shortcode || MPESA_SHORTCODE;
    const passkey = mpesaConfig.passkey || MPESA_PASSKEY;
    const password = Buffer.from(`${shortcode}${passkey}${timestamp}`).toString('base64');

    const stkPayload = {
      BusinessShortCode: shortcode,
      Password: password,
      Timestamp: timestamp,
      TransactionType: 'CustomerPayBillOnline',
      Amount: 1, // Sandbox force-amount override
      PartyA: phoneNumber,
      PartyB: shortcode,
      PhoneNumber: phoneNumber,
      CallBackURL: mpesaConfig.callbackUrl,
      AccountReference: 'AeroRide',
      TransactionDesc: 'AeroRide ride payment',
    };

    // 4. Send Request to Safaricom Daraja API
    const stkResponse = await fetchJson(`${mpesaConfig.baseUrl}/mpesa/stkpush/v1/processrequest`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(stkPayload),
    });

    console.log('initiateStkPush: stk status', stkResponse.status);

    if (stkResponse.ok) {
      const checkoutRequestID = stkResponse.body?.CheckoutRequestID;
      if (checkoutRequestID) {
        await db.collection('payments').doc(checkoutRequestID).set({
          status: 'PENDING',
          phoneNumber: phoneNumber,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    if (!stkResponse.ok) {
      res.status(400).json({ 
        data: { 
          success: false, 
          error: stkResponse.body || 'STK push request failed.' 
        } 
      });
      return;
    }

    // 5. Respond to Flutter with exact wrapper layout
    res.status(200).json({
      data: {
        success: true,
        MerchantRequestID: stkResponse.body?.MerchantRequestID || null,
        CheckoutRequestID: stkResponse.body?.CheckoutRequestID || null,
        ResponseCode: stkResponse.body?.ResponseCode || null,
        ResponseDescription: stkResponse.body?.ResponseDescription || null,
        CustomerMessage: stkResponse.body?.CustomerMessage || null,
      }
    });

  } catch (error) {
    console.error("Internal STK Push Error:", error);
    // ✅ Formatted specifically to stop the generic 'internal' wrapper fallback in Flutter
    res.status(500).json({
      error: {
        status: "INTERNAL",
        message: error.message || "Internal Server Error",
        details: error.stack || null
      }
    });
  }
});


// ==========================================
// 2. MPESA CALLBACK FUNCTION
// ==========================================
exports.mpesaCallback = onRequest({ region: 'us-central1', cors: true }, async (req, res) => {
  try {
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

    console.log("M-Pesa Callback Payload received:", payload);
    
    const body = payload.Body?.stkCallback;
    if (body) {
      const checkoutRequestID = body.CheckoutRequestID;
      const status = body.ResultCode === 0 ? 'SUCCESSFUL' : 'FAILED';
      
      const updateData = {
        status: status,
        resultCode: body.ResultCode,
        resultDesc: body.ResultDesc,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Extract M-Pesa Receipt Number from metadata if successful
      if (body.ResultCode === 0 && body.CallbackMetadata) {
        const items = body.CallbackMetadata.Item || [];
        const receiptItem = items.find(i => i.Name === 'MpesaReceiptNumber');
        if (receiptItem) {
          updateData.receiptNumber = receiptItem.Value;
        }
      }

      await db.collection('payments').doc(checkoutRequestID).update(updateData);
    }

    res.status(200).send({ ResultCode: 0, ResultDesc: "Accepted successfully" });

  } catch (callbackError) {
    console.error("Callback Processing Error:", callbackError);
    res.status(500).send({ ResultCode: 1, ResultDesc: "Internal Error" });
  }
});

// ==========================================
// 3. DIRECTIONS PROXY FUNCTION
// ==========================================
exports.directionsProxy = onRequest({ region: 'us-central1', cors: true }, async (req, res) => {
  try {
    const origin = req.query.origin;
    const destination = req.query.destination;
    const apiKey = req.query.key || process.env.GOOGLE_MAPS_API_KEY;

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

    https.get(directionsUrl, (googleRes) => {
      let body = '';
      googleRes.setEncoding('utf8');
      googleRes.on('data', (chunk) => { body += chunk; });
      googleRes.on('end', () => {
        res.status(googleRes.statusCode || 200).type('application/json').send(body);
      });
    }).on('error', (error) => {
      console.error('directionsProxy external request failed:', error);
      res.status(500).json({ status: 'ERROR', error_message: error.message });
    });

  } catch (error) {
    console.error("Directions Proxy Internal Error:", error);
    res.status(500).json({ status: 'ERROR', error_message: "Internal Server Error" });
  }
});

// ==========================================
// 4. RIDE STATE MACHINE ENFORCER (v1 Background Firestore Trigger)
// ==========================================
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

    if (prev === next) return null;

    const allowedNext = ALLOWED[prev] || [];
    if (!allowedNext.includes(next)) {
      await db.collection('rides').doc(rideId).update({
        status: prev,
        stateMachineError: `Invalid transition ${prev} -> ${next}`,
        stateMachineErrorAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.warn(`Reverted invalid transition for ride ${rideId}: ${prev} -> ${next}`);
    }
    return null;
  });
