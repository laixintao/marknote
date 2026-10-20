// Shared by the offline preview and standalone HTML exports.
function enableDiagramViewer(diagram) {
    const chinese = document.documentElement.lang.startsWith('zh');
    const words = chinese
        ? {open:'放大查看', close:'关闭', fit:'适应窗口', plus:'放大', minus:'缩小', hint:'滚轮缩放 · 拖动平移 · Esc 关闭'}
        : {open:'Enlarge diagram', close:'Close', fit:'Fit', plus:'Zoom in', minus:'Zoom out', hint:'Scroll to zoom · Drag to pan · Esc to close'};
    const opener = document.createElement('button');
    opener.className = 'diagram-open';
    opener.type = 'button';
    opener.textContent = words.open;
    diagram.append(opener);
    function openViewer() {
        if (document.querySelector('.diagram-viewer')) return;
        const svg = diagram.querySelector('svg');
        const dialog = document.createElement('dialog');
        dialog.className = 'diagram-viewer';
        dialog.setAttribute('aria-label', words.open);
        const toolbar = document.createElement('div');
        toolbar.className = 'diagram-toolbar';
        const stage = document.createElement('div');
        stage.className = 'diagram-stage';
        const amount = document.createElement('output');
        amount.setAttribute('aria-live', 'polite');
        const hint = document.createElement('span');
        hint.className = 'diagram-hint';
        hint.textContent = words.hint;
        let scale = 1, x = 0, y = 0, drag = null;
        const originalStyle = svg.getAttribute('style');
        const box = svg.viewBox.baseVal;
        const bounds = svg.getBoundingClientRect();
        const width = box.width || bounds.width || 800;
        const height = box.height || bounds.height || 600;
        function draw() {
            svg.style.transform = `translate(${x}px, ${y}px) scale(${scale})`;
            amount.textContent = Math.round(scale * 100) + '%';
        }
        function zoom(factor, cx = stage.clientWidth / 2, cy = stage.clientHeight / 2) {
            const next = Math.min(8, Math.max(0.05, scale * factor));
            x = cx - (cx - x) * next / scale;
            y = cy - (cy - y) * next / scale;
            scale = next;
            draw();
        }
        function fit() {
            scale = Math.min(1, Math.max(0.05, Math.min((stage.clientWidth - 48) / width, (stage.clientHeight - 48) / height)));
            x = (stage.clientWidth - width * scale) / 2;
            y = (stage.clientHeight - height * scale) / 2;
            draw();
        }
        function button(label, text, action) {
            const item = document.createElement('button');
            item.type = 'button';
            item.textContent = text;
            item.title = label;
            item.setAttribute('aria-label', label);
            item.addEventListener('click', action);
            toolbar.append(item);
            return item;
        }
        button(words.minus, '−', () => zoom(1 / 1.25));
        toolbar.append(amount);
        button(words.plus, '+', () => zoom(1.25));
        button(words.fit, words.fit, fit);
        toolbar.append(hint);
        const close = button(words.close, words.close, () => dialog.close());
        dialog.append(toolbar, stage);
        document.body.append(dialog);
        // Move the SVG instead of cloning it, preserving unique marker/style IDs.
        stage.append(svg);
        svg.style.width = width + 'px';
        svg.style.height = height + 'px';
        svg.style.maxWidth = 'none';
        dialog.showModal();
        fit();
        close.focus();
        stage.addEventListener('wheel', event => {
            event.preventDefault();
            const rect = stage.getBoundingClientRect();
            zoom(Math.exp(-Math.max(-100, Math.min(100, event.deltaY)) * 0.005), event.clientX - rect.left, event.clientY - rect.top);
        }, {passive:false});
        stage.addEventListener('pointerdown', event => {
            if (event.button !== 0) return;
            event.preventDefault();
            drag = {id:event.pointerId, x:event.clientX, y:event.clientY};
            stage.setPointerCapture(event.pointerId);
            stage.classList.add('dragging');
        });
        stage.addEventListener('pointermove', event => {
            if (!drag || drag.id !== event.pointerId) return;
            x += event.clientX - drag.x;
            y += event.clientY - drag.y;
            drag.x = event.clientX;
            drag.y = event.clientY;
            draw();
        });
        function stopDrag() { drag = null; stage.classList.remove('dragging'); }
        stage.addEventListener('pointerup', stopDrag);
        stage.addEventListener('pointercancel', stopDrag);
        stage.addEventListener('lostpointercapture', stopDrag);
        dialog.addEventListener('keydown', event => {
            if (event.key === '+' || event.key === '=') { event.preventDefault(); zoom(1.25); }
            if (event.key === '-') { event.preventDefault(); zoom(1 / 1.25); }
            if (event.key === '0') { event.preventDefault(); fit(); }
        });
        const beforePrint = () => dialog.close();
        window.addEventListener('resize', fit);
        window.addEventListener('beforeprint', beforePrint);
        dialog.addEventListener('close', () => {
            diagram.prepend(svg);
            if (originalStyle === null) svg.removeAttribute('style');
            else svg.setAttribute('style', originalStyle);
            window.removeEventListener('resize', fit);
            window.removeEventListener('beforeprint', beforePrint);
            dialog.remove();
            opener.focus({preventScroll:true});
        }, {once:true});
    }
    opener.addEventListener('click', openViewer);
    diagram.addEventListener('click', event => {
        if (event.target.closest('svg') && !event.target.closest('a')) openViewer();
    });
}
