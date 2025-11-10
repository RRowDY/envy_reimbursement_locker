let adminUIVisible = false;

function showUI() {
    const ui = document.getElementById('admin-ui');
    if (!ui) {
        return;
    }
    
    ui.classList.remove('hidden');
    ui.classList.add('active');
    ui.style.display = 'flex';
    ui.style.opacity = '1';
    ui.style.visibility = 'visible';
    ui.style.zIndex = '999999';
    ui.style.pointerEvents = 'all';
    
    adminUIVisible = true;
    
    setTimeout(() => {
        const input = document.getElementById('license-input');
        if (input) {
            input.focus();
        }
        
        fetch(`https://${GetParentResourceName()}/uiReady`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ ready: true })
        }).catch(() => {});
    }, 100);
}

function hideUI() {
    const ui = document.getElementById('admin-ui');
    ui.classList.remove('active');
    setTimeout(() => {
        ui.classList.add('hidden');
    }, 200);
    adminUIVisible = false;
}

function showLoading() {
    document.getElementById('loading').classList.remove('hidden');
    document.getElementById('error-message').classList.add('hidden');
    document.getElementById('characters-list').classList.add('hidden');
}

function hideLoading() {
    document.getElementById('loading').classList.add('hidden');
}

function showError(message) {
    const errorEl = document.getElementById('error-message');
    errorEl.textContent = message;
    errorEl.classList.remove('hidden');
    document.getElementById('characters-list').classList.add('hidden');
}

function hideError() {
    document.getElementById('error-message').classList.add('hidden');
}

function displayCharacters(characters) {
    const grid = document.getElementById('characters-grid');
    grid.innerHTML = '';
    
    if (!characters || characters.length === 0) {
        showError('No characters found for this license.');
        return;
    }
    
    characters.forEach(char => {
        const card = document.createElement('div');
        card.className = 'character-card';
        card.innerHTML = `
            <div class="character-name">
                ${char.online ? '<span class="character-online"></span>' : '<span class="character-offline"></span>'}
                ${char.firstname} ${char.lastname}
            </div>
            <div class="character-identifier">${char.identifier}</div>
        `;
        
        card.addEventListener('click', () => {
            if (!char.identifier || typeof char.identifier !== 'string') {
                showError('Invalid character identifier.');
                return;
            }
            
            let identifier = char.identifier.replace(/[^a-zA-Z0-9:]/g, '');
            if (identifier.length === 0 || identifier.length > 128) {
                showError('Invalid character identifier format.');
                return;
            }
            
            fetch(`https://${GetParentResourceName()}/selectCharacter`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    identifier: identifier
                })
            }).catch(() => {
                showError('Failed to select character. Please try again.');
            });
        });
        
        grid.appendChild(card);
    });
    
    document.getElementById('characters-list').classList.remove('hidden');
    hideError();
}

window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (!data || !data.action) {
        return;
    }
    
    if (data.action === 'showAdmin') {
        showUI();
    } else if (data.action === 'hideAdmin') {
        hideUI();
    } else if (data.action === 'characters') {
        hideLoading();
        if (data.error) {
            showError(data.error);
        } else {
            displayCharacters(data.characters);
        }
    }
});

function notifyNUIReady() {
    try {
        const resourceName = GetParentResourceName();
        fetch(`https://${resourceName}/nuiReady`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ ready: true })
        }).catch(() => {});
    } catch (err) {}
}

if (typeof GetParentResourceName === 'function') {
    notifyNUIReady();
} else {
    setTimeout(() => {
        if (typeof GetParentResourceName === 'function') {
            notifyNUIReady();
        }
    }, 500);
}

function initEventListeners() {
    const closeBtn = document.getElementById('close-btn');
    const searchBtn = document.getElementById('search-btn');
    const licenseInput = document.getElementById('license-input');
    
    if (!closeBtn || !searchBtn || !licenseInput) {
        return;
    }
    
    closeBtn.addEventListener('click', () => {
        fetch(`https://${GetParentResourceName()}/closeAdmin`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            }
        });
        hideUI();
    });

    searchBtn.addEventListener('click', () => {
        let license = licenseInput.value.trim();
        if (!license) {
            showError('Please enter a license identifier.');
            return;
        }
        
        license = license.replace(/[^a-zA-Z0-9:]/g, '');
        
        if (license.length === 0 || license.length > 64) {
            showError('Invalid license format. Maximum 64 characters allowed.');
            return;
        }
        
        if (!/^[a-zA-Z0-9:]+$/.test(license)) {
            showError('Invalid license format. Only alphanumeric characters and colons allowed.');
            return;
        }
        
        showLoading();
        hideError();
        
        fetch(`https://${GetParentResourceName()}/searchLicense`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                license: license
            })
        }).catch(() => {
            hideLoading();
            showError('Failed to search. Please try again.');
        });
    });

    licenseInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            searchBtn.click();
        }
    });

    licenseInput.addEventListener('input', (e) => {
        let value = e.target.value;
        value = value.replace(/[^a-zA-Z0-9:]/g, '');
        if (value.length > 64) {
            value = value.substring(0, 64);
        }
        if (e.target.value !== value) {
            e.target.value = value;
        }
        hideError();
    });
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initEventListeners);
} else {
    initEventListeners();
}

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && adminUIVisible) {
        fetch(`https://${GetParentResourceName()}/closeAdmin`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            }
        });
        hideUI();
    }
});

