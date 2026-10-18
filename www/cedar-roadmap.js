/* Degree Explorer semester board: hover previews, chain highlighting and the
   connector overlay. Requirements, schedules and every prerequisite chain arrive
   from R in the board's JSON payload; this file only presents them. A click
   reports the tile to Shiny, which opens the standard CEDAR modal. */
(() => {
  const svgNS = 'http://www.w3.org/2000/svg';
  const splitIds = ids => (ids ? ids.split('|') : []);
  const modalOpen = () => document.body.classList.contains('modal-open');

  function initialize(root) {
    if (!root || root.dataset.ready) return;
    root.dataset.ready = 'true';
    const board = root.querySelector('.cedar-roadmap-board');
    const hover = root.querySelector('.cedar-roadmap-hover');
    const cards = [...root.querySelectorAll('[data-node]')];
    const byId = new Map(cards.map(card => [card.dataset.node, card]));
    const readJson = selector => JSON.parse(root.querySelector(selector).textContent);
    const links = readJson('.cedar-roadmap-links');
    const metadata = new Map([...readJson('.cedar-roadmap-node-data'), ...readJson('.cedar-roadmap-allowance-data')]
      .map(tile => [tile.node_id, tile]));
    const svg = document.createElementNS(svgNS, 'svg');
    svg.classList.add('cedar-roadmap-connectors');
    svg.setAttribute('aria-hidden', 'true');
    board.prepend(svg);

    let selected = null, hovered = null, focused = null, previewed = null;
    let restoreTimer, insidePreview = false, returningFocus = false, dismissed = false;
    let relevant = new Set(), upstream = new Set();

    // The tile itself plus its chain in each direction, as computed in R.
    function chain(card) {
      if (!card) return { before: new Set(), after: new Set() };
      const data = metadata.get(card.dataset.node);
      return {
        before: new Set([card.dataset.node, ...splitIds(data.upstream_ids)]),
        after: new Set([card.dataset.node, ...splitIds(data.downstream_ids)]),
      };
    }

    function draw() {
      if (!root.isConnected || !board.offsetWidth) return;
      const box = board.getBoundingClientRect();
      svg.setAttribute('width', board.scrollWidth);
      svg.setAttribute('height', board.scrollHeight);
      svg.replaceChildren();
      links.filter(link => relevant.has(link.from) && relevant.has(link.to)).forEach(link => {
        const fromCard = byId.get(link.from), toCard = byId.get(link.to);
        const from = fromCard.getBoundingClientRect(), to = toCard.getBoundingClientRect();
        const x1 = from.right - box.left, y1 = from.top + from.height / 2 - box.top;
        const x2 = to.left - box.left, y2 = to.top + to.height / 2 - box.top;
        const sameTerm = fromCard.dataset.semester === toCard.dataset.semester;
        const path = document.createElementNS(svgNS, 'path');
        path.dataset.from = link.from;
        path.dataset.to = link.to;
        path.setAttribute('d', sameTerm
          ? `M ${x1} ${y1} C ${x1 + 12} ${y1}, ${x1 + 12} ${y2}, ${to.right - box.left} ${y2}`
          : `M ${x1} ${y1} C ${x1 + 20} ${y1}, ${x2 - 20} ${y2}, ${x2} ${y2}`);
        if (link.timing === 'before_or_same') path.classList.add('cedar-roadmap-concurrent');
        path.classList.add(upstream.has(link.to) ? 'cedar-roadmap-link-before' : 'cedar-roadmap-link-after');
        const title = document.createElementNS(svgNS, 'title');
        title.textContent = `${fromCard.dataset.title} → ${toCard.dataset.title}`;
        path.append(title);
        svg.append(path);
        const arrow = document.createElementNS(svgNS, 'polygon');
        const endX = sameTerm ? to.right - box.left : x2;
        const tailX = endX + (sameTerm ? 6 : -6);
        arrow.setAttribute('points', `${endX},${y2} ${tailX},${y2 - 3} ${tailX},${y2 + 3}`);
        svg.append(arrow);
      });
    }

    function highlight(card) {
      const { before, after } = chain(card);
      const qualifying = new Set(card ? splitIds(metadata.get(card.dataset.node).qualifying_ids) : []);
      upstream = before;
      relevant = new Set([...before, ...after]);
      cards.forEach(c => {
        const id = c.dataset.node;
        c.classList.toggle('is-related', relevant.has(id));
        c.classList.toggle('is-selected', c === card);
        c.classList.toggle('is-muted', !!card && !relevant.has(id));
        c.classList.toggle('is-before', before.has(id) && c !== card);
        c.classList.toggle('is-after', after.has(id) && c !== card);
        c.classList.toggle('is-qualifying', qualifying.has(id));
        c.setAttribute('aria-pressed', c === selected ? 'true' : 'false');
      });
      root.dataset.chainNode = card?.dataset.node || '';
      draw();
      return { before, after };
    }

    function hidePreview() {
      clearTimeout(restoreTimer);
      previewed = null;
      insidePreview = false;
      hover.hidden = true;
      delete root.dataset.previewNode;
      cards.forEach(card => card.removeAttribute('aria-describedby'));
    }

    function positionPreview() {
      if (!previewed || hover.hidden) return;
      const anchor = previewed.getBoundingClientRect(), host = root.getBoundingClientRect();
      const pad = 12, gap = 10, width = hover.offsetWidth, scrollTop = hover.scrollTop;
      hover.style.maxHeight = '';
      let left = anchor.right + gap;
      if (left + width > document.documentElement.clientWidth - pad) left = anchor.left - gap - width;
      let top;
      if (left < pad) {
        // On narrow screens place the preview above/below, keeping the course
        // itself available to click. Long previews can scroll within that space.
        const above = anchor.top - gap - pad;
        const below = window.innerHeight - anchor.bottom - gap - pad;
        const useBelow = below >= above;
        hover.style.maxHeight = `${Math.max(48, useBelow ? below : above)}px`;
        top = useBelow ? anchor.bottom + gap : anchor.top - gap - hover.offsetHeight;
        left = anchor.left + (anchor.width - width) / 2;
      } else {
        top = Math.max(pad, Math.min(anchor.top, window.innerHeight - pad - hover.offsetHeight));
      }
      left = Math.max(pad, Math.min(left, document.documentElement.clientWidth - pad - width));
      hover.style.left = `${left - host.left}px`;
      hover.style.top = `${top - host.top}px`;
      hover.scrollTop = scrollTop;
    }

    function preview(card) {
      if (modalOpen() || !root.isConnected) return;
      clearTimeout(restoreTimer);
      previewed = card;
      const { before, after } = highlight(card);
      const data = metadata.get(card.dataset.node);
      const codes = set => cards.filter(c => c !== card && set.has(c.dataset.node))
        .map(c => metadata.get(c.dataset.node).code).join(', ');
      const unselected = ['choice', 'allowance'].includes(data.kind);
      hover.querySelector('.cedar-roadmap-hover-title').textContent = card.dataset.title;
      hover.querySelector('.cedar-roadmap-hover-before').textContent = codes(before) ||
        (unselected ? 'Depends on the course chosen; review the individual options.'
                    : 'No named prerequisite course shown in this route.');
      hover.querySelector('.cedar-roadmap-hover-after').textContent = codes(after) ||
        (data.kind === 'allowance' ? 'An unselected planning slot, with no catalog prerequisite arrows.'
                                   : 'No later course shown in this route.');
      const condition = hover.querySelector('.cedar-roadmap-hover-conditions');
      condition.hidden = !data.condition_label;
      condition.textContent = data.condition_label ? `◇ ${data.condition_label}` : '';
      const choices = hover.querySelector('.cedar-roadmap-hover-options');
      choices.hidden = !data.option_count && data.kind !== 'allowance';
      choices.textContent = data.kind === 'allowance' ? data.detail : (data.option_count
        ? [data.requirement_summary, `${data.option_label}: ${data.option_codes}`].filter(Boolean).join('. ') : '');
      cards.forEach(c => c.removeAttribute('aria-describedby'));
      card.setAttribute('aria-describedby', hover.id);
      root.dataset.previewNode = card.dataset.node;
      hover.hidden = false;
      positionPreview();
    }

    function restorePreview() {
      if (!root.isConnected || modalOpen() || insidePreview) return;
      if (hovered || focused) preview(hovered || focused);
      else { hidePreview(); highlight(selected); }
    }

    function deferRestore() {
      clearTimeout(restoreTimer);
      // Let the pointer cross the small gap into the readable preview.
      restoreTimer = setTimeout(restorePreview, 120);
    }

    cards.forEach(card => {
      card.addEventListener('pointerenter', event => {
        if (event.pointerType === 'touch' || modalOpen() || dismissed) return;
        hovered = card;
        preview(card);
      });
      card.addEventListener('pointerleave', () => {
        if (hovered === card) hovered = null;
        deferRestore();
      });
      card.addEventListener('focus', () => {
        if (returningFocus || modalOpen() || !card.matches(':focus-visible')) return;
        dismissed = false;
        focused = card;
        preview(card);
      });
      card.addEventListener('blur', () => {
        if (focused === card) focused = null;
        deferRestore();
      });
      card.addEventListener('click', () => {
        selected = card;
        hovered = null;
        focused = null;
        dismissed = false;
        hidePreview();
        highlight(card);
        root.dataset.modalPending = 'true';
        if (window.Shiny) window.Shiny.setInputValue(root.dataset.selectInput, {
          catalog_id: root.dataset.catalog, node_id: card.dataset.node, type: card.dataset.cardType,
          math_start: root.dataset.mathStart, english_start: root.dataset.englishStart,
          start_season: root.dataset.startSeason,
        }, { priority: 'event' });
      });
    });
    hover.addEventListener('pointerenter', () => { insidePreview = true; clearTimeout(restoreTimer); });
    hover.addEventListener('pointerleave', () => { insidePreview = false; deferRestore(); });

    // Closing the course popup returns keyboard focus to the tile that opened it.
    root.addEventListener('cedar:modal-closed', () => {
      if (!selected || !selected.isConnected) return;
      hovered = null;
      focused = null;
      returningFocus = true;
      selected.focus({ preventScroll: true });
      returningFocus = false;
      hidePreview();
      highlight(selected);
    });
    root.addEventListener('cedar:hide-preview', () => {
      if (modalOpen()) return;
      dismissed = true;
      hovered = null;
      focused = null;
      hidePreview();
      highlight(selected);
    });
    root.addEventListener('pointermove', event => {
      if (!dismissed || !(event.movementX || event.movementY) || event.pointerType === 'touch') return;
      dismissed = false;
      const card = event.target.closest('.cedar-roadmap-course');
      if (card) { hovered = card; preview(card); }
    });
    root.addEventListener('scroll', event => { if (event.target !== hover) positionPreview(); }, true);
    const observer = new ResizeObserver(() => {
      if (!root.isConnected) { observer.disconnect(); clearTimeout(restoreTimer); return; }
      draw();
      positionPreview();
    });
    observer.observe(board);
    highlight(null);
  }

  // The board's renderer calls initialize() once its markup is in place.
  window.CedarRoadmap = { initialize };

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') document.querySelectorAll('[data-roadmap][data-preview-node]')
      .forEach(root => root.dispatchEvent(new Event('cedar:hide-preview')));
  });
  // Bootstrap reports modal events through jQuery, which Shiny always loads.
  window.jQuery(document).on('hidden.bs.modal', () => {
    document.querySelectorAll('[data-roadmap][data-modal-pending]').forEach(root => {
      delete root.dataset.modalPending;
      root.dispatchEvent(new Event('cedar:modal-closed'));
    });
  });
  document.addEventListener('shown.bs.tab', () => window.dispatchEvent(new Event('resize')));
})();
