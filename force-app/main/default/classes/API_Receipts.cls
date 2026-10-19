public without sharing class API_Receipts {

    public enum Operation { CREATE_RECORD, UPDATE_RECORD }

    public class ReceiptException extends Exception {}

    public class ReceiptRequest {
        public String requestId;
        public List<ReceiptRecord> records;
    }

    public class ReceiptRecord {
        public String orderNumber;
        public String documentDate;
        public String postingDate;
        public String fiscalYear;
        public String documentType;
        public String unit;
        public String transactionDate;
        public String customer;
        public String currencyCode;
        public Decimal amount;
    }

    public class ResultItem {
        public String orderNumber;
        public String customer;
        public String unit;
        public Boolean success;
        public String message;
        public String recordId;

        public ResultItem(ReceiptRecord receipt) {
            this.orderNumber = receipt == null ? null : receipt.orderNumber;
            this.customer = receipt == null ? null : receipt.customer;
            this.unit = receipt == null ? null : receipt.unit;
            this.success = false;
        }

        public void succeed(String message, Id recordId) {
            this.success = true;
            this.message = message;
            this.recordId = recordId;
        }

        public void fail(String message) {
            this.success = false;
            this.message = message;
            this.recordId = null;
        }
    }

    public class ResponseBody {
        public Boolean success;
        public String message;
        public String requestId;
        public Integer totalRecords;
        public Integer successCount;
        public Integer failureCount;
        public List<ResultItem> results;
    }

    public class Result {
        public Integer statusCode;
        public ResponseBody body;

        public Result(Integer statusCode, ResponseBody body) {
            this.statusCode = statusCode;
            this.body = body;
        }
    }

    private static Boolean multiCurrencyEnabled;

    public static Result processReceipts(String requestBody, Operation receiptOperation) {
        String requestId;
        try {
            if (receiptOperation == null) {
                throw new IllegalArgumentException('Operation is required.');
            }

            if (String.isBlank(requestBody)) {
                throw new IllegalArgumentException('Request body is required.');
            }

            String normalizedBody = requestBody.replace('"currency"', '"currencyCode"');
            ReceiptRequest receiptRequest = (ReceiptRequest) JSON.deserialize(normalizedBody, ReceiptRequest.class);
            if (receiptRequest == null) {
                throw new IllegalArgumentException('Request body is empty.');
            }

            requestId = String.isBlank(receiptRequest.requestId) ? null : receiptRequest.requestId.trim();
            if (requestId == null) {
                throw new IllegalArgumentException('requestId is required.');
            }

            if (receiptRequest.records == null || receiptRequest.records.isEmpty()) {
                throw new IllegalArgumentException('records is required and must not be empty.');
            }

            return processRecords(requestId, receiptRequest.records, requestBody, receiptOperation);
        } catch (JSONException jsonEx) {
            logError('processReceipts', jsonEx, requestBody);
            return buildFailure(400, requestId, 'Request body is not valid JSON.');
        } catch (IllegalArgumentException argEx) {
            logError('processReceipts', argEx, requestBody);
            return buildFailure(400, requestId, argEx.getMessage());
        } catch (Exception ex) {
            logError('processReceipts', ex, requestBody);
            return buildFailure(500, requestId, 'Internal server error.');
        }
    }

    private static Result processRecords(String requestId, List<ReceiptRecord> receipts, String requestBody, Operation receiptOperation) {
        Boolean isCreate = receiptOperation == Operation.CREATE_RECORD;
        List<ResultItem> results = new List<ResultItem>();
        List<Integer> validIndexes = new List<Integer>();
        Set<Id> opportunityIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Set<String> unitCodes = new Set<String>();
        Set<String> requestKeys = new Set<String>();

        for (Integer i = 0; i < receipts.size(); i++) {
            ReceiptRecord receipt = receipts[i];
            ResultItem item = new ResultItem(receipt);
            results.add(item);

            String validationError = validateReceipt(receipt);
            if (validationError != null) {
                item.fail(validationError);
                continue;
            }

            Id opportunityId = parseId(receipt.orderNumber, Opportunity.SObjectType, 'orderNumber');
            Id accountId = parseId(receipt.customer, Account.SObjectType, 'customer');
            String unitCode = receipt.unit.trim();

            if (!requestKeys.add(opportunityId + '|' + accountId + '|' + unitCode)) {
                item.fail('Duplicate receipt record in request for the same orderNumber, customer and unit.');
                continue;
            }

            opportunityIds.add(opportunityId);
            accountIds.add(accountId);
            unitCodes.add(unitCode);
            validIndexes.add(i);
        }

        Set<Id> foundOpportunityIds = queryOpportunityIds(opportunityIds);
        Set<Id> foundAccountIds = queryAccountIds(accountIds);
        Map<String, Unit__c> unitsByCode = queryUnits(unitCodes);

        Map<Integer, Id> unitIdByIndex = new Map<Integer, Id>();
        Set<Id> lookupOpportunityIds = new Set<Id>();
        Set<Id> lookupAccountIds = new Set<Id>();
        Set<Id> lookupUnitIds = new Set<Id>();

        for (Integer index : validIndexes) {
            ReceiptRecord receipt = receipts[index];
            Id opportunityId = parseId(receipt.orderNumber, Opportunity.SObjectType, 'orderNumber');
            Id accountId = parseId(receipt.customer, Account.SObjectType, 'customer');
            Unit__c existingUnit = unitsByCode.get(receipt.unit.trim());

            if (!foundOpportunityIds.contains(opportunityId)) {
                results[index].fail('No matching Opportunity record found.');
                continue;
            }

            if (!foundAccountIds.contains(accountId)) {
                results[index].fail('No matching Account record found.');
                continue;
            }

            if (existingUnit == null) {
                results[index].fail('No matching Unit record found.');
                continue;
            }

            unitIdByIndex.put(index, existingUnit.Id);
            lookupOpportunityIds.add(opportunityId);
            lookupAccountIds.add(accountId);
            lookupUnitIds.add(existingUnit.Id);
        }

        Map<String, List<SAP_Receipt__c>> existingByKey = queryExistingReceipts(lookupOpportunityIds, lookupAccountIds, lookupUnitIds);

        List<SAP_Receipt__c> receiptRecords = new List<SAP_Receipt__c>();
        List<Integer> receiptRecordIndexes = new List<Integer>();

        for (Integer index : validIndexes) {
            if (!unitIdByIndex.containsKey(index)) {
                continue;
            }

            ReceiptRecord receipt = receipts[index];
            Id opportunityId = parseId(receipt.orderNumber, Opportunity.SObjectType, 'orderNumber');
            Id accountId = parseId(receipt.customer, Account.SObjectType, 'customer');
            Id unitId = unitIdByIndex.get(index);

            List<SAP_Receipt__c> existingReceipts = existingByKey.get(buildKey(opportunityId, accountId, unitId));
            Boolean receiptExists = existingReceipts != null && !existingReceipts.isEmpty();

            if (isCreate) {
                if (receiptExists) {
                    results[index].fail('Receipt already exists for this orderNumber, customer and unit.');
                    continue;
                }

                SAP_Receipt__c newReceipt = new SAP_Receipt__c();
                mapReceipt(newReceipt, receipt, opportunityId, accountId, unitId, true);
                receiptRecords.add(newReceipt);
            } else {
                if (!receiptExists) {
                    results[index].fail('No matching Receipt record found.');
                    continue;
                }

                if (existingReceipts.size() > 1) {
                    results[index].fail('Multiple Receipt records found for this orderNumber, customer and unit.');
                    continue;
                }

                SAP_Receipt__c existingReceipt = new SAP_Receipt__c(Id = existingReceipts[0].Id);
                mapReceipt(existingReceipt, receipt, opportunityId, accountId, unitId, false);
                receiptRecords.add(existingReceipt);
            }
            receiptRecordIndexes.add(index);
        }

        saveRecords(receiptRecords, receiptRecordIndexes, results, isCreate, isCreate ? 'Receipt created successfully.' : 'Receipt updated successfully.');

        return buildResult(requestId, results, requestBody);
    }

    private static void saveRecords(List<SObject> records, List<Integer> resultIndexes, List<ResultItem> results, Boolean isInsert, String successMessage) {
        if (records == null || records.isEmpty()) {
            return;
        }

        List<Database.SaveResult> saveResults = isInsert? Database.insert(records, false, AccessLevel.SYSTEM_MODE): Database.update(records, false, AccessLevel.SYSTEM_MODE);

        applySaveResults(saveResults, resultIndexes, results, successMessage);
    }

    private static void applySaveResults(List<Database.SaveResult> saveResults, List<Integer> resultIndexes, List<ResultItem> results, String successMessage) {
        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.SaveResult saveResult = saveResults[i];
            ResultItem item = results[resultIndexes[i]];

            if (saveResult.isSuccess()) {
                item.succeed(successMessage, saveResult.getId());
                continue;
            }

            List<String> errorMessages = new List<String>();
            for (Database.Error error : saveResult.getErrors()) {
                errorMessages.add(error.getMessage());
            }
            item.fail(errorMessages.isEmpty() ? 'Save failed.' : String.join(errorMessages, '; '));
        }
    }

    private static Result buildResult(String requestId, List<ResultItem> results, String requestBody) {
        Integer successCount = 0;
        List<String> failureSummaries = new List<String>();
        for (ResultItem item : results) {
            if (item.success) {
                successCount++;
            } else {
                failureSummaries.add(item.orderNumber + ': ' + item.message);
            }
        }

        Integer failureCount = results.size() - successCount;

        ResponseBody body = new ResponseBody();
        body.requestId = requestId;
        body.totalRecords = results.size();
        body.successCount = successCount;
        body.failureCount = failureCount;
        body.results = results;

        if (failureCount == 0) {
            body.success = true;
            body.message = 'Receipt processing completed successfully.';
            return new Result(200, body);
        }

        body.success = false;
        body.message = 'Receipt processing completed with some failures.';

        String summary = 'Receipt processing failed for ' + failureCount + ' of ' + results.size() + ' record(s): ' + String.join(failureSummaries, ' | ');
        logError('processReceipts', new ReceiptException(summary.abbreviate(255)), requestBody);

        return new Result(207, body);
    }

    private static Result buildFailure(Integer statusCode, String requestId, String message) {
        ResponseBody body = new ResponseBody();
        body.success = false;
        body.message = String.isBlank(message) ? 'Request failed.' : message;
        body.requestId = requestId;
        return new Result(statusCode, body);
    }

    private static String validateReceipt(ReceiptRecord receipt) {
        if (receipt == null) {
            return 'Receipt record is empty.';
        }

        if (String.isBlank(receipt.orderNumber)) {
            return 'orderNumber is required.';
        }

        if (String.isBlank(receipt.customer)) {
            return 'customer is required.';
        }

        if (String.isBlank(receipt.unit)) {
            return 'unit is required.';
        }

        try {
            parseId(receipt.orderNumber, Opportunity.SObjectType, 'orderNumber');
            parseId(receipt.customer, Account.SObjectType, 'customer');
            parseDate(receipt.documentDate, 'documentDate');
            parseDate(receipt.postingDate, 'postingDate');
            parseDate(receipt.transactionDate, 'transactionDate');
            parseFiscalYear(receipt.fiscalYear);
        } catch (IllegalArgumentException argEx) {
            return argEx.getMessage();
        }

        return null;
    }

    private static Id parseId(String value, Schema.SObjectType expectedType, String fieldName) {
        String objectName = expectedType.getDescribe().getName();
        Id parsedId;
        try {
            parsedId = Id.valueOf(value.trim());
        } catch (Exception ex) {
            throw new IllegalArgumentException(fieldName + ' must be a valid ' + objectName + ' Id.');
        }

        if (parsedId.getSobjectType() != expectedType) {
            throw new IllegalArgumentException(fieldName + ' must be a valid ' + objectName + ' Id.');
        }

        return parsedId;
    }

    private static Date parseDate(String value, String fieldName) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return Date.valueOf(value.trim());
        } catch (Exception ex) {
            throw new IllegalArgumentException(fieldName + ' must be a valid date in yyyy-MM-dd format.');
        }
    }

    private static Integer parseFiscalYear(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return Integer.valueOf(value.trim());
        } catch (Exception ex) {
            throw new IllegalArgumentException('fiscalYear must be a valid whole number.');
        }
    }

    private static String buildKey(Id opportunityId, Id accountId, Id unitId) {
        return opportunityId + '|' + accountId + '|' + unitId;
    }

    private static Set<Id> queryOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds.isEmpty()) {
            return new Set<Id>();
        }

        return new Map<Id, Opportunity>([SELECT Id FROM Opportunity WHERE Id IN :opportunityIds WITH SYSTEM_MODE]).keySet();
    }

    private static Set<Id> queryAccountIds(Set<Id> accountIds) {
        if (accountIds.isEmpty()) {
            return new Set<Id>();
        }

        return new Map<Id, Account>([SELECT Id FROM Account WHERE Id IN :accountIds WITH SYSTEM_MODE]).keySet();
    }

    private static Map<String, Unit__c> queryUnits(Set<String> unitCodes) {
        Map<String, Unit__c> unitsByCode = new Map<String, Unit__c>();
        if (unitCodes.isEmpty()) {
            return unitsByCode;
        }

        for (Unit__c unit : [SELECT Id, Unit_Name_Code__c FROM Unit__c WHERE Unit_Name_Code__c IN :unitCodes WITH SYSTEM_MODE]) {
            unitsByCode.put(unit.Unit_Name_Code__c, unit);
        }
        return unitsByCode;
    }

    private static Map<String, List<SAP_Receipt__c>> queryExistingReceipts(Set<Id> opportunityIds, Set<Id> accountIds, Set<Id> unitIds) {
        Map<String, List<SAP_Receipt__c>> existingByKey = new Map<String, List<SAP_Receipt__c>>();
        if (opportunityIds.isEmpty() || accountIds.isEmpty() || unitIds.isEmpty()) {
            return existingByKey;
        }

        for (SAP_Receipt__c receipt : [SELECT Id, Opportunity__c, Customer__c, Unit__c FROM SAP_Receipt__c WHERE Opportunity__c IN :opportunityIds AND Customer__c IN :accountIds AND Unit__c IN :unitIds WITH SYSTEM_MODE]) {
            String key = buildKey(receipt.Opportunity__c, receipt.Customer__c, receipt.Unit__c);
            if (!existingByKey.containsKey(key)) {
                existingByKey.put(key, new List<SAP_Receipt__c>());
            }
            existingByKey.get(key).add(receipt);
        }
        return existingByKey;
    }

    private static void mapReceipt(SAP_Receipt__c record, ReceiptRecord receipt, Id opportunityId, Id accountId, Id unitId, Boolean isCreate) {
        if (isCreate) {
            record.Opportunity__c = opportunityId;
            record.Customer__c = accountId;
            record.Unit__c = unitId;
            record.Name = receipt.orderNumber.trim().abbreviate(80);
        }

        Date documentDate = parseDate(receipt.documentDate, 'documentDate');
        if (documentDate != null) {
            record.Document_Date__c = documentDate;
        }

        Date postingDate = parseDate(receipt.postingDate, 'postingDate');
        if (postingDate != null) {
            record.Posting_Date__c = postingDate;
        }

        Date transactionDate = parseDate(receipt.transactionDate, 'transactionDate');
        if (transactionDate != null) {
            record.Transaction_Date__c = transactionDate;
        }

        Integer fiscalYear = parseFiscalYear(receipt.fiscalYear);
        if (fiscalYear != null) {
            record.Fiscal_year__c = fiscalYear;
        }

        if (String.isNotBlank(receipt.documentType)) {
            record.Document_Type__c = receipt.documentType.trim();
        }

        if (receipt.amount != null) {
            record.Amount__c = receipt.amount;
        }

        if (isMultiCurrency() && String.isNotBlank(receipt.currencyCode)) {
            record.put('CurrencyIsoCode', receipt.currencyCode.trim().toUpperCase());
        }
    }

    private static Boolean isMultiCurrency() {
        if (multiCurrencyEnabled == null) {
            multiCurrencyEnabled = Schema.SObjectType.SAP_Receipt__c.fields.getMap().containsKey('currencyisocode');
        }
        return multiCurrencyEnabled;
    }

    private static void logError(String apexMethodName, Exception ex, String requestBody) {
        try {
            IntegrationLogUtility.captureError('API_Receipts', apexMethodName, ex, requestBody, 'SAP - SFDC');
        } catch (Exception loggingEx) {
            System.debug(LoggingLevel.ERROR, 'API_Receipts.' + apexMethodName + ' failed to write integration log: ' + loggingEx.getMessage());
        }
    }
}