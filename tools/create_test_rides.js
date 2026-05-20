/**
 * Script to seed test rides into Firestore for local/dev testing.
 * Usage: set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON, then:
 *   node tools/create_test_rides.js
 */
const admin = require('firebase-admin');
const faker = require('faker');

admin.initializeApp();
const db = admin.firestore();

async function seed(count = 5) {
  const center = { lat: -1.2921, lng: 36.8219 }; // Nairobi center as example

  for (let i = 0; i < count; i++) {
    const pickup = {
      latitude: center.lat + (Math.random() - 0.5) * 0.02,
      longitude: center.lng + (Math.random() - 0.5) * 0.02,
    };
    const dest = {
      latitude: center.lat + (Math.random() - 0.5) * 0.03,
      longitude: center.lng + (Math.random() - 0.5) * 0.03,
    };

    const doc = {
      userId: `test-user-${i}`,
      pickupLocation: new admin.firestore.GeoPoint(pickup.latitude, pickup.longitude),
      destinationLocation: new admin.firestore.GeoPoint(dest.latitude, dest.longitude),
      pickupAddress: faker.address.streetAddress(),
      destinationAddress: faker.address.streetAddress(),
      status: 'searching',
      estimatedCost: Math.round((Math.random() * 30 + 10) * 100) / 100,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const ref = await db.collection('rides').add(doc);
    console.log(`Created test ride ${ref.id}`);
  }
}

seed(process.argv[2] ? Number(process.argv[2]) : 5).then(() => {
  console.log('Done');
  process.exit(0);
}).catch(err => {
  console.error(err);
  process.exit(1);
});
