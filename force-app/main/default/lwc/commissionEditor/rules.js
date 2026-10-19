// The rules of a commission configuration as the editor checks them while Finance types.
// They mirror CommissionConfigValidator (same codes and sections); the server stays the authority.
import { fill, formatDate, formatNumber, formatPeriod, indexBy, periodsOverlap, sum } from 'c/commissionUtils';
import { labels } from './labels';

// Structural values of the data model (CommissionDto and the picklists behind it)
export const STAGE_INITIAL = 'Initial';
export const STAGE_MID = 'Mid';
export const STAGE_FINAL = 'Final';
export const RATE_FLAT = 'Flat';
export const SPLIT_OWN = 'Own';
export const SPLIT_SINGLE = 'Single';
export const RELEASE_ALL = 'All At Initial';
export const RELEASE_SPLIT = 'Split';
export const TARGET_REQUIRED = 'Required';
export const TARGET_NONE = 'None';
export const CHANGE_NEW = 'New';
export const CHANGE_CORRECTION = 'Correction';
export const CHANGE_FROM_DATE = 'Change From Date';
export const CHANGE_NEXT_PERIOD = 'Next Period';
export const CHANGE_END_EARLY = 'End Early';
export const CHANGE_COPY = 'Copy';
export const STATUS_APPROVED = 'Approved';
export const STATUS_PENDING = 'Pending Approval';
const PARAMETER_PERCENT = 'Percent';
const PARAMETER_TRANCHE = 'Tranche';
const PARAMETER_INSTALLMENT = 'Installment';
const BASELINE_PREVIOUS = 'PREVIOUS_PERIOD';
const FULL = 100;

// The cards of the screen an issue belongs to
export const SECTION_PERIOD = 'period';
export const SECTION_STAGES = 'stages';
export const SECTION_RATES = 'rates';
export const SECTION_OPTIONS = 'options';
export const SECTION_GENERAL = 'general';
export const ownSection = (designation) => `own:${designation}`;
export const feeSection = (designation) => `fee:${designation}`;

// The place inside a card an issue is pinned to
export const SLOT = {
    PROJECT: 'project',
    START: 'start',
    END: 'end',
    PERIOD: 'period',
    TRIGGER: 'trigger',
    PARAMETER: 'parameter',
    RELEASE: 'release',
    SPLIT: 'split',
    CURRENT: 'current',
    EXCEED: 'exceed',
    TARGET: 'target',
    FLAT: 'flat',
    BASIS: 'basis',
    TARGET_PERIOD: 'targetPeriod',
    EXCEED_MODE: 'exceedMode',
    RELEASE_MODE: 'releaseMode',
    REASON: 'reason',
    SECTION: 'section'
};

const TYPE_ORDER = { [STAGE_INITIAL]: 0, [STAGE_MID]: 1, [STAGE_FINAL]: 2 };

export const isBlank = (value) => value === '' || value === null || value === undefined;
export const round = (value, decimals) => {
    const factor = Math.pow(10, decimals);
    return Math.round(value * factor) / factor;
};

// fee: a fixed amount (its own card) · own: its own release (its own card) · shared: a row of the rates table
export function kindOf(rate) {
    if (rate.rateType === RATE_FLAT || rate.split === SPLIT_SINGLE) {
        return 'fee';
    }
    return rate.split === SPLIT_OWN ? 'own' : 'shared';
}

export function sectionOfRate(rate) {
    const kind = kindOf(rate);
    if (kind === 'fee') {
        return feeSection(rate.designation);
    }
    return kind === 'own' ? ownSection(rate.designation) : SECTION_RATES;
}

// Initial first, then the Mid stages in their sequence, Final last
export function inOrder(stages) {
    return [...(stages || [])].sort((first, second) => {
        const byType = (TYPE_ORDER[first.stageType] ?? 1) - (TYPE_ORDER[second.stageType] ?? 1);
        return byType !== 0 ? byType : (first.sequence || 0) - (second.sequence || 0);
    });
}

