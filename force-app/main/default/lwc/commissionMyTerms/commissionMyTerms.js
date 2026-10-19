import { LightningElement, api } from 'lwc';
import { errorText, fill, formatNumber, formatPercent } from 'c/commissionUtils';
import getMyTerms from '@salesforce/apex/CommissionTargetController.getMyTerms';
const ERROR = 'Something went wrong. Please try again.';
const LOADING = 'Loading…';
const RETRY = 'Try again';
const NONE = '—';
const STAGE_INITIAL = 'Initial';
const STAGE_MID = 'Mid {0}';
const STAGE_FINAL = 'Final';
const TWO_PARTS = '{0} · {1}';
const TITLE = 'My commission terms';
const SUBTITLE = 'Your target and rates in the commission configurations in force today. Read-only.';
const EMPTY = 'No commission terms apply to you at the moment.';
const TARGET = 'Target';
const TARGET_DEFAULT = '{0} {1} · default';
const TARGET_PERSONAL = '{0} {1} · set for you';
const NO_TARGET = 'No target';
const CURRENT_RATE = 'Current rate';
const EXCEED_RATE = 'Exceed rate';
const FEE = 'Fee';
const CLAIM_OPENS = 'Claim opens';
const STAGES = 'Payout stages';
const COL_STAGE = 'Stage';
const COL_PAID_WHEN = 'Paid when';
const COL_PERCENT = '% of commission';
const PAID_WHEN_DETAIL = '{0}: {1}';
const NO_STAGES = 'No payout stages are set.';

const LABELS = {
    loading: LOADING,
    retry: RETRY,
    title: TITLE,
    subtitle: SUBTITLE,
    empty: EMPTY,
    target: TARGET,
    currentRate: CURRENT_RATE,
    exceedRate: EXCEED_RATE,
    fee: FEE,
    claimOpens: CLAIM_OPENS,
    stages: STAGES,
    colStage: COL_STAGE,
    colPaidWhen: COL_PAID_WHEN,
    colPercent: COL_PERCENT,
    noStages: NO_STAGES
};

// Structural values of CommissionDto (rate type, stage type, what a payout event asks for)
const RATE_FLAT = 'Flat';
const STAGE_TYPE_INITIAL = 'Initial';
const STAGE_TYPE_MID = 'Mid';
const STAGE_TYPE_FINAL = 'Final';
const PARAMETER_PERCENT = 'Percent';
const PARAMETER_TRANCHE = 'Tranche';
const PARAMETER_INSTALLMENT = 'Installment';

const isBlank = (value) => value === null || value === undefined || value === '';
const orDash = (text) => (isBlank(text) ? NONE : text);
// 80 -> '80%', 12.5 -> '12.50%': a share of the commission reads best without empty decimals
const shortPercent = (value) => (isBlank(value) ? '' : formatPercent(value, Number.isInteger(Number(value)) ? 0 : 2));

// The read-only "My terms" view: what the running user is paid in every configuration in force (CommissionDto.MyTerm)
export default class CommissionMyTerms extends LightningElement {
    labels = LABELS;

    // Shown in front of a flat fee; the shell passes the code from Commission Setting
    @api currencyCode;

    terms = [];
    loading = true;
    error = '';

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        this.error = '';
        try {
            const terms = await getMyTerms();
            this.terms = (terms || []).map((term, index) => this.toCard(term, index));
        } catch (error) {
            this.terms = [];
            this.error = errorText(error, ERROR);
        } finally {
            this.loading = false;
        }
    }

    // One card with its ready-made texts
    toCard(term, index) {
        const isFlat = term.rateType === RATE_FLAT;
        const amount = formatNumber(term.flatAmount);
        return {
            key: `term-${index}`,
            projectName: term.projectName,
            configLine: isBlank(term.periodText) ? term.configName : fill(TWO_PARTS, term.configName, term.periodText),
            designationLabel: term.designationLabel,
            isFlat,
            targetText: this.targetText(term),
            currentRateText: orDash(formatPercent(term.currentRate)),
            exceedRateText: orDash(formatPercent(term.exceedRate)),
            feeText: amount === '' ? NONE : isBlank(this.currencyCode) ? amount : `${this.currencyCode} ${amount}`,
            claimText: orDash(term.claimLabel),
            stages: this.toStages(term.stages),
            hasStages: (term.stages || []).length > 0
        };
    }

    // "10 units · default", or the personal target of this user
    targetText(term) {
        if (isBlank(term.target)) {
            return NO_TARGET;
        }
        const basis = isBlank(term.basisLabel) ? '' : String(term.basisLabel).toLowerCase();
        return fill(term.isDefault ? TARGET_DEFAULT : TARGET_PERSONAL, formatNumber(term.target), basis);
    }

    toStages(stages) {
        let mid = 0;
        return (stages || []).map((stage, index) => {
            let name = stage.stageType;
            if (stage.stageType === STAGE_TYPE_INITIAL) {
                name = STAGE_INITIAL;
            } else if (stage.stageType === STAGE_TYPE_FINAL) {
                name = STAGE_FINAL;
            } else if (stage.stageType === STAGE_TYPE_MID) {
                mid += 1;
                name = fill(STAGE_MID, mid);
            }
            return {
                key: stage.key || stage.id || `stage-${index}`,
                name,
                paidWhen: orDash(this.paidWhenText(stage)),
                percentText: orDash(shortPercent(stage.releasePercent))
            };
        });
    }

    // "% of purchase price paid: 50%", "A tranche is paid: 2", or the event alone
    paidWhenText(stage) {
        let detail = '';
        if (stage.parameterType === PARAMETER_PERCENT) {
            detail = shortPercent(stage.triggerPercent);
        } else if (stage.parameterType === PARAMETER_TRANCHE) {
            detail = formatNumber(stage.triggerTranche);
        } else if (stage.parameterType === PARAMETER_INSTALLMENT) {
            detail = stage.installmentName || '';
        }
        if (isBlank(stage.triggerLabel)) {
            return detail;
        }
        return detail === '' ? stage.triggerLabel : fill(PAID_WHEN_DETAIL, stage.triggerLabel, detail);
    }

    get hasError() {
        return !this.loading && this.error !== '';
    }

    get isEmpty() {
        return !this.loading && this.error === '' && this.terms.length === 0;
    }

    get hasTerms() {
        return !this.loading && this.error === '' && this.terms.length > 0;
    }

    handleRetry() {
        this.load();
    }
}