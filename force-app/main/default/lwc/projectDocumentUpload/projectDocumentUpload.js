import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import { refreshApex } from '@salesforce/apex';
import getProjectDocuments from '@salesforce/apex/ProjectDocumentUploadController.getProjectDocuments';
import createUploadSession from '@salesforce/apex/ProjectDocumentUploadController.createUploadSession';
import uploadChunk from '@salesforce/apex/ProjectDocumentUploadController.uploadChunk';
import saveSubDocument from '@salesforce/apex/ProjectDocumentUploadController.saveSubDocument';

// OneDrive needs upload ranges in multiples of 320 KiB; this size also keeps each Apex call well inside its limits
const CHUNK_SIZE = 5 * 320 * 1024;
const MAX_FILE_SIZE = 200 * 1024 * 1024;
const FILE_TYPES = {
    pdf: { icon: 'doctype:pdf', kind: 'pdf' },
    jpg: { icon: 'doctype:image', kind: 'image' },
    jpeg: { icon: 'doctype:image', kind: 'image' },
    png: { icon: 'doctype:image', kind: 'image' },
    mp4: { icon: 'doctype:video', kind: 'video' }
};
const STEPS = [
    { key: 'folder', number: 1, label: 'Choose folder' },
    { key: 'files', number: 2, label: 'Add files' },
    { key: 'upload', number: 3, label: 'Upload' }
];
// Circumference of the progress ring (r = 52)
const RING_LENGTH = 2 * Math.PI * 52;

export default class ProjectDocumentUpload extends LightningElement {
    @api recordId;

    folders = [];
    files = [];
    selectedFolderId;
    step = 'folder';
    isLoading = true;
    loadError;
    fileError;
    isDragging = false;
    acceptedTypes = '.pdf,.jpg,.jpeg,.png,.mp4';
    skeletonTiles = ['s1', 's2', 's3', 's4'];
    wiredFoldersResult;
    nextKey = 0;

    @wire(getProjectDocuments, { projectId: '$recordId' })
    wiredFolders(result) {
        this.wiredFoldersResult = result;
        if (result.data) {
            this.folders = result.data;
            this.loadError = undefined;
            this.isLoading = false;
        } else if (result.error) {
            this.loadError = this.reduceError(result.error);
            this.isLoading = false;
        }
    }

    // ---------- steps + hero ----------
    get isFolderStep() { return this.step === 'folder'; }
    get isFilesStep() { return this.step === 'files'; }
    get isUploadingStep() { return this.step === 'uploading'; }
    get isDoneStep() { return this.step === 'done'; }

    get steps() {
        let current = 2;
        if (this.isFolderStep) current = 0;
        else if (this.isFilesStep) current = 1;
        return STEPS.map((s, i) => {
            const done = i < current || this.isDoneStep;
            let className = 'step';
            if (done) className += ' step_done';
            else if (i === current) className += ' step_active';
            return {
                ...s,
                isDone: done,
                className,
                showConnector: i < STEPS.length - 1,
                connectorClass: i < current || this.isDoneStep ? 'connector connector_filled' : 'connector'
            };
        });
    }

    get heroIcon() {
        if (this.isFolderStep) return 'utility:open_folder';
        if (this.isFilesStep) return 'utility:upload';
        if (this.isUploadingStep) return 'utility:sync';
        return this.hasFailures ? 'utility:warning' : 'utility:success';
    }

    get heroIconClass() {
        return this.isUploadingStep ? 'hero-icon hero-icon_spin' : 'hero-icon';
    }

    get heroTitle() {
        if (this.isFolderStep) return 'Choose a document folder';
        if (this.isFilesStep) return 'Add your files';
        if (this.isUploadingStep) return 'Uploading to OneDrive';
        return this.hasFailures ? 'Upload finished with errors' : 'All done!';
    }

    get heroSubtitle() {
        if (this.isFolderStep) return 'Files are stored in this project\'s OneDrive folder.';
        if (this.isFilesStep) return 'PDF, images and MP4 videos — add as many as you need.';
        if (this.isUploadingStep) return 'Each file gets a shareable preview link.';
        return 'Your files are saved as Sub Documents with preview links.';
    }

