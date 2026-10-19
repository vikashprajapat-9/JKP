import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getConfig from '@salesforce/apex/CommissionSetupController.getConfig';
import saveConfig from '@salesforce/apex/CommissionSetupController.saveConfig';
import discardDraft from '@salesforce/apex/CommissionSetupController.discardDraft';
import SubmitDialog from 'c/commissionEditorSubmit';
import { clone, errorText, fill, formatDate, formatDateTime, formatNumber, indexBy, tempKey, toIso, toNumber } from 'c/commissionUtils';
import { labels } from './labels';
import {
    CHANGE_END_EARLY,
    CHANGE_FROM_DATE,
    CHANGE_NEW,
    CHANGE_NEXT_PERIOD,
    CHANGE_CORRECTION,
    CHANGE_COPY,
    RELEASE_ALL,
    RELEASE_SPLIT,
    SECTION_GENERAL,
    SECTION_OPTIONS,
    SECTION_PERIOD,
    SECTION_RATES,
    SECTION_STAGES,
    SLOT,
    STAGE_FINAL,
    STAGE_INITIAL,
    STATUS_APPROVED,
    STATUS_PENDING,
    TARGET_NONE,
    adoptIssues,
    feeSection,
    inOrder,
    isBlank,
    kindOf,
    ownSection,
    round,
    sectionOfRate,
    totals,
    validate
} from './rules';

const ACTION_DRAFT = 'DRAFT';
const ACTION_SUBMIT = 'SUBMIT';
const STATE_RETURNED = 'RETURNED';
const RATE_PERCENT = 'Percent';
const FULL = 100;

// Display state -> colour of the pill and its text when the server sent none
const STATE_LOOK = {
    DRAFT: { tone: 'grey', label: labels.stateDraft },
    RETURNED: { tone: 'red', label: labels.stateReturned },
    PENDING: { tone: 'blue', label: labels.statePending },
    UPCOMING: { tone: 'blue', label: labels.stateUpcoming },
    ACTIVE: { tone: 'green', label: labels.stateActive },
    EXPIRED: { tone: 'amber', label: labels.stateExpired },
    REPLACED: { tone: 'grey', label: labels.stateReplaced }
};

const CHANGE_LABEL = {
    [CHANGE_CORRECTION]: labels.changeCorrection,
    [CHANGE_FROM_DATE]: labels.changeFromDate,
    [CHANGE_NEXT_PERIOD]: labels.changeNextPeriod,
    [CHANGE_END_EARLY]: labels.changeEndEarly,
    [CHANGE_COPY]: labels.changeCopy
};

// Decimals kept per number box (the scale of the field behind it)
const DECIMALS = { currentRate: 3, exceedRate: 3, target: 2, flatAmount: 2 };
// Slot of the issues shown under each number box
const SLOT_OF_FIELD = { currentRate: SLOT.CURRENT, exceedRate: SLOT.EXCEED, target: SLOT.TARGET, flatAmount: SLOT.FLAT };
// What a save does not need to carry back (read-only context of the screen)
const NOT_SENT = ['baseline', 'siblings', 'approvers'];

const nullIfBlank = (value) => (isBlank(value) ? null : value);
// Rates read 10.00 (a third decimal is shown when it was entered); targets and amounts show decimals only when they have some
const digitsOf = (value, most) => {
    if (most === 3) {
        return !isBlank(value) && round(Number(value), 2) !== Number(value) ? 3 : 2;
    }
    return isBlank(value) || Number.isInteger(Number(value)) ? 0 : 2;
};
const clock = (moment) => `${String(moment.getHours()).padStart(2, '0')}:${String(moment.getMinutes()).padStart(2, '0')}`;
const issueId = (issue) => `${issue.section}|${issue.rowKey || ''}|${issue.code}`;

// The screen Finance works in: one working copy of the configuration (this.config), changed in place by the
// handlers; after every change refresh() works out the issues and everything the template shows (this.vm).
export default class CommissionEditor extends LightningElement {
    labels = labels;

    // workspace.flags: what the running user may do
    @api flags;
    // workspace.projects: for the project choice of a new configuration
    @api projects;

    _configId = null;
    _draft = null;
    _catalog = null;
    connected = false;
    loadCount = 0;

    // The working copy (CommissionDto.Config) and what the template shows of it
    config = null;
    vm = null;
    issues = [];

    isLoading = false;
    loadError = '';
    busy = false;
    // A save the server refused with an error (someone else changed it, no approver ...)
    saveError = '';
    // What stops a save or a submit, said once above the form
    blockNote = '';
    dirty = false;
    savedText = '';
    // Field marks for things that are only missing: shown once a section was touched, or everywhere after a save
    showAll = false;
    touched = {};
    serverIssues = [];
    // Choices of the screen that are not part of the configuration
    ui = { hasTarget: {} };
    // What the user typed in a number box, so that "12." is not rewritten to "12" while typing
    typed = {};
    // The project whose other configurations (config.siblings) are known
    siblingsProjectId = null;

    // The id of a saved configuration to load
    @api
    get configId() {
        return this._configId;
    }
    set configId(value) {
        const next = value || null;
        if (next === this._configId) {
            return;
        }
        this._configId = next;
        // After the first save the parent may hand back the id of the draft that is already open
        if (this.connected && next && !this._draft && !(this.config && this.config.id === next)) {
            this.load(next);
        }
    }

    // An unsaved configuration (CommissionDto.Config from newDraft or draftFrom)
    @api
    get draft() {
        return this._draft;
    }
    set draft(value) {
        this._draft = value || null;
        if (this.connected && this._draft) {
            this.adopt(this._draft);
        }
    }

