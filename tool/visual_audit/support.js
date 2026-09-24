// Minimal stand-in for the design canvas runtime the .dc.html artboards
// expect (it is not checked in). Supports exactly what the five artboards
// use: {{expr}} in text and attributes, <sc-for list as>, <sc-if value>,
// onClick="{{fn}}", DCLogic with props/state/setState/renderVals.
(function () {
  const FONT = '../fonts/';
  const faces = [
    ['Public Sans', 'PublicSans-400.ttf', 400],
    ['Public Sans', 'PublicSans-500.ttf', 500],
    ['Public Sans', 'PublicSans-600.ttf', 600],
    ['Public Sans', 'PublicSans-700.ttf', 700],
    ['Public Sans', 'PublicSans-800.ttf', 800],
    ['Instrument Serif', 'InstrumentSerif-400.ttf', 400],
  ];
  const css = faces
    .map(([f, file, w]) =>
      `@font-face{font-family:'${f}';src:url(${FONT}${file});font-weight:${w};}`)
    .join('\n');
  document.write(`<style>${css}</style>`);

  window.DCLogic = class {
    constructor(props) { this.props = props; this.state = {}; }
    setState(s) { Object.assign(this.state, s); window.__dcRender(); }
  };

  function evalIn(expr, scope) {
    const keys = Object.keys(scope);
    try {
      return new Function(...keys, 'return (' + expr + ');')(
        ...keys.map((k) => scope[k]));
    } catch (e) { return ''; }
  }
  const ONE = /^\s*\{\{([\s\S]+?)\}\}\s*$/;
  function interp(str, scope) {
    return str.replace(/\{\{([\s\S]+?)\}\}/g, (_, e) => {
      const v = evalIn(e, scope);
      return v == null ? '' : String(v);
    });
  }
  function proc(node, scope) {
    if (node.nodeType === 3) {
      node.textContent = interp(node.textContent, scope);
      return [node];
    }
    if (node.nodeType !== 1) return [node];
    const tag = node.tagName.toLowerCase();
    if (tag === 'sc-for') {
      const m = ONE.exec(node.getAttribute('list'));
      const list = m ? evalIn(m[1], scope) || [] : [];
      const as = node.getAttribute('as');
      const out = [];
      list.forEach((item) => {
        const s = Object.assign({}, scope, { [as]: item });
        Array.from(node.childNodes).forEach((c) => {
          out.push(...proc(c.cloneNode(true), s));
        });
      });
      return out;
    }
    if (tag === 'sc-if') {
      const m = ONE.exec(node.getAttribute('value'));
      if (!(m && evalIn(m[1], scope))) return [];
      const out = [];
      Array.from(node.childNodes).forEach((c) => {
        out.push(...proc(c.cloneNode(true), scope));
      });
      return out;
    }
    Array.from(node.attributes).forEach((a) => {
      if (a.name === 'onclick') {
        const m = ONE.exec(a.value);
        node.removeAttribute('onclick');
        const fn = m ? evalIn(m[1], scope) : null;
        if (typeof fn === 'function') node.addEventListener('click', fn);
      } else if (a.value.includes('{{')) {
        node.setAttribute(a.name, interp(a.value, scope));
      }
    });
    const kids = Array.from(node.childNodes);
    kids.forEach((c) => {
      const repl = proc(c, scope);
      if (repl.length === 1 && repl[0] === c) return;
      repl.forEach((r) => node.insertBefore(r, c));
      node.removeChild(c);
    });
    return [node];
  }

  window.addEventListener('DOMContentLoaded', () => {
    const host = document.querySelector('x-dc');
    const script = document.querySelector('script[data-dc-script]');
    const meta = JSON.parse(script.getAttribute('data-props') || '{}');
    const props = {};
    Object.keys(meta).forEach((k) => {
      if (meta[k] && 'default' in meta[k]) props[k] = meta[k].default;
    });
    const q = new URLSearchParams(location.search);
    q.forEach((v, k) => { props[k] = v; });
    const Comp = new Function('return Component;')();
    const inst = new Comp(props);
    const tpl = host.cloneNode(true);
    window.__dcRender = () => {
      const scope = inst.renderVals();
      const fresh = tpl.cloneNode(true);
      Array.from(fresh.childNodes).forEach((c) => {
        const repl = proc(c, scope);
        if (repl.length === 1 && repl[0] === c) return;
        repl.forEach((r) => fresh.insertBefore(r, c));
        fresh.removeChild(c);
      });
      host.innerHTML = '';
      Array.from(fresh.childNodes).forEach((c) => host.appendChild(c));
      if (q.get('dir')) host.querySelector('.app').dir = q.get('dir');
    };
    window.__dcRender();
  });
})();
