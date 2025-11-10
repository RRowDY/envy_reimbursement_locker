let isVisible = false;

function updatePosition(ui, x, y) {
    ui.style.left = x + 'px';
    ui.style.top = y + 'px';
}

function parseColorCodes(text) {
    if (!text) return '';
    
    const colorMap = {
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
    
    let htmlText = text;
    for (const [code, replacement] of Object.entries(colorMap)) {
        htmlText = htmlText.replace(new RegExp(code.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'), replacement);
    }
    
    return htmlText;
}

window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (data.action === 'showAdmin' || data.action === 'hideAdmin' || data.action === 'characters') {
        return;
    }
    
    const ui = document.getElementById('locker-ui');
    const text = document.getElementById('locker-text');
    
    if (data.action === 'show') {
        if (data.text) {
            text.innerHTML = parseColorCodes(data.text);
        }
        
        if (data.x !== undefined && data.y !== undefined) {
            updatePosition(ui, data.x, data.y);
        }
        
        if (data.opacity !== undefined) {
            ui.style.opacity = data.opacity;
        } else {
            ui.style.opacity = '1';
        }
        
        if (!isVisible) {
            ui.classList.remove('hidden');
            isVisible = true;
        }
    } else if (data.action === 'hide') {
        if (isVisible) {
            ui.classList.add('hidden');
            isVisible = false;
        }
    }
});

