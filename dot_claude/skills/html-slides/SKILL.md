---
name: html-slides
description: >
  Create a single-file HTML slide deck in a spartan monospace style (IBM Plex Mono,
  dynamical.org aesthetic). Use this skill any time the user asks for "slides", "a deck",
  "a presentation", "HTML slides", or wants to present information in a slide-by-slide format.
  Also trigger when the user says things like "make this into slides", "put this in a deck",
  or "I want to walk someone through X". Produces a fully self-contained .html file with
  keyboard navigation (arrow keys), dot indicators, and responsive layout. No frameworks,
  no build step — just open the file.
---

# HTML Slides Skill

You are creating a single-file HTML presentation in the dynamical.org aesthetic:
IBM Plex Mono throughout, minimal borders, CSS custom properties for light/dark mode,
native HTML elements only (tables, blockquotes, etc.), no custom UI libraries.

## Output

Save the file to the workspace folder and provide a `computer://` link. The file should
be fully self-contained — no external assets other than the Google Fonts CDN import for
IBM Plex Mono.

## Visual system

Use exactly this CSS foundation (copy verbatim into every deck):

```css
*, *::before, *::after { box-sizing: border-box; }

:root {
  color-scheme: light dark;
  --bg:        #ffffff;
  --text:      #111111;
  --muted:     #666666;
  --border:    #111111;
  --border-md: #444444;
  --accent:    #0b57d0;
  --slide-max: 860px;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg:        #0f0f10;
    --text:      #e8e8ea;
    --muted:     #b5b5b5;
    --border:    #e8e8ea;
    --border-md: #555558;
    --accent:    #8ab4f8;
  }
}

html { font-size: 62.5%; scroll-behavior: smooth; }

body {
  font-family: 'IBM Plex Mono', monospace;
  font-size: 1.4rem;
  line-height: 1.6;
  background: var(--bg);
  color: var(--text);
  margin: 0; padding: 0;
}
```

## Slide structure

The deck uses a **scroll-flow layout**: all slides live in the normal document flow, each
taking at least the full viewport height. The active slide is fully opaque; inactive slides
are dimmed. Navigating with prev/next or arrow keys smoothly scrolls the target slide into
view. This means the deck also prints cleanly — each slide lands on its own page.

```html
<div id="deck">
  <div id="slides">
    <div class="slide active" id="s1">…</div>
    <div class="slide" id="s2">…</div>
  </div>
  <div id="nav">
    <button id="prev" onclick="go(-1)" disabled>← prev</button>
    <div style="display:flex; align-items:center; gap:1.6rem;">
      <div id="dots"></div>
      <span id="counter">1 / N</span>
    </div>
    <button id="next" onclick="go(1)">next →</button>
  </div>
</div>
```

Each slide has a `.slide-inner` div (max-width: var(--slide-max); margin: 0 auto) and
starts with a `.slide-label` showing `NN / TT — Section Name`.

## Slide CSS

```css
.slide {
  min-height: 100vh;
  padding: 4rem 5rem;
  opacity: 0.12;
  transition: opacity 0.3s ease;
}
.slide.active { opacity: 1; }
.slide-inner { max-width: var(--slide-max); margin: 0 auto; }
.slide-label {
  font-size: 1.2rem; color: var(--muted); text-transform: uppercase;
  letter-spacing: 0.08em; margin-bottom: 2.4rem; padding-bottom: 1.2rem;
  border-bottom: 1px solid var(--border-md);
}
h1 { font-size: 2.4rem; font-weight: 700; margin: 0 0 0.4rem; }
h2 { font-size: 1.6rem; font-weight: 700; margin: 2.4rem 0 0.8rem; }
p  { margin: 0 0 1.2rem; }
```

## Navigation CSS

```css
#nav {
  position: sticky;
  bottom: 0;
  z-index: 10;
  background: var(--bg);
  display: flex; align-items: center; justify-content: space-between;
  padding: 1rem 5rem;
  border-top: 1px solid var(--border-md);
  font-size: 1.2rem;
}
#nav button {
  font-family: inherit; font-size: 1.2rem;
  background: none; border: 1px solid var(--border-md);
  color: var(--text); padding: 0.4rem 1.2rem; cursor: pointer;
}
#nav button:hover { border-color: var(--border); }
#nav button:disabled { opacity: 0.3; cursor: default; }
.dot { width: 6px; height: 6px; border-radius: 50%; background: var(--border-md); cursor: pointer; }
.dot.active { background: var(--text); }
#dots { display: flex; gap: 0.8rem; align-items: center; }
```

## Navigation JavaScript