    // workspace.catalog: designations, payout events, settings, instalments, option lists
    @api
    get catalog() {
        return this._catalog;
    }
    set catalog(value) {
        this._catalog = value || null;
        if (this.connected && this.config) {
            this.prepare();
            this.refresh();
        }
    }

    connectedCallback() {
        this.connected = true;
        // Closing the browser tab with unsaved changes asks first
        this.beforeUnload = (event) => {
            if (this.dirty) {
                event.preventDefault();
                event.returnValue = '';
            }
        };
        window.addEventListener('beforeunload', this.beforeUnload);
        if (this._draft) {
            this.adopt(this._draft);
        } else if (this._configId) {
            this.load(this._configId);
        }
    }

    disconnectedCallback() {
        this.connected = false;
        window.removeEventListener('beforeunload', this.beforeUnload);
    }

    // ------------------------------------------------------------ loading

    async load(configId) {
        const ticket = ++this.loadCount;
        this.isLoading = true;
        this.loadError = '';
        try {
            const config = await getConfig({ configId });
            if (ticket !== this.loadCount) {
                return;
            }
            if (config) {
                this.adopt(config);
            } else {
                this.config = null;
                this.vm = null;
                this.loadError = labels.nothingToShow;
            }
        } catch (error) {
            if (ticket === this.loadCount) {
                this.loadError = errorText(error, labels.loadError);
            }
        } finally {
            if (ticket === this.loadCount) {
                this.isLoading = false;
            }
        }
    }

    // Takes a configuration from the server as the new working copy
    adopt(source) {
        const config = clone(source) || {};
        config.stages = (config.stages || []).map((stage) => ({ ...stage, key: stage.key || stage.id || tempKey('stage') }));
        config.rates = (config.rates || []).map((rate) => ({ ...rate, key: rate.key || rate.id || tempKey('rate') }));
        this.config = config;
        this.typed = {};
        this.touched = {};
        this.serverIssues = [];
        this.saveError = '';
        this.blockNote = '';
        this.dirty = false;
        // A draft that was saved before shows right away what is still missing
        this.showAll = !!config.id;
        this.siblingsProjectId = config.projectId || null;
        this.savedText = config.id && config.lastModified ? fill(labels.savedAt, formatDateTime(config.lastModified)) : '';
        this.prepare();
        const hasTarget = {};
        config.rates.forEach((rate) => {
            hasTarget[rate.designation] = !isBlank(rate.target) || !isBlank(rate.exceedRate);
        });
        this.ui = { hasTarget };
        this.refresh();
    }

    // Makes the working copy complete against the catalog: one rate entry per designation, the catalog's
    // attributes on each entry, and the one choice that is no choice (a single target period)
    prepare() {
        const config = this.config;
        const catalog = this._catalog;
        if (!config || !catalog) {
            return;
        }
        const rateOf = indexBy(config.rates, 'designation');
        (catalog.designations || []).forEach((designation) => {
            let rate = rateOf[designation.key];
            if (!rate) {
                rate = { id: null, key: tempKey('rate'), designation: designation.key, paid: false };
                config.rates.push(rate);
            }
            rate.label = rate.label || designation.label;
            rate.rateType = rate.rateType || designation.rateType;
            rate.split = rate.split || designation.split;
            rate.targetRule = rate.targetRule || designation.targetRule;
            rate.claimLabel = rate.claimLabel || designation.claimLabel;
            rate.aggregateOf = rate.aggregateOf || designation.aggregateOf || null;
        });
        const percentRates = config.rates.filter((rate) => rate.rateType === RATE_PERCENT);
        const periods = catalog.targetPeriods || [];
        ['targetBasis', 'targetPeriod', 'exceedMode'].forEach((field) => {
            let common = (percentRates.find((rate) => !isBlank(rate[field])) || {})[field];
            if (isBlank(common) && field === 'targetPeriod' && periods.length === 1) {
                common = periods[0].value;
            }
            if (!isBlank(common)) {
                percentRates.filter((rate) => isBlank(rate[field])).forEach((rate) => {
                    rate[field] = common;
                });
            }
        });
    }

    // ------------------------------------------------------------ what can be done

    get editable() {
        const config = this.config;
        if (!config) {
            return false;
        }
        // An unsaved draft comes from newDraft / draftFrom, which only Finance can call
        return config.canEdit === true || (!config.id && config.canEdit !== false);
    }

    // Ending a period early changes the end date and the reason only
    get isEndEarly() {
        return !!this.config && this.config.changeType === CHANGE_END_EARLY;
    }

    get locked() {
        return !this.editable || this.isEndEarly;
    }

    get noAccess() {
        const flags = this.flags;
        return !!flags && flags.canView === false && flags.canConfigure !== true;
    }

    get showForm() {
        return !this.isLoading && !this.noAccess && !this.loadError && !!this.vm;
    }

    get showNothing() {
        return !this.isLoading && !this.noAccess && !this.loadError && !this.vm;
    }

    get no() {
        return false;
    }

    get settings() {
        return (this._catalog && this._catalog.settings) || {};
    }

    get siblingsKnown() {
        const config = this.config;
        return !!config && Array.isArray(config.siblings) && (config.projectId || null) === this.siblingsProjectId;
    }

    rateOf(designation) {
        return (this.config.rates || []).find((rate) => rate.designation === designation);
    }

    // The rate entries in the order of the catalog; entries of designations no longer in the catalog come last
    get orderedRates() {
        const order = {};
        ((this._catalog && this._catalog.designations) || []).forEach((designation, index) => {
            order[designation.key] = designation.order === undefined || designation.order === null ? index : designation.order;
        });
        return [...(this.config.rates || [])].sort(
            (first, second) => (order[first.designation] ?? Number.MAX_SAFE_INTEGER) - (order[second.designation] ?? Number.MAX_SAFE_INTEGER)
        );
    }

    get triggers() {
        return (this._catalog && this._catalog.triggers) || [];
    }

