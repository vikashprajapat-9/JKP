public without sharing class SAP_Pricing {

    public enum Operation { CREATE_RECORD, UPDATE_RECORD }

    public class PricingException extends Exception {}

    public class PricingRequest {
        public String requestId;
        public List<PricingMaster> pricings;
    }

    public class PricingMaster {
        public String materialCode;
        public String materialGroup;
        public String salesOrganization;
        public String distributionChannel;
        public String conditionType;
        public String validFrom;
        public String validTo;
        public Decimal amount;
        public String currencyCode; 
    }

    public class ResultItem {
        public String materialCode;
        public String materialGroup;
        public String conditionType;
        public String validFrom;
        public Boolean success;
        public String message;
        public String recordId;

        public ResultItem(PricingMaster pricing) {
            this.materialCode = pricing == null ? null : pricing.materialCode;
            this.materialGroup = pricing == null ? null : pricing.materialGroup;
            this.conditionType = pricing == null ? null : pricing.conditionType;
            this.validFrom = pricing == null ? null : pricing.validFrom;
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

//     public class GetResponseBody {
//         public Boolean success;
//         public String message;
//         public List<Map<String, Object>> pricings;
//     }
// 
//     public class GetResult {
//         public Integer statusCode;
//         public GetResponseBody body;
// 
//         public GetResult(Integer statusCode, GetResponseBody body) {
//             this.statusCode = statusCode;
//             this.body = body;
//         }
//     }

    private static Boolean multiCurrencyEnabled;

    public static Result processPricings(String requestBody, Operation pricingOperation) {
        String requestId;
        try {
            if (pricingOperation == null) {
                throw new IllegalArgumentException('Operation is required.');
            }

            if (String.isBlank(requestBody)) {
                throw new IllegalArgumentException('Request body is required.');
            }

            String normalizedBody = requestBody.replace('"currency"', '"currencyCode"');
            PricingRequest pricingRequest = (PricingRequest) JSON.deserialize(normalizedBody, PricingRequest.class);
            if (pricingRequest == null) {
                throw new IllegalArgumentException('Request body is empty.');
            }

            requestId = String.isBlank(pricingRequest.requestId) ? null : pricingRequest.requestId.trim();
            if (requestId == null) {
                throw new IllegalArgumentException('requestId is required.');
            }

            if (pricingRequest.pricings == null || pricingRequest.pricings.isEmpty()) {
                throw new IllegalArgumentException('pricings is required and must not be empty.');
            }

            return processRecords(requestId, pricingRequest.pricings, requestBody, pricingOperation);
        } catch (JSONException jsonEx) {
            logError('processPricings', jsonEx, requestBody);
            return buildFailure(400, requestId, 'Request body is not valid JSON.');
        } catch (IllegalArgumentException argEx) {
            logError('processPricings', argEx, requestBody);
            return buildFailure(400, requestId, argEx.getMessage());
        } catch (Exception ex) {
            logError('processPricings', ex, requestBody);
            return buildFailure(500, requestId, 'Internal server error.');
        }
    }

    private static Result processRecords(String requestId, List<PricingMaster> pricings, String requestBody, Operation pricingOperation) {
        Boolean isCreate = pricingOperation == Operation.CREATE_RECORD;
        List<ResultItem> results = new List<ResultItem>();
        List<Integer> validIndexes = new List<Integer>();
        Set<String> unitCodes = new Set<String>();
        Set<String> parkingCodes = new Set<String>();
        Set<String> requestKeys = new Set<String>();

        for (Integer i = 0; i < pricings.size(); i++) {
            PricingMaster pricing = pricings[i];
            ResultItem item = new ResultItem(pricing);
            results.add(item);

            String validationError = validatePricing(pricing);
            if (validationError != null) {
                item.fail(validationError);
                continue;
            }

            String materialCode = pricing.materialCode.trim();
            String requestKey = (isUnit(pricing) ? 'Unit' : 'Car Park') + '|' + materialCode + '|'+ keySuffix(pricing);
            if (!requestKeys.add(requestKey)) {
                item.fail('Duplicate pricing record in request for the same material, conditionType, salesOrganization, distributionChannel and validFrom.');
                continue;
            }

            if (isUnit(pricing)) {
                unitCodes.add(materialCode);
            } else {
                parkingCodes.add(materialCode);
            }
            validIndexes.add(i);
        }

        Map<String, Unit__c> unitsByCode = queryUnits(unitCodes);
        Map<String, List<Parking__c>> parkingsByCode = queryParkings(parkingCodes);

        Map<Integer, Id> parentIds = new Map<Integer, Id>();
        Set<Id> unitIds = new Set<Id>();
        Set<Id> parkingIds = new Set<Id>();

        for (Integer index : validIndexes) {
            PricingMaster pricing = pricings[index];
            String materialCode = pricing.materialCode.trim();

            if (isUnit(pricing)) {
                Unit__c unit = unitsByCode.get(materialCode);
                if (unit == null) {
                    results[index].fail('No matching Unit record found.');
                    continue;
                }
                parentIds.put(index, unit.Id);
                unitIds.add(unit.Id);
            } else {
                List<Parking__c> parkings = parkingsByCode.get(materialCode);
                if (parkings == null || parkings.isEmpty()) {
                    results[index].fail('No matching Parking record found.');
                    continue;
                }
                if (parkings.size() > 1) {
                    results[index].fail('Multiple Parking records found for this materialCode.');
                    continue;
                }
                parentIds.put(index, parkings[0].Id);
                parkingIds.add(parkings[0].Id);
            }
        }

        Map<String, List<Pricing_Master__c>> existingByKey = queryExistingPricings(unitIds, parkingIds);

        List<Pricing_Master__c> records = new List<Pricing_Master__c>();
        List<Integer> recordIndexes = new List<Integer>();

        for (Integer index : validIndexes) {
            if (!parentIds.containsKey(index)) {
                continue;
            }

            PricingMaster pricing = pricings[index];
            Id parentId = parentIds.get(index);
            String key = parentId + '|' + keySuffix(pricing);
            List<Pricing_Master__c> existing = existingByKey.get(key);
            Boolean exists = existing != null && !existing.isEmpty();

            if (isCreate) {
                if (exists) {
                    results[index].fail('Pricing already exists for this material, conditionType, salesOrganization, distributionChannel and validFrom.');
                    continue;
                }

                Pricing_Master__c newPricing = new Pricing_Master__c();
                mapPricing(newPricing, pricing, parentId, true);
                records.add(newPricing);
            } else {
                if (!exists) {
                    results[index].fail('No matching Pricing record found.');
                    continue;
                }
                if (existing.size() > 1) {
                    results[index].fail('Multiple Pricing records found for this key.');
                    continue;
                }

                Pricing_Master__c pricingRecord = new Pricing_Master__c(Id = existing[0].Id);
                mapPricing(pricingRecord, pricing, parentId, false);
                records.add(pricingRecord);
            }
            recordIndexes.add(index);
        }

        saveRecords(records, recordIndexes, results, isCreate,
            isCreate ? 'Pricing created successfully.' : 'Pricing updated successfully.');

        return buildResult(requestId, results, requestBody);
    }

//     public static GetResult getPricings(String recordId, String materialCode, String materialGroup) {
//         String requestInfo = 'id=' + recordId + ', materialCode=' + materialCode + ', materialGroup=' + materialGroup;
//         try {
//             String soql = 'SELECT Id, Material_Group__c, Condition_Type__c, Sales_Organization__c, '
//                 + 'Distribution_Channel__c, Valid_From__c, Valid_To__c, Amount__c, '
//                 + 'Unit__r.Unit_Name_Code__c, Parking__r.Material_Code__c'
//                 + (isMultiCurrency() ? ', CurrencyIsoCode' : '')
//                 + ' FROM Pricing_Master__c WHERE ';
//             Map<String, Object> binds = new Map<String, Object>();
// 
//             if (String.isNotBlank(recordId)) {
//                 Id parsedId;
//                 try {
//                     parsedId = Id.valueOf(recordId.trim());
//                 } catch (StringException strEx) {
//                     throw new IllegalArgumentException('id is not a valid Salesforce Id.');
//                 }
//                 if (parsedId.getSobjectType() != Pricing_Master__c.SObjectType) {
//                     throw new IllegalArgumentException('id does not belong to a Pricing record.');
//                 }
//                 soql += 'Id = :recordId';
//                 binds.put('recordId', parsedId);
//             } else {
//                 if (String.isBlank(materialCode)) {
//                     throw new IllegalArgumentException('id, or materialCode with materialGroup, is required.');
//                 }
//                 if (String.isBlank(materialGroup)) {
//                     throw new IllegalArgumentException('materialGroup is required.');
//                 }
// 
//                 String code = materialCode.trim();
//                 binds.put('code', code);
//                 if ('Unit'.equalsIgnoreCase(materialGroup.trim())) {
//                     soql += 'Unit__r.Unit_Name_Code__c = :code';
//                 } else if ('Car Park'.equalsIgnoreCase(materialGroup.trim())) {
//                     soql += 'Parking__r.Material_Code__c = :code';
//                 } else {
//                     throw new IllegalArgumentException('Unsupported materialGroup: ' + materialGroup.trim() + '.');
//                 }
//             }
//             soql += ' ORDER BY Valid_From__c ASC';
// 
//             List<Pricing_Master__c> records = Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
//             if (records.isEmpty()) {
//                 return buildGetResult(404, false, 'No matching Pricing record found.', null);
//             }
// 
//             List<Map<String, Object>> pricings = new List<Map<String, Object>>();
//             for (Pricing_Master__c record : records) {
//                 pricings.add(toResponseMap(record));
//             }
//             return buildGetResult(200, true, 'Pricing retrieved successfully.', pricings);
//         } catch (IllegalArgumentException argEx) {
//             logError('getPricings', argEx, requestInfo);
//             return buildGetResult(400, false, argEx.getMessage(), null);
//         } catch (Exception ex) {
//             logError('getPricings', ex, requestInfo);
//             return buildGetResult(500, false, 'Internal server error.', null);
//         }
//     }

//     private static Map<String, Object> toResponseMap(Pricing_Master__c record) {
//         Map<String, Object> row = new Map<String, Object>();
//         Boolean isUnitRecord = record.Unit__c != null;
// 
//         row.put('recordId', record.Id);
//         row.put('materialCode', isUnitRecord? (record.Unit__r == null ? null : record.Unit__r.Unit_Name_Code__c): (record.Parking__r == null ? null : record.Parking__r.Material_Code__c));
//         row.put('materialGroup', record.Material_Group__c);
//         row.put('salesOrganization', record.Sales_Organization__c);
//         row.put('distributionChannel', record.Distribution_Channel__c);
//         row.put('conditionType', record.Condition_Type__c);
//         row.put('validFrom', record.Valid_From__c == null ? null : String.valueOf(record.Valid_From__c));
//         row.put('validTo', record.Valid_To__c == null ? null : String.valueOf(record.Valid_To__c));
//         row.put('amount', record.Amount__c);
//         row.put('currency', isMultiCurrency() ? (String) record.get('CurrencyIsoCode') : null);
//         return row;
//     }

    private static Boolean isMultiCurrency() {
        if (multiCurrencyEnabled == null) {
            multiCurrencyEnabled = Schema.SObjectType.Pricing_Master__c.fields.getMap().containsKey('currencyisocode');
        }
        return multiCurrencyEnabled;
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
                failureSummaries.add(item.materialCode + ': ' + item.message);
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
            body.message = 'Pricing processing completed successfully.';
            return new Result(200, body);
        }

        body.success = false;
        body.message = 'Pricing processing completed with some failures.';

        String summary = 'Pricing processing failed for ' + failureCount + ' of ' + results.size() + ' record(s): ' + String.join(failureSummaries, ' | ');
        logError('processPricings', new PricingException(summary.abbreviate(255)), requestBody);

        return new Result(207, body);
    }

    private static Result buildFailure(Integer statusCode, String requestId, String message) {
        ResponseBody body = new ResponseBody();
        body.success = false;
        body.message = String.isBlank(message) ? 'Request failed.' : message;
        body.requestId = requestId;
        return new Result(statusCode, body);
    }

//     private static GetResult buildGetResult(Integer statusCode, Boolean success, String message, List<Map<String, Object>> pricings) {
//         GetResponseBody body = new GetResponseBody();
//         body.success = success;
//         body.message = message;
//         body.pricings = pricings;
//         return new GetResult(statusCode, body);
//     }

    private static String validatePricing(PricingMaster pricing) {
        if (pricing == null) {
            return 'Pricing record is empty.';
        }
        if (String.isBlank(pricing.materialCode)) {
            return 'materialCode is required.';
        }
        if (String.isBlank(pricing.materialGroup)) {
            return 'materialGroup is required.';
        }
        if (!isUnit(pricing) && !isCarPark(pricing)) {
            return 'Unsupported materialGroup: ' + pricing.materialGroup.trim() + '.';
        }
        if (String.isBlank(pricing.conditionType)) {
            return 'conditionType is required.';
        }
        if (String.isBlank(pricing.salesOrganization)) {
            return 'salesOrganization is required.';
        }
        if (String.isBlank(pricing.distributionChannel)) {
            return 'distributionChannel is required.';
        }
        if (pricing.amount == null) {
            return 'amount is required.';
        }

        try {
            Date validFrom = parseDate(pricing.validFrom, 'validFrom');
            Date validTo = parseDate(pricing.validTo, 'validTo');
            if (validFrom == null) {
                return 'validFrom is required.';
            }
            if (validTo != null && validTo < validFrom) {
                return 'validTo must not be earlier than validFrom.';
            }
        } catch (IllegalArgumentException argEx) {
            return argEx.getMessage();
        }

        return null;
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

    private static String keySuffix(PricingMaster pricing) {
        return pricing.conditionType.trim() + '|' + pricing.salesOrganization.trim() + '|'+ pricing.distributionChannel.trim() + '|' + String.valueOf(parseDate(pricing.validFrom, 'validFrom'));
    }

    private static Boolean isUnit(PricingMaster pricing) {
        return 'Unit'.equalsIgnoreCase(pricing.materialGroup.trim());
    }

    private static Boolean isCarPark(PricingMaster pricing) {
        return 'Car Park'.equalsIgnoreCase(pricing.materialGroup.trim());
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

    private static Map<String, List<Parking__c>> queryParkings(Set<String> parkingCodes) {
        Map<String, List<Parking__c>> parkingsByCode = new Map<String, List<Parking__c>>();
        if (parkingCodes.isEmpty()) {
            return parkingsByCode;
        }

        for (Parking__c parking : [SELECT Id, Material_Code__c FROM Parking__c WHERE Material_Code__c IN :parkingCodes WITH SYSTEM_MODE]) {
            if (!parkingsByCode.containsKey(parking.Material_Code__c)) {
                parkingsByCode.put(parking.Material_Code__c, new List<Parking__c>());
            }
            parkingsByCode.get(parking.Material_Code__c).add(parking);
        }
        return parkingsByCode;
    }

    private static Map<String, List<Pricing_Master__c>> queryExistingPricings(Set<Id> unitIds, Set<Id> parkingIds) {
        Map<String, List<Pricing_Master__c>> existingByKey = new Map<String, List<Pricing_Master__c>>();
        if (unitIds.isEmpty() && parkingIds.isEmpty()) {
            return existingByKey;
        }

        for (Pricing_Master__c pricing : [SELECT Id, Unit__c, Parking__c, Condition_Type__c, Sales_Organization__c,Distribution_Channel__c, Valid_From__c FROM Pricing_Master__c WHERE Unit__c IN :unitIds OR Parking__c IN :parkingIds WITH SYSTEM_MODE]) {
            Id parentId = pricing.Unit__c != null ? pricing.Unit__c : pricing.Parking__c;
            String key = parentId + '|' + pricing.Condition_Type__c + '|' + pricing.Sales_Organization__c + '|'
                + pricing.Distribution_Channel__c + '|' + String.valueOf(pricing.Valid_From__c);

            if (!existingByKey.containsKey(key)) {
                existingByKey.put(key, new List<Pricing_Master__c>());
            }
            existingByKey.get(key).add(pricing);
        }
        return existingByKey;
    }

    private static void mapPricing(Pricing_Master__c record, PricingMaster pricing, Id parentId, Boolean isCreate) {
        Boolean unitGroup = isUnit(pricing);

        if (isCreate) {
            if (unitGroup) {
                record.Unit__c = parentId;
            } else {
                record.Parking__c = parentId;
            }
            record.Name = (pricing.materialCode.trim() + ' - ' + pricing.conditionType.trim() + ' - ' + pricing.validFrom.trim()).abbreviate(80);
            record.Condition_Type__c = pricing.conditionType.trim();
            record.Sales_Organization__c = pricing.salesOrganization.trim();
            record.Distribution_Channel__c = pricing.distributionChannel.trim();
            record.Valid_From__c = parseDate(pricing.validFrom, 'validFrom');
        }

        record.Material_Group__c = unitGroup ? 'Unit' : 'Parking';
        record.Amount__c = pricing.amount;

        Date validTo = parseDate(pricing.validTo, 'validTo');
        if (validTo != null) {
            record.Valid_To__c = validTo;
        }

        if (isMultiCurrency() && String.isNotBlank(pricing.currencyCode)) {
            record.put('CurrencyIsoCode', pricing.currencyCode.trim().toUpperCase());
        }
    }

    private static void logError(String apexMethodName, Exception ex, String requestBody) {
        try {
            IntegrationLogUtility.captureError('SAP_Pricing', apexMethodName, ex, requestBody, 'SAP - SFDC');
        } catch (Exception loggingEx) {
            System.debug(LoggingLevel.ERROR, 'SAP_Pricing.' + apexMethodName + ' failed to write integration log: ' + loggingEx.getMessage());
        }
    }
}