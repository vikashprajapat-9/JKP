import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent, registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import getConfigurations from '@salesforce/apex/ProjectConfigurationController.getConfigurations';
import createConfigurations from '@salesforce/apex/ProjectConfigurationController.createConfigurations';
import updateConfiguration from '@salesforce/apex/ProjectConfigurationController.updateConfiguration';
import getFolderStatus from '@salesforce/apex/ProjectConfigurationController.getFolderStatus';
import requestFolder from '@salesforce/apex/ProjectConfigurationController.requestFolder';
import attachFile from '@salesforce/apex/ProjectConfigurationController.attachFile';
import { uploadFileToFolder, MAX_FILE_SIZE, UploadCancelledError, loadMaxFileSize, sizeLabel } from 'c/sharePointUploader';

// File types the SharePoint upload accepts that suit a configuration (price sheet, floor plan)
const ALLOWED_EXTENSIONS = ['pdf', 'jpg', 'jpeg', 'png'];
const FILE_ICONS = { pdf: 'doctype:pdf', jpg: 'doctype:image', jpeg: 'doctype:image', png: 'doctype:image' };
// The table layout needs about 750px (column minimums, gaps and paddings); narrower, each row is a stacked card
const TABLE_MIN_WIDTH = 760;
// Same limit as ProjectConfigurationController
const MAX_ROWS = 50;
const HIGHLIGHT_MS = 2600;
const UNIT_TONES = 7;
// A new configuration's SharePoint folder is created in the background a few seconds after it is saved
const FOLDER_POLL_MS = 1500;
const FOLDER_WAIT_MS = 120000;
// A folder that is missing, or still not in SharePoint after this long, is requested again every so often
const FOLDER_STALLED_MS = 50000;
const FOLDER_REQUEST_EVERY_MS = 15000;
const PAGE_LEFT = 'The upload stopped because the page was closed. Select Retry to upload it again.';

let keySequence = 0;
const nextKey = () => `k${++keySequence}`;
const isBlank = (value) => value === '' || value === null || value === undefined;
const toNumber = (value) => (isBlank(value) ? null : Number(value));
const hasData = (row) => !isBlank(row.unitType) || !isBlank(row.startingPrice) || !isBlank(row.squareFt) || !!row.file;
const extensionOf = (name) => (name && name.includes('.') ? name.split('.').pop().toLowerCase() : '');
const iconFor = (name) => FILE_ICONS[extensionOf(name)] || 'doctype:attachment';

function emptyRow() {
    return { key: nextKey(), unitType: '', startingPrice: '', squareFt: '', file: null, fileError: undefined };
}

function formatMoney(value) {
    if (isBlank(value)) {
        return '—';
    }
    // Whole amounts without decimals, others always with two (98,50,000.50, not 98,50,000.5)
    const decimals = Number.isInteger(Number(value)) ? 0 : 2;
    try {
        return new Intl.NumberFormat(LOCALE, {
            style: 'currency',
            currency: CURRENCY,
            currencyDisplay: 'code',
            minimumFractionDigits: decimals,
            maximumFractionDigits: 2
        }).format(value);
    } catch (e) {
        return Number(value).toLocaleString();
    }
}

function formatArea(value) {
    if (isBlank(value)) {
        return '—';
    }
    try {
        return `${new Intl.NumberFormat(LOCALE, { maximumFractionDigits: 0 }).format(value)} sq ft`;
    } catch (e) {
        return `${value} sq ft`;
    }
}