// Each stage with the name the screen gives it: "Initial", "Mid 1", "Mid 2", "Final"
function named(rows) {
    let mid = 0;
    return inOrder(rows).map((row) => {
        if (row.stageType === STAGE_INITIAL) {
            return { row, name: labels.initial };
        }
        if (row.stageType === STAGE_FINAL) {
            return { row, name: labels.final };
        }
        mid += 1;
        return { row, name: fill(labels.midNumbered, mid) };
    });
}

// What is allocated and what is left of the 100 % of one split
export function totals(rows) {
    const total = sum((rows || []).map((row) => row.releasePercent));
    return { total, left: round(FULL - total, 2) };
}

// The first other configuration of the project that shares a day with this period (the server decides finally)
export function findClash(config, siblings) {
    if (!config.startDate || !config.endDate) {
        return null;
    }
    // A new version of the same configuration may overlap the version it replaces or shortens
    const replaces = [CHANGE_CORRECTION, CHANGE_END_EARLY, CHANGE_FROM_DATE].includes(config.changeType);
    return (
        (siblings || []).find(
            (other) =>
                (other.status === STATUS_APPROVED || other.status === STATUS_PENDING) &&
                !(config.id && other.id === config.id) &&
                !(replaces && config.supersedesId && other.id === config.supersedesId) &&
                periodsOverlap(config.startDate, config.endDate, other.startDate, other.endDate)
        ) || null
    );
}

// Every open point of the configuration.
// config: what would be saved (stages of unpaid designations already left out)
// context: { hasTarget: { designation: true }, siblings: list or null when not known }
// An issue: { section, rowKey, slot, code, message, short, submitOnly, quiet, client }
//   submitOnly = the draft can be saved with it, but not submitted
//   quiet = something is still missing (not wrong): the checklist counts it, the field is marked once the user has been there
export function validate(config, catalog, context) {
    const issues = [];
    const add = (section, rowKey, slot, code, message, submitOnly, short) =>
        issues.push({
            section,
            rowKey: rowKey || null,
            slot,
            code,
            message,
            short: short || message,
            submitOnly: !!submitOnly,
            quiet: !!submitOnly || code === 'PERIOD_REQUIRED',
            client: true
        });
    const settings = (catalog && catalog.settings) || {};
    const triggers = indexBy((catalog && catalog.triggers) || [], 'key');
    const stages = config.stages || [];

    checkPeriod(config, context || {}, add);
    checkSplit(
        {
            section: SECTION_STAGES,
            rows: stages.filter((row) => !row.designation),
            triggers,
            finalRequired: settings.finalStageRequired === true,
            allowMid: true,
            totalCode: 'STAGES_TOTAL'
        },
        add
    );
    checkRates(config, triggers, context || {}, add);
    if (config.changeType && config.changeType !== CHANGE_NEW && isBlank(String(config.changeReason || '').trim())) {
        add(SECTION_OPTIONS, null, SLOT.REASON, 'REASON_REQUIRED', labels.needReason, true);
    }
    return issues;
}

