import { LightningElement } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import SHEETJS from '@salesforce/resourceUrl/SheetJS';
import uploadWorkbook from '@salesforce/apex/InventoryUploadController.uploadWorkbook';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const SHEET_NAMES = [
    'Company',
    'Project',
    'Block',
    'Floor',
    'Unit',
    'Parking'
];

const PAGE_SIZE = 10;

const TEMPLATE_HEADERS = {
    Company: [
        'Company_Code__c',
        'Name',
        'Short_Name__c',
        'Registration_Number__c',
        'Website__c',
        'TIN__c',
        'VAT_No__c',
        'Establishment_number__c',
        'Phone_Number__c',
        'Address__Street__s',
        'Address__City__s',
        'Address__StateCode__s',
        'Address__PostalCode__s',
        'Address__CountryCode__s'
    ],
    Project: [
        'Project_Code__c',
        'Name',
        'Company_Code__c',
        'Project_Type__c',
        'Email__c','Location__c',
        'Project_Status__c',
        'Project_Location_Country__c',
        'Estimated_Budget__c',
        'Launch_Date__c',
        'Active__c',
        'Project_Location__Street__s',
        'Project_Location__City__s',
        'Project_Location__StateCode__s',
        'Project_Location__CountryCode__s'
    ],
    Block: [
        'Block_Code__c',
        'Name',
        'Project_Code__c',
        'Total_Floors__c',
        'Total_Units__c',
        'Parking_Availability__c'
    ],
    Floor: [
        'Floor_Code__c',
        'Name',
        'Block_Code__c',
        'Floor_No__c',
        'Description__c'
    ],
    Unit: [
        // Must match UNIT_KEY in InventoryUploadController.
        'Unit_Name_Code__c',
        'Unit_Name__c',
        'Unit_No__c',
        'Floor_Code__c',
        'Unit_Type__c',
        'Unit_Layout__c',
        'Built_Up_Area__c',
        'Base_Price__c',
        'Balcony_Area__c',
        'Facing__c',
        'Status_Code__c',
        'Status__c',
        'Undivided_Share__c',
        'Utility_Area__c',
        'No_Bedroom__c',
        'No_Bathroom__c',
        'CRM_Code__c'
    ],
    Parking: [
        'Parking_Slot_ID__c',
        'Name',
        'Block_Code__c',
        'Parking_Type__c',
        'Parking_Amount__c',
        'Available_Parking__c',
        'Amount_Per_Parking__c',
        'Total_Parking__c',
        'Total_Sold_Parking__c'
    ]
};

const MATCH_KEYS = {
    Company: 'Company_Code__c',
    Project: 'Project_Code__c',
    Block: 'Block_Code__c',
    Floor: 'Floor_Code__c',
    Unit: 'Unit_Name_Code__c',
    Parking: 'Parking_Slot_ID__c'
};

const PARENT_KEYS = {
    Project: 'Company_Code__c',
    Block: 'Project_Code__c',
    Floor: 'Block_Code__c',
    Unit: 'Floor_Code__c',
    Parking: 'Block_Code__c'
};

export default class InventoryUpload extends LightningElement {
    libraryLoaded = false;
    libraryLoadPromise;

    isLoading = false;
    fileName = '';
    errorMessage = '';

    workbookData = {};
    previewSheets = [];
    activeSheet = 'Company';
    visibleRows = [];
    paginationRefreshNeeded = false;

    results = [];
    inserted = 0;
    updated = 0;
    failed = 0;

    connectedCallback() {
        this.loadSheetJs().catch(error => {
            this.libraryLoaded = false;
            console.error('SheetJS loading failed:', error);
        });
    }

    // --------------------------------------------------
    // SHEETJS
    // --------------------------------------------------

    async loadSheetJs() {
        if (window.XLSX) {
            this.libraryLoaded = true;
            return window.XLSX;
        }

        if (!this.libraryLoadPromise) {
            this.libraryLoadPromise = loadScript(this, SHEETJS)
                .catch(error => {
                    this.libraryLoadPromise = null;
                    console.error('loadScript failed:', error);
                    throw error;
                });
        }

        await this.libraryLoadPromise;

        if (!window.XLSX) {
            throw new Error(
                'SheetJS loaded, but window.XLSX is unavailable.'
            );
        }

        this.libraryLoaded = true;
        return window.XLSX;
    }

    // --------------------------------------------------
    // DOWNLOAD TEMPLATE
    // --------------------------------------------------

