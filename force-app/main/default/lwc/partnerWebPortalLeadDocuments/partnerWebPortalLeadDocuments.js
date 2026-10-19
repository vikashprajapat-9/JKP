import { LightningElement, api } from 'lwc';
import getLeadDocuments from '@salesforce/apex/partnerWebPortalLeadDocuments.getLeadDocuments';
import setCustomerType from '@salesforce/apex/partnerWebPortalLeadDocuments.setCustomerType';
import startUpload from '@salesforce/apex/partnerWebPortalLeadDocuments.startUpload';
import uploadChunk from '@salesforce/apex/partnerWebPortalLeadDocuments.uploadChunk';
import finishUpload from '@salesforce/apex/partnerWebPortalLeadDocuments.finishUpload';

const LABELS = {
    EDIT_FAILED: 'The lead could not be updated right now. Please try again or contact the JKP CP team.',
    TOO_LARGE: '{0} is larger than {1} MB.'
};

// SharePoint takes upload ranges in multiples of 320 KiB; this size keeps each Apex call well inside its limits
const CHUNK_SIZE = 5 * 320 * 1024;
const ALLOWED_TYPES = ['pdf', 'jpg', 'jpeg', 'png'];

function errorMessage(error) {
    if (error && error.body && error.body.message) {
        return error.body.message;
    }
    if (error && error.message) {
        return error.message;
    }
    return LABELS.EDIT_FAILED;
}

function format(template, ...values) {
    return values.reduce((text, value, index) => text.replace('{' + index + '}', value), template);
}

function readAsBase64(blob) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result.substring(reader.result.indexOf(',') + 1));
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(blob);
    });
}

// The Documents popup of the Leads page: the partner chooses whether the customer is an Individual or a Company, then
// uploads the customer's documents (the type's document list) against the lead. Fires "close".
export default class PartnerWebPortalLeadDocuments extends LightningElement {
    @api leadId;

    loading = true;
    busy = false;
    options;
    errorMessage;
    successMessage;
    // The document being uploaded and how far
    uploadingCategory;
    uploadingFile;
    progress = 0;

    connectedCallback() {
        this.load();
        this.keyHandler = (event) => {
            if (event.key === 'Escape' && !this.busy) {
                this.handleClose();
            }
        };
        window.addEventListener('keydown', this.keyHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this.keyHandler);
    }

    async load() {
        this.loading = true;
        try {
            this.options = await getLeadDocuments({ leadId: this.leadId });
        } catch (error) {
            this.errorMessage = errorMessage(error);
        } finally {
            this.loading = false;
        }
    }

    // ---------- what the popup shows ----------

    get leadName() {
        return this.options ? this.options.leadName : '';
    }

    get stage() {
        return this.options ? this.options.stage : '';
    }

    get projectName() {
        return this.options ? this.options.projectName : null;
    }

    get canUpload() {
        return Boolean(this.options) && this.options.canUpload;
    }

    get readOnly() {
        return Boolean(this.options) && !this.options.canUpload;
    }

    get readOnlyReason() {
        return this.options ? this.options.readOnlyReason : '';
    }

    get typeCards() {
        if (!this.options) {
            return [];
        }
        return this.options.typeOptions.map((option) => {
            const selected = option.value === this.options.customerType;
            const locked = this.options.typeLocked && !selected;
            let className = 'type-card';
            if (selected) {
                className += ' type-card_selected';
            }
            if (locked) {
                className += ' type-card_locked';
            }
            return {
                ...option,
                selected,
                disabled: locked || this.busy || !this.canUpload,
                ariaChecked: selected ? 'true' : 'false',
                className,
                isCompany: option.value === 'Company',
                description: option.value === 'Company'
                    ? 'The customer buys through a company.'
                    : 'The customer buys in their own name.'
            };
        });
    }

    get typeLockedNote() {
        return this.options && this.options.typeLocked
            ? 'Documents are already uploaded, so the customer type is fixed.'
            : null;
    }

    get notice() {
        return this.options ? this.options.notice : null;
    }

    get hint() {
        return this.options ? this.options.guidance : '';
    }

