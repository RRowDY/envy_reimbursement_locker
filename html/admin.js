let adminUIVisible = false;

const AdminDOM = {
    ui: null,
    loading: null,
    errorMessage: null,
    charactersList: null,
    charactersGrid: null,
    closeBtn: null,
    searchBtn: null,
    licenseInput: null
};

function getAdminDOM() {
    if (!AdminDOM.ui) {
        AdminDOM.ui = document.getElementById('admin-ui');
        AdminDOM.loading = document.getElementById('loading');
        AdminDOM.errorMessage = document.getElementById('error-message');
        AdminDOM.charactersList = document.getElementById('characters-list');
        AdminDOM.charactersGrid = document.getElementById('characters-grid');
        AdminDOM.closeBtn = document.getElementById('close-btn');
        AdminDOM.searchBtn = document.getElementById('search-btn');
        AdminDOM.licenseInput = document.getElementById('license-input');
    }
    return AdminDOM;
}

function showUI() {
    const dom = getAdminDOM();
    if (!dom.ui) {
        console.error('[envy_reimbursement_locker] Admin UI element not found');
        return;
    }
    
    dom.ui.classList.remove('hidden');
    dom.ui.classList.add('active');
    dom.ui.style.display = 'flex';
    dom.ui.style.opacity = '1';
    dom.ui.style.visibility = 'visible';
    dom.ui.style.zIndex = '999999';
    dom.ui.style.pointerEvents = 'all';
    
    adminUIVisible = true;
    
    setTimeout(() => {
        if (dom.licenseInput) {
            dom.licenseInput.focus();
        }
        
        if (typeof GetParentResourceName === 'function') {
            fetch(`https://${GetParentResourceName()}/uiReady`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ ready: true })
            }).catch(function(err) {
                console.error('[envy_reimbursement_locker] Failed to send uiReady:', err);
            });
        }
    }, 100);
}

function hideUI() {
    const dom = getAdminDOM();
    if (!dom.ui) return;
    
    dom.ui.classList.remove('active');
    setTimeout(() => {
        dom.ui.classList.add('hidden');
    }, 200);
    adminUIVisible = false;
}

function showLoading() {
    const dom = getAdminDOM();
    if (dom.loading) dom.loading.classList.remove('hidden');
    if (dom.errorMessage) dom.errorMessage.classList.add('hidden');
    if (dom.charactersList) dom.charactersList.classList.add('hidden');
}

function hideLoading() {
    const dom = getAdminDOM();
    if (dom.loading) dom.loading.classList.add('hidden');
}

function showError(message) {
    const dom = getAdminDOM();
    if (dom.errorMessage) {
        dom.errorMessage.textContent = message;
        dom.errorMessage.classList.remove('hidden');
    }
    if (dom.charactersList) dom.charactersList.classList.add('hidden');
}

function hideError() {
    const dom = getAdminDOM();
    if (dom.errorMessage) dom.errorMessage.classList.add('hidden');
}

function displayCharacters(characters) {
    const dom = getAdminDOM();
    if (!dom.charactersGrid) return;
    
    dom.charactersGrid.innerHTML = '';
    
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
            
            const identifier = char.identifier.replace(/[^a-zA-Z0-9:]/g, '');
            if (identifier.length === 0 || identifier.length > 128) {
                showError('Invalid character identifier format.');
                return;
            }
            
            fetch(`https://${GetParentResourceName()}/selectCharacter`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ identifier })
            }).catch(() => {
                showError('Failed to select character. Please try again.');
            });
        });
        
        dom.charactersGrid.appendChild(card);
    });
    
    if (dom.charactersList) dom.charactersList.classList.remove('hidden');
    hideError();
}

window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (!data || !data.action) return;
    
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
            headers: { 'Content-Type': 'application/json' },
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
    const dom = getAdminDOM();
    
    if (!dom.ui) {
        console.error('[envy_reimbursement_locker] Failed to initialize: admin-ui element not found');
        return;
    }
    
    if (!dom.closeBtn || !dom.searchBtn || !dom.licenseInput) {
        console.error('[envy_reimbursement_locker] Failed to initialize: required elements not found');
        return;
    }
    
    const sendCloseRequest = () => {
        fetch(`https://${GetParentResourceName()}/closeAdmin`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        });
        hideUI();
    };
    
    dom.closeBtn.addEventListener('click', sendCloseRequest);

    dom.searchBtn.addEventListener('click', () => {
        let license = dom.licenseInput.value.trim();
        if (!license) {
            showError('Please enter a license identifier.');
            return;
        }
        
        license = license.replace(/[^a-zA-Z0-9:]/g, '');
        
        if (license.length === 0 || license.length > 64) {
            showError('Invalid license format. Maximum 64 characters allowed.');
            return;
        }
        
        showLoading();
        hideError();
        
        fetch(`https://${GetParentResourceName()}/searchLicense`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ license })
        }).catch(() => {
            hideLoading();
            showError('Failed to search. Please try again.');
        });
    });

    dom.licenseInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            dom.searchBtn.click();
        }
    });

    dom.licenseInput.addEventListener('input', (e) => {
        let value = e.target.value.replace(/[^a-zA-Z0-9:]/g, '');
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
            headers: { 'Content-Type': 'application/json' }
        });
        hideUI();
    }
});
