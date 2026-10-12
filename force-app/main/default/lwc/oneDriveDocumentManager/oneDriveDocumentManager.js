import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent, registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import getDocuments from '@salesforce/apex/OneDriveDocumentManagerController.getDocuments';
import deleteFile from '@salesforce/apex/OneDriveDocumentManagerController.deleteFile';
import createUploadSession from '@salesforce/apex/OneDriveDocumentManagerController.createUploadSession';
import uploadChunk from '@salesforce/apex/OneDriveDocumentManagerController.uploadChunk';
import saveSubDocument from '@salesforce/apex/OneDriveDocumentManagerController.saveSubDocument';

// OneDrive needs upload ranges in multiples of 320 KiB; this size also keeps each Apex call well inside its limits
const CHUNK_SIZE = 5 * 320 * 1024;
const MAX_FILE_SIZE = 200 * 1024 * 1024;
const RETRIES = 2;
const FILE_ICONS = {
    pdf: 'doctype:pdf',
    jpg: 'doctype:image',
    jpeg: 'doctype:image',
    png: 'doctype:image',
    mp4: 'doctype:video'
};

export default class OneDriveDocumentManager extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api cardTitle = 'Document List';
    // Optional: API name of the Document__c lookup to this object; blank = detected automatically
    @api relationshipField;

    documents = [];
    expandedIds = [];
    isLoading = true;
    loadError;
    upload;
    targetDocumentId;
    cancelled = false;
    acceptedTypes = '.pdf,.jpg,.jpeg,.png,.mp4';
    skeletonRows = ['s1', 's2', 's3', 's4', 's5'];
    // Files being deleted right now
    deletingIds = [];
    refreshHandlerId;
    // Only the latest reload may replace the list; an older response could bring back a deleted file
    loadSeq = 0;

    connectedCallback() {
        this.cancelled = false;
        this.loadDocuments();
        // Reload when another component on the page changes files, for example an upload from Project Configurations
        this.refreshHandlerId = registerRefreshHandler(this, () => this.handlePageRefresh());
    }

    disconnectedCallback() {
        // Leaving the page stops any files that have not finished uploading
        this.cancelled = true;
        unregisterRefreshHandler(this.refreshHandlerId);
    }

    handlePageRefresh() {
        // A running upload reloads the list itself when it finishes
        if (this.upload) {
            return Promise.resolve(true);
        }
        return this.loadDocuments().then(() => true);
    }

    // Tells the page (related lists, Project Configurations) that files changed
    notifyPage() {
        this.dispatchEvent(new RefreshEvent());
    }

    async loadDocuments() {
        const seq = ++this.loadSeq;
        this.isLoading = true;
        this.loadError = undefined;
        try {
            const documents = await getDocuments({ recordId: this.recordId, relationshipField: this.relationshipField });
            if (seq === this.loadSeq) {
                this.documents = documents;
            }
        } catch (error) {
            if (seq === this.loadSeq) {
                this.loadError = this.reduceError(error);
            }
        } finally {
            if (seq === this.loadSeq) {
                this.isLoading = false;
            }
        }
    }

    // ---------- view state ----------
    get isBusy() { return this.isLoading || !!this.upload; }
    get hasDocuments() { return this.documents.length > 0; }
    get showEmptyState() { return !this.isLoading && !this.loadError && this.documents.length === 0; }
    get showSkeleton() { return this.isLoading && this.documents.length === 0; }
    get uploadedCount() { return this.documents.filter((d) => this.fileCount(d) > 0).length; }
    get summaryText() { return `${this.uploadedCount} of ${this.documents.length} folders have files`; }

    get rows() {
        return this.documents.map((doc, index) => this.folderView(doc, index, false));
    }

    // Files in a folder plus the files in its sub-folders
    fileCount(doc) {
        return doc.files.length + (doc.folders || []).reduce((sum, sub) => sum + sub.files.length, 0);
    }

    folderView(doc, index, isSubfolder) {
        const expanded = this.expandedIds.includes(doc.id);
        const hasFiles = doc.files.length > 0;
        const subfolders = isSubfolder ? [] : doc.folders || [];
        const uploading = !!this.upload && this.upload.documentId === doc.id;
        let rowClass = isSubfolder ? 'doc-row doc-row_sub' : 'doc-row';
        if (index % 2 === 1 && !isSubfolder) rowClass += ' doc-row_alt';
        if (expanded) rowClass += ' doc-row_open';
        if (uploading) rowClass += ' doc-row_uploading';
        return {
            ...doc,
            expanded,
            hasFiles,
            hasContent: this.fileCount(doc) > 0,
            hasSubfolders: subfolders.length > 0,
            showNoFiles: !hasFiles && subfolders.length === 0,
            uploading,
            ariaExpanded: String(expanded),
            toggleTitle: subfolders.length ? 'Show folders and files' : 'Show files',
            chevronClass: expanded ? 'chevron chevron_open' : 'chevron',
            folderIcon: isSubfolder ? 'utility:open_folder' : 'utility:file',
            rowClass,
            uploadClass: hasFiles ? 'upload-button upload-button_done' : 'upload-button',
            uploadDisabled: !doc.hasFolder || !!this.upload,
            uploadLabel: uploading ? 'Uploading…' : 'Upload',
            uploadTitle: doc.hasFolder
                ? `Upload files to ${doc.name}`
                : 'The OneDrive folder is still being created. Refresh in a minute.',
            countLabel: doc.files.length === 1 ? '1 file' : `${doc.files.length} files`,
            folderCountLabel: subfolders.length === 1 ? '1 folder' : `${subfolders.length} folders`,
            notReady: !doc.hasFolder,
            progressStyle: uploading ? `width: ${this.upload.progress}%` : '',
            progressText: uploading
                ? `Uploading ${this.upload.fileName} (${this.upload.fileIndex} of ${this.upload.fileCount}) · ${this.upload.progress}%`
                : '',
            files: doc.files.map((file) => this.fileView(file)),
            subfolders: subfolders.map((sub, subIndex) => this.folderView(sub, subIndex, true))
        };
    }

    fileView(file) {
        const deleting = this.deletingIds.includes(file.id);
        return {
            ...file,
            icon: this.iconFor(file.name),
            deleting,
            itemClass: deleting ? 'file-item file-item_deleting' : 'file-item',
            deleteLabel: `Delete ${file.name}`
        };
    }

    // The folder with this id and the folder it sits in, if any
    findFolder(id) {
        for (const doc of this.documents) {
            if (doc.id === id) {
                return { folder: doc, parentId: null };
            }
            const sub = (doc.folders || []).find((f) => f.id === id);
            if (sub) {
                return { folder: sub, parentId: doc.id };
            }
        }
        return null;
    }

    // ---------- actions ----------
    handleRefresh() {
        this.loadDocuments();
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.expandedIds = this.expandedIds.includes(id)
            ? this.expandedIds.filter((x) => x !== id)
            : [...this.expandedIds, id];
    }

    handleUploadClick(event) {
        this.targetDocumentId = event.currentTarget.dataset.id;
        this.template.querySelector('.file-input').click();
    }

    async handleFilesSelected(event) {
        const picked = Array.from(event.target.files || []);
        event.target.value = null;
        const documentId = this.targetDocumentId;
        if (!documentId || picked.length === 0) {
            return;
        }

        const rejected = [];
        const files = picked.filter((file) => {
            const ext = file.name.includes('.') ? file.name.split('.').pop().toLowerCase() : '';
            if (!FILE_ICONS[ext]) {
                rejected.push(`${file.name} (type not allowed)`);
                return false;
            }
            if (file.size === 0) {
                rejected.push(`${file.name} (empty)`);
                return false;
            }
            if (file.size > MAX_FILE_SIZE) {
                rejected.push(`${file.name} (over 200 MB)`);
                return false;
            }
            return true;
        });
        if (rejected.length) {
            this.toast('Some files were skipped', `${rejected.join(', ')}. Allowed: PDF, JPG, JPEG, PNG, MP4.`, 'warning');
        }
        if (files.length) {
            await this.uploadFiles(documentId, files);
        }
    }

    async uploadFiles(documentId, files) {
        const found = this.findFolder(documentId);
        const folder = found ? found.folder : null;
        // Open the folder, and the folder it sits in, so the progress and the new files are visible
        const toOpen = [documentId, found && found.parentId].filter((id) => id && !this.expandedIds.includes(id));
        if (toOpen.length) {
            this.expandedIds = [...this.expandedIds, ...toOpen];
        }
        this.upload = { documentId, fileName: '', fileIndex: 0, fileCount: files.length, progress: 0 };

        const failures = [];
        let uploaded = 0;
        for (let i = 0; i < files.length; i++) {
            if (this.cancelled) {
                return;
            }
            this.upload = { ...this.upload, fileName: files[i].name, fileIndex: i + 1, progress: 0 };
            try {
                // Files go one after another so each chunk upload keeps its own Apex limits
                // eslint-disable-next-line no-await-in-loop
                await this.uploadOne(documentId, files[i]);
                uploaded++;
            } catch (error) {
                failures.push(`${files[i].name}: ${this.reduceError(error)}`);
            }
        }
        if (this.cancelled) {
            return;
        }

        this.upload = undefined;
        await this.loadDocuments();
        this.notifyPage();
        const folderName = folder ? folder.name : 'the folder';
        if (failures.length) {
            this.toast(`${uploaded} uploaded, ${failures.length} failed`, failures.join(' | '), 'warning');
        } else {
            this.toast('Upload complete', `${uploaded === 1 ? '1 file' : uploaded + ' files'} saved to ${folderName}.`, 'success');
        }
    }

    async uploadOne(documentId, file) {
        const uploadUrl = await createUploadSession({ documentId, fileName: file.name });
        const total = file.size;
        let itemId;
        for (let start = 0; start < total; start += CHUNK_SIZE) {
            if (this.cancelled) {
                throw new Error('Upload cancelled');
            }
            const end = Math.min(start + CHUNK_SIZE, total);
            // eslint-disable-next-line no-await-in-loop
            const base64Chunk = await this.readAsBase64(file.slice(start, end));
            // eslint-disable-next-line no-await-in-loop
            const result = await this.withRetry(() =>
                uploadChunk({ uploadUrl, base64Chunk, startByte: start, endByte: end, totalSize: total })
            );
            if (result.complete) {
                itemId = result.itemId;
            }
            this.upload = { ...this.upload, progress: Math.floor((end / total) * 95) };
        }
        if (!itemId) {
            throw new Error('OneDrive did not confirm the upload.');
        }
        // The file is already in OneDrive, so only the preview link + Sub Document step is retried
        await this.withRetry(() => saveSubDocument({ documentId, itemId, fileName: file.name }));
        this.upload = { ...this.upload, progress: 100 };
    }

    async withRetry(action) {
        for (let attempt = 0; ; attempt++) {
            try {
                // eslint-disable-next-line no-await-in-loop
                return await action();
            } catch (error) {
                if (attempt >= RETRIES || this.cancelled) {
                    throw error;
                }
                // eslint-disable-next-line no-await-in-loop
                await this.wait(1000 * (attempt + 1));
            }
        }
    }

    // ---------- deleting a file (folders are never deleted) ----------
    async handleDeleteFile(event) {
        const id = event.currentTarget.dataset.id;
        const file = this.findFile(id);
        if (!file || !file.canDelete || this.deletingIds.includes(id)) {
            return;
        }
        const linked = file.linkedConfigurations || [];
        const confirmed = await LightningConfirm.open({
            label: 'Delete this file?',
            message: `"${file.name}" will be deleted and moved to the OneDrive recycle bin.`
                + (linked.length ? ` It is also removed from configuration ${linked.join(', ')}.` : ''),
            theme: 'error'
        });
        if (!confirmed) {
            return;
        }
        this.deletingIds = [...this.deletingIds, id];
        try {
            await deleteFile({ subDocumentId: id });
            await this.loadDocuments();
            this.notifyPage();
            this.toast('File deleted', `${file.name} was deleted.`, 'success');
        } catch (error) {
            this.toast('File not deleted', this.reduceError(error), 'error');
        } finally {
            this.deletingIds = this.deletingIds.filter((x) => x !== id);
        }
    }

    findFile(id) {
        for (const doc of this.documents) {
            const own = doc.files.find((f) => f.id === id);
            if (own) {
                return own;
            }
            for (const sub of doc.folders || []) {
                const inside = sub.files.find((f) => f.id === id);
                if (inside) {
                    return inside;
                }
            }
        }
        return null;
    }

    // ---------- helpers ----------
    wait(ms) {
        return new Promise((resolve) => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(resolve, ms);
        });
    }

    readAsBase64(blob) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result.substring(reader.result.indexOf(',') + 1));
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(blob);
        });
    }

    iconFor(name) {
        const ext = name && name.includes('.') ? name.split('.').pop().toLowerCase() : '';
        return FILE_ICONS[ext] || 'doctype:attachment';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'Something went wrong. Please try again.';
    }
}