import { LightningElement, api } from 'lwc';
import { errorText, fill, formatNumber, formatPercent } from 'c/commissionUtils';
import getMyTerms from '@salesforce/apex/CommissionTargetController.getMyTerms';
import ERROR from '@salesforce/label/c.Commission_Common_Error';
import LOADING from '@salesforce/label/c.Commission_Common_Loading';
import RETRY from '@salesforce/label/c.Commission_Common_Retry';
import NONE from '@salesforce/label/c.Commission_Common_None';
import STAGE_INITIAL from '@salesforce/label/c.Commission_Stage_Initial';
import STAGE_MID from '@salesforce/label/c.Commission_Stage_Mid_Numbered';
import STAGE_FINAL from '@salesforce/label/c.Commission_Stage_Final';
import TWO_PARTS from '@salesforce/label/c.Commission_Setup_Two_Parts';
import TITLE from '@salesforce/label/c.Commission_Setup_Terms_Title';
import SUBTITLE from '@salesforce/label/c.Commission_Setup_Terms_Subtitle';
import EMPTY from '@salesforce/label/c.Commission_Setup_Terms_Empty';
import TARGET from '@salesforce/label/c.Commission_Setup_Terms_Target';
import TARGET_DEFAULT from '@salesforce/label/c.Commission_Setup_Terms_Target_Default';
import TARGET_PERSONAL from '@salesforce/label/c.Commission_Setup_Terms_Target_Personal';
import NO_TARGET from '@salesforce/label/c.Commission_Setup_Terms_No_Target';
import CURRENT_RATE from '@salesforce/label/c.Commission_Setup_Terms_Current_Rate';
import EXCEED_RATE from '@salesforce/label/c.Commission_Setup_Terms_Exceed_Rate';
import FEE from '@salesforce/label/c.Commission_Setup_Terms_Fee';
import CLAIM_OPENS from '@salesforce/label/c.Commission_Setup_Terms_Claim_Opens';
import STAGES from '@salesforce/label/c.Commission_Setup_Terms_Stages';
import COL_STAGE from '@salesforce/label/c.Commission_Setup_Terms_Col_Stage';
import COL_PAID_WHEN from '@salesforce/label/c.Commission_Setup_Terms_Col_Paid_When';
import COL_PERCENT from '@salesforce/label/c.Commission_Setup_Terms_Col_Percent';
import PAID_WHEN_DETAIL from '@salesforce/label/c.Commission_Setup_Terms_Paid_When_Detail';
import NO_STAGES from '@salesforce/label/c.Commission_Setup_Terms_No_Stages';

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