function checkPeriod(config, context, add) {
    const start = config.startDate;
    const end = config.endDate;
    if (!config.projectId) {
        add(SECTION_PERIOD, null, SLOT.PROJECT, 'PERIOD_REQUIRED', labels.needProject, false);
    }
    if (!start) {
        add(SECTION_PERIOD, null, SLOT.START, 'PERIOD_REQUIRED', labels.needStart, false);
    }
    if (!end) {
        add(SECTION_PERIOD, null, SLOT.END, 'PERIOD_REQUIRED', labels.needEnd, false);
    }
    if (start && end && end < start) {
        add(SECTION_PERIOD, null, SLOT.END, 'PERIOD_ORDER', labels.endBeforeStart, false);
    }

    // Against the version this draft changes, or the period it follows
    const source = config.baseline;
    if (source) {
        const follows = config.baselineKind === BASELINE_PREVIOUS;
        if (config.changeType === CHANGE_FROM_DATE && !follows && start && source.startDate && source.endDate) {
            if (!(start > source.startDate && start <= source.endDate)) {
                const message = fill(labels.startInsideSource, formatDate(source.startDate), formatDate(source.endDate));
                add(SECTION_PERIOD, null, SLOT.START, 'PERIOD_SOURCE', message, false);
            }
        }
        if (config.changeType === CHANGE_NEXT_PERIOD && start && source.endDate && start <= source.endDate) {
            add(SECTION_PERIOD, null, SLOT.START, 'PERIOD_SOURCE', fill(labels.startAfterSource, formatDate(source.endDate)), false);
        }
        if (config.changeType === CHANGE_END_EARLY && !follows && end && source.endDate && end > source.endDate) {
            add(SECTION_PERIOD, null, SLOT.END, 'PERIOD_SOURCE', fill(labels.endNotAfterSource, formatDate(source.endDate)), false);
        }
    }

    const clash = context.siblings ? findClash(config, context.siblings) : null;
    if (clash && !(start && end && end < start)) {
        const message = fill(labels.overlap, clash.name, clash.version, formatPeriod(clash.startDate, clash.endDate));
        add(SECTION_PERIOD, null, SLOT.PERIOD, 'PERIOD_OVERLAP', message, false);
    }
}