    // The instalments of the project's company (all of them while no project is chosen)
    get installments() {
        const companyId = this.config && this.config.companyId;
        const all = (this._catalog && this._catalog.installments) || [];
        if (!this.config || !this.config.projectId) {
            return all;
        }
        return all.filter((entry) => (entry.companyId || null) === (companyId || null));
    }

    // ------------------------------------------------------------ what would be saved

    // The configuration as it is sent to the server and checked by the rules: the working copy without what is
    // switched off. The working copy itself keeps those values, so switching back on brings them back.
    effective() {
        const copy = clone(this.config);
        const rateOf = indexBy(copy.rates || [], 'designation');
        (copy.rates || []).forEach((rate) => {
            const noTarget = rate.targetRule === TARGET_NONE || (kindOf(rate) === 'own' && !this.ui.hasTarget[rate.designation]);
            if (noTarget) {
                rate.target = null;
                if (kindOf(rate) === 'own') {
                    rate.exceedRate = null;
                }
            }
            rate.contractReference = nullIfBlank(rate.contractReference);
        });
        const stages = [];
        (copy.stages || []).forEach((stage) => {
            if (!stage.designation) {
                stages.push(stage);
                return;
            }
            // Stages of a designation count only while it is paid
            const rate = rateOf[stage.designation];
            if (!rate || !rate.paid) {
                return;
            }
            if (kindOf(rate) !== 'own') {
                stages.push(stage);
            } else if (rate.releaseMode === RELEASE_ALL) {
                if (stage.stageType === STAGE_INITIAL) {
                    stages.push({ ...stage, releasePercent: FULL });
                }
            } else if (rate.releaseMode === RELEASE_SPLIT) {
                if (stage.stageType === STAGE_INITIAL || stage.stageType === STAGE_FINAL) {
                    stages.push(stage);
                }
            }
        });
        // The shared stages first, then each designation's own; every split numbered 1, 2, 3 ... in the order of the screen
        const splits = [''];
        stages.forEach((stage) => {
            if (stage.designation && !splits.includes(stage.designation)) {
                splits.push(stage.designation);
            }
        });
        copy.stages = [];
        splits.forEach((split) => {
            inOrder(stages.filter((stage) => (stage.designation || '') === split)).forEach((stage, index) => {
                copy.stages.push({ ...stage, designation: stage.designation || null, sequence: index + 1 });
            });
        });
        copy.startDate = nullIfBlank(copy.startDate);
        copy.endDate = nullIfBlank(copy.endDate);
        copy.changeReason = nullIfBlank(copy.changeReason);
        return copy;
    }

    payload(approverId) {
        const copy = this.effective();
        NOT_SENT.forEach((name) => delete copy[name]);
        if (approverId) {
            copy.approverId = approverId;
        }
        return JSON.stringify(copy);
    }

    // ------------------------------------------------------------ the view

