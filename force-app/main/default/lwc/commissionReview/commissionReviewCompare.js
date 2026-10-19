// What a commission configuration consists of, item by item, and how two versions of it differ.
// Kept apart from the component so that it can be tested on its own: no labels and no catalog are read here,
// the caller hands them in as the context { texts, currency, options }.
import { fill, formatDate, formatNumber } from 'c/commissionUtils';

// How a row of the comparison differs from the earlier version
export const SAME = 'same';
export const CHANGED = 'changed';
export const ADDED = 'added';
export const REMOVED = 'removed';

// Structural values of the data model (CommissionDto)
const STAGE_INITIAL = 'Initial';
const STAGE_MID = 'Mid';
const STAGE_FINAL = 'Final';
const STAGE_ORDER = { [STAGE_INITIAL]: 0, [STAGE_MID]: 1, [STAGE_FINAL]: 2 };
const RATE_FLAT = 'Flat';
const SPLIT_OWN = 'Own';
const SPLIT_SINGLE = 'Single';
const RELEASE_ALL = 'All At Initial';
const RELEASE_SPLIT = 'Split';
const PARAMETER_PERCENT = 'Percent';
const PARAMETER_TRANCHE = 'Tranche';
const PARAMETER_INSTALLMENT = 'Installment';
const TARGET_RULE_NONE = 'None';
const BASIS_UNITS = 'Units';
const BASIS_VALUE = 'Value';

const PLACEHOLDER = '{0}';

const isBlank = (value) => value === null || value === undefined || value === '';

// One piece of a value. Only `text` is compared and shown bold when it changed; the words around it come from
// the pattern: part('exceed', 'Exceed {0}', '12.50%') -> { prefix: 'Exceed ', text: '12.50%', suffix: '' }
function part(id, pattern, value) {
    const text = isBlank(value) ? '' : String(value);
    const template = isBlank(pattern) ? PLACEHOLDER : String(pattern);
    const at = template.indexOf(PLACEHOLDER);
    if (at < 0) {
        return { id, prefix: '', text, suffix: '' };
    }
    return { id, prefix: template.slice(0, at), text, suffix: template.slice(at + PLACEHOLDER.length) };
}

// 80 -> '80%', 12.5 -> '12.5%' as a share of the commission
function shareText(value, texts) {
    return isBlank(value) ? texts.notSet : `${formatNumber(value)}${texts.percentSuffix || ''}`;
}

// 10 -> '10.00%', 12.125 -> '12.125%' (rates hold up to three decimals)
function rateText(value, texts) {
    const amount = Number(value);
    const decimals = Number.isInteger(Math.round(amount * 1000) / 10) ? 2 : 3;
    return `${formatNumber(amount, decimals)}${texts.percentSuffix || ''}`;
}

// 'LKR 500,000', or the plain number when no currency is known
function amountText(value, context) {
    const amount = formatNumber(value);
    return context.currency ? fill(context.texts.amount || '{0} {1}', context.currency, amount) : amount;
}

// '10 units' or 'LKR 5,000,000', by what the target is counted in
function targetText(rate, context) {
    if (rate.targetBasis === BASIS_VALUE) {
        return amountText(rate.target, context);
    }
    const amount = formatNumber(rate.target);
    return rate.targetBasis === BASIS_UNITS ? fill(context.texts.units || PLACEHOLDER, amount) : amount;
}

// 'SPA signing date', '% of purchase price paid: 50%', 'A tranche is paid: 2'
function paidWhenText(stage, texts) {
    if (isBlank(stage.triggerLabel)) {
        return texts.notSet;
    }
    let detail = '';
    if (stage.parameterType === PARAMETER_PERCENT && !isBlank(stage.triggerPercent)) {
        detail = shareText(stage.triggerPercent, texts);
    } else if (stage.parameterType === PARAMETER_TRANCHE && !isBlank(stage.triggerTranche)) {
        detail = formatNumber(stage.triggerTranche);
    } else if (stage.parameterType === PARAMETER_INSTALLMENT && !isBlank(stage.installmentName)) {
        detail = stage.installmentName;
    }
    return detail === '' ? stage.triggerLabel : fill(texts.paidWhenDetail || '{0}: {1}', stage.triggerLabel, detail);
}

