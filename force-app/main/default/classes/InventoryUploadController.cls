public with sharing class InventoryUploadController {
    private static final String COMPANY_OBJECT = 'Company__c';
    private static final String COMPANY_KEY = 'Company_Code__c';

    private static final String PROJECT_OBJECT = 'Project__c';
    private static final String PROJECT_KEY = 'Project_Code__c';
    private static final String PROJECT_COMPANY_LOOKUP = 'Company__c';

    private static final String BLOCK_OBJECT = 'Block__c';
    private static final String BLOCK_KEY = 'Block_Code__c';
    private static final String BLOCK_PROJECT_LOOKUP = 'Project__c';

    private static final String FLOOR_OBJECT = 'Floor__c';
    private static final String FLOOR_KEY = 'Floor_Code__c';
    private static final String FLOOR_BLOCK_LOOKUP = 'Block__c';

    private static final String UNIT_OBJECT = 'Unit__c';
    private static final String UNIT_KEY = 'Unit_Name_Code__c';
    private static final String UNIT_FLOOR_LOOKUP = 'Floor__c';

    private static final String PARKING_OBJECT = 'Parking_Detail__c';
    private static final String PARKING_KEY = 'Parking_Slot_ID__c';
    private static final String PARKING_BLOCK_LOOKUP = 'Block__c';

    public class RowResult {
        @AuraEnabled public String sheet { get; set; }
        @AuraEnabled public Integer rowNumber { get; set; }
        @AuraEnabled public String recordKey { get; set; }
        @AuraEnabled public String action { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    public class UploadResponse {
        @AuraEnabled public Integer inserted { get; set; }
        @AuraEnabled public Integer updated { get; set; }
        @AuraEnabled public Integer failed { get; set; }
        @AuraEnabled public List<RowResult> results { get; set; }
    }

    private class SheetData {
        String name;
        String objectName;
        String externalId;
        String parentKeyColumn;
        String parentLookup;
        Map<String, Id> parentIds;
        List<Map<String, Object>> rows;

        SheetData(
            String name,
            String objectName,
            String externalId,
            String parentKeyColumn,
            String parentLookup,
            Map<String, Id> parentIds,
            List<Map<String, Object>> rows
        ) {
            this.name = name;
            this.objectName = objectName;
            this.externalId = externalId;
            this.parentKeyColumn = parentKeyColumn;
            this.parentLookup = parentLookup;
            this.parentIds = parentIds;
            this.rows = rows;
        }
    }

    @AuraEnabled
    public static UploadResponse uploadWorkbook(String workbookJson) {
        if (String.isBlank(workbookJson)) {
            throw new AuraHandledException('Workbook data is empty.');
        }

        Map<String, Object> workbook;
        try {
            workbook = (Map<String, Object>)JSON.deserializeUntyped(workbookJson);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Invalid workbook data: ' + e.getMessage()
            );
        }

        UploadResponse response = new UploadResponse();
        response.inserted = 0;
        response.updated = 0;
        response.failed = 0;
        response.results = new List<RowResult>();

        Integer totalRows = 0;
        for (String sheetName : new List<String>{'Company', 'Project', 'Block', 'Floor', 'Unit', 'Parking' }) {
            totalRows += readRows(workbook, sheetName).size();
        }
        // if (totalRows > 500) {
        //     throw new AuraHandledException('Maximum 500 rows per upload. Split the workbook into smaller batches.');
        // }
        Map<String, Id> companyIds = processSheet(
            new SheetData(
                'Company', COMPANY_OBJECT, COMPANY_KEY,
                null, null, null, readRows(workbook, 'Company')
            ),
            response
        );

        Map<String, Id> projectIds = processSheet(
            new SheetData(
                'Project', PROJECT_OBJECT, PROJECT_KEY,
                COMPANY_KEY, PROJECT_COMPANY_LOOKUP,
                companyIds, readRows(workbook, 'Project')
            ),
            response
        );

        Map<String, Id> blockIds = processSheet(
            new SheetData(
                'Block', BLOCK_OBJECT, BLOCK_KEY,
                PROJECT_KEY, BLOCK_PROJECT_LOOKUP,
                projectIds, readRows(workbook, 'Block')
            ),
            response
        );

        Map<String, Id> floorIds = processSheet(
            new SheetData(
                'Floor', FLOOR_OBJECT, FLOOR_KEY,
                BLOCK_KEY, FLOOR_BLOCK_LOOKUP,
                blockIds, readRows(workbook, 'Floor')
            ),
            response
        );

        processSheet(
            new SheetData(
                'Unit', UNIT_OBJECT, UNIT_KEY,
                'Floor_Code__c', UNIT_FLOOR_LOOKUP,
                floorIds, readRows(workbook, 'Unit')
            ),
            response
        );

        processSheet(
            new SheetData(
                'Parking', PARKING_OBJECT, PARKING_KEY,
                BLOCK_KEY, PARKING_BLOCK_LOOKUP,
                blockIds, readRows(workbook, 'Parking')
            ),
            response
        );
        return response;
    }

    private static List<Map<String, Object>> readRows(Map<String, Object> workbook, String sheetName ) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        Object raw = workbook.get(sheetName);
        if (raw == null) {
            return result;
        }
        for (Object item : (List<Object>) raw) {
            if (item == null) {
                continue;
            }
            result.add((Map<String, Object>) item);
        }
        return result;
    }

    private static Map<String, Id> processSheet( SheetData sheet,UploadResponse response) {
        Map<String, Id> resolvedIds = new Map<String, Id>();
        if (sheet.rows.isEmpty()) {
            return resolvedIds;
        }
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(sheet.objectName);

        if (objectType == null) {
            failAll( sheet, response,'Object does not exist: ' + sheet.objectName );
            return resolvedIds;
        }

        Map<String, Schema.SObjectField> fields = objectType.getDescribe().fields.getMap();

        if (!fields.containsKey(sheet.externalId)) {
            failAll(
                sheet, response,
                'Matching field does not exist: ' +
                sheet.objectName + '.' + sheet.externalId
            );
            return resolvedIds;
        }

        Schema.DescribeFieldResult keyDescription = fields.get(sheet.externalId).getDescribe();

        if (!keyDescription.isExternalId() &&  !keyDescription.isIdLookup() ) {
            failAll(
                sheet, response,
                sheet.externalId +
                ' must be configured as an External ID or Id Lookup.'
            );
            return resolvedIds;
        }

        if (sheet.parentLookup != null && !fields.containsKey(sheet.parentLookup) ) {
            failAll(
                sheet, response,
                'Parent lookup field does not exist: ' +
                sheet.objectName + '.' + sheet.parentLookup
            );
            return resolvedIds;
        }

        List<SObject> records = new List<SObject>();
        List<Map<String, Object>> sourceRows = new List<Map<String, Object>>();
        Set<String> seenKeys = new Set<String>();
        for (Integer i = 0; i < sheet.rows.size(); i++) {
            Map<String, Object> row = sheet.rows[i];

            String recordKey = normalize(
                row.get(sheet.externalId)
            );

            if (String.isBlank(recordKey)) {
                addResult(response, sheet.name, i + 2, null, 'Failed', 'Matching key is required.');
                continue;
            }

            if (seenKeys.contains(recordKey)) {
                addResult(response, sheet.name, i + 2, recordKey,
                    'Failed',
                    'Duplicate matching key in this worksheet.'
                );
                continue;
            }
            seenKeys.add(recordKey);

            SObject record = objectType.newSObject();

            Boolean valid = true;
            String errorMessage;

            // Resolve parent relationship using the parent's unique key.
            if (sheet.parentLookup != null) {
                String parentKey = normalize(
                    row.get(sheet.parentKeyColumn)
                );

                Id parentId = sheet.parentIds == null
                    ? null
                    : sheet.parentIds.get(parentKey);

                if (parentId == null) {
                    addResult(
                        response, sheet.name, i + 2, recordKey,
                        'Failed',
                        'Parent not found. Check ' +
                        sheet.parentKeyColumn + ' and the parent worksheet.'
                    );
                    continue;
                }

                record.put(sheet.parentLookup, parentId);
            }

            // Excel headers must be actual Salesforce API field names.
            for (String header : row.keySet()) {
                if (header == sheet.parentKeyColumn || header == 'Id' ||  header == '__excelRowNumber' ||  header == '_excelRowNumber' || header == '_rowKey' || header == '_errorMessage') {
                    continue;
                }

                if (!fields.containsKey(header)) {
                    valid = false;
                    errorMessage =
                        'Unknown field API name: ' +
                        sheet.objectName + '.' + header;
                    break;
                }

                Schema.DescribeFieldResult description =
                    fields.get(header).getDescribe();

                if (
                    !description.isCreateable() ||
                    !description.isUpdateable() ||
                    description.isCalculated() ||
                    description.isAutoNumber()
                ) {
                    valid = false;
                    errorMessage =
                        'Field cannot be written by this upload: ' + header;
                    break;
                }

                // Null values clear nullable fields.
                // Excel parser must send null for empty cells.
                Object value = row.get(header);

                try {
                    record.put(
                        header,
                        convertValue(value, description)
                    );
                } catch (Exception e) {
                    valid = false;
                    errorMessage = 'Invalid value for ' + header +
                        ': ' + e.getMessage();
                    break;
                }
            }

            if (!valid) {
                addResult(
                    response, sheet.name, i + 2, recordKey,
                    'Failed', errorMessage
                );
                continue;
            }

            records.add(record);
            sourceRows.add(row);
        }

        if (records.isEmpty()) {
            return resolvedIds;
        }

        Database.UpsertResult[] dmlResults = Database.upsert(
            records,
            fields.get(sheet.externalId),
            false
        );

        for (Integer i = 0; i < dmlResults.size(); i++) {
            Database.UpsertResult dml = dmlResults[i];

            String key = normalize(
                sourceRows[i].get(sheet.externalId)
            );

            if (dml.isSuccess()) {
                if (dml.isCreated()) {
                    response.inserted++;
                    addResult(
                        response, sheet.name, null, key,
                        'Inserted', 'Record created.'
                    );
                } else {
                    response.updated++;
                    addResult(
                        response, sheet.name, null, key,
                        'Updated', 'Record updated.'
                    );
                }
            } else {
                List<String> messages = new List<String>();

                for (Database.Error err : dml.getErrors()) {
                    messages.add(err.getMessage());
                }

                response.failed++;
                addResult(
                    response, sheet.name, null, key,
                    'Failed', String.join(messages, '; ')
                );
            }
        }

        // Resolve IDs for the next worksheet.
        // Only successful records should be used as parents.
        Set<String> keysToQuery = new Set<String>();

        for (Integer i = 0; i < dmlResults.size(); i++) {
            if (dmlResults[i].isSuccess()) {
                keysToQuery.add(
                    String.valueOf(
                        sourceRows[i].get(sheet.externalId)
                    ).trim()
                );
            }
        }

        if (!keysToQuery.isEmpty()) {
            String queryString =
                'SELECT Id, ' + sheet.externalId +
                ' FROM ' + sheet.objectName +
                ' WHERE ' + sheet.externalId + ' IN :keysToQuery';

            for (SObject saved : Database.query(queryString)) {
                resolvedIds.put(
                    normalize(saved.get(sheet.externalId)),
                    (Id) saved.get('Id')
                );
            }
        }

        return resolvedIds;
    }

    private static Object convertValue(
        Object value,
        Schema.DescribeFieldResult fieldDescription
    ) {
        if (value == null) {
            return null;
        }

        String dataType = String.valueOf(
            fieldDescription.getType()
        );

        if (dataType == 'STRING' ||
            dataType == 'TEXTAREA' ||
            dataType == 'PHONE' ||
            dataType == 'EMAIL' ||
            dataType == 'URL' ||
            dataType == 'PICKLIST' ||
            dataType == 'COMBOBOX' ||
            dataType == 'ENCRYPTEDSTRING') {
            return String.valueOf(value);
        }

        if (dataType == 'BOOLEAN') {
            String boolValue = String.valueOf(value).toLowerCase();

            if (boolValue == 'true' || boolValue == 'yes' ||
                boolValue == '1') {
                return true;
            }

            if (boolValue == 'false' || boolValue == 'no' ||
                boolValue == '0') {
                return false;
            }

            throw new AuraHandledException(
                'Expected true/false, yes/no, or 1/0.'
            );
        }

        if (dataType == 'INTEGER') {
            return Integer.valueOf(String.valueOf(value));
        }

        if (dataType == 'DOUBLE' ||
            dataType == 'CURRENCY' ||
            dataType == 'PERCENT') {
            return Decimal.valueOf(String.valueOf(value));
        }

        if (dataType == 'DATE') {
            return Date.valueOf(String.valueOf(value));
        }

        if (dataType == 'DATETIME') {
            return Datetime.valueOf(
                String.valueOf(value).replace('T', ' ')
            );
        }

        return value;
    }

    private static String normalize(Object value) {
        return value == null
            ? null
            : String.valueOf(value).trim().toLowerCase();
    }

    private static void addResult(
        UploadResponse response,
        String sheet,
        Integer rowNumber,
        String recordKey,
        String action,
        String message
    ) {
        RowResult result = new RowResult();
        result.sheet = sheet;
        result.rowNumber = rowNumber;
        result.recordKey = recordKey;
        result.action = action;
        result.message = message;

        response.results.add(result);

        if (action == 'Failed') {
            response.failed++;
        }
    }

    private static void failAll(
        SheetData sheet,
        UploadResponse response,
        String message
    ) {
        for (Integer i = 0; i < sheet.rows.size(); i++) {
            addResult(
                response, sheet.name, i + 2,
                null, 'Failed', message
            );
        }
    }
}