    // Works out the issues and everything the template shows. Called after every change.
    refresh() {
        const config = this.config;
        if (!config) {
            this.vm = null;
            this.issues = [];
            return;
        }
        const editable = this.editable;
        const locked = this.locked;
        const effective = this.effective();
        const client = editable
            ? validate(effective, this._catalog, { hasTarget: this.ui.hasTarget, siblings: this.siblingsKnown ? config.siblings : null })
            : [];

        // The cards of the screen, in order
        const rates = this.orderedRates;
        const sharedRates = rates.filter((rate) => kindOf(rate) === 'shared');
        const ownRates = rates.filter((rate) => kindOf(rate) === 'own');
        const feeRates = rates.filter((rate) => kindOf(rate) === 'fee');
        const sections = [SECTION_PERIOD, SECTION_STAGES, SECTION_RATES]
            .concat(ownRates.map((rate) => ownSection(rate.designation)))
            .concat(feeRates.map((rate) => feeSection(rate.designation)))
            .concat([SECTION_OPTIONS]);

        // Server issues first (the authority), then the client's own that the server did not name
        const server = this.serverIssues.map((issue) => (sections.includes(issue.section) ? issue : { ...issue, section: SECTION_GENERAL }));
        const named = new Set(server.map(issueId));
        const all = server.concat(client.filter((issue) => !named.has(issueId(issue))));
        this.issues = all;
        const visible = all.filter((issue) => !issue.quiet || this.showAll || this.touched[issue.section]);

        // Every visible issue is shown exactly once: at its field, or else at the foot of its card
        const placed = new Set();
        const take = (section, slot, rowKey) => {
            const found = visible.filter(
                (issue) => issue.section === section && issue.slot === slot && (rowKey === undefined || issue.rowKey === rowKey)
            );
            found.forEach((issue) => placed.add(issue));
            return found.map((issue) => issue.message).join(' ');
        };
        const forStageList = (section, rows) => {
            const keys = new Set(rows.map((row) => row.key));
            const stageSlots = [SLOT.TRIGGER, SLOT.PARAMETER, SLOT.RELEASE, SLOT.SPLIT];
            const found = visible.filter(
                (issue) => issue.section === section && (stageSlots.includes(issue.slot) || (issue.rowKey && keys.has(issue.rowKey)))
            );
            found.forEach((issue) => placed.add(issue));
            return found.map((issue) => ({ rowKey: issue.rowKey, field: issue.slot === SLOT.SPLIT ? '' : issue.slot, code: issue.code, message: issue.message }));
        };
        const fieldClass = (base, message) => (message ? `${base} haserror` : base);
        const toggleClass = (on) => (on ? 'toggle on' : 'toggle');
        const radioClass = (on) => (on ? 'radio on' : 'radio');
        // A number box of a designation with the issue under it. In the rates table an issue names its row;
        // a designation's own card holds one designation only.
        const numberBox = (rate, field, base) => {
            const rowKey = kindOf(rate) === 'shared' ? rate.key : undefined;
            const message = take(sectionOfRate(rate), SLOT_OF_FIELD[field], rowKey);
            return {
                value: this.shown(rate.designation, field, rate[field]),
                digits: digitsOf(rate[field], DECIMALS[field]),
                error: message,
                className: fieldClass(base, message)
            };
        };

        const vm = { editable, locked, readOnly: !editable };
        vm.head = this.buildHead(config);
        vm.period = this.buildPeriod(config, editable, take, fieldClass);

        // 2. shared payout stages
        const sharedStages = (config.stages || []).filter((stage) => !stage.designation);
        const shared = totals(sharedStages);
        vm.shared = {
            stages: sharedStages,
            issues: forStageList(SECTION_STAGES, sharedStages),
            hint:
                shared.left >= 0
                    ? fill(labels.stagesHint, formatNumber(shared.total), formatNumber(shared.left))
                    : fill(labels.stagesHintOver, formatNumber(shared.total), formatNumber(-shared.left)),
            finalRequired: this.settings.finalStageRequired === true
        };

        // 3. rates and targets of the internal team
        const percentRates = (config.rates || []).filter((rate) => rate.rateType === RATE_PERCENT);
        const common = (field) => (percentRates.find((rate) => !isBlank(rate[field])) || {})[field] || null;
        const catalog = this._catalog || {};
        const basisError = take(SECTION_RATES, SLOT.BASIS);
        const periodError = take(SECTION_RATES, SLOT.TARGET_PERIOD);
        const exceedMode = common('exceedMode');
        vm.rates = {
            basis: common('targetBasis'),
            basisOptions: withCurrent(catalog.targetBases, common('targetBasis')),
            basisError,
            basisClass: fieldClass('fld', basisError),
            period: common('targetPeriod'),
            periodOptions: withCurrent(catalog.targetPeriods, common('targetPeriod')),
            periodError,
            periodClass: fieldClass('fld', periodError),
            modes: withCurrent(catalog.exceedModes, exceedMode).map((option) => ({
                value: option.value,
                label: option.label,
                checked: option.value === exceedMode,
                radioClass: radioClass(option.value === exceedMode)
            })),
            modeError: take(SECTION_RATES, SLOT.EXCEED_MODE),
            hasRows: sharedRates.length > 0,
            rows: sharedRates.map((rate) => {
                const paid = rate.paid === true;
                const showTarget = rate.targetRule !== TARGET_NONE;
                const target = numberBox(rate, 'target', 'cell');
                const current = numberBox(rate, 'currentRate', 'cell');
                const exceed = numberBox(rate, 'exceedRate', 'cell');
                const errors = [target.error, current.error, exceed.error].filter(Boolean).join(' ');
                const name = rate.label || rate.designation;
                return {
                    key: rate.key,
                    designation: rate.designation,
                    label: name,
                    paid,
                    notPaid: !paid,
                    rowClass: paid ? '' : 'off',
                    toggleClass: toggleClass(paid),
                    payLabel: fill(labels.payDesignation, name),
                    showTarget,
                    teamTotal: showTarget && !!rate.aggregateOf,
                    target,
                    current,
                    exceed,
                    targetLabel: fill(labels.fieldOf, name, labels.colTarget),
                    currentLabel: fill(labels.fieldOf, name, labels.colCurrent),
                    exceedLabel: fill(labels.fieldOf, name, labels.colExceed),
                    claimLabel: rate.claimLabel,
                    errors,
                    errorKey: `${rate.key}-errors`
                };
            })
        };

        // 4. one card per designation with its own release
        let number = 3;
        vm.own = ownRates.map((rate) => {
            number += 1;
            const section = ownSection(rate.designation);
            const name = rate.label || rate.designation;
            const paid = rate.paid === true;
            const hasTarget = this.ui.hasTarget[rate.designation] === true;
            const isAll = rate.releaseMode === RELEASE_ALL;
            const isSplit = rate.releaseMode === RELEASE_SPLIT;
            const rows = (config.stages || []).filter((stage) => stage.designation === rate.designation);
            const modeError = take(section, SLOT.RELEASE_MODE);
            return {
                key: rate.key,
                designation: rate.designation,
                section,
                number,
                title: fill(labels.sectionOwn, name),
                shortTitle: name,
                paid,
                notPaid: !paid,
                toggleClass: toggleClass(paid),
                payLabel: fill(labels.payDesignation, name),
                rate: numberBox(rate, 'currentRate', 'fld'),
                rateLabel: fill(labels.fieldOf, name, labels.rate),
                contract: rate.contractReference || '',
                contractLabel: fill(labels.fieldOf, name, labels.contractReference),
                showTargetToggle: rate.targetRule !== TARGET_NONE,
                hasTarget,
                targetToggleClass: toggleClass(hasTarget),
                target: numberBox(rate, 'target', 'fld'),
                exceed: numberBox(rate, 'exceedRate', 'fld'),
                targetLabel: fill(labels.fieldOf, name, labels.colTarget),
                exceedLabel: fill(labels.fieldOf, name, labels.exceedRate),
                radioName: `commission-release-${rate.designation}`,
                modes: [
                    { value: RELEASE_ALL, label: labels.releaseAllInitial, on: isAll },
                    { value: RELEASE_SPLIT, label: labels.releaseSplit, on: isSplit }
                ].map((mode) => ({
                    value: mode.value,
                    label: mode.label,
                    checked: mode.on,
                    cardClass: mode.on ? 'radio-card on' : 'radio-card',
                    radioClass: radioClass(mode.on)
                })),
                modeError,
                showStages: paid && (isAll || isSplit),
                isAllAtInitial: isAll,
                stages: rows,
                issues: paid ? forStageList(section, rows) : []
            };
        });

        // 5. one card per fixed fee
        vm.fees = feeRates.map((rate) => {
            number += 1;
            const name = rate.label || rate.designation;
            const paid = rate.paid === true;
            return {
                key: rate.key,
                designation: rate.designation,
                section: feeSection(rate.designation),
                number,
                title: name,
                shortTitle: name,
                paid,
                notPaid: !paid,
                toggleClass: toggleClass(paid),
                payLabel: fill(labels.payDesignation, name),
                amountLabel: this.settings.currencyCode ? fill(labels.feeAmount, name, this.settings.currencyCode) : name,
                amount: numberBox(rate, 'flatAmount', 'fld'),
                claimLabel: rate.claimLabel
            };
        });

        // 6. options
        const reasonError = take(SECTION_OPTIONS, SLOT.REASON);
        vm.options = {
            number: number + 1,
            priceExcludesTax: config.priceExcludesTax === true,
            priceClass: toggleClass(config.priceExcludesTax === true),
            reason: config.changeReason || '',
            reasonPlaceholder: editable ? labels.changeReasonPlaceholder : '',
            reasonError,
            reasonClass: fieldClass('fld', reasonError),
            showCarryOver: config.changeType === CHANGE_NEXT_PERIOD,
            carryOver: config.carryOverTargets === true,
            carryClass: toggleClass(config.carryOverTargets === true)
        };

        // Issues that have no field of their own: at the foot of their card
        const leftovers = (section) =>
            visible
                .filter((issue) => issue.section === section && !placed.has(issue))
                .map((issue, index) => ({ key: `${section}-${index}`, message: issue.message }));
        vm.period.others = leftovers(SECTION_PERIOD);
        vm.shared.others = leftovers(SECTION_STAGES);
        vm.rates.others = leftovers(SECTION_RATES);
        vm.own.forEach((card) => {
            card.others = card.paid ? leftovers(card.section) : [];
        });
        vm.fees.forEach((card) => {
            card.others = leftovers(card.section);
        });
        vm.options.others = leftovers(SECTION_OPTIONS);
        vm.general = all
            .filter((issue) => issue.section === SECTION_GENERAL)
            .map((issue, index) => ({ key: `general-${index}`, message: issue.message }));
        vm.hasGeneral = vm.general.length > 0;

        // Checklist and footer count every open point, shown at its field yet or not
        const cards = [
            { section: SECTION_PERIOD, label: labels.sectionPeriod },
            { section: SECTION_STAGES, label: labels.sectionStages, left: shared.left },
            { section: SECTION_RATES, label: labels.sectionRates }
        ]
            .concat(vm.own.map((card) => ({ section: card.section, label: card.shortTitle, off: card.notPaid })))
            .concat(vm.fees.map((card) => ({ section: card.section, label: card.shortTitle, off: card.notPaid })))
            .concat([{ section: SECTION_OPTIONS, label: labels.sectionOptions }]);
        const open = all.filter((issue) => issue.section !== SECTION_GENERAL);
        vm.checklist = cards.map((card) => this.buildCheck(card, open.filter((issue) => issue.section === card.section), editable));
        vm.showChecklistFoot = editable;
        if (open.length === 0) {
            vm.checklistFoot = labels.checklistReady;
        } else {
            vm.checklistFoot = open.length === 1 ? labels.checklistItemLeft : fill(labels.checklistItemsLeft, open.length);
        }
        vm.footer = this.buildFooter(config, editable, open, client);
        vm.note = this.buildNote(config, editable);
        this.vm = vm;
    }

