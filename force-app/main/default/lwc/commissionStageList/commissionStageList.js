import { LightningElement, api } from 'lwc';
import { clone, fill, formatNumber, indexBy, sum, tempKey, toNumber } from 'c/commissionUtils';
import { labels } from './labels';

// Structural values of the data model (CommissionDto.Stage, Commission_Trigger__mdt)
const INITIAL = 'Initial';
const MID = 'Mid';
const FINAL = 'Final';
const TYPE_ORDER = { [INITIAL]: 0, [MID]: 1, [FINAL]: 2 };
const SEGMENT_TONE = { [INITIAL]: 'a', [MID]: 'b', [FINAL]: 'c' };
const PARAMETER_PERCENT = 'Percent';
const PARAMETER_TRANCHE = 'Tranche';
const PARAMETER_INSTALLMENT = 'Installment';
const PARAMETER_NONE = 'None';
const FULL = 100;

// The three places of a row an issue can be pinned to
const SLOT_TRIGGER = 'trigger';
const SLOT_PARAMETER = 'parameter';
const SLOT_RELEASE = 'release';

const isBlank = (value) => value === '' || value === null || value === undefined;
const round = (value, decimals) => {
    const factor = Math.pow(10, decimals);
    return Math.round(value * factor) / factor;
};
// Whole numbers without decimals, others with two
const digitsOf = (value) => (isBlank(value) || Number.isInteger(Number(value)) ? 0 : 2);

// Initial first, then the Mid stages in their sequence, Final last
function inOrder(stages) {
    return [...(stages || [])].sort((first, second) => {
        const byType = (TYPE_ORDER[first.stageType] ?? 1) - (TYPE_ORDER[second.stageType] ?? 1);
        return byType !== 0 ? byType : (first.sequence || 0) - (second.sequence || 0);
    });
}

// Where on the row an issue belongs. The editor sends trigger / parameter / release; the names of
// CommissionDto.Stage and the validator's codes are understood too.
function slotOf(issue) {
    const field = String(issue.field || '').toLowerCase().replace(/__c$/, '').replace(/[^a-z]/g, '');
    const code = String(issue.code || '');
    if (field.includes('release')) {
        return SLOT_RELEASE;
    }
    if (field.includes('parameter') || field.includes('installment') || field.includes('tranche') || field === 'triggerpercent') {
        return SLOT_PARAMETER;
    }
    if (field.includes('trigger')) {
        return SLOT_TRIGGER;
    }
    if (code === 'STAGE_TRIGGER_REQUIRED' || code === 'STAGE_TRIGGER_INVALID') {
        return SLOT_TRIGGER;
    }
    if (code === 'STAGE_PARAMETER_REQUIRED' || code === 'STAGE_MID_ORDER') {
        return SLOT_PARAMETER;
    }
    if (code === 'STAGE_PERCENT_REQUIRED' || code === 'STAGE_PERCENT_RANGE') {
        return SLOT_RELEASE;
    }
    return '';
}

// The payout stages of one split: the shared stages of the internal team, or the own release of one designation.
// It keeps no copy: every edit is sent to the parent as the whole new list (event "change", detail.stages).
export default class CommissionStageList extends LightningElement {
    labels = labels;

    // catalog.triggers: the payout events ("paid when")
    @api triggers;
    // catalog.installments of the project's company
    @api installments;
    // true: the Final stage cannot be removed
    @api finalRequired = false;
    // Blank for the shared stages, else the key of the designation whose own release this is
    @api designation;
    @api readOnly = false;
    // The issues of this split (CommissionDto.Issue): pinned to a row by rowKey, else shown under the rows
    @api issues;
    // true: only the Initial row, released at 100 % ("All at the Initial event")
    @api single = false;

    _stages = [];
    _allowMid = true;
    // What the user typed in a number box, so that "12." is not rewritten to "12" while typing
    typed = {};

    @api
    get stages() {
        return this._stages;
    }
    set stages(value) {
        this._stages = Array.isArray(value) ? value : [];
    }

    // false: no Mid stages (a designation's own release has Initial and Final only)
    @api
    get allowMid() {
        return this._allowMid;
    }
    set allowMid(value) {
        this._allowMid = !(value === false || value === 'false');
    }

    // ------------------------------------------------------------ what the template shows

    get ordered() {
        const rows = inOrder(this._stages);
        return this.single ? rows.filter((row) => row.stageType === INITIAL).slice(0, 1) : rows;
    }

    get triggerIndex() {
        return indexBy(this.triggers || [], 'key');
    }

    nameOf(row, midNumber) {
        if (row.stageType === INITIAL) {
            return labels.initial;
        }
        if (row.stageType === FINAL) {
            return labels.final;
        }
        return fill(labels.midNumbered, midNumber);
    }