    async handleDownloadTemplate() {
        try {
            const XLSX = await this.loadSheetJs();
            const workbook = XLSX.utils.book_new();

            Object.entries(TEMPLATE_HEADERS).forEach(
                ([sheetName, headers]) => {
                    const worksheet = XLSX.utils.aoa_to_sheet([
                        headers,
                        headers.map(() => '')
                    ]);

                    worksheet['!cols'] = headers.map(header => ({
                        wch: Math.max(header.length + 3, 18)
                    }));

                    XLSX.utils.book_append_sheet(
                        workbook,
                        worksheet,
                        sheetName
                    );
                }
            );

            XLSX.writeFile(
                workbook,
                'Inventory_Upload_Template.xlsx'
            );

            this.showToast(
                'Success',
                'Excel template with six worksheets generated.',
                'success'
            );
        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);
            this.showToast(
                'Template generation failed',
                this.errorMessage,
                'error'
            );
        }
    }

    // --------------------------------------------------
    // READ EXCEL FILE
    // --------------------------------------------------

    async handleFileChange(event) {
        const file = event.target.files?.[0];

        this.resetUploadState();

        if (!file) {
            return;
        }

        if (!/\.(xlsx|xls)$/i.test(file.name)) {
            this.errorMessage =
                'Please select an Excel workbook (.xlsx or .xls).';
            return;
        }

        this.isLoading = true;
        this.fileName = file.name;

        try {
            const XLSX = await this.loadSheetJs();
            const buffer = await file.arrayBuffer();

            const workbook = XLSX.read(buffer, {
                type: 'array',
                cellDates: true
            });

            const payload = {};
            const previews = [];
            let totalRows = 0;

            SHEET_NAMES.forEach(sheetName => {
                const worksheet = workbook.Sheets[sheetName];

                // Empty or missing worksheets are allowed.
                if (!worksheet) {
                    payload[sheetName] = [];
                    previews.push({
                        name: sheetName,
                        headers: [],
                        rows: []
                    });
                    return;
                }

                const data = XLSX.utils.sheet_to_json(
                    worksheet,
                    {
                        header: 1,
                        defval: null,
                        raw: false
                    }
                );

                if (!data.length) {
                    payload[sheetName] = [];
                    previews.push({
                        name: sheetName,
                        headers: [],
                        rows: []
                    });
                    return;
                }

                const headers = data[0].map(value =>
                    String(value ?? '').trim()
                );

                const headerErrors = this.validateHeaders(
                    sheetName,
                    headers
                );

                const nonBlankHeaders = headers.filter(Boolean);
                const records = [];
                const previewRows = [];
                const matchKey = MATCH_KEYS[sheetName];

                data.slice(1).forEach((cells, index) => {
                    const isEmpty = cells.every(value =>
                        value === null ||
                        value === undefined ||
                        String(value).trim() === ''
                    );

                    if (isEmpty) {
                        return;
                    }

                    const record = {};

                    headers.forEach((header, columnIndex) => {
                        if (!header) {
                            return;
                        }

                        const value = cells[columnIndex];

                        record[header] =
                            value === undefined ||
                            value === null ||
                            value === ''
                                ? null
                                : value;
                    });

                    const hasMappedValue = Object.values(record).some(
                        value =>
                            value !== null &&
                            value !== undefined &&
                            String(value).trim() !== ''
                    );

                    if (!hasMappedValue) {
                        return;
                    }

                    const excelRowNumber = index + 2;

                    const rowErrors = [...headerErrors];

                    const keyValue = record[matchKey];

                    if (
                        keyValue === null ||
                        keyValue === undefined ||
                        String(keyValue).trim() === ''
                    ) {
                        rowErrors.push(
                            `Missing matching key: ${matchKey}`
                        );
                    }

                    // Check blank parent references.
                    const parentKey = PARENT_KEYS[sheetName];

                    if (parentKey && (
                        record[parentKey] === null ||
                        record[parentKey] === undefined ||
                        String(record[parentKey]).trim() === ''
                    )) {
                        rowErrors.push(
                            `Parent key is required: ${parentKey}`
                        );
                    }

                    const row = {
                        ...record,
                        __excelRowNumber: excelRowNumber
                    };

                    records.push(row);

                    previewRows.push({
                        ...record,
                        _rowKey: `${sheetName}-${excelRowNumber}`,
                        _excelRowNumber: excelRowNumber,
                        _errorMessage: this.joinErrors(rowErrors)
                    });
                });

                payload[sheetName] = records;
                totalRows += records.length;

                previews.push({
                    name: sheetName,
                    headers: nonBlankHeaders,
                    rows: previewRows
                });
            });

            if (totalRows === 0) {
                throw new Error(
                    'No inventory records found in the workbook.'
                );
            }

            this.workbookData = payload;
            this.previewSheets = previews;

            // Validate keys and duplicates immediately after reading.
            this.validateWorkbook();

            this.activeSheet =
                this.previewSheets.find(
                    sheet => sheet.rows.length > 0
                )?.name || 'Company';

            this.paginationRefreshNeeded = true;

            if (this.hasValidationErrors) {
                this.showToast(
                    'Validation errors found',
                    'Review the Error column in each worksheet before uploading.',
                    'error'
                );
            } else {
                this.showToast(
                    'Workbook ready',
                    `${totalRows} records loaded. No errors found.`,
                    'success'
                );
            }
        } catch (error) {
            this.workbookData = {};
            this.previewSheets = [];
            this.visibleRows = [];
            this.errorMessage = this.getErrorMessage(error);

            this.showToast(
                'Excel validation failed',
                this.errorMessage,
                'error'
            );
        } finally {
            this.isLoading = false;
        }
    }

    resetUploadState() {
        this.workbookData = {};
        this.previewSheets = [];
        this.visibleRows = [];
        this.results = [];

        this.inserted = 0;
        this.updated = 0;
        this.failed = 0;

        this.errorMessage = '';
        this.fileName = '';
        this.activeSheet = 'Company';
        this.paginationRefreshNeeded = true;
    }

    // --------------------------------------------------
    // HEADER VALIDATION
    // --------------------------------------------------

    validateHeaders(sheetName, headers) {
        const errors = [];
        const nonBlankHeaders = headers.filter(Boolean);
        const seen = new Set();
        const duplicateHeaders = new Set();

        nonBlankHeaders.forEach(header => {
            const normalized = header.toLowerCase();

            if (seen.has(normalized)) {
                duplicateHeaders.add(header);
            }

            seen.add(normalized);
        });

        if (duplicateHeaders.size > 0) {
            errors.push(
                `Duplicate column header(s): ${
                    [...duplicateHeaders].join(', ')
                }`
            );
        }

        const allowedHeaders = TEMPLATE_HEADERS[sheetName] || [];
        const allowedSet = new Set(
            allowedHeaders.map(header => header.toLowerCase())
        );

        const unknownHeaders = nonBlankHeaders.filter(
            header => !allowedSet.has(header.toLowerCase())
        );

        if (unknownHeaders.length > 0) {
            errors.push(
                `Unexpected header(s): ${unknownHeaders.join(', ')}. ` +
                'Use the downloaded template headers.'
            );
        }

        const missingHeaders = allowedHeaders.filter(
            header => !nonBlankHeaders.some(
                actual => actual.toLowerCase() === header.toLowerCase()
            )
        );

        const matchKey = MATCH_KEYS[sheetName];

        if (
            matchKey &&
            missingHeaders.includes(matchKey)
        ) {
            errors.push(
                `Required matching-key column is missing: ${matchKey}`
            );
        }

        return errors;
    }

    // --------------------------------------------------
    // WORKBOOK VALIDATION
    // --------------------------------------------------

    validateWorkbook() {
        const updatedSheets = this.previewSheets.map(sheet => {
            const matchKey = MATCH_KEYS[sheet.name];
            const parentKey = PARENT_KEYS[sheet.name];
            const seenKeys = new Map();

            const rows = sheet.rows.map(row => {
                const errors = row._errorMessage
                    ? row._errorMessage
                        .split(' | ')
                        .filter(Boolean)
                    : [];

                const rawKey = row[matchKey];
                const normalizedKey = String(rawKey ?? '')
                    .trim()
                    .toLowerCase();

                if (normalizedKey) {
                    if (seenKeys.has(normalizedKey)) {
                        errors.push(
                            `Duplicate matching key "${rawKey}". ` +
                            `Also found on Excel row ${seenKeys.get(normalizedKey)}.`
                        );
                    } else {
                        seenKeys.set(
                            normalizedKey,
                            row._excelRowNumber
                        );
                    }
                }

                if (parentKey) {
                    const parentValue = row[parentKey];

                    if (
                        parentValue === null ||
                        parentValue === undefined ||
                        String(parentValue).trim() === ''
                    ) {
                        errors.push(
                            `Parent key is required: ${parentKey}`
                        );
                    }
                }

                return {
                    ...row,
                    _errorMessage: this.joinErrors(errors)
                };
            });

            return {
                ...sheet,
                rows
            };
        });

        this.previewSheets = updatedSheets;

        // Keep the Apex payload in sync with preview validation.
        // Metadata is excluded from actual Salesforce field mapping
        // in Apex and is used for row-level error matching.
        const newPayload = {};

        updatedSheets.forEach(sheet => {
            newPayload[sheet.name] = sheet.rows.map(row => {
                const payloadRow = { ...row };

                delete payloadRow._rowKey;
                delete payloadRow._errorMessage;
                delete payloadRow._excelRowNumber;


                return payloadRow;
            });
        });

        this.workbookData = newPayload;
        this.paginationRefreshNeeded = true;
    }

    joinErrors(errors) {
        return [...new Set(
            errors
                .filter(Boolean)
                .map(error => String(error).trim())
        )].join(' | ');
    }

    // --------------------------------------------------
    // VALIDATION STATE
    // --------------------------------------------------

    get hasValidationErrors() {
        return this.previewSheets.some(sheet =>
            sheet.rows.some(row => Boolean(row._errorMessage))
        );
    }

    get isSubmitDisabled() {
        return (
            this.isLoading ||
            !this.hasWorkbook ||
            this.hasValidationErrors
        );
    }

    get hasWorkbook() {
        return Object.keys(this.workbookData).length > 0;
    }

    // --------------------------------------------------
    // SHEET TABS AND SUMMARY
    // --------------------------------------------------

    get sheetTabs() {
        return this.previewSheets.map(sheet => {
            const errorCount = sheet.rows.filter(
                row => Boolean(row._errorMessage)
            ).length;

            return {
                name: sheet.name,
                count: sheet.rows.length,
                errorCount,
                hasErrors: errorCount > 0,
                isActive: sheet.name === this.activeSheet,
                label: errorCount > 0
                    ? `⚠ ${sheet.name} (${errorCount})`
                    : sheet.name
            };
        });
    }

    get sheetSummaries() {
        return this.previewSheets.map(sheet => {
            const errorCount = sheet.rows.filter(
                row => Boolean(row._errorMessage)
            ).length;

            return {
                name: sheet.name,
                count: sheet.rows.length,
                errorCount,
                hasErrors: errorCount > 0
            };
        });
    }

    get activeSheetData() {
        return this.previewSheets.find(
            sheet => sheet.name === this.activeSheet
        );
    }

    get currentSheetRows() {
        return this.activeSheetData?.rows || [];
    }

    get hasActiveRows() {
        return this.currentSheetRows.length > 0;
    }

    handleTabActive(event) {
        const selectedSheet = event.target.value;

        if (selectedSheet && selectedSheet !== this.activeSheet) {
            this.activeSheet = selectedSheet;
            this.visibleRows = [];
            this.paginationRefreshNeeded = true;
        }
    }

    // --------------------------------------------------
    // DATATABLE COLUMNS
    // --------------------------------------------------

    get activeColumns() {
    const columns = [
        {
            label: 'Excel Row',
            fieldName: '_excelRowNumber',
            type: 'number',
            initialWidth: 90
        }
    ];

    const sheet = this.activeSheetData;

    if (sheet) {
        sheet.headers.forEach(header => {
            columns.push({
                label: header,
                fieldName: header,
                type: 'text',
                wrapText: true
            });
        });

        // Show Error only when this worksheet contains an error.
        const sheetHasErrors = sheet.rows.some(
            row => Boolean(row._errorMessage)
        );

        if (sheetHasErrors) {
            columns.push({
                label: 'Error',
                fieldName: '_errorMessage',
                type: 'text',
                wrapText: true
            });
        }
    }

    return columns;
}
    // --------------------------------------------------
    // PAGINATION
    // --------------------------------------------------

    renderedCallback() {
        if (!this.paginationRefreshNeeded) {
            return;
        }

        const pagination = this.template.querySelector(
            'c-custom-pagination-comp'
        );

        if (!pagination) {
            return;
        }

        this.paginationRefreshNeeded = false;

        pagination.list = [...this.currentSheetRows];
        pagination.setPagination(PAGE_SIZE);
    }

    handlePageChanged(event) {
        this.visibleRows = event.detail.recordToDisplay || [];
    }

    // --------------------------------------------------
    // UPLOAD WORKBOOK
    // --------------------------------------------------

    async handleUpload() {
        if (this.isSubmitDisabled) {
            if (this.hasValidationErrors) {
                this.showToast(
                    'Cannot upload workbook',
                    'Correct the errors shown in the Error column first.',
                    'error'
                );
            }

            return;
        }

        this.isLoading = true;
        this.errorMessage = '';
        this.results = [];

        try {
            const response = await uploadWorkbook({
                workbookJson: JSON.stringify(this.workbookData)
            });

            this.inserted = response?.inserted || 0;
            this.updated = response?.updated || 0;
            this.failed = response?.failed || 0;

            const uploadResults = response?.results || [];

            this.results = uploadResults.map((row, index) => ({
                ...row,
                key: `${row.sheet}-${row.rowNumber ?? index}-${index}`
            }));

            // Apply Apex errors to the corresponding preview rows.
            this.previewSheets = this.previewSheets.map(sheet => ({
                ...sheet,
                rows: sheet.rows.map(previewRow => {
                    const matchKey = MATCH_KEYS[sheet.name];

                    const previewKey = String(
                        previewRow[matchKey] ?? ''
                    ).trim().toLowerCase();

                    const rowResult = uploadResults.find(result => {
                        if (result.sheet !== sheet.name) {
                            return false;
                        }

                        // Preferred: exact original Excel row number.
                        if (
                            result.rowNumber !== null &&
                            result.rowNumber !== undefined
                        ) {
                            return Number(result.rowNumber) ===
                                Number(previewRow._excelRowNumber);
                        }

                        // Fallback for Apex responses without rowNumber.
                        const resultKey = String(
                            result.recordKey ?? ''
                        ).trim().toLowerCase();

                        return previewKey !== '' &&
                            resultKey !== '' &&
                            previewKey === resultKey;
                    });

                    // Clear old upload errors when the latest result
                    // does not indicate a failure.
                    if (!rowResult) {
                        return {
                            ...previewRow,
                            _errorMessage: ''
                        };
                    }

                    const action = String(
                        rowResult.action || ''
                    ).toLowerCase();

                    const isError =
                        action.includes('fail') ||
                        action.includes('error') ||
                        rowResult.success === false;

                    return {
                        ...previewRow,
                        _errorMessage: isError
                            ? (
                                rowResult.message ||
                                'Record could not be processed.'
                            )
                            : ''
                    };
                })
            }));

            // Update payload preview state and refresh pagination.
            this.paginationRefreshNeeded = true;

            if (this.failed > 0) {
                this.showToast(
                    'Upload completed with errors',
                    `Inserted: ${this.inserted}, Updated: ${this.updated}, Failed: ${this.failed}. Review the Error column.`,
                    'warning'
                );
            } else {
                this.showToast(
                    'Inventory upload completed',
                    `Inserted: ${this.inserted}, Updated: ${this.updated}, Failed: ${this.failed}.`,
                    'success'
                );
            }
        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);

            // A request-level Apex error may not identify a particular
            // row. Show the message at the component level.
            this.showToast(
                'Upload failed',
                this.errorMessage,
                'error'
            );
        } finally {
            this.isLoading = false;
        }
    }

    // --------------------------------------------------
    // UPLOAD RESULTS TABLE
    // --------------------------------------------------

    get hasResults() {
        return this.results.length > 0;
    }

    get resultColumns() {
        return [
            {
                label: 'Worksheet',
                fieldName: 'sheet'
            },
            {
                label: 'Excel Row',
                fieldName: 'rowNumber',
                type: 'number'
            },
            {
                label: 'Record Key',
                fieldName: 'recordKey'
            },
            {
                label: 'Action',
                fieldName: 'action'
            },
            {
                label: 'Message',
                fieldName: 'message',
                type: 'text',
                wrapText: true
            }
        ];
    }

    // --------------------------------------------------
    // COMMON HELPERS
    // --------------------------------------------------

    getErrorMessage(error) {
        const body = error?.body;

        if (Array.isArray(body)) {
            return body.map(item => item.message).join('; ');
        }

        if (body?.pageErrors?.length) {
            return body.pageErrors
                .map(item => item.message)
                .join('; ');
        }

        if (body?.fieldErrors) {
            return Object.values(body.fieldErrors)
                .flat()
                .map(item => item.message)
                .join('; ');
        }

        return body?.message ||
            error?.message ||
            'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}