    buildHead(config) {
        const look = STATE_LOOK[config.state] || STATE_LOOK.DRAFT;
        const versionText = fill(labels.version, config.version || 1);
        const name = config.name || config.reference;
        let sub = '';
        if (name) {
            sub = fill(labels.joined, name, versionText);
        } else if (config.projectName) {
            sub = labels.newConfiguration;
        }
        let savedText = this.savedText || (config.id ? '' : labels.notSavedYet);
        if (this.busy) {
            savedText = labels.saving;
        } else if (this.dirty) {
            savedText = labels.unsavedChanges;
        }
        const returned = config.state === STATE_RETURNED;
        let banner = '';
        if (returned) {
            // The day of the decision in the browser's time zone, as the review shows it
            const moment = config.decisionOn ? new Date(config.decisionOn) : null;
            const returnedOn = moment && !Number.isNaN(moment.getTime()) ? formatDate(toIso(moment)) : formatDate(config.decisionOn);
            banner = config.decisionComments
                ? fill(labels.returnedBanner, returnedOn, config.decisionComments)
                : fill(labels.returnedBannerNoComment, returnedOn);
        }
        return {
            title: config.projectName || labels.newConfiguration,
            sub,
            pillClass: `pill ${look.tone}`,
            pillText: config.stateLabel || look.label,
            savedText: this.editable ? savedText : '',
            banner,
            changeLabel: CHANGE_LABEL[config.changeType] || '',
            consequence: config.consequence || '',
            hasConsequence: !!config.consequence
        };
    }

    // Why nothing can be changed here
    buildNote(config, editable) {
        if (editable) {
            return this.isEndEarly ? { text: labels.endEarlyNote, className: 'note grey' } : null;
        }
        if (config.status === STATUS_PENDING) {
            return { text: labels.readOnlyPending, className: 'note amber' };
        }
        if (config.status === STATUS_APPROVED) {
            return { text: labels.readOnlyApproved, className: 'note amber' };
        }
        return { text: labels.readOnlyOther, className: 'note grey' };
    }

