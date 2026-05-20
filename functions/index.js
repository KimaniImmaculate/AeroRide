/**
 * Cloud Function template to enforce ride state machine transitions.
 *
 * Deploy with Firebase Functions (`firebase init functions` then `firebase deploy --only functions`).
 * This function rejects invalid state transitions by writing an error field and optionally reverting.
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

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