```js
const slides = document.querySelectorAll('.slide');
const counter = document.getElementById('counter');
const prevBtn = document.getElementById('prev');
const nextBtn = document.getElementById('next');
const dotsEl  = document.getElementById('dots');
let cur = 0;

slides.forEach((_, i) => {
  const d = document.createElement('span');
  d.className = 'dot' + (i === 0 ? ' active' : '');
  d.onclick = () => showSlide(i);
  dotsEl.appendChild(d);
});

function showSlide(n) {
  slides[cur].classList.remove('active');
  dotsEl.children[cur].classList.remove('active');
  cur = Math.max(0, Math.min(n, slides.length - 1));
  slides[cur].classList.add('active');
  dotsEl.children[cur].classList.add('active');
  slides[cur].scrollIntoView({ behavior: 'smooth', block: 'start' });
  counter.textContent = (cur + 1) + ' / ' + slides.length;
  prevBtn.disabled = cur === 0;
  nextBtn.disabled = cur === slides.length - 1;
}

function go(dir) { showSlide(cur + dir); }

document.addEventListener('keydown', e => {
  if (e.key === 'ArrowRight' || e.key === 'ArrowDown') { e.preventDefault(); go(1); }
  if (e.key === 'ArrowLeft'  || e.key === 'ArrowUp')   { e.preventDefault(); go(-1); }
});

// Sync active state when user scrolls manually
const observer = new IntersectionObserver(entries => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      const i = Array.from(slides).indexOf(entry.target);
      if (i !== cur) {
        slides[cur].classList.remove('active');
        dotsEl.children[cur].classList.remove('active');
        cur = i;
        slides[cur].classList.add('active');
        dotsEl.children[cur].classList.add('active');
        counter.textContent = (cur + 1) + ' / ' + slides.length;
        prevBtn.disabled = cur === 0;
        nextBtn.disabled = cur === slides.length - 1;
      }
    }
  });
}, { threshold: 0.5 });

slides.forEach(s => observer.observe(s));
```

## Print to PDF

Because slides are in normal document flow, browser print (Cmd+P / Ctrl+P) works cleanly.
Add this `@media print` block to make each slide its own page:

```css
@media print {
  #nav { display: none; }
  .slide {
    opacity: 1 !important;
    min-height: 0;
    break-before: page;
    padding: 3rem 4rem;
  }
  .slide:first-child { break-before: avoid; }
}
```

**To export as PDF:**
1. Open the HTML file in Chrome or Safari
2. Press Cmd+P (Mac) or Ctrl+P (Windows)
3. Set paper size to match your slide dimensions (e.g. A4 landscape, or custom 1280×720px)
4. Disable "Headers and footers"
5. Enable "Background graphics"
6. Save as PDF

Each slide lands on its own page. No headless browser or build step required.

## Content components

Use these patterns to present content. All are implemented with plain CSS — no JS needed.

### Slide label (always first inside .slide-inner)
```html
<div class="slide-label">01 / 05 — Section Name</div>
<h1>Slide Title</h1>
```

### Callout box (for key findings, warnings, headlines)
```html
<div class="callout">
  <strong>The main point in one line</strong>
  Supporting detail here.
</div>
```
Style: `border: 1px solid var(--border); padding: 1.4rem 1.8rem; margin: 1.6rem 0;`

### Note / blockquote (ONLY for quoting an external source)
```html
<div class="note">"Quoted text from an external source." — Source name</div>
```
Style: `border-left: 2px solid var(--border-md); padding-left: 1rem; font-size: 1.2rem; color: var(--muted);`

The left-border style reads as a blockquote, so reserve `.note` for actual quotations from an external source. Do NOT use it for your own caveats, annotations, or secondary context — that's what `.small-note` is for (fine print, no border). It's an easy style to overuse; default to a plain `<p>` or `.small-note` and reach for `.note` only when there's a source to attribute.

### Data table
```html
<div class="table-wrap">
  <table>
    <thead><tr><th>Label</th><th>Value</th></tr></thead>
    <tbody>
      <tr><td>Row</td><td>Data</td></tr>
    </tbody>
  </table>
</div>
```
Style: `border-collapse: collapse; font-size: 1.3rem;` — td/th: `padding: 6px 16px; border-bottom: 1px dotted var(--border-md); text-align: right;` — first column left-aligned — thead th gets `border-bottom: 1px solid var(--border);`

### Two-column layout
```html
<div class="cols">
  <div class="col-block">
    <div class="col-label">Left heading</div>
    <p>Content here.</p>
  </div>
  <div class="col-block">
    <div class="col-label">Right heading</div>
    <p>Content here.</p>
  </div>
</div>
```
Style: `display: grid; grid-template-columns: 1fr 1fr; gap: 2.4rem;` — col-block: `border: 1px solid var(--border-md); padding: 1.2rem 1.6rem;`

### Stat row (for KPIs, key numbers)
```html
<div class="stat-row">
  <div class="stat">
    <div class="stat-val">$4.2M</div>
    <div class="stat-lbl">ARR</div>
  </div>
  …
</div>
```
Style: `display: flex; gap: 2rem; flex-wrap: wrap;` — each stat: `border-left: 2px solid var(--border); padding-left: 1rem;` — stat-val: `font-size: 2rem; font-weight: 700;`

### Big number (hero metric for a slide)
```html
<div class="big-num">$18.0M</div>
<div class="big-num-label">founder value at exit</div>
```
Style: `font-size: 2.8rem; font-weight: 700; line-height: 1.1;`

## Typography helpers