    buildPeriod(config, editable, take, fieldClass) {
        const isNew = !config.changeType || config.changeType === CHANGE_NEW;
        const projects = (this.projects || []).map((row) => ({ value: row.projectId, label: row.projectName }));
        if (config.projectId && !projects.some((option) => option.value === config.projectId)) {
            projects.push({ value: config.projectId, label: config.projectName || config.projectId });
        }
        const startEditable = editable && !this.isEndEarly && config.changeType !== CHANGE_NEXT_PERIOD;
        const endEditable = editable && config.changeType !== CHANGE_FROM_DATE;
        const projectError = take(SECTION_PERIOD, SLOT.PROJECT);
        const startError = take(SECTION_PERIOD, SLOT.START);
        const endError = take(SECTION_PERIOD, SLOT.END);
        const overlapError = take(SECTION_PERIOD, SLOT.PERIOD);
        const datesGiven = !!config.startDate && !!config.endDate && config.endDate >= config.startDate;
        return {
            showProjectPicker: editable && isNew && !config.id && (this.projects || []).length > 0,
            projectOptions: projects,
            projectId: config.projectId || null,
            projectName: config.projectName || labels.none,
            projectError,
            projectClass: fieldClass('fld', projectError),
            startEditable,
            startDate: config.startDate || null,
            startText: formatDate(config.startDate) || labels.none,
            startError,
            startClass: fieldClass('fld', startError),
            endEditable,
            endDate: config.endDate || null,
            endText: formatDate(config.endDate) || labels.none,
            endError,
            endClass: fieldClass('fld', endError),
            overlapError,
            overlapOk: editable && !overlapError && datesGiven && this.siblingsKnown,
            overlapUnknown: editable && !overlapError && datesGiven && !this.siblingsKnown
        };
    }

    // One line of the checklist: done, or how much is open and the first thing to do
    buildCheck(card, open, editable) {
        const todo = editable && open.length > 0;
        const off = card.off === true && !todo;
        let state = '';
        let stateClass = 'state';
        if (todo) {
            state = card.left > 0 ? fill(labels.stageLeft, formatNumber(card.left)) : fill(labels.checklistOpen, open.length);
        } else if (off) {
            state = labels.checklistNotPaid;
            stateClass = 'state quiet';
        }
        let markClass = 'mark';
        if (todo) {
            markClass = 'mark todo';
        } else if (off) {
            markClass = 'mark off';
        }
        return {
            key: card.section,
            section: card.section,
            label: card.label,
            isTodo: todo,
            isOff: off,
            isDone: !todo && !off,
            markClass,
            state,
            stateClass,
            first: todo ? open[0].message : '',
            goTo: fill(labels.checklistGoTo, card.label),
            assistive: todo || off ? '' : labels.checklistDone
        };
    }

    buildFooter(config, editable, open, client) {
        let leftText = '';
        if (editable) {
            if (open.length === 0) {
                leftText = labels.ready;
            } else {
                leftText = open.length === 1 ? fill(labels.itemLeftFirst, open[0].short) : fill(labels.itemsLeftFirst, open.length, open[0].short);
            }
        }
        // Only the editor's own checks keep Submit off: what the server said is asked again by pressing it
        const submitOff = this.busy || client.length > 0 || config.canSubmit === false;
        return {
            showDiscard: editable && !!config.id && config.canDiscard === true,
            leftText,
            saveDisabled: this.busy || (!this.dirty && !!config.id),
            submitDisabled: submitOff,
            submitClass: submitOff ? 'btn disabled' : 'btn primary'
        };
    }

    // ------------------------------------------------------------ typed text of the number boxes

    remember(designation, field, text, amount) {
        this.typed[`${designation}|${field}`] = { text, amount };
    }

    // The text exactly as typed while it still stands for the stored number, else the stored number
    shown(designation, field, amount) {
        const typed = this.typed[`${designation}|${field}`];
        const stored = isBlank(amount) ? null : Number(amount);
        return typed && typed.amount === stored ? typed.text : stored;
    }

    // ------------------------------------------------------------ changes

    // After the working copy changed: the section counts as touched, what the server said about it is outdated
    changed(section) {
        this.dirty = true;
        this.touched[section] = true;
        this.serverIssues = this.serverIssues.filter((issue) => issue.section !== section && issue.section !== SECTION_GENERAL);
        this.blockNote = '';
        this.refresh();
    }

    handleProject(event) {
        const config = this.config;
        const projectId = event.detail.value || null;
        const project = (this.projects || []).find((row) => row.projectId === projectId);
        // Before a project was chosen the instalments of every company were on offer
        const hadProject = !!config.projectId;
        config.projectId = projectId;
        config.projectName = project ? project.projectName : null;
        const companyId = project ? project.companyId || null : null;
        if (companyId !== (config.companyId || null) || !hadProject) {
            // Instalments belong to a company: one of another company cannot stay
            const allowed = new Set(
                ((this._catalog && this._catalog.installments) || []).filter((entry) => (entry.companyId || null) === companyId).map((entry) => entry.id)
            );
            (config.stages || []).forEach((stage) => {
                if (stage.installmentId && !allowed.has(stage.installmentId)) {
                    stage.installmentId = null;
                    stage.installmentName = null;
                }
            });
        }
        config.companyId = companyId;
        this.changed(SECTION_PERIOD);
    }

    handleDate(event) {
        const field = event.currentTarget.dataset.field;
        this.config[field] = nullIfBlank(event.detail.value);
        // The sentence under the title names this date: it comes back from the server with the next save
        if (this.config.changeType === CHANGE_FROM_DATE || this.config.changeType === CHANGE_END_EARLY) {
            this.config.consequence = null;
        }
        this.changed(SECTION_PERIOD);
    }

    // A stage list sends its whole new list. The inputs inside it fire "change" too: those carry no list.
    handleSharedStages(event) {
        const rows = event.detail && event.detail.stages;
        if (!Array.isArray(rows)) {
            return;
        }
        const others = (this.config.stages || []).filter((stage) => stage.designation);
        this.config.stages = rows.map((row) => ({ ...row, designation: null })).concat(others);
        this.changed(SECTION_STAGES);
    }