// The stages of one split: the shared stages, or the own release of one designation
function checkSplit(split, add) {
    const { section, rows, triggers, finalRequired, allowMid, totalCode } = split;
    const entries = named(rows);
    const initials = rows.filter((row) => row.stageType === STAGE_INITIAL);
    const finals = rows.filter((row) => row.stageType === STAGE_FINAL);
    const { total, left } = totals(rows);

    if (!initials.length) {
        add(section, null, SLOT.SPLIT, 'STAGE_INITIAL_REQUIRED', labels.needInitial, true);
    }
    if (finalRequired && !finals.length) {
        add(section, null, SLOT.SPLIT, 'STAGE_FINAL_REQUIRED', labels.needFinal, true);
    }
    if (initials.length > 1) {
        add(section, initials[1].key, SLOT.SPLIT, 'STAGE_DUPLICATE', fill(labels.duplicateStage, labels.initial), false);
    }
    if (finals.length > 1) {
        add(section, finals[1].key, SLOT.SPLIT, 'STAGE_DUPLICATE', fill(labels.duplicateStage, labels.final), false);
    }

    let percentMissing = false;
    const lastOfGroup = {};
    entries.forEach(({ row, name }) => {
        const trigger = triggers[row.triggerKey];
        if (row.stageType === STAGE_MID && !allowMid) {
            add(section, row.key, SLOT.SPLIT, 'STAGE_MID_NOT_ALLOWED', labels.midNotAllowed, false);
        }

        // Paid when
        if (!row.triggerKey) {
            add(section, row.key, SLOT.TRIGGER, 'STAGE_TRIGGER_REQUIRED', fill(labels.needEvent, name), true, fill(labels.shortStageEvent, name));
        } else if (trigger && !(trigger.stageTypes || []).includes(row.stageType)) {
            add(section, row.key, SLOT.TRIGGER, 'STAGE_TRIGGER_INVALID', fill(labels.eventNotAllowed, name), false);
        }

        // The parameter of the event: % paid, tranche number or instalment
        const parameterType = trigger ? trigger.parameterType : row.parameterType;
        let orderValue = null;
        if (parameterType === PARAMETER_PERCENT) {
            if (isBlank(row.triggerPercent)) {
                add(section, row.key, SLOT.PARAMETER, 'STAGE_PARAMETER_REQUIRED', fill(labels.needParameterPercent, name), true);
            } else if (!(row.triggerPercent > 0 && row.triggerPercent <= FULL)) {
                add(section, row.key, SLOT.PARAMETER, 'STAGE_PERCENT_RANGE', labels.percentRange, false);
            } else {
                orderValue = Number(row.triggerPercent);
            }
        } else if (parameterType === PARAMETER_TRANCHE) {
            if (isBlank(row.triggerTranche)) {
                add(section, row.key, SLOT.PARAMETER, 'STAGE_PARAMETER_REQUIRED', fill(labels.needParameterTranche, name), true);
            } else if (!(row.triggerTranche >= 1)) {
                add(section, row.key, SLOT.PARAMETER, 'STAGE_PERCENT_RANGE', labels.trancheRange, false);
            } else {
                orderValue = Number(row.triggerTranche);
            }
        } else if (parameterType === PARAMETER_INSTALLMENT && !row.installmentId) {
            add(section, row.key, SLOT.PARAMETER, 'STAGE_PARAMETER_REQUIRED', fill(labels.needParameterInstallment, name), true);
        }

        // Mid stages of the same kind of event must come later and later (50 % paid, then 75 % paid)
        if (row.stageType === STAGE_MID && trigger && trigger.orderGroup && orderValue !== null) {
            const earlier = lastOfGroup[trigger.orderGroup];
            if (earlier && orderValue <= earlier.value) {
                add(section, row.key, SLOT.PARAMETER, 'STAGE_MID_ORDER', fill(labels.midOrder, name, earlier.name), true);
            }
            lastOfGroup[trigger.orderGroup] = { value: orderValue, name };
        }

        // % of commission
        if (isBlank(row.releasePercent)) {
            percentMissing = true;
            const message = left > 0 ? fill(labels.needPercentLeft, formatNumber(left)) : labels.needPercent;
            add(section, row.key, SLOT.RELEASE, 'STAGE_PERCENT_REQUIRED', message, true, fill(labels.shortStagePercent, name));
        } else if (!(row.releasePercent > 0 && row.releasePercent <= FULL)) {
            add(section, row.key, SLOT.RELEASE, 'STAGE_PERCENT_RANGE', labels.percentRange, false);
        }
    });

    // The total: an empty percentage is already reported on its row
    if (rows.length) {
        if (left < 0) {
            add(section, null, SLOT.SPLIT, totalCode, fill(labels.totalOver, formatNumber(total), formatNumber(-left)), true);
        } else if (left > 0 && !percentMissing) {
            add(section, null, SLOT.SPLIT, totalCode, fill(labels.totalLeft, formatNumber(left)), true);
        }
    }
}

