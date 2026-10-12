import { LightningElement, api } from 'lwc';

// Tags a Rich Text Area can hold. Other tags are unwrapped (their text stays); active content is dropped entirely.
const ALLOWED_TAGS = new Set([
    'P', 'BR', 'B', 'STRONG', 'I', 'EM', 'U', 'S', 'STRIKE', 'DEL', 'INS', 'SUB', 'SUP', 'SMALL', 'BIG', 'SPAN', 'DIV',
    'FONT', 'UL', 'OL', 'LI', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'BLOCKQUOTE', 'PRE', 'CODE', 'HR', 'A',
    'TABLE', 'CAPTION', 'COLGROUP', 'COL', 'THEAD', 'TBODY', 'TFOOT', 'TR', 'TH', 'TD'
]);
// Images are dropped too: the editor stores uploads behind Salesforce's own login, which partners cannot open
const DROPPED_TAGS = new Set([
    'SCRIPT', 'STYLE', 'IFRAME', 'FRAME', 'FRAMESET', 'OBJECT', 'EMBED', 'APPLET', 'FORM', 'INPUT', 'BUTTON', 'SELECT',
    'TEXTAREA', 'LINK', 'META', 'BASE', 'SVG', 'MATH', 'TEMPLATE', 'NOSCRIPT', 'AUDIO', 'VIDEO', 'SOURCE', 'CANVAS',
    'IMG', 'PICTURE'
]);
// Besides style (checked separately), the attributes each tag may keep
const ALLOWED_ATTRIBUTES = {
    A: ['href', 'title'],
    TD: ['colspan', 'rowspan'],
    TH: ['colspan', 'rowspan'],
    COL: ['span'],
    COLGROUP: ['span'],
    OL: ['start', 'type'],
    FONT: ['color', 'size', 'face']
};
const SAFE_URL = /^(https?:|mailto:|tel:|\/|#)/i;
const UNSAFE_STYLE = /url\s*\(|expression\s*\(|javascript:|@import|behavior\s*:/i;

function clean(parent) {
    Array.from(parent.childNodes).forEach((node) => {
        if (node.nodeType === 3) {
            return;
        }
        if (node.nodeType !== 1) {
            node.remove();
            return;
        }
        const tag = node.tagName.toUpperCase();
        if (DROPPED_TAGS.has(tag)) {
            node.remove();
            return;
        }
        clean(node);
        if (!ALLOWED_TAGS.has(tag)) {
            node.replaceWith(...Array.from(node.childNodes));
            return;
        }
        const allowed = ALLOWED_ATTRIBUTES[tag] || [];
        Array.from(node.attributes).forEach((attribute) => {
            const name = attribute.name.toLowerCase();
            const value = attribute.value.trim();
            if (name === 'class') {
                // Only the editor's indent levels (ql-indent-1 to 9) are kept, so indented lines and sub-points stay indented
                const indents = value.split(/\s+/).filter((token) => /^ql-indent-[1-9]$/.test(token));
                if (indents.length) {
                    node.setAttribute('class', indents.join(' '));
                } else {
                    node.removeAttribute(attribute.name);
                }
                return;
            }
            const keep = name === 'style'
                ? !UNSAFE_STYLE.test(value)
                : allowed.includes(name) && (name !== 'href' || SAFE_URL.test(value));
            if (!keep) {
                node.removeAttribute(attribute.name);
            }
        });
        if (tag === 'A' && node.hasAttribute('href')) {
            node.setAttribute('target', '_blank');
            node.setAttribute('rel', 'noopener noreferrer');
        }
    });
}

// Only the markup a Rich Text Area produces survives: no scripts, event handlers or javascript: links
function sanitize(html) {
    const doc = new DOMParser().parseFromString(`<!doctype html><body>${html || ''}</body>`, 'text/html');
    clean(doc.body);
    return doc.body.innerHTML;
}

// Shows the HTML of a Rich Text Area field (content entered by admins in Salesforce) with the portal's typography.
export default class PortalRichText extends LightningElement {
    _value;
    renderedValue;

    @api
    get value() {
        return this._value;
    }
    set value(html) {
        this._value = html;
        // The template reads no state, so a new value would not re-render it: show it straight away
        this.inject();
    }

    renderedCallback() {
        this.inject();
    }

    inject() {
        const container = this.template.querySelector('.rich-text');
        if (container && this.renderedValue !== this._value) {
            this.renderedValue = this._value;
            // eslint-disable-next-line @lwc/lwc/no-inner-html
            container.innerHTML = sanitize(this._value);
        }
    }
}