    handleOwnStages(event) {
        const rows = event.detail && event.detail.stages;
        if (!Array.isArray(rows)) {
            return;
        }
        const designation = event.currentTarget.dataset.key;
        const others = (this.config.stages || []).filter((stage) => stage.designation !== designation);
        this.config.stages = others.concat(rows.map((row) => ({ ...row, designation })));
        this.changed(ownSection(designation));
    }

    // The three choices above the rates table apply to every percentage rate
    setOnPercentRates(field, value) {
        (this.config.rates || [])
            .filter((rate) => rate.rateType === RATE_PERCENT)
            .forEach((rate) => {
                rate[field] = value;
            });
        this.changed(SECTION_RATES);
    }

    handleBasis(event) {
        this.setOnPercentRates('targetBasis', event.detail.value || null);
    }

    handleTargetPeriod(event) {
        this.setOnPercentRates('targetPeriod', event.detail.value || null);
    }

    handleExceedMode(event) {
        this.setOnPercentRates('exceedMode', event.target.value || null);
    }

    handlePaid(event) {
        const rate = this.rateOf(event.currentTarget.dataset.key);
        if (!rate) {
            return;
        }
        rate.paid = event.target.checked === true;
        this.changed(sectionOfRate(rate));
    }

    // Target, current rate, exceed rate and the amount of a fee
    handleRateNumber(event) {
        const { key, field } = event.currentTarget.dataset;
        const rate = this.rateOf(key);
        if (!rate) {
            return;
        }
        const text = event.detail.value;
        let amount = toNumber(text);
        if (amount !== null) {
            amount = round(amount, DECIMALS[field]);
        }
        this.remember(key, field, text, amount);
        rate[field] = amount;
        this.changed(sectionOfRate(rate));
    }

    handleContract(event) {
        const rate = this.rateOf(event.currentTarget.dataset.key);
        if (!rate) {
            return;
        }
        rate.contractReference = event.detail.value;
        this.changed(sectionOfRate(rate));
    }

    handleHasTarget(event) {
        const designation = event.currentTarget.dataset.key;
        this.ui.hasTarget[designation] = event.target.checked === true;
        this.changed(ownSection(designation));
    }

    // "All at the Initial event" needs the Initial stage; "Split" an Initial and a Final stage
    handleReleaseMode(event) {
        const designation = event.currentTarget.dataset.key;
        const rate = this.rateOf(designation);
        if (!rate) {
            return;
        }
        const mode = event.target.value;
        rate.releaseMode = mode;
        const stages = this.config.stages || [];
        const mine = stages.filter((stage) => stage.designation === designation);
        let initial = mine.find((stage) => stage.stageType === STAGE_INITIAL);
        let final = mine.find((stage) => stage.stageType === STAGE_FINAL);
        if (!initial) {
            initial = this.newStage(STAGE_INITIAL, designation, 1);
            stages.push(initial);
        }
        if (mode === RELEASE_SPLIT) {
            if (!final) {
                final = this.newStage(STAGE_FINAL, designation, 2);
                stages.push(final);
            }
            // Coming from "all at Initial": the 100 % makes room for the split
            if (Number(initial.releasePercent) === FULL && isBlank(final.releasePercent)) {
                initial.releasePercent = null;
            }
        }
        this.config.stages = stages;
        this.changed(ownSection(designation));
    }

    newStage(stageType, designation, sequence) {
        return {
            id: null,
            key: tempKey('stage'),
            stageType,
            sequence,
            triggerKey: null,
            triggerLabel: null,
            parameterType: 'None',
            triggerPercent: null,
            triggerTranche: null,
            installmentId: null,
            installmentName: null,
            releasePercent: null,
            designation
        };
    }

    handlePriceTax(event) {
        this.config.priceExcludesTax = event.target.checked === true;
        this.changed(SECTION_OPTIONS);
    }

    handleCarryOver(event) {
        this.config.carryOverTargets = event.target.checked === true;
        this.changed(SECTION_OPTIONS);
    }

    handleReason(event) {
        this.config.changeReason = event.detail.value;
        this.changed(SECTION_OPTIONS);
    }

