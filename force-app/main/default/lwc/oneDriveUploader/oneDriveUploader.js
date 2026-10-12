import createUploadSession from '@salesforce/apex/OneDriveDocumentManagerController.createUploadSession';
import uploadChunk from '@salesforce/apex/OneDriveDocumentManagerController.uploadChunk';
import saveSubDocument from '@salesforce/apex/OneDriveDocumentManagerController.saveSubDocument';

// OneDrive needs upload ranges in multiples of 320 KiB; this size also keeps each Apex call well inside its limits
const CHUNK_SIZE = 5 * 320 * 1024;
const RETRIES = 2;

export const MAX_FILE_SIZE = 200 * 1024 * 1024;

export class UploadCancelledError extends Error {
    constructor() {
        super('Upload cancelled');
        this.name = 'UploadCancelledError';
    }
}

/**
 * Uploads one file into the OneDrive folder of a Document__c record and saves it as a Sub Document
 * with a public preview link.
 * @param {object} options
 * @param {string} options.documentId Document__c Id of the target folder
 * @param {File} options.file
 * @param {(percent: number) => void} [options.onProgress]
 * @param {() => boolean} [options.isCancelled] checked between steps; true stops the upload
 * @param {(itemId: string) => void} [options.onUploaded] called once OneDrive holds the whole file
 * @param {string} [options.itemId] a file already uploaded into the folder; only its link and Sub Document are made
 * @returns {Promise<{subDocumentId: string, fileUrl: string, isPublic: boolean}>}
 */
export async function uploadFileToFolder({
    documentId,
    file,
    onProgress = () => {},
    isCancelled = () => false,
    onUploaded = () => {},
    itemId: uploadedItemId
}) {
    let itemId = uploadedItemId;
    if (!itemId) {
        const uploadUrl = await createUploadSession({ documentId, fileName: file.name });
        const total = file.size;
        for (let start = 0; start < total; start += CHUNK_SIZE) {
            if (isCancelled()) {
                throw new UploadCancelledError();
            }
            const end = Math.min(start + CHUNK_SIZE, total);
            // eslint-disable-next-line no-await-in-loop
            const base64Chunk = await readAsBase64(file.slice(start, end));
            // eslint-disable-next-line no-await-in-loop
            const result = await withRetry(
                () => uploadChunk({ uploadUrl, base64Chunk, startByte: start, endByte: end, totalSize: total }),
                isCancelled
            );
            if (result.complete) {
                itemId = result.itemId;
            }
            onProgress(Math.floor((end / total) * 95));
        }
        if (!itemId) {
            throw new Error('OneDrive did not confirm the upload.');
        }
        onUploaded(itemId);
    }
    // A cancelled upload must not get a public link or a Sub Document
    if (isCancelled()) {
        throw new UploadCancelledError();
    }
    // The file is already in OneDrive, so only the preview link + Sub Document step is retried
    const saved = await withRetry(() => saveSubDocument({ documentId, itemId, fileName: file.name }), isCancelled);
    onProgress(100);
    return saved;
}

async function withRetry(action, isCancelled) {
    for (let attempt = 0; ; attempt++) {
        try {
            // eslint-disable-next-line no-await-in-loop
            return await action();
        } catch (error) {
            if (attempt >= RETRIES || isCancelled()) {
                throw error;
            }
            // eslint-disable-next-line no-await-in-loop
            await wait(1000 * (attempt + 1));
        }
    }
}

function wait(ms) {
    return new Promise((resolve) => {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(resolve, ms);
    });
}

function readAsBase64(blob) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result.substring(reader.result.indexOf(',') + 1));
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(blob);
    });
}