    // ---------- step 1: folder ----------
    get folderTiles() {
        return this.folders.map((folder, index) => {
            const selected = folder.id === this.selectedFolderId;
            let tileClass = 'folder-tile';
            if (selected) tileClass += ' folder-tile_selected';
            if (!folder.hasFolder) tileClass += ' folder-tile_disabled';
            return {
                ...folder,
                tileClass,
                style: `--delay: ${index * 70}ms`,
                disabled: !folder.hasFolder,
                ariaChecked: String(selected),
                meta: folder.hasFolder ? this.fileCountLabel(folder.fileCount) : 'Folder is still being created',
                badgeClass: folder.status === 'Uploaded' ? 'status-chip status-chip_success' : 'status-chip status-chip_pending'
            };
        });
    }
    get showEmptyState() { return !this.isLoading && !this.loadError && this.folders.length === 0; }
    get hasFolders() { return this.folders.length > 0; }
    get selectedFolderName() {
        const folder = this.folders.find((f) => f.id === this.selectedFolderId);
        return folder ? folder.name : '';
    }
    get isNextDisabled() { return !this.selectedFolderId; }

    handleFolderSelect(event) {
        const folder = this.folders.find((f) => f.id === event.currentTarget.dataset.id);
        if (folder && folder.hasFolder) {
            this.selectedFolderId = folder.id;
        }
    }

    handleNext() {
        this.step = 'files';
    }

    handleBack() {
        this.step = 'folder';
    }

    // ---------- step 2: files ----------
    get hasFiles() { return this.files.length > 0; }
    get isSaveDisabled() { return this.files.length === 0; }
    get dropzoneClass() { return this.isDragging ? 'dropzone dropzone_active' : 'dropzone'; }
    get dropTitle() { return this.isDragging ? 'Drop to add your files' : 'Drag & drop files here'; }
    get fileCountText() { return this.fileCountLabel(this.files.length) + ' selected'; }
    get totalSizeLabel() { return this.formatSize(this.files.reduce((sum, f) => sum + f.file.size, 0)); }
    get fileRows() {
        return this.files.map((f, index) => ({ ...f, rowStyle: `--delay: ${Math.min(index, 10) * 50}ms` }));
    }

    handleBrowse() {
        this.template.querySelector('.file-input').click();
    }

    handleDropzoneKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleBrowse();
        }
    }

    handleFileInput(event) {
        this.addFiles(event.target.files);
        event.target.value = null;
    }

    handleDragOver(event) {
        event.preventDefault();
        this.isDragging = true;
    }

    handleDragLeave() {
        this.isDragging = false;
    }

    handleDrop(event) {
        event.preventDefault();
        this.isDragging = false;
        this.addFiles(event.dataTransfer.files);
    }

    addFiles(fileList) {
        const rejected = [];
        const added = [];
        Array.from(fileList || []).forEach((file) => {
            const ext = file.name.includes('.') ? file.name.split('.').pop().toLowerCase() : '';
            const type = FILE_TYPES[ext];
            if (!type) {
                rejected.push(`${file.name} (file type not allowed)`);
            } else if (file.size === 0) {
                rejected.push(`${file.name} (empty file)`);
            } else if (file.size > MAX_FILE_SIZE) {
                rejected.push(`${file.name} (larger than 200 MB)`);
            } else {
                added.push(this.decorate({
                    key: `file-${this.nextKey++}`,
                    file,
                    name: file.name,
                    icon: type.icon,
                    kind: type.kind,
                    sizeLabel: this.formatSize(file.size),
                    status: 'ready',
                    progress: 0
                }));
            }
        });
        this.files = [...this.files, ...added];
        this.fileError = rejected.length
            ? `Not added: ${rejected.join(', ')}. Allowed types: PDF, JPG, JPEG, PNG, MP4.`
            : undefined;
    }

    handleRemove(event) {
        const key = event.currentTarget.dataset.key;
        this.files = this.files.filter((f) => f.key !== key);
    }

    handleClearAll() {
        this.files = [];
        this.fileError = undefined;
    }

    // ---------- step 3: upload ----------
    get uploadedCount() { return this.files.filter((f) => f.status === 'done').length; }
    get failedCount() { return this.files.filter((f) => f.status === 'error').length; }
    get hasFailures() { return this.failedCount > 0; }
    get hasOrgOnlyLinks() { return this.files.some((f) => f.status === 'done' && !f.isPublic); }
    get overallProgress() {
        if (!this.files.length) return 0;
        return Math.floor(this.files.reduce((sum, f) => sum + (f.status === 'error' ? 100 : f.progress), 0) / this.files.length);
    }
    get ringStyle() {
        return `stroke-dasharray: ${RING_LENGTH}; stroke-dashoffset: ${RING_LENGTH * (1 - this.overallProgress / 100)}`;
    }
    get uploadingText() {
        const current = this.files.findIndex((f) => f.status === 'uploading') + 1;
        return `Uploading file ${current || this.uploadedCount} of ${this.files.length} to "${this.selectedFolderName}"`;
    }
    get doneTitle() {
        if (!this.hasFailures) return `${this.fileCountLabel(this.uploadedCount)} uploaded`;
        return `${this.uploadedCount} uploaded, ${this.failedCount} failed`;
    }
    get doneHeroClass() { return this.hasFailures ? 'done-hero done-hero_warning' : 'done-hero'; }

    async handleSave() {
        this.step = 'uploading';
        await this.uploadPending();
    }

    async handleRetry() {
        this.step = 'uploading';
        await this.uploadPending();
    }

    async uploadPending() {
        const pending = this.files.filter((f) => f.status !== 'done');
        for (const item of pending) {
            // Files go one after another so each chunk upload keeps its own Apex limits
            // eslint-disable-next-line no-await-in-loop
            await this.uploadFile(item);
        }
        this.step = 'done';
        refreshApex(this.wiredFoldersResult);
        this.dispatchEvent(new RefreshEvent());
        this.dispatchEvent(new ShowToastEvent({
            title: this.hasFailures ? 'Upload finished with errors' : 'Files uploaded',
            message: this.hasFailures
                ? `${this.uploadedCount} uploaded, ${this.failedCount} failed.`
                : `${this.fileCountLabel(this.uploadedCount)} saved to "${this.selectedFolderName}".`,
            variant: this.hasFailures ? 'warning' : 'success'
        }));
    }

    async uploadFile(item) {
        this.patchFile(item.key, { status: 'uploading', progress: 0, error: undefined });
        try {
            const uploadUrl = await createUploadSession({ documentId: this.selectedFolderId, fileName: item.name });
            const total = item.file.size;
            let itemId;
            for (let start = 0; start < total; start += CHUNK_SIZE) {
                const end = Math.min(start + CHUNK_SIZE, total);
                // eslint-disable-next-line no-await-in-loop
                const base64Chunk = await this.readAsBase64(item.file.slice(start, end));
                // eslint-disable-next-line no-await-in-loop
                const result = await uploadChunk({ uploadUrl, base64Chunk, startByte: start, endByte: end, totalSize: total });
                if (result.complete) {
                    itemId = result.itemId;
                }
                this.patchFile(item.key, { progress: Math.floor((end / total) * 95) });
            }
            if (!itemId) {
                throw new Error('OneDrive did not confirm the upload. Please try again.');
            }
            const saved = await saveSubDocument({ documentId: this.selectedFolderId, itemId, fileName: item.name });
            this.patchFile(item.key, { status: 'done', progress: 100, url: saved.fileUrl, isPublic: saved.isPublic });
        } catch (error) {
            this.patchFile(item.key, { status: 'error', error: this.reduceError(error) });
        }
    }

    handleUploadMore() {
        this.files = [];
        this.fileError = undefined;
        this.step = 'files';
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // ---------- helpers ----------
    patchFile(key, changes) {
        this.files = this.files.map((f) => (f.key === key ? this.decorate({ ...f, ...changes }) : f));
    }

    decorate(file) {
        let chipClass = 'status-chip status-chip_waiting';
        let chipLabel = 'Waiting';
        if (file.status === 'uploading') {
            chipClass = 'status-chip status-chip_active';
            chipLabel = `${file.progress}%`;
        } else if (file.status === 'done') {
            chipClass = 'status-chip status-chip_success';
            chipLabel = 'Done';
        } else if (file.status === 'error') {
            chipClass = 'status-chip status-chip_error';
            chipLabel = 'Failed';
        }
        return {
            ...file,
            isUploading: file.status === 'uploading',
            isDone: file.status === 'done',
            isError: file.status === 'error',
            badgeClass: `file-badge file-badge_${file.kind}`,
            barStyle: `width: ${file.progress}%`,
            chipClass,
            chipLabel,
            linkLabel: file.isPublic === false ? 'Open (sign-in)' : 'Open preview'
        };
    }

    readAsBase64(blob) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result.substring(reader.result.indexOf(',') + 1));
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(blob);
        });
    }

    formatSize(bytes) {
        if (bytes < 1024) return `${bytes} B`;
        if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
        return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }

    fileCountLabel(count) {
        return count === 1 ? '1 file' : `${count} files`;
    }

    reduceError(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'Something went wrong. Please try again.';
    }
}