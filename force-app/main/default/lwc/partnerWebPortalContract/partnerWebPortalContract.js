import { LightningElement } from 'lwc';
import getMyContract from '@salesforce/apex/partnerWebPortalContractController.getMyContract';
import getContractFile from '@salesforce/apex/partnerWebPortalContractController.getContractFile';

const NO_VALUE = '–';
const LOAD_ERROR = 'Your contract could not be loaded right now. Please try again.';
const DOWNLOAD_ERROR = 'The contract could not be downloaded right now. Please try again, or ask your JKP CP Executive for a copy.';
const DRAFT_FILE = 'draft';
const SIGNED_FILE = 'signed';
const EXCLUSIVE = 'Exclusive';
const READY_STEP = 2;
const SIGNED_STEP = 3;
const LAST_STEP = 4;

// The contract's steps (the controller's step numbers). The partner signs it offline, on paper.
const STEPS = [
    { value: 1, label: 'Prepared', caption: 'Drafted and verified by JKP' },
    { value: 2, label: 'Ready to sign', caption: 'Download, print and sign' },
    { value: 3, label: 'Signed', caption: 'Recorded by your CP Executive' },
    { value: 4, label: 'Completed', caption: 'Signed copy on record' }
];

// The status badge of each step (0: no contract yet), in the colours of the portal's other badges
const STATUSES = {
    0: { label: 'Not started', className: 'badge badge-neutral' },
    1: { label: 'Being prepared', className: 'badge badge-pending' },
    2: { label: 'Ready to sign', className: 'badge badge-ready' },
    3: { label: 'Signed', className: 'badge badge-signed' },
    4: { label: 'Completed', className: 'badge badge-completed' }
};

function errorMessage(error, fallback) {
    return (error && error.body && error.body.message) || fallback;
}

function isBlank(value) {
    return value === null || value === undefined || value === '';
}

// Saves the file. A file in SharePoint comes as its direct download link (SharePoint sends it as an attachment, so the
// browser saves it and the page stays). A file in Salesforce Files comes as its contents and is saved the way the Leads
// page saves its export: a link to the contents, clicked; a blob: link where the browser allows one (Chrome does not
// download data: links over 2 MB), else a data: link.
function saveFile(file) {
    if (file.url) {
        const download = document.createElement('a');
        download.href = file.url;
        download.rel = 'noopener';
        download.download = file.fileName || 'Contract';
        download.click();
        return;
    }
    const type = file.mimeType || 'application/octet-stream';
    let url;
    try {
        const bytes = window.atob(file.base64);
        const data = new Uint8Array(bytes.length);
        for (let i = 0; i < bytes.length; i++) {
            data[i] = bytes.charCodeAt(i);
        }
        url = URL.createObjectURL(new Blob([data], { type }));
    } catch (blobError) {
        console.warn('The contract is saved through a data: link instead of a blob: link.', blobError);
        url = 'data:' + type + ';base64,' + file.base64;
    }
    const link = document.createElement('a');
    link.href = url;
    link.download = file.fileName || 'Contract';
    link.click();
    if (url.indexOf('blob:') === 0) {
        // The browser has the file by then; the link's memory is given back
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => URL.revokeObjectURL(url), 10000);
    }
}

// The My Contract page: the channel head's exclusive partner contract, its progress and its files. Executives see only
// that their channel partner holds the contract (the portal shows them no My Contract page).
export default class PartnerWebPortalContract extends LightningElement {
    // The controller's ContractView, or undefined until it arrives
    view;
    isLoading = true;
    loadError;
    downloadError;
    // The kind of file being downloaded ('draft' or 'signed'), if any
    downloading;

    connectedCallback() {
        this.loadContract();
    }

    // Read each time the page opens, as the contract moves on outside the portal. A refresh that fails keeps the page.
    async loadContract() {
        this.loadError = undefined;
        this.isLoading = !this.view;
        try {
            const view = await getMyContract();
            if (!view) {
                throw new Error(LOAD_ERROR);
            }
            this.view = view;
        } catch (error) {
            if (!this.view) {
                this.loadError = errorMessage(error, LOAD_ERROR);
            }
        } finally {
            this.isLoading = false;
        }
    }

    // ================= STATES =================
    get busy() {
        return String(this.isLoading);
    }

    // How the contract works, for whoever has one here (not for an executive)
    get showDescription() {
        return !this.view || this.view.available === true;
    }

    // An executive, or a user without a partner account: only the message
    get showMessageOnly() {
        return !this.isLoading && Boolean(this.view) && !this.view.available;
    }

    get showContract() {
        return !this.isLoading && Boolean(this.view) && this.view.available === true;
    }

    get message() {
        return this.view ? this.view.message : '';
    }

    get step() {
        return (this.view && Number(this.view.step)) || 0;
    }

    // ================= STATUS CARD =================
    get statusLabel() {
        return (STATUSES[this.step] || STATUSES[0]).label;
    }