    // Every row with its name: "Initial", "Mid 1", "Mid 2", "Final"
    get named() {
        let mid = 0;
        return this.ordered.map((row) => {
            if (row.stageType === MID) {
                mid += 1;
            }
            return { row, name: this.nameOf(row, mid) };
        });
    }

    get total() {
        if (this.single) {
            return FULL;
        }
        return sum(this.ordered.map((row) => row.releasePercent));
    }

    get left() {
        return round(FULL - this.total, 2);
    }

    get rows() {
        const triggerIndex = this.triggerIndex;
        const named = this.named;
        const midCount = named.filter((entry) => entry.row.stageType === MID).length;
        const pinned = this.pinnedIssues;
        let midSeen = 0;
        return named.map(({ row, name }) => {
            const isMid = row.stageType === MID;
            if (isMid) {
                midSeen += 1;
            }
            const trigger = triggerIndex[row.triggerKey];
            const parameterType = (trigger ? trigger.parameterType : row.parameterType) || PARAMETER_NONE;
            const errors = pinned.filter((entry) => entry.rowKey === row.key);
            const hasError = (slot) => errors.some((entry) => entry.slot === slot);
            const canRemove = !this.readOnly && !this.single && (isMid || (row.stageType === FINAL && !this.finalRequired));
            const isPercent = parameterType === PARAMETER_PERCENT;
            const isTranche = parameterType === PARAMETER_TRANCHE;
            const parameterField = isPercent ? 'triggerPercent' : 'triggerTranche';
            const parameterLabel = (trigger && trigger.parameterLabel) || '';
            return {
                key: row.key,
                name,
                triggerKey: row.triggerKey || null,
                triggerOptions: this.triggerOptions(row),
                triggerLabel: fill(labels.fieldOf, name, labels.paidWhen),
                triggerClass: hasError(SLOT_TRIGGER) ? 'fld haserror' : 'fld',
                showNumberParameter: isPercent || isTranche,
                showInstallment: parameterType === PARAMETER_INSTALLMENT,
                parameterField,
                parameterValue: this.shown(row.key, parameterField, row[parameterField]),
                parameterDigits: isPercent ? digitsOf(row.triggerPercent) : 0,
                parameterSuffix: parameterLabel,
                parameterLabel: fill(labels.fieldOf, name, parameterLabel || trigger?.label || labels.paidWhen),
                parameterClass: hasError(SLOT_PARAMETER) ? 'fld narrow haserror' : 'fld narrow',
                installmentId: row.installmentId || null,
                installmentOptions: this.installmentOptions(row),
                installmentLabel: fill(labels.fieldOf, name, labels.installment),
                installmentClass: hasError(SLOT_PARAMETER) ? 'fld haserror' : 'fld',
                releaseValue: this.shown(row.key, 'releasePercent', row.releasePercent),
                releaseDigits: digitsOf(row.releasePercent),
                releaseLabel: fill(labels.fieldOf, name, labels.percentOfCommission),
                releaseClass: hasError(SLOT_RELEASE) ? 'fld narrow haserror' : 'fld narrow',
                canRemove,
                removeLabel: fill(labels.removeNamed, name),
                showMove: !this.readOnly && isMid && midCount > 1,
                cannotMoveUp: midSeen <= 1,
                cannotMoveDown: midSeen >= midCount,
                moveUpLabel: fill(labels.moveUp, name),
                moveDownLabel: fill(labels.moveDown, name),
                hasErrors: errors.length > 0,
                errors: errors.map((entry, index) => ({ key: `${row.key}-e${index}`, message: entry.message }))
            };
        });
    }

    // The events allowed for the stage type; an event that was switched off stays visible on the row that uses it
    triggerOptions(row) {
        const options = (this.triggers || [])
            .filter((trigger) => (trigger.stageTypes || []).includes(row.stageType))
            .map((trigger) => ({ value: trigger.key, label: trigger.label }));
        if (row.triggerKey && !options.some((option) => option.value === row.triggerKey)) {
            const known = this.triggerIndex[row.triggerKey];
            options.push({ value: row.triggerKey, label: (known && known.label) || row.triggerLabel || row.triggerKey });
        }
        return options;
    }

    installmentOptions(row) {
        const options = (this.installments || []).map((entry) => ({ value: entry.id, label: entry.name }));
        if (row.installmentId && !options.some((option) => option.value === row.installmentId)) {
            options.push({ value: row.installmentId, label: row.installmentName || row.installmentId });
        }
        return options;
    }

