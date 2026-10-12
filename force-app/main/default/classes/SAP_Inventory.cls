public without sharing class SAP_Inventory {

    public class InventoryException extends Exception {}

    public class MaterialRequest {
        public String requestId;
        public List<MaterialMaster> materialMasters;
    }

    public class MaterialMaster {
        public String materialCode;
        public String materialGroup;
        public String materialDescription;
        public String plant;
        public String salesOrganization;
        public String distributionChannel;
        public String itemCategoryGroup;
        public Decimal builtUpArea;
        public String uom;
        public String status;
    }

    public class ResultItem {
        public String materialCode;
        public String materialGroup;
        public Boolean success;
        public String message;
        public String recordId;

        public ResultItem(MaterialMaster material) {
            this.materialCode = material == null ? null : material.materialCode;
            this.materialGroup = material == null ? null : material.materialGroup;
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

    public static Result processMaterialMasters(String requestBody) {
        String requestId;
        try {
            if (String.isBlank(requestBody)) {
                throw new IllegalArgumentException('Request body is required.');
            }

            MaterialRequest materialRequest = (MaterialRequest) JSON.deserialize(requestBody, MaterialRequest.class);
            if (materialRequest == null) {
                throw new IllegalArgumentException('Request body is empty.');
            }

            requestId = String.isBlank(materialRequest.requestId) ? null : materialRequest.requestId.trim();
            if (requestId == null) {
                throw new IllegalArgumentException('requestId is required.');
            }

            if (materialRequest.materialMasters == null || materialRequest.materialMasters.isEmpty()) {
                throw new IllegalArgumentException('materialMasters is required and must not be empty.');
            }

            return processRecords(requestId, materialRequest.materialMasters, requestBody);
        } catch (JSONException jsonEx) {
            logError('processMaterialMasters', jsonEx, requestBody);
            return buildFailure(400, requestId, 'Request body is not valid JSON.');
        } catch (IllegalArgumentException argEx) {
            logError('processMaterialMasters', argEx, requestBody);
            return buildFailure(400, requestId, argEx.getMessage());
        } catch (Exception ex) {
            logError('processMaterialMasters', ex, requestBody);
            return buildFailure(500, requestId, 'Internal server error.');
        }
    }

    private static Result processRecords(String requestId, List<MaterialMaster> materials, String requestBody) {
        List<ResultItem> results = new List<ResultItem>();
        List<Integer> unitIndexes = new List<Integer>();
        List<Integer> parkingIndexes = new List<Integer>();
        Set<String> unitCodes = new Set<String>();
        Set<String> parkingCodes = new Set<String>();

        for (Integer i = 0; i < materials.size(); i++) {
            MaterialMaster material = materials[i];
            ResultItem item = new ResultItem(material);
            results.add(item);

            String validationError = validateMaterial(material);
            if (validationError != null) {
                item.fail(validationError);
                continue;
            }

            String materialCode = material.materialCode.trim();
            if (isUnit(material)) {
                if (unitCodes.add(materialCode)) {
                    unitIndexes.add(i);
                } else {
                    item.fail('Duplicate materialCode in request for materialGroup Unit.');
                }
            } else {
                if (parkingCodes.add(materialCode)) {
                    parkingIndexes.add(i);
                } else {
                    item.fail('Duplicate materialCode in request for materialGroup Car Park.');
                }
            }
        }

        Map<String, Unit__c> unitsByCode = queryUnits(unitCodes, parkingCodes);

        List<Unit__c> unitUpdates = new List<Unit__c>();
        List<Integer> unitUpdateIndexes = new List<Integer>();
        for (Integer index : unitIndexes) {
            MaterialMaster material = materials[index];
            Unit__c existingUnit = unitsByCode.get(material.materialCode.trim());
            if (existingUnit == null) {
                results[index].fail('No matching Unit record found.');
                continue;
            }

            Unit__c unit = new Unit__c(Id = existingUnit.Id);
            mapUnit(unit, material);
            unitUpdates.add(unit);
            unitUpdateIndexes.add(index);
        }

        Set<Id> parkingUnitIds = new Set<Id>();
        for (Integer index : parkingIndexes) {
            Unit__c existingUnit = unitsByCode.get(materials[index].materialCode.trim());
            if (existingUnit != null) {
                parkingUnitIds.add(existingUnit.Id);
            }
        }

        Map<Id, List<Parking__c>> parkingsByUnitId = queryParkings(parkingUnitIds);

        List<Parking__c> parkingUpdates = new List<Parking__c>();
        List<Integer> parkingUpdateIndexes = new List<Integer>();
        for (Integer index : parkingIndexes) {
            MaterialMaster material = materials[index];
            Unit__c existingUnit = unitsByCode.get(material.materialCode.trim());
            if (existingUnit == null) {
                results[index].fail('No matching Unit record found.');
                continue;
            }

            List<Parking__c> relatedParkings = parkingsByUnitId.get(existingUnit.Id);
            if (relatedParkings == null || relatedParkings.isEmpty()) {
                results[index].fail('No matching Parking record found.');
                continue;
            }

            if (relatedParkings.size() > 1) {
                results[index].fail('Multiple Parking records found for the Unit.');
                continue;
            }

            Parking__c parking = new Parking__c(Id = relatedParkings[0].Id);
            mapParking(parking, material);
            parkingUpdates.add(parking);
            parkingUpdateIndexes.add(index);
        }

        if (!unitUpdates.isEmpty()) {
            List<Database.SaveResult> unitSaveResults = Database.update(unitUpdates, false, AccessLevel.SYSTEM_MODE);
            applySaveResults(unitSaveResults, unitUpdateIndexes, results, 'Unit updated successfully.');
        }

        if (!parkingUpdates.isEmpty()) {
            List<Database.SaveResult> parkingSaveResults = Database.update(parkingUpdates, false, AccessLevel.SYSTEM_MODE);
            applySaveResults(parkingSaveResults, parkingUpdateIndexes, results, 'Parking updated successfully.');
        }

        return buildResult(requestId, results, requestBody);
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
            body.message = 'Material master processing completed successfully.';
            return new Result(200, body);
        }

        body.success = false;
        body.message = 'Material master processing completed with some failures.';

        String summary = 'Material master processing failed for ' + failureCount + ' of ' + results.size() + ' record(s): ' + String.join(failureSummaries, ' | ');
        logError('processMaterialMasters', new InventoryException(summary.abbreviate(255)), requestBody);

        return new Result(207, body);
    }

    private static Result buildFailure(Integer statusCode, String requestId, String message) {
        ResponseBody body = new ResponseBody();
        body.success = false;
        body.message = String.isBlank(message) ? 'Request failed.' : message;
        body.requestId = requestId;
        return new Result(statusCode, body);
    }

    private static String validateMaterial(MaterialMaster material) {
        if (material == null) {
            return 'Material record is empty.';
        }

        if (String.isBlank(material.materialCode)) {
            return 'materialCode is required.';
        }

        if (String.isBlank(material.materialGroup)) {
            return 'materialGroup is required.';
        }

        if (!isUnit(material) && !isCarPark(material)) {
            return 'Unsupported materialGroup: ' + material.materialGroup.trim() + '.';
        }

        return null;
    }

    private static Boolean isUnit(MaterialMaster material) {
        return 'Unit'.equalsIgnoreCase(material.materialGroup.trim());
    }

    private static Boolean isCarPark(MaterialMaster material) {
        return 'Car Park'.equalsIgnoreCase(material.materialGroup.trim());
    }

    private static Map<String, Unit__c> queryUnits(Set<String> unitCodes, Set<String> parkingCodes) {
        Set<String> allCodes = new Set<String>(unitCodes);
        allCodes.addAll(parkingCodes);

        Map<String, Unit__c> unitsByCode = new Map<String, Unit__c>();
        if (allCodes.isEmpty()) {
            return unitsByCode;
        }

        for (Unit__c unit : [SELECT Id, Unit_Name_Code__c FROM Unit__c WHERE Unit_Name_Code__c IN :allCodes WITH SYSTEM_MODE]) {
            unitsByCode.put(unit.Unit_Name_Code__c, unit);
        }

        return unitsByCode;
    }

    private static Map<Id, List<Parking__c>> queryParkings(Set<Id> unitIds) {
        Map<Id, List<Parking__c>> parkingsByUnitId = new Map<Id, List<Parking__c>>();
        if (unitIds.isEmpty()) {
            return parkingsByUnitId;
        }

        for (Parking__c parking : [SELECT Id, Unit__c FROM Parking__c WHERE Unit__c IN :unitIds WITH SYSTEM_MODE]) {
            if (!parkingsByUnitId.containsKey(parking.Unit__c)) {
                parkingsByUnitId.put(parking.Unit__c, new List<Parking__c>());
            }
            parkingsByUnitId.get(parking.Unit__c).add(parking);
        }

        return parkingsByUnitId;
    }

    private static void mapUnit(Unit__c unit, MaterialMaster material) {
        setIfPresent(unit, 'Description__c', material.materialDescription);
        setIfPresent(unit, 'Plant__c', material.plant);
        setIfPresent(unit, 'Sales_Organization__c', material.salesOrganization);
        setIfPresent(unit, 'Distribution_Channel__c', material.distributionChannel);
        setIfPresent(unit, 'Item_Category_Group__c', material.itemCategoryGroup);
        setIfPresent(unit, 'UOM__c', material.uom);
        setIfPresent(unit, 'Status__c', material.status);
        if (material.builtUpArea != null) {
            unit.put('Built_Up_Area_sq_ft__c', material.builtUpArea);
        }
    }

    private static void mapParking(Parking__c parking, MaterialMaster material) {
        setIfPresent(parking, 'Description__c', material.materialDescription);
        setIfPresent(parking, 'Plant__c', material.plant);
        setIfPresent(parking, 'Sales_Organization__c', material.salesOrganization);
        setIfPresent(parking, 'Distribution_Channel__c', material.distributionChannel);
        setIfPresent(parking, 'Item_Category_Group__c', material.itemCategoryGroup);
        setIfPresent(parking, 'Status__c', material.status);
    }

    private static void setIfPresent(SObject record, String fieldName, String value) {
        if (String.isNotBlank(value)) {
            record.put(fieldName, value.trim());
        }
    }

    private static void applySaveResults(List<Database.SaveResult> saveResults,List<Integer> resultIndexes,List<ResultItem> results,String successMessage) {
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
            item.fail(errorMessages.isEmpty() ? 'Update failed.' : String.join(errorMessages, '; '));
        }
    }

    private static void logError(String apexMethodName, Exception ex, String requestBody) {
        try {
            IntegrationLogUtility.captureError('SAP_Inventory', apexMethodName, ex, requestBody, 'SAP - SFDC');
        } catch (Exception loggingEx) {
            System.debug(LoggingLevel.ERROR, 'SAP_Inventory.' + apexMethodName + ' failed to write integration log: ' + loggingEx.getMessage());
        }
    }
}