function formatSize(bytes) {
    if (bytes >= 1024 * 1024) {
        return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }
    return `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

function fileProblem(file, maxFileSize) {
    if (!ALLOWED_EXTENSIONS.includes(extensionOf(file.name))) {
        return `${file.name}: only PDF, JPG, JPEG and PNG files can be uploaded.`;
    }
    if (file.size === 0) {
        return `${file.name} is empty.`;
    }
    if (file.size > maxFileSize) {
        return `${file.name} is larger than ${sizeLabel(maxFileSize)}.`;
    }
    return undefined;
}

function reduceError(error) {
    const body = error && error.body;
    if (Array.isArray(body) && body.length) {
        return body.map((e) => e.message).join(', ');
    }
    if (body && body.message) {
        return body.message;
    }
    if (body && body.pageErrors && body.pageErrors.length) {
        return body.pageErrors[0].message;
    }
    if (error && error.message) {
        return error.message;
    }
    return 'Something went wrong. Please try again.';
}

function wait(ms) {
    return new Promise((resolve) => {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(resolve, ms);
    });
}

export default class ProjectConfigurationManager extends LightningElement {
    @api recordId;
    @api cardTitle = 'Project Configurations';

    configurations = [];
    unitTypeOptions = [];
    canRead = true;
    canCreate = false;
    canEdit = false;
    isLoading = true;
    hasLoaded = false;
    loadError;

    isAdding = false;
    newRows = [];
    isSaving = false;
    formError;

    // configuration Id -> draft values while that row is being edited
    edits = {};
    // configuration Id -> file waiting for, or being uploaded into, that configuration's own folder
    uploads = {};
    highlightIds = [];
    compact = true;

    acceptedTypes = ALLOWED_EXTENSIONS.map((ext) => `.${ext}`).join(',');
    skeletonRows = ['s1', 's2', 's3'];

    // Where the next chosen file goes: "new|<row key>" or "edit|<configuration Id>|<edit session>"
    fileTarget;
    focusKey;
    restoreFocus;
    uploadWorkerRunning = false;
    // Only the latest reload may replace the list; an older response could hide newer changes
    loadSeq = 0;
    refreshHandlerId;
    resizeObserver;
    highlightTimer;
    isDisconnected = false;
    // The largest file allowed, from the SharePoint setting
    maxFileSize = MAX_FILE_SIZE;

    connectedCallback() {
        this.isDisconnected = false;
        this.loadConfigurations();
        loadMaxFileSize().then((bytes) => {
            this.maxFileSize = bytes;
        });
        // Reload when another component changes files, for example a file deleted from the Document List
        this.refreshHandlerId = registerRefreshHandler(this, () => this.handlePageRefresh());
    }

    renderedCallback() {
        this.observeWidth();
        if (this.focusKey) {
            const field = this.template.querySelector(`lightning-combobox[data-focus="${this.focusKey}"]`);
            if (field) {
                this.focusKey = undefined;
                field.focus();
            }
        } else if (this.restoreFocus) {
            // Put focus back on a sensible control after the one that had it was removed
            const target = this.template.querySelector(this.restoreFocus);
            this.restoreFocus = undefined;
            if (target) {
                target.focus();
            }
        }
    }

    disconnectedCallback() {
        this.isDisconnected = true;
        unregisterRefreshHandler(this.refreshHandlerId);
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
            this.resizeObserver = undefined;
        }
        clearTimeout(this.highlightTimer);
        this.highlightIds = [];
        // Leaving the page stops the uploads; they keep their files so they can be retried if the page comes back
        const uploads = {};
        Object.values(this.uploads).forEach((upload) => {
            uploads[upload.configurationId] =
                upload.status === 'error' ? upload : { ...upload, status: 'error', error: PAGE_LEFT, token: nextKey() };
        });
        this.uploads = uploads;
    }

    handlePageRefresh() {
        return this.loadConfigurations().then(() => true);
    }

    // Tells the page (related lists, the Document List) that configurations or their files changed
    notifyPage() {
        this.dispatchEvent(new RefreshEvent());
    }

    observeWidth() {
        if (this.resizeObserver || typeof ResizeObserver === 'undefined') {
            return;
        }
        const card = this.template.querySelector('.pc-card');
        if (!card) {
            return;
        }
        this.resizeObserver = new ResizeObserver((entries) => {
            const compact = entries[0].contentRect.width < TABLE_MIN_WIDTH;
            if (compact !== this.compact) {
                this.compact = compact;
            }
        });
        this.resizeObserver.observe(card);
    }

    async loadConfigurations() {
        const seq = ++this.loadSeq;
        this.isLoading = true;
        this.loadError = undefined;
        try {
            const data = await getConfigurations({ projectId: this.recordId });
            if (seq !== this.loadSeq) {
                return;
            }
            this.canRead = data.canRead;
            this.canCreate = data.canCreate;
            this.canEdit = data.canEdit;
            this.unitTypeOptions = data.unitTypes || [];
            this.configurations = data.configurations || [];
            // Drop drafts of rows that are no longer there
            const ids = new Set(this.configurations.map((config) => config.id));
            const edits = {};
            Object.keys(this.edits).forEach((id) => {
                if (ids.has(id)) {
                    edits[id] = this.edits[id];
                }
            });
            this.edits = edits;
        } catch (error) {
            if (seq === this.loadSeq) {
                this.loadError = reduceError(error);
            }
        } finally {
            if (seq === this.loadSeq) {
                this.isLoading = false;
                this.hasLoaded = true;
            }
        }
    }

    // ---------- view state ----------
    get cardClass() {
        return this.compact ? 'pc-card pc-card_compact' : 'pc-card pc-card_table';
    }

    get isTable() {
        return !this.compact;
    }

    get inputVariant() {
        return this.compact ? 'standard' : 'label-hidden';
    }

    get showSkeleton() {
        return this.isLoading && !this.hasLoaded;
    }

    get showNoAccess() {
        return this.hasLoaded && !this.canRead && !this.loadError;
    }

    get showAddButton() {
        return this.hasLoaded && this.canRead && this.canCreate && !this.isAdding && !this.loadError;
    }

    get showEmptyState() {
        return this.hasLoaded && this.canRead && !this.loadError && !this.isAdding && this.configurations.length === 0;
    }

    get hasConfigurations() {
        return this.canRead && this.configurations.length > 0;
    }

    get isAnyEditSaving() {
        return Object.values(this.edits).some((draft) => draft.saving);
    }

    get isBusy() {
        return this.isLoading || this.isSaving || this.isAnyEditSaving;
    }

    get summaryText() {
        const count = this.configurations.length;
        const label = count === 1 ? '1 configuration' : `${count} configurations`;
        const prices = this.configurations.map((config) => config.startingPrice).filter((price) => !isBlank(price));
        return prices.length ? `${label} · from ${formatMoney(Math.min(...prices))}` : label;
    }

    get newRowCountLabel() {
        return this.newRows.length === 1 ? '1 row' : `${this.newRows.length} rows`;
    }

    get cannotAddRow() {
        return this.isSaving || this.newRows.length >= MAX_ROWS;
    }

    get saveLabel() {
        return this.isSaving ? 'Saving…' : 'Save';
    }

    get activeUploadCount() {
        return Object.values(this.uploads).filter((upload) => upload.status !== 'error').length;
    }

    get showUploadBanner() {
        return this.activeUploadCount > 0;
    }

    get uploadBannerText() {
        const count = this.activeUploadCount;
        return `Uploading ${count === 1 ? '1 file' : `${count} files`} into the configuration folders. Keep this page open until it finishes.`;
    }

    get footnote() {
        return `Files upload after you save, into Project Configurations › the configuration’s own folder in SharePoint · PDF, JPG, JPEG or PNG, up to ${sizeLabel(this.maxFileSize)}`;
    }

    get newRowViews() {
        const single = this.newRows.length === 1;
        return this.newRows.map((row, index) => ({
            ...row,
            srNo: index + 1,
            focusKey: row.key,
            target: `new|${row.key}`,
            // Only rows with something in them must have a unit type; empty rows are skipped
            unitRequired: hasData(row),
            deleteLabel: `Delete row ${index + 1}`,
            deleteDisabled: single || this.isSaving,
            hasFile: !!row.file,
            fileName: row.file ? row.file.name : '',
            fileMeta: row.file ? `${formatSize(row.file.size)} · uploads after you save` : '',
            fileIcon: iconFor(row.file ? row.file.name : ''),
            uploadLabel: row.fileError ? 'Choose again' : 'Upload',
            uploadClass: row.fileError ? 'upload-button upload-button_error' : 'upload-button'
        }));
    }

    get configurationRows() {
        const toneByType = new Map(this.unitTypeOptions.map((option, index) => [option.value, index % UNIT_TONES]));
        return this.configurations.map((config, index) => {
            const draft = this.edits[config.id];
            const upload = this.uploads[config.id];
            let rowClass = 'config-row';
            if (index % 2 === 1) rowClass += ' config-row_alt';
            if (draft) rowClass += ' config-row_editing';
            if (this.highlightIds.includes(config.id)) rowClass += ' config-row_flash';
            const tone = toneByType.has(config.unitType) ? toneByType.get(config.unitType) : 0;
            return {
                ...config,
                srNo: index + 1,
                rowClass,
                unitClass: `unit-pill unit-pill_${tone}`,
                priceText: formatMoney(config.startingPrice),
                areaText: formatArea(config.squareFt),
                hasFile: !!config.fileUrl,
                fileIcon: iconFor(config.fileName),
                editLabel: `Edit configuration ${index + 1} (${config.unitType})`,
                // Editing waits for the row's upload, so the edit cannot overwrite the file it links
                editDisabled: !!upload && upload.status !== 'error',
                editTitle: upload && upload.status !== 'error' ? 'Wait for the upload to finish' : 'Edit',
                hasUpload: !!upload,
                uploadCellClass: upload ? 'cell cell-upload cell-upload_busy' : 'cell cell-upload',
                upload: upload ? this.uploadView(upload) : undefined,
                isEditing: !!draft,
                draft: draft ? this.draftView(config, draft) : undefined
            };
        });
    }

    uploadView(upload) {
        const uploading = upload.status === 'uploading';
        let statusText = 'Waiting…';
        if (upload.status === 'preparing') {
            statusText = 'Preparing folder…';
        } else if (uploading) {
            statusText = `${upload.progress}%`;
        }
        return {
            name: upload.name,
            icon: iconFor(upload.name),
            isError: upload.status === 'error',
            error: upload.error,
            statusText,
            progress: uploading ? upload.progress : 0,
            progressStyle: `width: ${uploading ? upload.progress : 100}%`,
            fillClass: uploading ? 'bar-fill' : 'bar-fill bar-fill_waiting',
            progressLabel: `${upload.name}: ${statusText}`
        };
    }

    draftView(config, draft) {
        const pending = draft.pendingFile;
        const current = draft.current;
        return {
            ...draft,
            focusKey: `edit-${config.id}`,
            target: `edit|${config.id}|${draft.session}`,
            inputsDisabled: draft.saving,
            showPending: !!pending,
            pendingName: pending ? pending.name : '',
            pendingMeta: pending ? `${formatSize(pending.size)} · uploads when you save` : '',
            pendingIcon: iconFor(pending ? pending.name : ''),
            showCurrent: !pending && !!current,
            currentName: current ? current.name : '',
            currentUrl: current ? current.url : undefined,
            currentIcon: iconFor(current ? current.name : ''),
            uploadLabel: draft.fileError ? 'Choose again' : 'Upload',
            uploadClass: draft.fileError ? 'upload-button upload-button_error' : 'upload-button',
            folderText: config.folderReady
                ? `Files go to Project Configurations › ${config.folderName}`
                : 'This configuration’s SharePoint folder is still being created; a chosen file waits for it.'
        };
    }

    // ---------- adding ----------
    handleRefresh() {
        this.loadConfigurations();
    }

    handleAddConfiguration() {
        const row = emptyRow();
        this.newRows = [row];
        this.formError = undefined;
        this.isAdding = true;
        this.focusKey = row.key;
    }

    handleAddRow() {
        if (this.cannotAddRow) {
            return;
        }
        const row = emptyRow();
        this.newRows = [...this.newRows, row];
        this.focusKey = row.key;
    }

    handleDeleteRow(event) {
        // The second click of a double-click would land on the next row's delete icon
        if (event.detail > 1 || this.newRows.length <= 1 || this.isSaving) {
            return;
        }
        const key = event.currentTarget.dataset.key;
        this.newRows = this.newRows.filter((row) => row.key !== key);
        // The row it repeated may be the one removed; Save checks again
        this.clearRepeatMarks('new');
        this.formError = undefined;
        this.restoreFocus = '.add-row-btn';
    }

    handleNewRowChange(event) {
        const { key, field } = event.currentTarget.dataset;
        const value = event.detail.value;
        if (field === 'unitType') {
            this.clearRepeatMarks('new');
        }
        this.newRows = this.newRows.map((row) => (row.key === key ? { ...row, [field]: value } : row));
        this.formError = undefined;
    }

    async handleCancelAdd() {
        if (this.isSaving) {
            return;
        }
        if (this.newRows.some(hasData)) {
            const confirmed = await LightningConfirm.open({
                label: 'Discard these configurations?',
                message: 'The rows you filled in, and the files you chose for them, will not be saved.',
                theme: 'warning'
            });
            if (!confirmed) {
                return;
            }
        }
        this.newRows = [];
        this.isAdding = false;
        this.formError = undefined;
        this.restoreFocus = '.add-config-btn';
    }

    async handleSave() {
        if (this.isSaving) {
            return;
        }
        const filled = this.newRows.filter(hasData);
        if (!filled.length) {
            this.formError = 'Fill in at least one configuration before saving.';
            return;
        }
        // Rows left completely empty are skipped; the others must pass the field checks
        const keys = new Set(filled.map((row) => row.key));
        this.template.querySelectorAll('lightning-combobox[data-scope="new"]').forEach((field) => field.setCustomValidity(''));
        let valid = true;
        this.template.querySelectorAll('[data-scope="new"]').forEach((field) => {
            if (keys.has(field.dataset.key)) {
                valid = field.reportValidity() && valid;
            }
        });
        if (!valid) {
            this.formError = 'Please fix the highlighted fields.';
            return;
        }
        if (this.flagRepeatedUnitTypes(filled)) {
            this.formError = 'Each unit type can be added only once per project.';
            return;
        }
        // Drop the empty rows so the row numbers match the ones the server reports
        if (filled.length !== this.newRows.length) {
            this.newRows = filled;
        }

        this.isSaving = true;
        this.formError = undefined;
        try {
            const saved = await createConfigurations({
                projectId: this.recordId,
                configurations: filled.map((row) => ({
                    unitType: row.unitType,
                    startingPrice: toNumber(row.startingPrice),
                    squareFt: toNumber(row.squareFt)
                }))
            });
            // The result follows the order of the rows sent, which pairs each chosen file with its configuration
            let fileCount = 0;
            filled.forEach((row, index) => {
                if (this.canEdit && row.file && saved[index]) {
                    this.queueUpload(saved[index].id, row.file);
                    fileCount++;
                }
            });
            this.applySaved(saved);
            this.clearRepeatMarks('edit');
            this.isAdding = false;
            this.newRows = [];
            this.restoreFocus = '.add-config-btn';
            this.flash(saved.map((config) => config.id));
            this.notifyPage();
            const added = saved.length === 1 ? '1 configuration was added' : `${saved.length} configurations were added`;
            this.toast(
                'Configurations saved',
                fileCount
                    ? `${added}. Uploading ${fileCount === 1 ? 'its file' : `${fileCount} files`} into the configuration folders…`
                    : `${added} to this project.`,
                'success'
            );
            this.processUploads();
            this.loadConfigurations();
        } catch (error) {
            this.formError = reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    // Marks the Unit Type of each new row whose unit type the project already has, or an earlier row already uses.
    // True when a row was marked.
    flagRepeatedUnitTypes(rows) {
        const onProject = new Set(this.configurations.map((config) => config.unitType).filter(Boolean));
        const inForm = new Set();
        let repeated = false;
        rows.forEach((row) => {
            let message = '';
            if (row.unitType && onProject.has(row.unitType)) {
                message = `This project already has a ${this.unitTypeLabel(row.unitType)} configuration.`;
            } else if (row.unitType && inForm.has(row.unitType)) {
                message = `${this.unitTypeLabel(row.unitType)} is already in an earlier row.`;
            }
            if (row.unitType) {
                inForm.add(row.unitType);
            }
            const field = this.template.querySelector(`lightning-combobox[data-scope="new"][data-key="${row.key}"]`);
            if (field && message) {
                field.setCustomValidity(message);
                field.reportValidity();
            }
            repeated = repeated || !!message;
        });
        return repeated;
    }

    // Clears the "already used" marks in the add form ('new') or the edit forms ('edit') once any unit type changes,
    // since fixing one row can resolve another row's mark; Save checks every row again
    clearRepeatMarks(scope) {
        this.template.querySelectorAll(`lightning-combobox[data-scope="${scope}"]`).forEach((field) => {
            if (field.validity && field.validity.customError) {
                field.setCustomValidity('');
                field.reportValidity();
            }
        });
    }

    unitTypeLabel(value) {
        const option = this.unitTypeOptions.find((o) => o.value === value);
        return option ? option.label : value;
    }

    // ---------- editing ----------
    handleEdit(event) {
        const id = event.currentTarget.dataset.id;
        const config = this.configurations.find((c) => c.id === id);
        const upload = this.uploads[id];
        if (!config || this.edits[id] || (upload && upload.status !== 'error')) {
            return;
        }
        this.edits = {
            ...this.edits,
            [id]: {
                session: nextKey(),
                unitType: config.unitType || '',
                startingPrice: isBlank(config.startingPrice) ? '' : config.startingPrice,
                squareFt: isBlank(config.squareFt) ? '' : config.squareFt,
                // The file linked when the edit started; only this one can be removed by the save
                originalFileId: config.subDocumentId || null,
                current: config.subDocumentId
                    ? { subDocumentId: config.subDocumentId, name: config.fileName, url: config.fileUrl }
                    : null,
                pendingFile: null,
                fileError: undefined,
                saving: false,
                error: undefined
            }
        };
        this.focusKey = `edit-${id}`;
    }

    handleEditChange(event) {
        const { id, field } = event.currentTarget.dataset;
        if (field === 'unitType') {
            this.clearRepeatMarks('edit');
        }
        this.patchEdit(id, { [field]: event.detail.value, error: undefined });
    }

    handleEditCancel(event) {
        // The pencil sits where this button appears, so the second click of a double-click is ignored
        if (event.detail > 1) {
            return;
        }
        const id = event.currentTarget.dataset.id;
        const draft = this.edits[id];
        if (!draft || draft.saving) {
            return;
        }
        this.dropEdit(id);
        this.restoreFocus = `button.icon-btn_edit[data-id="${id}"]`;
    }

    async handleEditSave(event) {
        const id = event.currentTarget.dataset.id;
        const draft = this.edits[id];
        if (!draft || draft.saving) {
            return;
        }
        const unitField = this.template.querySelector(`lightning-combobox[data-scope="edit"][data-id="${id}"]`);
        if (unitField) {
            unitField.setCustomValidity('');
        }
        let valid = true;
        this.template.querySelectorAll(`[data-scope="edit"][data-id="${id}"]`).forEach((field) => {
            valid = field.reportValidity() && valid;
        });
        if (!valid) {
            return;
        }
        // A new unit type must not be one another configuration of the project already has (checked on the server too)
        const config = this.configurations.find((c) => c.id === id);
        const changedType = !config || config.unitType !== draft.unitType;
        if (unitField && changedType && this.configurations.some((c) => c.id !== id && c.unitType === draft.unitType)) {
            unitField.setCustomValidity(`This project already has a ${this.unitTypeLabel(draft.unitType)} configuration.`);
            unitField.reportValidity();
            return;
        }

        this.patchEdit(id, { saving: true, error: undefined });
        try {
            const saved = await updateConfiguration({
                projectId: this.recordId,
                configuration: {
                    id,
                    unitType: draft.unitType,
                    startingPrice: toNumber(draft.startingPrice),
                    squareFt: toNumber(draft.squareFt),
                    subDocumentId: draft.originalFileId,
                    removeFile: !!draft.originalFileId && !draft.current
                }
            });
            this.applySaved([saved]);
            this.clearRepeatMarks('edit');
            this.dropEdit(id);
            this.restoreFocus = `button.icon-btn_edit[data-id="${id}"]`;
            // A newly chosen file goes into the same folder as the configuration's earlier files
            if (draft.pendingFile) {
                this.queueUpload(id, draft.pendingFile);
                this.processUploads();
                // The pencil waits for the upload, so focus goes to the upload's cancel button
                this.restoreFocus = `button.chip-remove[data-id="${id}"]`;
            }
            this.flash([id]);
            this.notifyPage();
            const unitType = saved && saved.unitType ? saved.unitType : 'The configuration';
            this.toast(
                'Configuration updated',
                draft.pendingFile ? `${unitType} was saved. Uploading its file into the configuration folder…` : `${unitType} was saved.`,
                'success'
            );
            this.loadConfigurations();
        } catch (error) {
            this.patchEdit(id, { saving: false, error: reduceError(error) });
        }
    }

    patchEdit(id, patch) {
        const draft = this.edits[id];
        if (draft) {
            this.edits = { ...this.edits, [id]: { ...draft, ...patch } };
        }
    }

    dropEdit(id) {
        const edits = { ...this.edits };
        delete edits[id];
        this.edits = edits;
    }

    // ---------- choosing files ----------
    handleChooseFile(event) {
        if (this.isSaving) {
            return;
        }
        this.fileTarget = event.currentTarget.dataset.target;
        this.template.querySelector('.file-input').click();
    }

    handleFileSelected(event) {
        const file = event.target.files && event.target.files[0];
        event.target.value = null;
        const target = this.fileTarget;
        this.fileTarget = undefined;
        if (!file || !target) {
            return;
        }
        const problem = fileProblem(file, this.maxFileSize);
        if (problem) {
            this.setChosenFile(target, undefined, problem);
            this.toast('File not added', problem, 'warning');
            return;
        }
        this.setChosenFile(target, file, undefined);
    }

    handleRemoveChosenFile(event) {
        const target = event.currentTarget.dataset.target;
        this.setChosenFile(target, null, undefined);
        // Back to the Upload button, or to Replace when the configuration's current file shows again
        this.restoreFocus = `button.upload-button[data-target="${target}"], button.chip-action[data-target="${target}"]`;
    }

    // Unlinks the configuration's current file when the edit is saved (the file stays in its folder)
    handleRemoveCurrentFile(event) {
        const target = event.currentTarget.dataset.target;
        const id = target.split('|')[1];
        this.patchEdit(id, { current: null });
        this.restoreFocus = `button.upload-button[data-target="${target}"]`;
    }

    // file: the chosen File, null to clear the choice, or undefined to keep it and only set the error
    setChosenFile(target, file, fileError) {
        const [kind, id, session] = target.split('|');
        if (kind === 'new') {
            this.newRows = this.newRows.map((row) =>
                row.key === id ? { ...row, file: file === undefined ? row.file : file, fileError } : row
            );
        } else {
            const draft = this.edits[id];
            if (draft && draft.session === session) {
                this.patchEdit(id, { pendingFile: file === undefined ? draft.pendingFile : file, fileError });
            }
        }
    }

    // ---------- uploading into each configuration's folder ----------
    queueUpload(configurationId, file) {
        // Queued after the page was left (a save that finished late): offer Retry when the page comes back
        const pageLeft = this.isDisconnected;
        this.uploads = {
            ...this.uploads,
            [configurationId]: {
                configurationId,
                file,
                name: file.name,
                status: pageLeft ? 'error' : 'queued',
                progress: 0,
                error: pageLeft ? PAGE_LEFT : undefined,
                token: nextKey()
            }
        };
    }

    patchUpload(configurationId, token, patch) {
        const upload = this.uploads[configurationId];
        if (upload && upload.token === token) {
            this.uploads = { ...this.uploads, [configurationId]: { ...upload, ...patch } };
        }
    }

    removeUpload(configurationId, token) {
        const upload = this.uploads[configurationId];
        if (upload && (token === undefined || upload.token === token)) {
            const uploads = { ...this.uploads };
            delete uploads[configurationId];
            this.uploads = uploads;
        }
    }

    handleCancelUpload(event) {
        const id = event.currentTarget.dataset.id;
        // Removing the entry changes nothing else; the running upload sees it is no longer current and stops
        this.removeUpload(id);
        this.restoreFocus = this.canEdit ? `button.icon-btn_edit[data-id="${id}"]` : 'button.icon-btn[aria-label="Refresh configurations"]';
    }

    handleRetryUpload(event) {
        const id = event.currentTarget.dataset.id;
        const upload = this.uploads[id];
        if (upload && upload.status === 'error') {
            // Keeps what already worked (the uploaded file, its Sub Document), so only the failed step runs again
            this.uploads = { ...this.uploads, [id]: { ...upload, status: 'queued', progress: 0, error: undefined, token: nextKey() } };
            this.restoreFocus = `button.chip-remove[data-id="${id}"]`;
            this.processUploads();
        }
    }

    async processUploads() {
        if (this.uploadWorkerRunning) {
            return;
        }
        this.uploadWorkerRunning = true;
        let uploaded = 0;
        // configuration Id -> file name; a later successful retry of the same configuration clears it
        const failed = new Map();
        try {
            for (;;) {
                const next = this.isDisconnected
                    ? undefined
                    : Object.values(this.uploads).find((upload) => upload.status === 'queued');
                if (!next) {
                    break;
                }
                // One file at a time, so each keeps its chunk calls well inside the Apex limits
                // eslint-disable-next-line no-await-in-loop
                const outcome = await this.runUpload(next);
                if (outcome === 'failed') {
                    failed.set(next.configurationId, next.name);
                } else {
                    failed.delete(next.configurationId);
                }
                if (outcome === 'done') {
                    uploaded++;
                }
            }
        } finally {
            this.uploadWorkerRunning = false;
        }
        // Only files that are still waiting for a Retry (not dismissed meanwhile)
        const stillFailed = [...failed.entries()]
            .filter(([id]) => this.uploads[id] && this.uploads[id].status === 'error')
            .map(([, name]) => name);
        if (stillFailed.length) {
            this.toast(
                stillFailed.length === 1 ? 'A file was not uploaded' : `${stillFailed.length} files were not uploaded`,
                `${stillFailed.join(', ')}. Select Retry on the configuration to try again.`,
                'warning'
            );
        } else if (uploaded) {
            this.toast('Upload complete', `${uploaded === 1 ? '1 file' : `${uploaded} files`} saved in the configuration folders.`, 'success');
        }
    }

    async runUpload({ configurationId, file, token, itemId, subDocumentId }) {
        const isCurrent = () => {
            const current = this.uploads[configurationId];
            return !this.isDisconnected && !!current && current.token === token;
        };
        try {
            let fileId = subDocumentId;
            if (!fileId) {
                this.patchUpload(configurationId, token, { status: 'preparing' });
                const folderId = await this.waitForFolder(configurationId, isCurrent);
                this.patchUpload(configurationId, token, { status: 'uploading', progress: itemId ? 95 : 0 });
                const result = await uploadFileToFolder({
                    documentId: folderId,
                    file,
                    itemId,
                    onProgress: (progress) => this.patchUpload(configurationId, token, { progress }),
                    // Remembered so that a Retry does not send the whole file again
                    onUploaded: (uploadedItemId) => this.patchUpload(configurationId, token, { itemId: uploadedItemId }),
                    isCancelled: () => !isCurrent()
                });
                fileId = result.subDocumentId;
                this.patchUpload(configurationId, token, { subDocumentId: fileId });
            } else {
                this.patchUpload(configurationId, token, { status: 'uploading', progress: 100 });
            }
            // The file is in the configuration's folder now, so it is linked even if the row was dismissed meanwhile
            const saved = await attachFile({ projectId: this.recordId, configurationId, subDocumentId: fileId });
            this.applySaved([saved]);
            // Also clears an entry that the page closing turned into an error while this upload was finishing
            const current = this.uploads[configurationId];
            if (current && (current.token === token || current.file === file)) {
                this.removeUpload(configurationId);
            }
            this.flash([configurationId]);
            // A reload sent now replaces any older one that might still show the row without its file
            this.loadConfigurations();
            this.notifyPage();
            return 'done';
        } catch (error) {
            if (error instanceof UploadCancelledError || !isCurrent()) {
                return 'cancelled';
            }
            this.patchUpload(configurationId, token, { status: 'error', error: reduceError(error) });
            return 'failed';
        }
    }

    // A just-saved configuration's folder is created by a background job; wait until SharePoint has it
    async waitForFolder(configurationId, isCurrent) {
        const started = Date.now();
        const deadline = started + FOLDER_WAIT_MS;
        let lastRequest = 0;
        for (;;) {
            if (!isCurrent()) {
                throw new UploadCancelledError();
            }
            // eslint-disable-next-line no-await-in-loop
            const [status] = await getFolderStatus({ projectId: this.recordId, configurationIds: [configurationId] });
            if (!status) {
                throw new Error('This configuration is no longer on this project.');
            }
            if (status.ready) {
                return status.folderId;
            }
            // No folder yet (saved before folders existed, or right after its project), or one SharePoint has not
            // created for a while: ask the server to create it or queue it again
            const now = Date.now();
            if ((!status.folderId || now - started > FOLDER_STALLED_MS) && now - lastRequest >= FOLDER_REQUEST_EVERY_MS) {
                lastRequest = now;
                // eslint-disable-next-line no-await-in-loop
                await requestFolder({ projectId: this.recordId, configurationId });
            }
            if (Date.now() > deadline) {
                throw new Error('The SharePoint folder for this configuration is not ready yet. Select Retry in a minute.');
            }
            // eslint-disable-next-line no-await-in-loop
            await wait(FOLDER_POLL_MS);
        }
    }

    // ---------- helpers ----------
    // Shows saved values straight away; the reload that follows only re-sorts the list
    applySaved(saved) {
        const list = (saved || []).filter(Boolean);
        if (!list.length) {
            return;
        }
        const byId = new Map(list.map((config) => [config.id, config]));
        const known = new Set(this.configurations.map((config) => config.id));
        const merged = this.configurations.map((config) => byId.get(config.id) || config);
        list.forEach((config) => {
            if (!known.has(config.id)) {
                merged.push(config);
            }
        });
        this.configurations = merged;
    }

    flash(ids) {
        this.highlightIds = ids;
        clearTimeout(this.highlightTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.highlightTimer = setTimeout(() => {
            this.highlightIds = [];
        }, HIGHLIGHT_MS);
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}