    get statusClass() {
        return (STATUSES[this.step] || STATUSES[0]).className;
    }

    get subtitle() {
        return this.view && this.view.hasContract && this.view.contractNumber
            ? 'Contract No. ' + this.view.contractNumber
            : 'John Keells Properties';
    }

    // Steps before the current one are done, and the last one once it is reached; the current one is highlighted
    get steps() {
        const current = this.step;
        return STEPS.map((step) => {
            const isCurrent = step.value === current;
            const done = step.value < current || (isCurrent && current === LAST_STEP);
            let itemClass = 'step';
            let stateText = 'Not yet';
            if (done) {
                itemClass += ' step-done';
                stateText = 'Done';
            }
            if (isCurrent) {
                itemClass += ' step-current';
                stateText = done ? 'Done' : 'Current step';
            }
            return {
                ...step,
                done,
                itemClass,
                stateText,
                ariaCurrent: isCurrent ? 'step' : undefined
            };
        });
    }

    // Information while JKP prepares the contract, a call to act when it is ready to sign, a confirmation once signed
    get messageTone() {
        if (this.step === READY_STEP) {
            return 'action';
        }
        return this.step >= SIGNED_STEP ? 'success' : 'info';
    }

    get messageClass() {
        return 'message message-' + this.messageTone;
    }

    get isActionMessage() {
        return this.messageTone === 'action';
    }

    get isSuccessMessage() {
        return this.messageTone === 'success';
    }

    // ================= DOWNLOADS =================
    get canDownloadDraft() {
        return this.showContract && this.view.canDownloadDraft === true;
    }

    get canDownloadSigned() {
        return this.showContract && this.view.canDownloadSigned === true;
    }

    get hasDownloads() {
        return this.canDownloadDraft || this.canDownloadSigned;
    }

    get isDownloading() {
        return Boolean(this.downloading);
    }

    get isDownloadingDraft() {
        return this.downloading === DRAFT_FILE;
    }

    get isDownloadingSigned() {
        return this.downloading === SIGNED_FILE;
    }

    // The draft is the call to act while it waits for the partner's signature; once signed it is only a copy, and the
    // signed contract becomes the main download
    get draftButtonClass() {
        return this.step === READY_STEP && !this.canDownloadSigned ? 'btn btn-primary' : 'btn btn-outline';
    }

    // ================= DETAILS =================
    get hasContract() {
        return this.showContract && this.view.hasContract === true;
    }

    get details() {
        const view = this.view || {};
        const term = Number(view.termMonths);
        return [
            { key: 'number', label: 'Contract number', value: view.contractNumber },
            { key: 'version', label: 'Draft version', value: isBlank(view.draftVersion) ? null : String(view.draftVersion) },
            { key: 'term', label: 'Term', value: isBlank(view.termMonths) ? null : term + (term === 1 ? ' month' : ' months') },
            { key: 'signedOn', label: 'Signed on', value: view.signedOn },
            { key: 'start', label: 'Contract start date', value: view.contractStart },
            { key: 'end', label: 'Contract end date', value: view.contractEnd }
        ].map((detail) => ({ ...detail, value: isBlank(detail.value) ? NO_VALUE : detail.value }));
    }

    // The temporary access period, while the partner is not Exclusive yet (signing the contract makes them Exclusive)
    get temporaryAccess() {
        const view = this.view;
        if (!this.showContract || view.partnerType === EXCLUSIVE || this.step >= SIGNED_STEP) {
            return null;
        }
        if (view.temporaryStart && view.temporaryEnd) {
            return view.temporaryStart + ' – ' + view.temporaryEnd;
        }
        if (view.temporaryEnd) {
            return 'Until ' + view.temporaryEnd;
        }
        return view.temporaryStart ? 'From ' + view.temporaryStart : null;
    }

    get showTemporaryAccess() {
        return Boolean(this.temporaryAccess);
    }

    // ================= HANDLERS =================
    handleRetry() {
        this.loadContract();
    }

    handleCloseError() {
        this.downloadError = undefined;
    }

    async handleDownload(event) {
        const kind = event.currentTarget.dataset.kind;
        if (this.downloading || (kind !== DRAFT_FILE && kind !== SIGNED_FILE)) {
            return;
        }
        this.downloading = kind;
        this.downloadError = undefined;
        try {
            const file = await getContractFile({ kind });
            // A SharePoint file comes as a download link (url), a Salesforce File as its contents (base64)
            if (!file || (!file.url && !file.base64)) {
                throw new Error(DOWNLOAD_ERROR);
            }
            saveFile(file);
        } catch (error) {
            this.downloadError = errorMessage(error, DOWNLOAD_ERROR);
            // The contract may have moved on since the page opened: show where it is now
            this.loadContract();
        } finally {
            this.downloading = undefined;
        }
    }
}