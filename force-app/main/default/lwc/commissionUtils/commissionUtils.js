// Helpers shared by the Commission Setup components: formatting, small collection helpers and error text.

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// '2026-09-01' or a date-time string -> '01 Sep 2026'; '' for no value
export function formatDate(value) {
    if (!value) {
        return '';
    }
    const text = String(value);
    const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(text);
    if (!match) {
        return text;
    }
    return `${match[3]} ${MONTHS[Number(match[2]) - 1]} ${match[1]}`;
}

// A date-time string -> '01 Sep 2026, 10:42' in the browser's time zone
export function formatDateTime(value) {
    if (!value) {
        return '';
    }
    const moment = new Date(value);
    if (Number.isNaN(moment.getTime())) {
        return String(value);
    }
    const day = String(moment.getDate()).padStart(2, '0');
    const hours = String(moment.getHours()).padStart(2, '0');
    const minutes = String(moment.getMinutes()).padStart(2, '0');
    return `${day} ${MONTHS[moment.getMonth()]} ${moment.getFullYear()}, ${hours}:${minutes}`;
}

// '01 Sep 2026 – 31 Aug 2027'
export function formatPeriod(startDate, endDate) {
    if (!startDate && !endDate) {
        return '';
    }
    return `${formatDate(startDate)} – ${formatDate(endDate)}`;
}

// 500000 -> '500,000'; 12.5 with decimals 2 -> '12.50'; '' for no value
export function formatNumber(value, decimals) {
    if (value === null || value === undefined || value === '') {
        return '';
    }
    const amount = Number(value);
    if (Number.isNaN(amount)) {
        return String(value);
    }
    const places = decimals === undefined ? (Number.isInteger(amount) ? 0 : 2) : decimals;
    return amount.toLocaleString('en-US', { minimumFractionDigits: places, maximumFractionDigits: places });
}

// 10 -> '10.00%'
export function formatPercent(value, decimals) {
    const text = formatNumber(value, decimals === undefined ? 2 : decimals);
    return text === '' ? '' : `${text}%`;
}

// What a user typed -> a number, or null when empty or not a number
export function toNumber(value) {
    if (value === null || value === undefined) {
        return null;
    }
    const text = String(value).replace(/,/g, '').trim();
    if (text === '') {
        return null;
    }
    const amount = Number(text);
    return Number.isNaN(amount) ? null : amount;
}

// Sum of numbers, ignoring empty values; rounded to 3 decimals so that 33.3 + 33.3 + 33.4 is exactly 100
export function sum(values) {
    const total = (values || []).reduce((soFar, value) => soFar + (toNumber(value) || 0), 0);
    return Math.round(total * 1000) / 1000;
}

// 'YYYY-MM-DD' of today in the browser's time zone
export function todayIso() {
    return toIso(new Date());
}

export function toIso(moment) {
    const month = String(moment.getMonth() + 1).padStart(2, '0');
    const day = String(moment.getDate()).padStart(2, '0');
    return `${moment.getFullYear()}-${month}-${day}`;
}

// 'YYYY-MM-DD' plus a number of days (may be negative)
export function addDays(isoDate, days) {
    if (!isoDate) {
        return null;
    }
    const parts = isoDate.split('-').map(Number);
    const moment = new Date(parts[0], parts[1] - 1, parts[2]);
    moment.setDate(moment.getDate() + days);
    return toIso(moment);
}

// Days from the first date to the second (second - first)
export function daysBetween(fromIso, toIsoDate) {
    if (!fromIso || !toIsoDate) {
        return null;
    }
    const first = fromIso.split('-').map(Number);
    const second = toIsoDate.split('-').map(Number);
    const start = Date.UTC(first[0], first[1] - 1, first[2]);
    const end = Date.UTC(second[0], second[1] - 1, second[2]);
    return Math.round((end - start) / 86400000);
}

// Whether two periods share at least one day (all four are 'YYYY-MM-DD')
export function periodsOverlap(startA, endA, startB, endB) {
    if (!startA || !endA || !startB || !endB) {
        return false;
    }
    return startA <= endB && startB <= endA;
}

// A copy that can be changed freely (wired and @api data is read-only)
export function clone(value) {
    return value === undefined || value === null ? value : JSON.parse(JSON.stringify(value));
}

let counter = 0;
// A key for a row that is not saved yet
export function tempKey(prefix) {
    counter += 1;
    return `${prefix || 'new'}-${Date.now().toString(36)}-${counter}`;
}

// A label with {0}, {1} ... filled in
export function fill(label, ...values) {
    return String(label || '').replace(/\{(\d+)\}/g, (whole, index) => {
        const value = values[Number(index)];
        return value === undefined || value === null ? '' : String(value);
    });
}

// The message of whatever a failed Apex call or a script error gave us
export function errorText(error, fallback) {
    if (!error) {
        return fallback || '';
    }
    if (typeof error === 'string') {
        return error;
    }
    const body = error.body;
    if (Array.isArray(body)) {
        return body.map((entry) => entry.message).filter(Boolean).join(' ') || fallback || '';
    }
    if (body) {
        if (typeof body.message === 'string' && body.message) {
            return body.message;
        }
        const pageErrors = body.pageErrors || (body.output && body.output.errors) || [];
        if (pageErrors.length && pageErrors[0].message) {
            return pageErrors.map((entry) => entry.message).join(' ');
        }
        const fieldErrors = body.fieldErrors || (body.output && body.output.fieldErrors);
        if (fieldErrors) {
            const messages = [];
            Object.keys(fieldErrors).forEach((field) => {
                (fieldErrors[field] || []).forEach((entry) => messages.push(entry.message));
            });
            if (messages.length) {
                return messages.join(' ');
            }
        }
    }
    if (typeof error.message === 'string' && error.message) {
        return error.message;
    }
    return fallback || '';
}

// The entries of a list grouped by a key: groupBy(issues, 'section') -> { stages: [...], rates: [...] }
export function groupBy(list, property) {
    const groups = {};
    (list || []).forEach((entry) => {
        const key = entry[property] === undefined || entry[property] === null ? '' : entry[property];
        if (!groups[key]) {
            groups[key] = [];
        }
        groups[key].push(entry);
    });
    return groups;
}

// A map of the entries of a list by a key
export function indexBy(list, property) {
    const index = {};
    (list || []).forEach((entry) => {
        index[entry[property]] = entry;
    });
    return index;
}