// ---- Helpers ----
function getParameterByName(name) {
    const url = window.location.href;
    name = name.replace(/[\[\]]/g, '\\$&');
    const regex = new RegExp('[?&]' + name + '(=([^&#]*)|&|#|$)');
    const results = regex.exec(url);
    if (!results) return null;
    if (!results[2]) return '';
    return decodeURIComponent(results[2].replace(/\+/g, ' '));
}

function getShareCode() {
    const path = window.location.pathname;
    const parts = path.split('/');
    const code = parts[parts.length - 1];
    if (code && code !== 'p' && code !== '') {
        return code;
    }
    return null;
}

// ---- Init ----
document.addEventListener('DOMContentLoaded', async () => {
    const mode = getParameterByName('mode');
    const actionCode = getParameterByName('oobCode');

    // Password reset
    if (mode === 'resetPassword' && actionCode) {
        document.getElementById('message').innerText = 'Ingresa tu nueva contraseña';
        document.getElementById('app-actions').style.display = 'none';
        document.getElementById('reset-password-container').style.display = 'block';
        return;
    }

    // Shared semester code
    const shareCode = getShareCode();
    if (shareCode && shareCode.startsWith('share_')) {
        const realId = shareCode.replace('share_', '');
        document.getElementById('share-code-text').innerText = realId;
        document.getElementById('share-code-container').style.display = 'block';
        document.getElementById('message').innerText = 'Alguien te compartió un semestre';
    }

    tryOpenApp();
});

// ---- Password Reset via Server API ----
async function handleResetPassword() {
    const newPassword = document.getElementById('new-password').value;
    const actionCode = getParameterByName('oobCode');

    if (!newPassword) {
        alert('Por favor ingresa una contraseña');
        return;
    }

    if (newPassword.length < 6) {
        alert('La contraseña debe tener al menos 6 caracteres');
        return;
    }

    try {
        const response = await fetch('/api/reset-password', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ actionCode, newPassword }),
        });

        const data = await response.json();

        if (!response.ok) {
            throw new Error(data.error || 'Error desconocido');
        }

        alert('Contraseña actualizada correctamente. Ya puedes iniciar sesión en la app.');
        document.getElementById('message').innerText = '✅ Contraseña actualizada.';
        document.getElementById('reset-password-container').style.display = 'none';
    } catch (error) {
        alert('Error: ' + error.message);
    }
}

// ---- Copy Share Code ----
function copyShareCode() {
    const code = document.getElementById('share-code-text').innerText;
    navigator.clipboard.writeText(code).then(() => {
        const btn = document.querySelector('.copy-btn');
        btn.innerText = '✅';
        setTimeout(() => { btn.innerText = '📋'; }, 2000);
    }).catch(() => {
        const temp = document.createElement('textarea');
        temp.value = code;
        document.body.appendChild(temp);
        temp.select();
        document.execCommand('copy');
        document.body.removeChild(temp);
        const btn = document.querySelector('.copy-btn');
        btn.innerText = '✅';
        setTimeout(() => { btn.innerText = '📋'; }, 2000);
    });
}

// ---- Deep Link ----
function tryOpenApp() {
    const path = window.location.pathname;
    const parts = path.split('/');
    const code = parts[parts.length - 1];

    if (code && code !== 'p' && code !== '') {
        const deepLink = `calendario://app/p/${code}${window.location.search}`;
        console.log("Intentando abrir:", deepLink);

        window.location.href = deepLink;

        setTimeout(() => {
            document.getElementById('message').innerText =
                "Si la app no se abre, usa el código de arriba para importar manualmente.";
        }, 2500);
    }
}