    // Issues with the place they belong to. An issue whose row is not in this list is shown under the rows.
    get located() {
        const keyOf = {};
        this.ordered.forEach((row) => {
            keyOf[row.key] = row.key;
            if (row.id) {
                keyOf[row.id] = row.key;
            }
        });
        return (this.issues || []).map((issue) => ({
            rowKey: isBlank(issue.rowKey) ? null : keyOf[issue.rowKey] || null,
            slot: slotOf(issue),
            message: issue.message
        }));
    }

    get pinnedIssues() {
        return this.located.filter((entry) => entry.rowKey);
    }

    get generalIssues() {
        return this.located
            .filter((entry) => !entry.rowKey)
            .map((entry, index) => ({ key: `general-${index}`, message: entry.message }));
    }

    get hasGeneralIssues() {
        return this.generalIssues.length > 0;
    }

    get hasRows() {
        return this.ordered.length > 0;
    }

    get showEmpty() {
        return !this.hasRows && this.readOnly;
    }

    // The 100 % bar is of no use for a single payout at 100 %
    get showBar() {
        return !this.single;
    }

    get barClass() {
        return this.designation ? 'bar thin' : 'bar';
    }

    // One segment per stage that has a percentage, then "x% left". Above 100 % the segments are scaled down to fit.
    get segments() {
        const total = this.total;
        const scale = total > FULL ? FULL / total : 1;
        const segments = [];
        const named = this.named;
        // A single Mid stage is simply "Mid" on the bar
        const oneMid = named.filter((entry) => entry.row.stageType === MID).length === 1;
        named.forEach(({ row, name }) => {
            const percent = toNumber(row.releasePercent);
            if (percent && percent > 0) {
                segments.push({
                    key: row.key,
                    className: `seg ${SEGMENT_TONE[row.stageType] || 'b'}`,
                    style: `width:${round(percent * scale, 3)}%`,
                    text: fill(labels.segment, oneMid && row.stageType === MID ? labels.mid : name, formatNumber(percent))
                });
            }
        });
        if (this.left > 0) {
            segments.push({ key: 'left', className: 'seg left', style: `width:${this.left}%`, text: fill(labels.left, formatNumber(this.left)) });
        }
        return segments;
    }

    // Read out by a screen reader whenever the total changes
    get summaryText() {
        if (this.single) {
            return '';
        }
        const total = formatNumber(this.total);
        return this.left >= 0
            ? fill(labels.summaryLeft, total, formatNumber(this.left))
            : fill(labels.summaryOver, total, formatNumber(-this.left));
    }

    get showHead() {
        return !this.designation && this.hasRows;
    }

    get hasParameterColumn() {
        if (this.single) {
            return this.rows.some((row) => row.showNumberParameter || row.showInstallment);
        }
        return this._allowMid || this.rows.some((row) => row.showNumberParameter || row.showInstallment);
    }

    get gridClass() {
        return this.hasParameterColumn ? 'stages' : 'stages short';
    }

    get headClass() {
        return `${this.gridClass} head`;
    }

    get editable() {
        return !this.readOnly;
    }

    get hasInitial() {
        return this.ordered.some((row) => row.stageType === INITIAL);
    }

    get finalRow() {
        return this.ordered.find((row) => row.stageType === FINAL);
    }

    get showAddInitial() {
        return this.editable && !this.hasInitial;
    }

    get showAddMid() {
        return this.editable && !this.single && this._allowMid;
    }

    get showAddFinal() {
        return this.editable && !this.single && !this.finalRow;
    }

    get isComplete() {
        return !this.single && this.hasRows && this.left === 0;
    }

    get isOver() {
        return !this.single && this.left < 0;
    }

    get hasLeft() {
        return !this.single && this.hasRows && this.left > 0;
    }

    get allocatedText() {
        return fill(labels.allocated, formatNumber(FULL));
    }

    get leftText() {
        return fill(labels.left, formatNumber(this.left));
    }

    get overText() {
        return fill(labels.over, formatNumber(-this.left));
    }

    // "Put the remaining 10% in Final": once something is allocated and only while Final has no percentage yet
    get showPutRemaining() {
        const final = this.finalRow;
        return this.editable && this.hasLeft && this.total > 0 && !!final && isBlank(final.releasePercent);
    }

    get putRemainingText() {
        return fill(labels.putRemaining, formatNumber(this.left));
    }

    get fixedPercentText() {
        return formatNumber(FULL);
    }

    // ------------------------------------------------------------ typed text of the number boxes

    remember(rowKey, field, text, amount) {
        this.typed[`${rowKey}|${field}`] = { text, amount };
    }

    // The text exactly as typed while it still stands for the stored number, else the stored number
    shown(rowKey, field, amount) {
        const typed = this.typed[`${rowKey}|${field}`];
        const stored = isBlank(amount) ? null : Number(amount);
        return typed && typed.amount === stored ? typed.text : stored;
    }