function checkRates(config, triggers, context, add) {
    const rates = config.rates || [];
    const stages = config.stages || [];
    const hasTarget = context.hasTarget || {};
    if (!rates.some((rate) => rate.paid)) {
        add(SECTION_RATES, null, SLOT.SECTION, 'RATES_NONE', labels.needAnyRate, true);
    }

    const withTarget = [];
    rates.forEach((rate) => {
        if (!rate.paid) {
            return;
        }
        const kind = kindOf(rate);
        const section = sectionOfRate(rate);
        const name = rate.label || rate.designation;

        if (kind === 'fee') {
            if (!isBlank(rate.flatAmount) && rate.flatAmount < 0) {
                add(section, rate.key, SLOT.FLAT, 'RATE_RANGE', labels.amountRange, false);
            } else if (isBlank(rate.flatAmount) || Number(rate.flatAmount) === 0) {
                add(section, rate.key, SLOT.FLAT, 'RATE_REQUIRED', fill(labels.needAmount, name), true);
            }
            return;
        }

        // Current rate: 0 % is allowed, empty is not
        if (isBlank(rate.currentRate)) {
            add(section, rate.key, SLOT.CURRENT, 'RATE_REQUIRED', fill(labels.needRate, name), true);
        } else if (rate.currentRate < 0 || rate.currentRate > FULL) {
            add(section, rate.key, SLOT.CURRENT, 'RATE_RANGE', labels.rateRange, false);
        }

        // Target: required by the designation, or because the contract of an own-release designation has one
        const usesTarget = rate.targetRule !== TARGET_NONE;
        const targetWanted = usesTarget && (rate.targetRule === TARGET_REQUIRED || (kind === 'own' && hasTarget[rate.designation] === true));
        const targetGiven = usesTarget && !isBlank(rate.target) && rate.target > 0;
        if (usesTarget && !isBlank(rate.target) && rate.target < 0) {
            add(section, rate.key, SLOT.TARGET, 'RATE_RANGE', labels.targetRange, false);
        } else if (targetWanted && !targetGiven) {
            add(section, rate.key, SLOT.TARGET, 'TARGET_REQUIRED', fill(labels.needTarget, name), true);
        }
        if (targetGiven) {
            withTarget.push(rate);
        }

        // Exceed rate: needed with a target, never below the current rate
        if (isBlank(rate.exceedRate)) {
            if (targetGiven || targetWanted) {
                add(section, rate.key, SLOT.EXCEED, 'EXCEED_REQUIRED', fill(labels.needExceed, name), true);
            }
        } else if (rate.exceedRate < 0 || rate.exceedRate > FULL) {
            add(section, rate.key, SLOT.EXCEED, 'RATE_RANGE', labels.rateRange, false);
        } else if (!isBlank(rate.currentRate) && rate.exceedRate < rate.currentRate) {
            add(section, rate.key, SLOT.EXCEED, 'EXCEED_LOWER', fill(labels.exceedLower, name), false);
        }

        // Own release: all at the Initial event, or split between Initial and Final
        if (kind === 'own') {
            if (rate.releaseMode !== RELEASE_ALL && rate.releaseMode !== RELEASE_SPLIT) {
                add(section, rate.key, SLOT.RELEASE_MODE, 'OWN_RELEASE_REQUIRED', fill(labels.needReleaseMode, name), true);
            } else {
                checkSplit(
                    {
                        section,
                        rows: stages.filter((row) => row.designation === rate.designation),
                        triggers,
                        finalRequired: rate.releaseMode === RELEASE_SPLIT,
                        allowMid: false,
                        totalCode: 'OWN_TOTAL'
                    },
                    add
                );
            }
        }
    });

    // The three choices above the table apply to every designation with a target
    if (withTarget.length) {
        if (withTarget.some((rate) => isBlank(rate.targetBasis))) {
            add(SECTION_RATES, null, SLOT.BASIS, 'TARGET_OPTIONS_REQUIRED', labels.needBasis, true);
        }
        if (withTarget.some((rate) => isBlank(rate.targetPeriod))) {
            add(SECTION_RATES, null, SLOT.TARGET_PERIOD, 'TARGET_OPTIONS_REQUIRED', labels.needTargetPeriod, true);
        }
        if (withTarget.some((rate) => isBlank(rate.exceedMode))) {
            add(SECTION_RATES, null, SLOT.EXCEED_MODE, 'TARGET_OPTIONS_REQUIRED', labels.needExceedMode, true);
        }
    }
}

// ------------------------------------------------------------ issues that came back from a save