    get categories() {
        if (!this.options) {
            return [];
        }
        return this.options.categories.map((category) => {
            const uploading = this.uploadingCategory === category.name;
            return {
                ...category,
                key: category.name,
                hasFiles: category.files.length > 0,
                countLabel: category.files.length === 1 ? '1 file' : category.files.length + ' files',
                statusClass: category.files.length > 0 ? 'doc-status doc-status_done' : 'doc-status',
                statusLabel: category.files.length > 0 ? 'Uploaded' : 'Pending',
                uploading,
                progressStyle: 'width: ' + this.progress + '%',
                uploadDisabled: this.busy || !this.canUpload,
                files: category.files.map((file, index) => ({ ...file, key: category.name + '-' + index }))
            };
        });
    }

    get hasCategories() {
        return this.categories.length > 0;
    }

    get acceptTypes() {
        return ALLOWED_TYPES.map((type) => '.' + type).join(',');
    }

    // ---------- events ----------

    async handleType(event) {
        const value = event.currentTarget.dataset.value;
        if (!this.canUpload || this.busy || !this.options || value === this.options.customerType) {
            return;
        }
        this.busy = true;
        this.clearMessages();
        try {
            this.options = await setCustomerType({ leadId: this.leadId, customerType: value });
        } catch (error) {
            this.errorMessage = errorMessage(error);
        } finally {
            this.busy = false;
        }
    }

    handlePick(event) {
        const category = event.currentTarget.dataset.category;
        const input = this.template.querySelector(`input[data-category="${category}"]`);
        if (input) {
            input.value = null;
            input.click();
        }
    }

    async handleFiles(event) {
        const category = event.target.dataset.category;
        const files = Array.from(event.target.files || []);
        if (!files.length) {
            return;
        }
        this.clearMessages();
        const maxBytes = (this.options.maxSizeMb || 10) * 1024 * 1024;
        for (const file of files) {
            const extension = file.name.includes('.') ? file.name.split('.').pop().toLowerCase() : '';
            if (!ALLOWED_TYPES.includes(extension)) {
                this.errorMessage = this.hint;
                return;
            }
            if (file.size > maxBytes) {
                this.errorMessage = format(LABELS.TOO_LARGE, file.name, String(this.options.maxSizeMb || 10));
                return;
            }
        }
        this.busy = true;
        const done = [];
        try {
            for (const file of files) {
                // eslint-disable-next-line no-await-in-loop
                await this.upload(category, file);
                done.push(file.name);
            }
            this.successMessage = done.length === 1 ? done[0] + ' uploaded.' : done.length + ' files uploaded.';
        } catch (error) {
            this.errorMessage = errorMessage(error);
        } finally {
            this.busy = false;
            this.uploadingCategory = null;
            this.uploadingFile = null;
            this.progress = 0;
        }
    }

    // One file: the handle, its chunks through Apex, then its link and record
    async upload(category, file) {
        this.uploadingCategory = category;
        this.uploadingFile = file.name;
        this.progress = 0;
        const handle = await startUpload({ leadId: this.leadId, category, fileName: file.name, size: file.size });
        let itemId;
        for (let start = 0; start < file.size; start += CHUNK_SIZE) {
            const end = Math.min(start + CHUNK_SIZE, file.size);
            // eslint-disable-next-line no-await-in-loop
            const base64Chunk = await readAsBase64(file.slice(start, end));
            // eslint-disable-next-line no-await-in-loop
            const result = await uploadChunk({ leadId: this.leadId, handle, base64Chunk, startByte: start, endByte: end });
            if (result && result.complete) {
                itemId = result.itemId;
            }
            this.progress = Math.floor((end / file.size) * 95);
        }
        if (!itemId) {
            throw new Error(LABELS.EDIT_FAILED);
        }
        this.options = await finishUpload({ leadId: this.leadId, handle, itemId });
        this.progress = 100;
    }

    handleClose() {
        if (this.busy) {
            return;
        }
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleBackdrop() {
        this.handleClose();
    }

    handleCloseError() {
        this.errorMessage = undefined;
    }

    handleCloseSuccess() {
        this.successMessage = undefined;
    }

    clearMessages() {
        this.errorMessage = undefined;
        this.successMessage = undefined;
    }
}