    // ------------------------------------------------------------ changes

    // The inner inputs fire "change" too; only the list's own event may reach the parent
    quiet(event) {
        event.stopPropagation();
        return event.currentTarget.dataset.key;
    }

    // Sends the new list: Initial, Mid in their order, Final, numbered 1, 2, 3 ...
    send(rows) {
        const designation = this.designation || null;
        const stages = inOrder(rows).map((row, index) => ({ ...row, sequence: index + 1, designation }));
        this.dispatchEvent(new CustomEvent('change', { detail: { stages } }));
    }

    // A copy of the rows with one of them changed
    change(rowKey, apply) {
        const rows = clone(inOrder(this._stages));
        const row = rows.find((entry) => entry.key === rowKey);
        if (!row) {
            return;
        }
        apply(row, rows);
        this.send(rows);
    }

    newRow(stageType) {
        return {
            id: null,
            key: tempKey('stage'),
            stageType,
            sequence: null,
            triggerKey: null,
            triggerLabel: null,
            parameterType: PARAMETER_NONE,
            triggerPercent: null,
            triggerTranche: null,
            installmentId: null,
            installmentName: null,
            releasePercent: null,
            designation: this.designation || null
        };
    }

    handleTrigger(event) {
        const rowKey = this.quiet(event);
        const triggerKey = event.detail.value || null;
        const trigger = this.triggerIndex[triggerKey];
        this.change(rowKey, (row) => {
            row.triggerKey = triggerKey;
            row.triggerLabel = trigger ? trigger.label : null;
            row.parameterType = (trigger && trigger.parameterType) || PARAMETER_NONE;
            // A parameter of another kind of event means nothing for this one
            if (row.parameterType !== PARAMETER_PERCENT) {
                row.triggerPercent = null;
            }
            if (row.parameterType !== PARAMETER_TRANCHE) {
                row.triggerTranche = null;
            }
            if (row.parameterType !== PARAMETER_INSTALLMENT) {
                row.installmentId = null;
                row.installmentName = null;
            }
        });
    }

    // Release %, % paid and tranche number
    handleNumber(event) {
        const rowKey = this.quiet(event);
        const field = event.currentTarget.dataset.field;
        const text = event.detail ? event.detail.value : event.target.value;
        let amount = toNumber(text);
        if (amount !== null) {
            // Percentages keep two decimals (the fields are Number(5,2)); a tranche number is whole
            amount = field === 'triggerTranche' ? Math.round(amount) : round(amount, 2);
        }
        this.remember(rowKey, field, text, amount);
        this.change(rowKey, (row) => {
            row[field] = amount;
        });
    }

    handleInstallment(event) {
        const rowKey = this.quiet(event);
        const installmentId = event.detail.value || null;
        const chosen = (this.installments || []).find((entry) => entry.id === installmentId);
        this.change(rowKey, (row) => {
            row.installmentId = installmentId;
            row.installmentName = chosen ? chosen.name : null;
        });
    }

    handleRemove(event) {
        const rowKey = event.currentTarget.dataset.key;
        this.send(clone(inOrder(this._stages)).filter((row) => row.key !== rowKey));
    }

    handleMoveUp(event) {
        this.move(event.currentTarget.dataset.key, -1);
    }

    handleMoveDown(event) {
        this.move(event.currentTarget.dataset.key, 1);
    }

    // Swaps a Mid stage with its neighbour; the order is what "Mid 1", "Mid 2" means
    move(rowKey, step) {
        const rows = clone(inOrder(this._stages));
        const from = rows.findIndex((row) => row.key === rowKey);
        const to = from + step;
        if (from < 0 || to < 0 || to >= rows.length || rows[to].stageType !== MID || rows[from].stageType !== MID) {
            return;
        }
        [rows[from], rows[to]] = [rows[to], rows[from]];
        rows.forEach((row, index) => {
            row.sequence = index + 1;
        });
        this.send(rows);
    }

    handleAddInitial() {
        this.send([...clone(inOrder(this._stages)), this.newRow(INITIAL)]);
    }

    handleAddMid() {
        const rows = clone(inOrder(this._stages));
        const row = this.newRow(MID);
        // After the last Mid stage, before Final
        row.sequence = rows.reduce((highest, entry) => Math.max(highest, entry.sequence || 0), 0) + 1;
        this.send([...rows, row]);
    }

    handleAddFinal() {
        this.send([...clone(inOrder(this._stages)), this.newRow(FINAL)]);
    }

    handlePutRemaining() {
        const final = this.finalRow;
        const left = this.left;
        if (!final || left <= 0) {
            return;
        }
        delete this.typed[`${final.key}|releasePercent`];
        this.change(final.key, (row) => {
            row.releasePercent = left;
        });
    }
}