module.exports = async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') return res.status(200).end();

    if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
    }

    const { actionCode, newPassword } = req.body;

    if (!actionCode || !newPassword) {
        return res.status(400).json({ error: 'Missing actionCode or newPassword' });
    }

    if (newPassword.length < 6) {
        return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }

    try {
        const apiKey = process.env.FIREBASE_API_KEY;

        if (!apiKey) {
            throw new Error('Missing FIREBASE_API_KEY env var');
        }

        const response = await fetch(
            `https://identitytoolkit.googleapis.com/v1/accounts:resetPassword?key=${apiKey}`,
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ oobCode: actionCode, newPassword }),
            }
        );

        const data = await response.json();

        if (data.error) {
            return res.status(400).json({ error: data.error.message });
        }

        return res.status(200).json({ success: true });
    } catch (err) {
        console.error('Error resetting password:', err);
        return res.status(500).json({ error: err.message || 'Internal server error' });
    }
};