    // A line of the checklist brings its card into view
    handleChecklist(event) {
        const section = event.currentTarget.dataset.section;
        const card = [...this.template.querySelectorAll('[data-card]')].find((element) => element.dataset.card === section);
        if (card && typeof card.scrollIntoView === 'function') {
            card.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    // ------------------------------------------------------------ save, submit, discard, back

    toast(title, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, variant }));
    }

    announce(name, detail) {
        this.dispatchEvent(new CustomEvent(name, { detail }));
    }

    handleSave() {
        return this.save(ACTION_DRAFT, null, false);
    }

    // Saves the draft, or saves and submits it. Whatever goes wrong, the working copy stays as typed.
    // Returns true when the server saved it.
    async save(action, approverId, quiet) {
        if (this.busy || !this.editable) {
            return false;
        }
        // What the server would refuse anyway is said at once, without the round trip
        const blocking = this.issues.filter((issue) => issue.client && !issue.submitOnly);
        if (blocking.length) {
            this.showAll = true;
            this.blockNote =
                blocking.length === 1 ? fill(labels.notSavedOne, blocking[0].message) : fill(labels.notSavedMany, blocking.length, blocking[0].message);
            this.refresh();
            return false;
        }
        this.busy = true;
        this.saveError = '';
        this.blockNote = '';
        this.refresh();
        let saved = false;
        try {
            const result = (await saveConfig({ payload: this.payload(approverId), action })) || {};
            saved = this.afterSave(result, action, quiet);
        } catch (error) {
            this.saveError = errorText(error, labels.error);
        } finally {
            this.busy = false;
            this.refresh();
        }
        return saved;
    }

    afterSave(result, action, quiet) {
        if (result.saved !== true) {
            const issues = adoptIssues(result.issues, this.config);
            this.serverIssues = issues;
            this.showAll = true;
            if (issues.length === 0) {
                this.blockNote = labels.error;
            } else {
                this.blockNote =
                    issues.length === 1 ? fill(labels.notSavedOne, issues[0].message) : fill(labels.notSavedMany, issues.length, issues[0].message);
            }
            return false;
        }
        // The saved configuration (with its ids) replaces the working copy
        if (result.config) {
            // The three target options live on paid percentage rates only: while none is paid the server has
            // nowhere to keep them, so what was chosen stays in the working copy
            const optionFields = ['targetBasis', 'targetPeriod', 'exceedMode'];
            const percentOf = (copy) => ((copy && copy.rates) || []).filter((rate) => rate.rateType === RATE_PERCENT);
            const chosen = {};
            optionFields.forEach((field) => {
                chosen[field] = (percentOf(this.config).find((rate) => !isBlank(rate[field])) || {})[field];
            });
            this.adopt(result.config);
            if (this.editable) {
                optionFields.forEach((field) => {
                    const rates = percentOf(this.config);
                    if (!isBlank(chosen[field]) && !rates.some((rate) => !isBlank(rate[field]))) {
                        rates.forEach((rate) => {
                            rate[field] = chosen[field];
                        });
                    }
                });
            }
        } else {
            this.dirty = false;
        }
        this.showAll = true;
        this.savedText = fill(labels.savedAt, clock(new Date()));
        this.serverIssues = adoptIssues(result.issues, this.config);
        const config = clone(this.config);
        if (action === ACTION_SUBMIT && result.submitted === true) {
            this.toast(labels.toastSubmitted, 'success');
            this.announce('submitted', { config });
            return true;
        }
        if (action === ACTION_SUBMIT) {
            // Saved, but the server found something that stops the submit
            const first = this.serverIssues.length ? this.serverIssues[0].message : labels.error;
            this.blockNote = fill(labels.notSubmitted, first);
        } else if (!quiet) {
            this.toast(labels.toastSaved, 'success');
        }
        this.announce('saved', { config });
        return true;
    }

    async handleSubmit() {
        if (this.busy || !this.editable || !this.vm || this.vm.footer.submitDisabled) {
            return;
        }
        // Who can approve is known once the draft exists on the server
        if (!this.config.id) {
            const saved = await this.save(ACTION_DRAFT, null, true);
            if (!saved || this.vm.footer.submitDisabled) {
                return;
            }
        }
        const approvers = this.config.approvers || [];
        let approverId = null;
        if (approvers.length > 1) {
            approverId = await SubmitDialog.open({
                size: 'small',
                label: labels.submitTitle,
                approvers: approvers.map((person) => ({ value: person.id, label: person.name })),
                selected: this.config.approverId || null
            });
            if (!approverId) {
                return;
            }
        } else {
            const message = approvers.length === 1 ? fill(labels.submitMessageTo, approvers[0].name) : labels.submitMessage;
            const confirmed = await LightningConfirm.open({ message, label: labels.submitTitle, variant: 'header', theme: 'default' });
            if (!confirmed) {
                return;
            }
            approverId = approvers.length === 1 ? approvers[0].id : null;
        }
        await this.save(ACTION_SUBMIT, approverId, false);
    }

    async handleDiscard() {
        const config = this.config;
        if (this.busy || !config || !config.id) {
            return;
        }
        const confirmed = await LightningConfirm.open({
            message: fill(labels.discardMessage, config.name || ''),
            label: labels.discardTitle,
            variant: 'header',
            theme: 'error'
        });
        if (!confirmed) {
            return;
        }
        this.busy = true;
        this.saveError = '';
        this.refresh();
        try {
            await discardDraft({ configId: config.id });
            this.dirty = false;
            this.toast(labels.toastDiscarded, 'success');
            this.announce('discarded');
        } catch (error) {
            this.saveError = errorText(error, labels.error);
        } finally {
            this.busy = false;
            this.refresh();
        }
    }

    // Leaving with unsaved changes asks first
    async handleBack() {
        if (this.dirty && this.editable) {
            const confirmed = await LightningConfirm.open({
                message: labels.leaveMessage,
                label: labels.leaveTitle,
                variant: 'header',
                theme: 'warning'
            });
            if (!confirmed) {
                return;
            }
        }
        this.dirty = false;
        this.announce('back');
    }

    handleRetry() {
        if (this._draft) {
            this.loadError = '';
            this.adopt(this._draft);
        } else if (this._configId) {
            this.load(this._configId);
        }
    }

    // After a refused save (someone else changed the configuration): take the latest version from the server
    async handleReload() {
        const configId = this.config && this.config.id;
        if (!configId) {
            return;
        }
        if (this.dirty) {
            const confirmed = await LightningConfirm.open({
                message: labels.reloadMessage,
                label: labels.reloadTitle,
                variant: 'header',
                theme: 'warning'
            });
            if (!confirmed) {
                return;
            }
        }
        this._draft = null;
        this.load(configId);
    }

    get showReload() {
        return !!this.saveError && !!this.config && !!this.config.id;
    }

    get showBlockNote() {
        return !!this.blockNote && !this.saveError;
    }
}

// The options of a list, with the stored value added when the catalog no longer offers it
function withCurrent(options, value) {
    const list = (options || []).map((option) => ({ value: option.value, label: option.label }));
    if (!isBlank(value) && !list.some((option) => option.value === value)) {
        list.push({ value, label: value });
    }
    return list;
}