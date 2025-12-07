let isVisible = false;

const DOM = {
    ui: null,
    text: null
};

function getDOM() {
    if (!DOM.ui) {
        DOM.ui = document.getElementById('locker-ui');
        DOM.text = document.getElementById('locker-text');
    }
    return DOM;
}

function updatePosition(ui, x, y) {
    ui.style.left = x + 'px';
    ui.style.top = y + 'px';
}

const COLOR_MAP = {
    '~r~': '<span style="color: #ff4444;">',
    '~g~': '<span style="color: #44ff44;">',
    '~b~': '<span style="color: #00ffff;">',
    '~y~': '<span style="color: #ffff44;">',
    '~p~': '<span style="color: #ff44ff;">',
    '~c~': '<span style="color: #cccccc;">',
    '~m~': '<span style="color: #888888;">',
    '~u~': '<span style="color: #000000;">',
    '~o~': '<span style="color: #ff8844;">',
    '~eb~': '<span style="color: #0987ff;">',
    '~s~': '</span>',
    '~w~': '</span>'
};

const COLOR_REGEX = new RegExp(Object.keys(COLOR_MAP).map(code => code.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|'), 'g');

function parseColorCodes(text) {
    if (!text) return '';
    return text.replace(COLOR_REGEX, (match) => COLOR_MAP[match] || match);
}

window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (!data || !data.action || data.action === 'showAdmin' || data.action === 'hideAdmin' || data.action === 'characters') {
        return;
    }
    
    const dom = getDOM();
    if (!dom.ui || !dom.text) return;
    
    if (data.action === 'show') {
        if (data.text) {
            dom.text.innerHTML = parseColorCodes(data.text);
        }
        
        if (data.x !== undefined && data.y !== undefined) {
            updatePosition(dom.ui, data.x, data.y);
        }
        
        dom.ui.style.opacity = data.opacity !== undefined ? data.opacity : '1';
        
        if (!isVisible) {
            dom.ui.classList.remove('hidden');
            isVisible = true;
        }
    } else if (data.action === 'hide') {
        if (isVisible) {
            dom.ui.classList.add('hidden');
            isVisible = false;
        }
    }
});
