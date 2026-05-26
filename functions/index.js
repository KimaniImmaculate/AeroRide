/**
 * Cloud Function template to enforce ride state machine transitions.
 *
 * Deploy with Firebase Functions (`firebase init functions` then `firebase deploy --only functions`).
 * This function rejects invalid state transitions by writing an error field and optionally reverting.
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const https = require('https');
const { URL } = require('url');

admin.initializeApp();
const db = admin.firestore();

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
