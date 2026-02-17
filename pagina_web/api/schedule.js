const admin = require('firebase-admin');

// Lazy initialization
function getDb() {
    if (!admin.apps.length) {
        const base64 = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64;

        if (!base64) {
            throw new Error('Missing FIREBASE_SERVICE_ACCOUNT_BASE64 env var');
        }

        // Decode base64 → JSON string → object
        const serviceAccount = JSON.parse(
            Buffer.from(base64, 'base64').toString('utf-8')
        );

        admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
        });
    }
    return admin.firestore();
}

module.exports = async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET');

    if (req.method !== 'GET') {
        return res.status(405).json({ error: 'Method not allowed' });
    }

    const { id } = req.query;

    if (!id) {
        return res.status(400).json({ error: 'Missing schedule ID' });
    }

    try {
        const db = getDb();
        const doc = await db.collection('shared_schedules').doc(id).get();

        if (!doc.exists) {
            return res.status(404).json({ error: 'Schedule not found' });
        }

        return res.status(200).json(doc.data());
    } catch (err) {
        console.error('Error fetching schedule:', err);
        return res.status(500).json({ error: err.message || 'Internal server error' });
    }
};