// The stages of one split in reading order (Initial, Mid 1, Mid 2 …, Final), each with its place among its type
function numbered(stages) {
    const sorted = (stages || [])
        .filter((stage) => stage && !isBlank(stage.stageType))
        .slice()
        .sort((first, second) => {
            const byType = (STAGE_ORDER[first.stageType] || 0) - (STAGE_ORDER[second.stageType] || 0);
            return byType !== 0 ? byType : (first.sequence || 0) - (second.sequence || 0);
        });
    const counts = {};
    return sorted.map((stage) => {
        counts[stage.stageType] = (counts[stage.stageType] || 0) + 1;
        return { stage, place: counts[stage.stageType] };
    });
}

function stageName(stageType, place, texts) {
    if (stageType === STAGE_MID) {
        return fill(texts.midNumbered || PLACEHOLDER, place);
    }
    return stageType === STAGE_FINAL ? texts.final : texts.initial;
}

function optionText(group, value, context) {
    if (isBlank(value)) {
        return context.texts.notSet;
    }
    const labels = (context.options && context.options[group]) || {};
    return labels[value] || value;
}

// A configuration as a list of items a person can read: [{ key, label, parts: [{ id, prefix, text, suffix }] }].
// Two versions are compared item by item through `key`, and inside an item part by part through `id`.
export function describe(config, context) {
    if (!config) {
        return [];
    }
    const settings = context || {};
    const texts = settings.texts || {};
    const scope = { texts, currency: settings.currency, options: settings.options };
    const items = [];
    const add = (key, label, parts) => items.push({ key, label: label || '', parts });
    const single = (value) => [part('value', null, value)];

    // Period and price basis
    add('period:start', texts.startDate, single(formatDate(config.startDate) || texts.notSet));
    add('period:end', texts.endDate, single(formatDate(config.endDate) || texts.notSet));
    add('price', texts.priceBasis, single(config.priceExcludesTax === true ? texts.priceExcludingTax : texts.priceIncludingTax));

    // Payout stages shared by the internal team: "paid when · %"
    const stages = config.stages || [];
    numbered(stages.filter((stage) => stage && isBlank(stage.designation))).forEach((entry) => {
        add(
            `stage:${entry.stage.stageType}:${entry.place}`,
            fill(texts.payoutItem || PLACEHOLDER, stageName(entry.stage.stageType, entry.place, texts)),
            [part('when', null, paidWhenText(entry.stage, texts)), part('percent', null, shareText(entry.stage.releasePercent, texts))]
        );
    });

    // One item per designation: its rate (or its flat fee), and its own release when it has one
    const rates = (config.rates || []).filter((rate) => rate && !isBlank(rate.designation));
    rates.forEach((rate) => {
        const name = rate.label || rate.designation;
        const paid = rate.paid === true;
        if (rate.rateType === RATE_FLAT || rate.split === SPLIT_SINGLE) {
            const fee = isBlank(rate.flatAmount) ? texts.notSet : amountText(rate.flatAmount, scope);
            add(`fee:${rate.designation}`, name, paid ? [part('amount', null, fee)] : [part('paid', null, texts.notPaid)]);
            return;
        }
        const parts = [];
        if (!paid) {
            parts.push(part('paid', null, texts.notPaid));
        } else {
            if (!isBlank(rate.target) && rate.targetRule !== TARGET_RULE_NONE) {
                parts.push(part('target', texts.partTarget, targetText(rate, scope)));
            }
            if (!isBlank(rate.currentRate)) {
                parts.push(part('current', texts.partCurrent, rateText(rate.currentRate, texts)));
            }
            if (!isBlank(rate.exceedRate)) {
                parts.push(part('exceed', texts.partExceed, rateText(rate.exceedRate, texts)));
            }
            if (!isBlank(rate.contractReference)) {
                parts.push(part('contract', texts.partContract, rate.contractReference));
            }
            if (parts.length === 0) {
                parts.push(part('value', null, texts.notSet));
            }
        }
        add(`rate:${rate.designation}`, fill(texts.rateItem || PLACEHOLDER, name), parts);

        if (paid && rate.split === SPLIT_OWN) {
            const own = numbered(stages.filter((stage) => stage && stage.designation === rate.designation));
            const release = [];
            if (rate.releaseMode === RELEASE_ALL) {
                release.push(part('mode', null, texts.releaseAll));
                const initial = own.find((entry) => entry.stage.stageType === STAGE_INITIAL);
                release.push(part('when:Initial:1', null, initial ? paidWhenText(initial.stage, texts) : texts.notSet));
            } else {
                release.push(part('mode', null, rate.releaseMode === RELEASE_SPLIT ? texts.releaseSplit : texts.notSet));
                own.forEach((entry) => {
                    const id = `${entry.stage.stageType}:${entry.place}`;
                    // "Initial: {0}" so that only the payout event itself is marked when it changed
                    const pattern = fill(texts.stagePart || '{0}: {1}', stageName(entry.stage.stageType, entry.place, texts), PLACEHOLDER);
                    release.push(part(`when:${id}`, pattern, paidWhenText(entry.stage, texts)));
                    release.push(part(`percent:${id}`, null, shareText(entry.stage.releasePercent, texts)));
                });
            }
            add(`release:${rate.designation}`, fill(texts.releaseItem || PLACEHOLDER, name), release);
        }
    });

    // The three options Finance sets once for every percentage rate
    const percentRates = rates.filter((rate) => rate.rateType !== RATE_FLAT && rate.split !== SPLIT_SINGLE);
    const firstValue = (field) => {
        const holder = percentRates.find((rate) => rate.paid === true && !isBlank(rate[field])) || percentRates.find((rate) => !isBlank(rate[field]));
        return holder ? holder[field] : null;
    };
    add('option:targetBasis', texts.targetBasis, single(optionText('targetBasis', firstValue('targetBasis'), scope)));
    add('option:targetPeriod', texts.targetPeriod, single(optionText('targetPeriod', firstValue('targetPeriod'), scope)));
    add('option:exceedMode', texts.exceedMode, single(optionText('exceedMode', firstValue('exceedMode'), scope)));
    return items;
}

