/* A shared semester-board renderer. All requirement/scheduling decisions arrive from R. */
(() => {
  const svgNS = 'http://www.w3.org/2000/svg';
  function initialize(root) {
    if (root.dataset.ready) return;
    root.dataset.ready = 'true';
    const board = root.querySelector('.cedar-roadmap-board');
    const cards = [...root.querySelectorAll('[data-node]')];
    const byId = new Map(cards.map(card => [card.dataset.node, card]));
    const links = JSON.parse(root.querySelector('.cedar-roadmap-links').textContent);
    const conditions = JSON.parse(root.querySelector('.cedar-roadmap-conditions').textContent);
    const options = JSON.parse(root.querySelector('.cedar-roadmap-options').textContent);
    const optionGroups = JSON.parse(root.querySelector('.cedar-roadmap-option-groups').textContent);
    const metadata = new Map([
      ...JSON.parse(root.querySelector('.cedar-roadmap-node-data').textContent),
      ...JSON.parse(root.querySelector('.cedar-roadmap-allowance-data').textContent),
    ].map(n => [n.node_id, n]));
    const svg = document.createElementNS(svgNS, 'svg');
    svg.classList.add('cedar-roadmap-connectors');
    svg.setAttribute('aria-hidden', 'true');
    board.prepend(svg);
    let selected = null, hovered = null, focused = null, previewed = null;
    let restoreTimer, insidePreview = false, returningFocus = false, dismissed = false;
    const hover = root.querySelector('.cedar-roadmap-hover');
    const dialog = root.querySelector('.cedar-roadmap-dialog');
    root.querySelectorAll('.cedar-roadmap-close').forEach(button =>
      button.addEventListener('click', () => dialog.close()));
    dialog.addEventListener('close', () => {
      document.body.classList.remove('cedar-course-modal-open');
      hovered = null; focused = null;
      returningFocus = true;
      selected.focus({ preventScroll: true });
      returningFocus = false;
      hidePreview();
      highlight(selected);
    });
    dialog.addEventListener('click', event => { if (event.target === dialog) {
      const box = dialog.getBoundingClientRect();
      if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) dialog.close();
    }});
    let relevant = new Set(), beforeNodes = new Set();
    function traverse(id, forward) {
      const seen = new Set([id]);
      const queue = [id];
      while (queue.length) {
        const current = queue.shift();
        links.forEach(link => {
          const next = forward ? (link.from === current && link.to) : (link.to === current && link.from);
          if (next && !seen.has(next)) { seen.add(next); queue.push(next); }
        });
      }
      return seen;
    }
    function draw() {
      if (!root.isConnected || !board.offsetWidth) return;
      const box = board.getBoundingClientRect();
      svg.setAttribute('width', board.scrollWidth);
      svg.setAttribute('height', board.scrollHeight);
      svg.replaceChildren();
      links.filter(link => relevant.has(link.from) && relevant.has(link.to)).forEach(link => {
        const from = byId.get(link.from).getBoundingClientRect();
        const to = byId.get(link.to).getBoundingClientRect();
        const x1 = from.right - box.left, y1 = from.top + from.height / 2 - box.top;
        const x2 = to.left - box.left, y2 = to.top + to.height / 2 - box.top;
        const sameTerm = byId.get(link.from).dataset.semester === byId.get(link.to).dataset.semester;
        const path = document.createElementNS(svgNS, 'path');
        path.dataset.from = link.from; path.dataset.to = link.to;
        path.setAttribute('d', sameTerm
          ? `M ${x1} ${y1} C ${x1 + 12} ${y1}, ${x1 + 12} ${y2}, ${to.right - box.left} ${y2}`
          : `M ${x1} ${y1} C ${x1 + 20} ${y1}, ${x2 - 20} ${y2}, ${x2} ${y2}`);
        if (link.timing === 'before_or_same') path.classList.add('cedar-roadmap-concurrent');
        path.classList.add(beforeNodes.has(link.to) ? 'cedar-roadmap-link-before' : 'cedar-roadmap-link-after');
        const title = document.createElementNS(svgNS, 'title');
        title.textContent = `${byId.get(link.from).dataset.title} → ${byId.get(link.to).dataset.title}`;
        path.append(title); svg.append(path);
        const arrow = document.createElementNS(svgNS, 'polygon');
        const endX = sameTerm ? to.right - box.left : x2;
        const tailX = endX + (sameTerm ? 6 : -6);
        arrow.setAttribute('points', `${endX},${y2} ${tailX},${y2 - 3} ${tailX},${y2 + 3}`);
        svg.append(arrow);
      });
    }
    function highlight(card) {
      const before = card ? traverse(card.dataset.node, false) : new Set();
      const after = card ? traverse(card.dataset.node, true) : new Set();
      const activeConditions = conditions.filter(condition => condition.node_id === card?.dataset.node);
      const qualifying = new Set(activeConditions.flatMap(condition => condition.eligible_node_ids.split('|')).filter(Boolean));
      beforeNodes = before;
      relevant = new Set([...before, ...after]);
      cards.forEach(c => {
        c.classList.toggle('is-related', relevant.has(c.dataset.node));
        c.classList.toggle('is-selected', c === card);
        c.classList.toggle('is-muted', !!card && !relevant.has(c.dataset.node));
        c.classList.toggle('is-before', before.has(c.dataset.node) && c !== card);
        c.classList.toggle('is-after', after.has(c.dataset.node) && c !== card);
        c.classList.toggle('is-qualifying', qualifying.has(c.dataset.node));
        c.setAttribute('aria-pressed', c === selected ? 'true' : 'false');
      });
      root.dataset.chainNode = card?.dataset.node || '';
      draw();
      return { before, after };
    }
    function hidePreview() {
      clearTimeout(restoreTimer);
      previewed = null; insidePreview = false;
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
      } else top = Math.max(pad, Math.min(anchor.top, window.innerHeight - pad - hover.offsetHeight));
      left = Math.max(pad, Math.min(left, document.documentElement.clientWidth - pad - width));
      hover.style.left = `${left - host.left}px`;
      hover.style.top = `${top - host.top}px`;
      hover.scrollTop = scrollTop;
    }
    function preview(card) {
      if (dialog.open || !root.isConnected) return;
      clearTimeout(restoreTimer);
      previewed = card;
      const { before, after } = highlight(card);
      const data = metadata.get(card.dataset.node);
      const codes = set => cards.filter(c => c !== card && set.has(c.dataset.node))
        .map(c => metadata.get(c.dataset.node).code).join(', ');
      hover.querySelector('.cedar-roadmap-hover-title').textContent = card.dataset.title;
      hover.querySelector('.cedar-roadmap-hover-before').textContent = codes(before) ||
        (['choice', 'allowance'].includes(data.kind) ? 'Depends on the course chosen; review the individual options.' : 'No named prerequisite course shown in this route.');
      hover.querySelector('.cedar-roadmap-hover-after').textContent = codes(after) ||
        (data.kind === 'allowance' ? 'An unselected planning slot, with no catalog prerequisite arrows.' : 'No later course shown in this route.');
      const condition = hover.querySelector('.cedar-roadmap-hover-conditions');
      condition.hidden = !data.condition_label;
      condition.textContent = data.condition_label ? `◇ ${data.condition_label}` : '';
      const choices = hover.querySelector('.cedar-roadmap-hover-options');
      choices.hidden = !data.option_count && data.kind !== 'allowance';
      choices.textContent = data.kind === 'allowance' ? data.detail :
        (data.option_count ? [data.requirement_summary, `${data.option_label}: ${data.option_codes}`].filter(Boolean).join('. ') : '');
      cards.forEach(c => c.removeAttribute('aria-describedby'));
      card.setAttribute('aria-describedby', hover.id);
      root.dataset.previewNode = card.dataset.node;
      hover.hidden = false;
      positionPreview();
    }
    function restorePreview() {
      if (!root.isConnected || dialog.open || insidePreview) return;
      if (hovered || focused) preview(hovered || focused);
      else { hidePreview(); highlight(selected); }
    }
    function deferRestore() {
      clearTimeout(restoreTimer);
      // Let the pointer cross the small gap into the readable preview.
      restoreTimer = setTimeout(restorePreview, 120);
    }
    function populateDetails(card) {
      const activeConditions = conditions.filter(condition => condition.node_id === card.dataset.node);
      root.querySelector('.cedar-roadmap-detail-title').textContent = card.dataset.title;
      const data = metadata.get(card.dataset.node);
      const detail = root.querySelector('.cedar-roadmap-detail');
      const courseLink = root.querySelector('.cedar-roadmap-detail-course');
      const summary = root.querySelector('.cedar-roadmap-dialog-summary');
      detail.hidden = data.kind === 'allowance';
      if (data.kind === 'allowance') {
        summary.hidden = false; summary.textContent = `${data.credits} credits reserved · ${data.season_label} examples · no course selected.`;
        courseLink.href = data.source_url; courseLink.textContent = 'Current Gen Ed course list ↗';
        return;
      }
      summary.hidden = !data.requirement_summary;
      summary.textContent = data.requirement_summary ? `${data.requirement_summary}. ${data.option_label}. Full choices and paired labs appear below the offering history.` : '';
      root.querySelector('.cedar-roadmap-detail-text').textContent = `${data.detail} ${data.requisite_note}`;
      courseLink.href = data.source_url;
      courseLink.textContent = data.kind === 'choice' ? 'Course group details ↗' : 'Course description ↗';
      root.querySelector('.cedar-roadmap-evidence-basis').textContent = data.basis_explanation;
      const location = root.querySelector('.cedar-roadmap-evidence-location');
      location.textContent = `${data.evidence_section} ↗`;
      location.href = data.evidence_source_url;
      root.querySelector('.cedar-roadmap-evidence-quote').textContent = data.evidence_quote;
      root.querySelector('.cedar-roadmap-evidence-stamp').textContent = `${data.evidence_catalog_year} · retrieved ${data.evidence_retrieved_on} · ${data.evidence_review_status}`;
      root.querySelector('.cedar-roadmap-evidence-note').textContent = data.evidence_note;
      root.querySelector('.cedar-roadmap-evidence').dataset.review = data.evidence_review_status;
      root.querySelector('.cedar-roadmap-chain-detail').textContent = [data.planning_note, data.chain_note].filter(Boolean).join(' ');
      const conditionDetail = root.querySelector('.cedar-roadmap-condition-detail');
      conditionDetail.replaceChildren();
      activeConditions.forEach(condition => {
        const block = document.createElement('div');
        const label = document.createElement('strong');
        label.textContent = `◇ ${condition.label}`;
        const citation = document.createElement('a');
        citation.textContent = `${condition.section} ↗`;
        citation.href = condition.source_url; citation.target = '_blank'; citation.rel = 'noopener noreferrer';
        const quote = document.createElement('q'); quote.textContent = condition.quote;
        block.append(label, citation, quote); conditionDetail.append(block);
      });
      const optionDetail = root.querySelector('.cedar-roadmap-option-detail');
      optionDetail.replaceChildren();
      const groups = optionGroups.filter(option => option.node_id === card.dataset.node);
      if (groups.length) {
        const heading = document.createElement('h4'); heading.textContent = data.option_label;
        const summary = document.createElement('p'); summary.textContent = [data.requirement_summary, data.detail].filter(Boolean).join('. ');
        const list = document.createElement('ul');
        groups.forEach(group => {
          const item = document.createElement('li');
          item.dataset.option = group.option_id;
          if (group.component_count > 1) {
            const label = document.createElement('strong');
            label.textContent = `${group.option_code} · ${group.credit_label} credits together`;
            item.append(label);
          }
          options.filter(option => option.node_id === card.dataset.node && option.option_id === group.option_id).forEach(option => {
            const component = document.createElement('div');
            const link = document.createElement('a');
            link.href = option.source_url; link.target = '_blank'; link.rel = 'noopener noreferrer';
            link.textContent = `${option.subject_course} — ${option.course_title} (${option.credit_label} credits · ${option.course_level}-level) ↗`;
            component.append(link);
            if (option.prerequisite_note) {
              const note = document.createElement('p');
              note.textContent = `Course prerequisite: ${option.prerequisite_note}`; component.append(note);
            }
            item.append(component);
          });
          list.append(item);
        });
        optionDetail.append(heading, summary, list);
      }

    }
    cards.forEach(card => {
      card.addEventListener('pointerenter', event => {
        if (event.pointerType === 'touch' || dialog.open || dismissed) return;
        hovered = card; preview(card);
      });
      card.addEventListener('pointerleave', () => {
        if (hovered === card) hovered = null;
        deferRestore();
      });
      card.addEventListener('focus', () => {
        if (returningFocus || dialog.open || !card.matches(':focus-visible')) return;
        dismissed = false;
        focused = card; preview(card);
      });
      card.addEventListener('blur', () => {
        if (focused === card) focused = null;
        deferRestore();
      });
      card.addEventListener('click', () => {
        selected = card; hovered = null; focused = null; dismissed = false;
        hidePreview(); highlight(card); populateDetails(card);
        const history = root.querySelector('.cedar-roadmap-history');
        if (card.dataset.cardType === 'allowance' || !history.querySelector(`[data-history-node="${card.dataset.node}"]`)) {
          history.textContent = card.dataset.cardType === 'allowance' ? 'Loading course suggestions…' : 'Loading offering history…';
        }
        dialog.showModal();
        dialog.querySelector('.cedar-roadmap-dialog-body').scrollTop = 0;
        document.body.classList.add('cedar-course-modal-open');
        if (window.Shiny) window.Shiny.setInputValue(root.dataset.selectInput,
          { catalog_id: root.dataset.catalog, node_id: card.dataset.node, type: card.dataset.cardType,
            math_start: root.dataset.mathStart, english_start: root.dataset.englishStart,
            start_season: root.dataset.startSeason }, { priority: 'event' });
      });
    });
    hover.addEventListener('pointerenter', () => { insidePreview = true; clearTimeout(restoreTimer); });
    hover.addEventListener('pointerleave', () => { insidePreview = false; deferRestore(); });
    root.addEventListener('cedar:hide-preview', () => {
      if (!dialog.open) {
        dismissed = true;
        hovered = null; focused = null;
        hidePreview(); highlight(selected);
      }
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
      draw(); positionPreview();
    });
    observer.observe(board);
    highlight(null);
  }
  function scan() {
    document.querySelectorAll('[data-roadmap]').forEach(initialize);
    if (document.body && !document.querySelector('.cedar-roadmap-dialog[open]')) {
      document.body.classList.remove('cedar-course-modal-open');
    }
  }
  new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', scan); else scan();
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') document.querySelectorAll('[data-roadmap][data-preview-node]')
      .forEach(root => root.dispatchEvent(new Event('cedar:hide-preview')));
  });
  document.addEventListener('shown.bs.tab', () => window.dispatchEvent(new Event('resize')));
})();