- `.hi` — `font-weight: 700` — highlight a cell or span
- `.dim` — `color: var(--muted)` — de-emphasize
- `.small-note` — `font-size: 1.2rem; color: var(--muted)` — fine print

## Slide design principles

**One idea per slide.** If you're cramming more than ~3 distinct points onto a slide, split it.

**Lead with the conclusion.** The `<h1>` is the takeaway, not the topic. "We are 40% below market" beats "Compensation Analysis."

**Prefer tables and structured components over prose lists.** The aesthetic is data-forward — show numbers in tables, not bullet points.

**Spartan means no decorative elements.** No icons, no gradients, no shadows, no colored backgrounds. The only visual weight comes from borders and typography.

**Slide count.** 4–8 slides is the sweet spot. Under 4 feels like notes; over 10 loses focus. Ask the user if you're unsure of the right scope.

**Tone: neutral and direct, not dramatic.** Avoid charged language ("crisis", "cannot be ignored", "has to change"). Frame slide titles and content positively or factually — describe what is true, not what is alarming.

**Bullets are one line.** When using a bullet list, each item must fit on a single line. If it spills to two, rewrite it as a short declarative phrase or move it to a `<p>`. Use the `.bullet-list` CSS pattern for large, prominent bullet points:

```css
.bullet-list { list-style: none; padding: 0; margin: 2.4rem 0; }
.bullet-list li { font-size: 1.8rem; line-height: 1.5; padding: 1.2rem 0; border-bottom: 1px solid var(--border-md); }
.bullet-list li::before { content: "— "; color: var(--muted); }
```

## Responsive

Add this media query for narrow screens:
```css
@media (max-width: 680px) {
  body { font-size: 1.3rem; }
  .slide { padding: 2rem 1.6rem; }
  .cols { grid-template-columns: 1fr; }
  #nav { padding: 1rem 1.6rem; }
}
```

## Line-wrap audit

After saving the file, open it in a browser and run a DOM check to find "widow" lines — text that wraps but leaves only a word or two on the second line. These read as layout mistakes even when the content is correct.

**Step 1 — open the file**

Use the Playwright browser tool to navigate to the saved file:
```
file:///absolute/path/to/the/file.html
```

**Step 2 — inject the detection script**

Run this in `browser_evaluate` (or equivalent):

```js
const results = [];
document.querySelectorAll('h1, h2, p, li, td, th, .callout strong, .slide-label').forEach(el => {
  // Skip invisible elements
  if (!el.offsetParent && el.tagName !== 'BODY') return;
  // Measure natural (no-wrap) width vs actual rendered width
  const saved = el.style.whiteSpace;
  el.style.whiteSpace = 'nowrap';
  const naturalWidth = el.scrollWidth;
  el.style.whiteSpace = saved;
  const containerWidth = el.getBoundingClientRect().width;
  if (naturalWidth <= containerWidth) return; // fits fine
  // Measure actual line count via range rects
  const range = document.createRange();
  range.selectNodeContents(el);
  const rects = [...range.getClientRects()].filter(r => r.width > 4);
  if (rects.length < 2) return;
  const lastLineWidth = rects[rects.length - 1].width;
  const spillRatio = lastLineWidth / containerWidth;
  if (spillRatio < 0.45) {
    results.push({
      slide: el.closest('.slide')?.id ?? '?',
      tag: el.tagName.toLowerCase(),
      text: el.textContent.trim().slice(0, 100),
      spillPct: Math.round(spillRatio * 100),
      overflowPx: Math.round(naturalWidth - containerWidth),
    });
  }
});
return results;
```

Each result describes a widow: `spillPct` is how much of the container width the last line occupies (low = worse), and `overflowPx` is how many pixels over the container the full text would be if unbroken.

**Step 3 — fix findings**

For each flagged element, apply the least-invasive fix that eliminates the widow:

- **Content edit (preferred):** shorten the phrase — cut a word, tighten a clause, replace a long word with a shorter synonym. Preserve the meaning exactly.
- **CSS: `letter-spacing`:** reducing by up to `−0.03em` is imperceptible; use this when `overflowPx` is small (< 10px) and rewording would change the meaning.
- **CSS: `font-size`:** only on headings, and only drop by 0.1–0.2rem at most. Not on body text.
- **Do not:** add `white-space: nowrap` (hides the problem), force a manual `<br>`, or make content changes that alter the meaning or tone.

After fixes, re-run the detection script to confirm all widows are gone before reporting the file as complete.

## Succinctness review

After writing all slide content, do a final pass before saving:

- **Remove notes that repeat the table.** If a `.note` or callout restates information already visible in a table on the same slide, cut it.
- **Merge intro paragraphs.** If two consecutive paragraphs say the same thing at different levels of abstraction, merge them into one.
- **Cap secondary annotations at one per slide.** If you have two `.small-note`/caveat lines, keep the one that adds new information; cut the other.
- **Cut implicit qualifications.** Phrases like "subject to board approval" or "as always, individual results may vary" are usually clear from context. Remove them unless they carry real legal or practical weight for the audience.
- **Trim callouts to headline + one sentence.** A callout's `<strong>` line should stand alone. If the supporting sentence just re-explains the headline, delete it.
