import createUploadSession from '@salesforce/apex/SharePointDocumentManagerController.createUploadSession';
import uploadChunk from '@salesforce/apex/SharePointDocumentManagerController.uploadChunk';
import saveSubDocument from '@salesforce/apex/SharePointDocumentManagerController.saveSubDocument';
import getMaxUploadBytes from '@salesforce/apex/SharePointDocumentManagerController.getMaxUploadBytes';

// SharePoint needs upload ranges in multiples of 320 KiB; this size also keeps each Apex call well inside its limits
const CHUNK_SIZE = 5 * 320 * 1024;
const RETRIES = 2;

// The limit used until the SharePoint setting's own (Max Upload MB) has loaded, and whenever it cannot be read
export const MAX_FILE_SIZE = 200 * 1024 * 1024;

let maxFileSizeRequest;

/**
 * The largest file an upload accepts, in bytes: Max Upload MB of the SharePoint setting, or MAX_FILE_SIZE when it
 * cannot be read. Asked once per page; a request that failed is asked again the next time.
 * @returns {Promise<number>}
 */
export function loadMaxFileSize() {
    if (!maxFileSizeRequest) {
        maxFileSizeRequest = getMaxUploadBytes()
            .then((bytes) => (Number(bytes) > 0 ? Number(bytes) : MAX_FILE_SIZE))
            .catch(() => {
                maxFileSizeRequest = undefined;
                return MAX_FILE_SIZE;
            });
    }
    return maxFileSizeRequest;
}

/**
 * A size limit as people read it, for example "200 MB" or "1.5 GB".
 * @param {number} bytes
 * @returns {string}
 */
export function sizeLabel(bytes) {
    const mb = bytes / (1024 * 1024);
    return mb >= 1024 ? `${+(mb / 1024).toFixed(1)} GB` : `${+mb.toFixed(1)} MB`;
}

export class UploadCancelledError extends Error {
    constructor() {
        super('Upload cancelled');
        this.name = 'UploadCancelledError';
    }
}

/**
 * Uploads one file into the SharePoint folder of a Document__c record and saves it as a Sub Document
 * with a public preview link.
 * @param {object} options
 * @param {string} options.documentId Document__c Id of the target folder
 * @param {File} options.file
 * @param {(percent: number) => void} [options.onProgress]
 * @param {() => boolean} [options.isCancelled] checked between steps; true stops the upload
 * @param {(itemId: string) => void} [options.onUploaded] called once SharePoint holds the whole file
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
            throw new Error('SharePoint did not confirm the upload.');
        }
        onUploaded(itemId);
    }
    // A cancelled upload must not get a public link or a Sub Document
    if (isCancelled()) {
        throw new UploadCancelledError();
    }
    // The file is already in SharePoint, so only the preview link + Sub Document step is retried
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