const plain = (parts) => (parts || []).map((piece) => Object.assign({ changed: false }, piece));

// Two descriptions side by side: [{ key, label, status, before, after }] in the order of the newer version, an item
// that was removed standing where it stood before. `after` parts carry changed = true where they differ.
export function compare(beforeItems, afterItems) {
    const earlier = beforeItems || [];
    const later = afterItems || [];
    const earlierByKey = {};
    earlier.forEach((item) => {
        earlierByKey[item.key] = item;
    });
    const laterKeys = new Set(later.map((item) => item.key));

    const rows = later.map((item) => {
        const old = earlierByKey[item.key];
        if (!old) {
            return {
                key: item.key,
                label: item.label,
                status: ADDED,
                before: null,
                after: (item.parts || []).map((piece) => Object.assign({}, piece, { changed: true }))
            };
        }
        const oldText = {};
        (old.parts || []).forEach((piece) => {
            oldText[piece.id] = piece.text;
        });
        let differs = (old.parts || []).length !== (item.parts || []).length;
        const after = (item.parts || []).map((piece) => {
            const changed = !(piece.id in oldText) || oldText[piece.id] !== piece.text;
            differs = differs || changed;
            return Object.assign({}, piece, { changed });
        });
        return { key: item.key, label: item.label, status: differs ? CHANGED : SAME, before: plain(old.parts), after };
    });

    // An item only the earlier version has goes right after the item it followed there
    earlier.forEach((item, index) => {
        if (laterKeys.has(item.key)) {
            return;
        }
        const removed = { key: item.key, label: item.label, status: REMOVED, before: plain(item.parts), after: null };
        const previousKey = index > 0 ? earlier[index - 1].key : null;
        const at = previousKey === null ? -1 : rows.findIndex((row) => row.key === previousKey);
        rows.splice(at + 1, 0, removed);
    });
    return rows;
}

// The rows of the "What changes" table. Without an earlier version there is nothing to compare: every item is
// listed as it is.
export function compareConfigs(baseline, config, context) {
    const items = describe(config, context);
    if (!baseline) {
        return items.map((item) => ({ key: item.key, label: item.label, status: SAME, before: null, after: plain(item.parts) }));
    }
    return compare(describe(baseline, context), items);
}

// For the hint "3 changes · 14 items unchanged"
export function summarise(rows) {
    const list = rows || [];
    const unchanged = list.filter((row) => row.status === SAME).length;
    return { total: list.length, unchanged, changes: list.length - unchanged };
}