// Where a server issue is shown: the validator names a section, a row and a field; codes help when the field is not given
function slotOf(issue) {
    const field = String(issue.field || '').toLowerCase().replace(/__c$/, '').replace(/[^a-z]/g, '');
    const code = String(issue.code || '');
    if (code.startsWith('STAGE') || code === 'OWN_TOTAL') {
        if (field.includes('release')) {
            return SLOT.RELEASE;
        }
        if (field.includes('parameter') || field.includes('installment') || field.includes('tranche') || field === 'triggerpercent') {
            return SLOT.PARAMETER;
        }
        if (field.includes('trigger')) {
            return SLOT.TRIGGER;
        }
        if (code === 'STAGE_TRIGGER_REQUIRED' || code === 'STAGE_TRIGGER_INVALID') {
            return SLOT.TRIGGER;
        }
        if (code === 'STAGE_PARAMETER_REQUIRED' || code === 'STAGE_MID_ORDER') {
            return SLOT.PARAMETER;
        }
        if (code === 'STAGE_PERCENT_REQUIRED' || code === 'STAGE_PERCENT_RANGE') {
            return SLOT.RELEASE;
        }
        return SLOT.SPLIT;
    }
    if (code.startsWith('PERIOD') || issue.section === SECTION_PERIOD) {
        if (code === 'PERIOD_OVERLAP') {
            return SLOT.PERIOD;
        }
        if (field.includes('project')) {
            return SLOT.PROJECT;
        }
        if (field.includes('start')) {
            return SLOT.START;
        }
        if (field.includes('end') || code === 'PERIOD_ORDER') {
            return SLOT.END;
        }
        return code === 'PERIOD_SOURCE' ? SLOT.START : SLOT.PERIOD;
    }
    if (code === 'REASON_REQUIRED' || field.includes('reason')) {
        return SLOT.REASON;
    }
    if (code === 'OWN_RELEASE_REQUIRED' || field.includes('releasemode')) {
        return SLOT.RELEASE_MODE;
    }
    if (field.includes('exceedmode')) {
        return SLOT.EXCEED_MODE;
    }
    if (field.includes('targetbasis') || field === 'basis') {
        return SLOT.BASIS;
    }
    if (field.includes('targetperiod')) {
        return SLOT.TARGET_PERIOD;
    }
    if (field.includes('flat') || field.includes('amount')) {
        return SLOT.FLAT;
    }
    if (field.includes('exceed') || code === 'EXCEED_LOWER' || code === 'EXCEED_REQUIRED') {
        return SLOT.EXCEED;
    }
    if (field.includes('target') || code === 'TARGET_REQUIRED') {
        return SLOT.TARGET;
    }
    if (field.includes('rate') || code === 'RATE_REQUIRED' || code === 'RATE_RANGE') {
        return String(issue.section || '').startsWith('fee:') ? SLOT.FLAT : SLOT.CURRENT;
    }
    return SLOT.SECTION;
}

// Server issues in the editor's terms: the card they belong to, the row key of the screen and the slot
export function adoptIssues(serverIssues, config) {
    const rateOf = {};
    (config.rates || []).forEach((rate) => {
        [rate.key, rate.id, rate.designation].filter(Boolean).forEach((name) => {
            rateOf[name] = rate;
        });
    });
    const stageOf = {};
    (config.stages || []).forEach((stage) => {
        [stage.key, stage.id].filter(Boolean).forEach((name) => {
            stageOf[name] = stage;
        });
    });
    return (serverIssues || [])
        .filter((issue) => issue && issue.message)
        .map((issue) => {
            let section = issue.section || SECTION_GENERAL;
            let rowKey = isBlank(issue.rowKey) ? null : issue.rowKey;
            const stage = rowKey ? stageOf[rowKey] : null;
            const rate = rowKey && !stage ? rateOf[rowKey] : null;
            if (stage) {
                rowKey = stage.key;
                // A stage of a designation's own release belongs to that designation's card
                const owner = stage.designation ? rateOf[stage.designation] : null;
                if (owner && (section === SECTION_STAGES || section === SECTION_GENERAL)) {
                    section = sectionOfRate(owner);
                }
            } else if (rate) {
                rowKey = rate.key;
                if (section === SECTION_RATES || section === SECTION_GENERAL) {
                    section = sectionOfRate(rate);
                }
            }
            return {
                section,
                rowKey,
                slot: slotOf({ ...issue, section }),
                code: issue.code || '',
                message: issue.message,
                short: issue.message,
                submitOnly: false,
                quiet: false,
                client: false
            };
        });
}