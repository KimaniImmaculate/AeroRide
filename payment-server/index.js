const { onRequest } = require("firebase-functions/v2/https");
const admin = require('firebase-admin');
const express = require('express');
const cors = require('cors');
const IntaSend = require('intasend-node');

// Initialize Firebase Admin SDK
admin.initializeApp();
const db = admin.firestore();

const app = express();
app.use(express.json());
app.use(cors()); // Critical fix to allow Chrome viewports to bypass CORS barriers

// Initialize your aggregator module with keys
// The third argument "true" targets the testing pool environment
const intasend = new IntaSend(
    "ISPubKey_test_80ee9e72-d0bd-4fcd-bedd-f5e32879bfd7",
    "ISSecretKey_test_4fda33ac-6b47-4fb5-8fa2-6856ddd59645",
    true 
);

const apiRouter = express.Router();

apiRouter.post('/stkpush', async (req, res) => {
    const { phone, amount, driverPhone } = req.body; // Captured from Flutter

    try {
        let collection = intasend.collection();
        
        const response = await collection.mpesaStkPush({
            first_name: 'AeroRide',
            last_name: 'Passenger',
            email: 'rider@aeroride.co.ke',
            amount: amount,
            phone_number: phone, 
            api_ref: 'AeroRide-Trip-Charge'
        });

        console.log("🚀 Gateway Response Status:", response);

        // Link this invoice ID with the driver's phone number in Firestore
        if (response && response.invoice && response.invoice.invoice_id) {
            const invoiceId = response.invoice.invoice_id;
            await db.collection('intasend_payments').doc(invoiceId).set({
                driverPhone: driverPhone || "254000000000",
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            });
        }

        res.status(200).json(response);
    } catch (error) {
        console.error("❌ STK Push Dispatch Failure:", error);
        res.status(500).json({ error: "Failed to communicate with M-Pesa node wrapper" });
    }
});

apiRouter.get('/payment-status/:invoiceId', async (req, res) => {
    const { invoiceId } = req.params;

    try {
        let collection = intasend.collection();
        const statusResponse = await collection.status(invoiceId);
        const invoice = statusResponse.invoice;
        const state = invoice.state;

        console.log(`🔍 Checking Status for ${invoiceId}:`, state);

        // Extract M-Pesa transaction reference (available when COMPLETE)
        const mpesaRef = invoice.mpesa_reference || invoice.charges?.[0]?.mpesa_reference || null;

        if (state === 'COMPLETE' || state === 'COMPLETED') {
            const totalPaid = invoice.value; 
            
            const companyCommission = totalPaid * 0.20; 
            const driverEarnings = totalPaid - companyCommission; 

            console.log(`💰 AeroRide Split Math -> Total: KES ${totalPaid} | Platform Keeps: KES ${companyCommission.toFixed(2)} | Driver Gets: KES ${driverEarnings.toFixed(2)}`);

            try {
                let payouts = intasend.payouts();
                
                // Retrieve the actual driver phone number mapped to this invoice from Firestore
                const paymentDocRef = db.collection('intasend_payments').doc(invoiceId);
                const paymentSnap = await paymentDocRef.get();
                const driverPhone = paymentSnap.exists ? (paymentSnap.data().driverPhone || "254000000000") : "254000000000"; 
                
                const payoutResponse = await payouts.mpesa({
                    currency: "KES",
                    transactions: [
                        {
                            name: "AeroRide Driver Payout",
                            account: driverPhone,
                            amount: Math.round(driverEarnings).toString(), 
                            narrative: "Trip Fare Payout"
                        }
                    ]
                });

                console.log("🚀 Aggregator Payout API Response:", payoutResponse);
                console.log(`✅ Sandbox Transfer Successfully sent to Driver (${driverPhone})!`);
                
                // Clean up Firestore doc
                await paymentDocRef.delete();

            } catch (payoutError) {
                console.error("❌ Payout Dispatch Internal Error:", payoutError.message || payoutError);
            }
        }

        // Return state + M-Pesa reference so Flutter can save it
        res.status(200).json({ state: state, mpesaReference: mpesaRef });
    } catch (error) {
        console.error("❌ Grand Status Route Failure:", error.message || error);
        res.status(500).json({ error: "Failed to process payment status check pipeline" });
    }
});


// Mount the router under both '/api' and '/' to ensure robustness
app.use('/api', apiRouter);
app.use('/', apiRouter);

// Export as Firebase Cloud Function
exports.api = onRequest({ cors: true }, app);

// Run as standalone express app if run directly
if (require.main === module) {
    const PORT = process.env.PORT || 5000;
    app.listen(PORT, () => console.log(`🚀 Aggregator Payment Node running on port ${PORT}`));
}
