public without sharing class SAP_Inventory {

    public enum Operation { CREATE_RECORD, UPDATE_RECORD }

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

    public class GetResponseBody {
        public Boolean success;
        public String message;
        public MaterialMaster materialMaster;
    }

    public class GetResult {
        public Integer statusCode;
        public GetResponseBody body;

        public GetResult(Integer statusCode, GetResponseBody body) {
            this.statusCode = statusCode;
            this.body = body;
        }
    }

    public static Result processMaterialMasters(String requestBody, Operation inventoryOperation) {
        String requestId;
        try {
            if (inventoryOperation == null) {
                throw new IllegalArgumentException('Operation is required.');
            }

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

            return processRecords(requestId, materialRequest.materialMasters, requestBody, inventoryOperation);
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

    private static Result processRecords(String requestId, List<MaterialMaster> materials, String requestBody, Operation inventoryOperation) {
        Boolean isCreate = inventoryOperation == Operation.CREATE_RECORD;
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

        Map<String, Unit__c> unitsByCode = queryUnits(unitCodes);
        Map<String, List<Parking__c>> parkingsByCode = queryParkings(parkingCodes);

        List<Unit__c> unitRecords = new List<Unit__c>();
        List<Integer> unitRecordIndexes = new List<Integer>();

        for (Integer index : unitIndexes) {
            MaterialMaster material = materials[index];
            String materialCode = material.materialCode.trim();
            Unit__c existingUnit = unitsByCode.get(materialCode);

            if (isCreate) {
                if (existingUnit != null) {
                    results[index].fail('Unit already exists for this materialCode.');
                    continue;
                }

                Unit__c newUnit = new Unit__c(Unit_Name_Code__c = materialCode);
                mapUnit(newUnit, material);
                unitRecords.add(newUnit);
            } else {
                if (existingUnit == null) {
                    results[index].fail('No matching Unit record found.');
                    continue;
                }

                Unit__c unit = new Unit__c(Id = existingUnit.Id);
                mapUnit(unit, material);
                unitRecords.add(unit);
            }
            unitRecordIndexes.add(index);
        }

        List<Parking__c> parkingRecords = new List<Parking__c>();
        List<Integer> parkingRecordIndexes = new List<Integer>();

        for (Integer index : parkingIndexes) {
            MaterialMaster material = materials[index];
            String materialCode = material.materialCode.trim();
            List<Parking__c> existingParkings = parkingsByCode.get(materialCode);
            Boolean parkingExists = existingParkings != null && !existingParkings.isEmpty();

            if (isCreate) {
                if (parkingExists) {
                    results[index].fail('Parking already exists for this materialCode.');
                    continue;
                }

                Parking__c newParking = new Parking__c(Material_Code__c = materialCode);
                mapParking(newParking, material);
                parkingRecords.add(newParking);
            } else {
                if (!parkingExists) {
                    results[index].fail('No matching Parking record found.');
                    continue;
                }

                if (existingParkings.size() > 1) {
                    results[index].fail('Multiple Parking records found for this materialCode.');
                    continue;
                }

                Parking__c parking = new Parking__c(Id = existingParkings[0].Id);
                mapParking(parking, material);
                parkingRecords.add(parking);
            }
            parkingRecordIndexes.add(index);
        }

        saveRecords(unitRecords, unitRecordIndexes, results, isCreate, isCreate ? 'Unit created successfully.' : 'Unit updated successfully.');
        saveRecords(parkingRecords, parkingRecordIndexes, results, isCreate, isCreate ? 'Parking created successfully.' : 'Parking updated successfully.');

        return buildResult(requestId, results, requestBody);
    }

    private static void saveRecords(List<SObject> records,List<Integer> resultIndexes,List<ResultItem> results,Boolean isInsert,String successMessage) {
        if (records == null || records.isEmpty()) {
            return;
        }

        List<Database.SaveResult> saveResults = isInsert
            ? Database.insert(records, false, AccessLevel.SYSTEM_MODE)
            : Database.update(records, false, AccessLevel.SYSTEM_MODE);

        applySaveResults(saveResults, resultIndexes, results, successMessage);
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

    private static void logError(String apexMethodName, Exception ex, String requestBody) {
        try {
            IntegrationLogUtility.captureError('SAP_Inventory', apexMethodName, ex, requestBody, 'SAP - SFDC');
        } catch (Exception loggingEx) {
            System.debug(LoggingLevel.ERROR, 'SAP_Inventory.' + apexMethodName + ' failed to write integration log: ' + loggingEx.getMessage());
        }
    }

    // public static GetResult getMaterialMaster(String recordId, String materialGroup) {
    //     try {
    //         if (String.isBlank(recordId)) {
    //             throw new IllegalArgumentException('id is required.');
    //         }
    //         if (String.isBlank(materialGroup)) {
    //             throw new IllegalArgumentException('materialGroup is required.');
    //         }

    //         Id parsedId;
    //         try {
    //             parsedId = Id.valueOf(recordId.trim());
    //         } catch (StringException strEx) {
    //             throw new IllegalArgumentException('id is not a valid Salesforce Id.');
    //         }

    //         String groupName = materialGroup.trim();
    //         MaterialMaster material;

    //         if ('Unit'.equalsIgnoreCase(groupName)) {
    //             if (parsedId.getSobjectType() != Unit__c.SObjectType) {
    //                 throw new IllegalArgumentException('id does not belong to a Unit record.');
    //             }
    //             material = getUnitMaterial(parsedId);
    //         } else if ('Car Park'.equalsIgnoreCase(groupName)) {
    //             if (parsedId.getSobjectType() != Parking__c.SObjectType) {
    //                 throw new IllegalArgumentException('id does not belong to a Parking record.');
    //             }
    //             material = getParkingMaterial(parsedId);
    //         } else {
    //             throw new IllegalArgumentException('Unsupported materialGroup: ' + groupName + '.');
    //         }

    //         if (material == null) {
    //             return buildGetResult(404, false, 'No matching ' + groupName + ' record found.', null);
    //         }

    //         return buildGetResult(200, true, 'Material master retrieved successfully.', material);
    //     } catch (IllegalArgumentException argEx) {
    //         logError('getMaterialMaster', argEx, 'id=' + recordId + ', materialGroup=' + materialGroup);
    //         return buildGetResult(400, false, argEx.getMessage(), null);
    //     } catch (Exception ex) {
    //         logError('getMaterialMaster', ex, 'id=' + recordId + ', materialGroup=' + materialGroup);
    //         return buildGetResult(500, false, 'Internal server error.', null);
    //     }
    // }

    // private static MaterialMaster getUnitMaterial(Id unitId) {
    //     List<Unit__c> units = [SELECT Id, Unit_Name_Code__c, Description__c, Plant__c, Sales_Organization__c,Distribution_Channel__c, Item_Category_Group__c, UOM__c, Status__c,Built_Up_Area_sq_ft__c FROM Unit__c WHERE Id = :unitId WITH SYSTEM_MODE LIMIT 1];
    //     if (units.isEmpty()) {
    //         return null;
    //     }

    //     Unit__c unit = units[0];
    //     MaterialMaster material = new MaterialMaster();
    //     material.materialCode = unit.Unit_Name_Code__c;
    //     material.materialGroup = 'Unit';
    //     material.materialDescription = unit.Description__c;
    //     material.plant = unit.Plant__c;
    //     material.salesOrganization = unit.Sales_Organization__c;
    //     material.distributionChannel = unit.Distribution_Channel__c;
    //     material.itemCategoryGroup = unit.Item_Category_Group__c;
    //     material.builtUpArea = (Decimal) unit.get('Built_Up_Area_sq_ft__c');
    //     material.uom = unit.UOM__c;
    //     material.status = unit.Status__c;
    //     return material;
    // }

    // private static MaterialMaster getParkingMaterial(Id parkingId) {
    //     List<Parking__c> parkings = [SELECT Id, Material_Code__c, Description__c, Plant__c, Sales_Organization__c,Distribution_Channel__c, Item_Category_Group__c, Status__c FROM Parking__c WHERE Id = :parkingId WITH SYSTEM_MODE LIMIT 1];
    //     if (parkings.isEmpty()) {
    //         return null;
    //     }

    //     Parking__c parking = parkings[0];
    //     MaterialMaster material = new MaterialMaster();
    //     material.materialCode = parking.Material_Code__c;
    //     material.materialGroup = 'Car Park';
    //     material.materialDescription = parking.Description__c;
    //     material.plant = parking.Plant__c;
    //     material.salesOrganization = parking.Sales_Organization__c;
    //     material.distributionChannel = parking.Distribution_Channel__c;
    //     material.itemCategoryGroup = parking.Item_Category_Group__c;
    //     material.status = parking.Status__c;
    //     return material;
    // }

    // private static GetResult buildGetResult(Integer statusCode, Boolean success, String message, MaterialMaster material) {
    //     GetResponseBody body = new GetResponseBody();
    //     body.success = success;
    //     body.message = message;
    //     body.materialMaster = material;
    //     return new GetResult(statusCode, body);
    // }
}