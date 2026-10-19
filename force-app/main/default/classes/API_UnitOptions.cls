@RestResource(urlMapping='/api/v1/unit-options/*')
global without sharing class API_UnitOptions {

    @HttpGet
    global static void getUnitOptions() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            UnitOptionsResponse result = buildUnitOptionsResponse(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_UnitOptions.getUnitOptions ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_UnitOptions', 'getUnitOptions', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'An unexpected error occurred while retrieving unit options', null)));
        }
    }

    private static UnitOptionsResponse buildUnitOptionsResponse(RestRequest request) {
        try {
            Map<String, String> params = request != null && request.params != null ? request.params : new Map<String, String>();

            String projectId = params.get('projectId');
            if (String.isBlank(projectId)) {
                return createResponse(false, 400, 'projectId is required', null);
            }
            projectId = projectId.trim();
            if (!isValidSalesforceId(projectId)) {
                return createResponse(false, 400, 'projectId is required', null);
            }

            Integer offsetValue = params.containsKey('offsetValue') && String.isNotBlank(params.get('offsetValue'))? Integer.valueOf(params.get('offsetValue')) : 0;
            Integer limitValue = params.containsKey('limitValue') && String.isNotBlank(params.get('limitValue'))? Integer.valueOf(params.get('limitValue')) : 20;
            if (offsetValue == null || offsetValue < 0) {
                offsetValue = 0;
            }
            if (limitValue == null || limitValue <= 0) {
                limitValue = 20;
            }

            List<Project__c> matchedProjects = [SELECT Id FROM Project__c WHERE Id = :projectId WITH SYSTEM_MODE LIMIT 1];
            if (matchedProjects.isEmpty()) {
                return createResponse(false, 404, 'Project not found', null);
            }

            String currentUserId = UserInfo.getUserId();
            List<User> matchedUsers = [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :currentUserId WITH SYSTEM_MODE LIMIT 1];

            UnitOptionsData data = new UnitOptionsData();
            data.options = new List<OptionWrapper>();

            Id accountId = (!matchedUsers.isEmpty() && matchedUsers[0].Contact != null) ? matchedUsers[0].Contact.AccountId : null;
            if (accountId == null) {
                data.pagination = buildPagination(0, offsetValue, limitValue, 0);
                return createResponse(true, 200, 'Unit options retrieved successfully', data);
            }

            Set<Id> ownedUnitIds = new Set<Id>();
            for (Opportunity opportunity : [SELECT Id, Unit__c FROM Opportunity WHERE AccountId = :accountId AND Unit__c != null WITH SYSTEM_MODE]) {
                ownedUnitIds.add(opportunity.Unit__c);
            }
            if (ownedUnitIds.isEmpty()) {
                data.pagination = buildPagination(0, offsetValue, limitValue, 0);
                return createResponse(true, 200, 'Unit options retrieved successfully', data);
            }

            Integer totalCount = [SELECT COUNT() FROM Unit__c WHERE Id IN :ownedUnitIds AND Floor__r.Block__r.Project__c = :projectId WITH SYSTEM_MODE];

            List<Unit__c> pagedUnits = [SELECT Id, Unit_Name_Code__c FROM Unit__c WHERE Id IN :ownedUnitIds AND Floor__r.Block__r.Project__c = :projectId WITH SYSTEM_MODE ORDER BY Unit_Name_Code__c ASC LIMIT :limitValue OFFSET :offsetValue];

            for (Unit__c unit : pagedUnits) {
                if (String.isBlank(unit.Unit_Name_Code__c)) {
                    continue;
                }
                OptionWrapper option = new OptionWrapper();
                option.label = unit.Unit_Name_Code__c;
                option.value = String.valueOf(unit.Id);
                data.options.add(option);
            }

            data.pagination = buildPagination(totalCount, offsetValue, limitValue, pagedUnits.size());

            return createResponse(true, 200, 'Unit options retrieved successfully', data);
        } catch (Exception e) {
            System.debug('Error in API_UnitOptions.buildUnitOptionsResponse ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_UnitOptions', 'buildUnitOptionsResponse', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'An unexpected error occurred while retrieving unit options', null);
        }
    }

    private static Map<String, Object> buildPagination(Integer totalCount, Integer offsetValue, Integer limitValue, Integer returnedCount) {
        return new Map<String, Object>{
            'totalCount'  => totalCount,
            'offsetValue' => offsetValue + limitValue,
            'limitValue'  => limitValue,
            'hasMore'     => (offsetValue + returnedCount) < totalCount
        };
    }

    private static Boolean isValidSalesforceId(String recordId) {
        try {
            Id.valueOf(recordId);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static UnitOptionsResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, UnitOptionsData data) {
        UnitOptionsResponse apiResponse = new UnitOptionsResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class UnitOptionsResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public UnitOptionsData data;
    }

    public class UnitOptionsData {
        public List<OptionWrapper> options;
        public Map<String, Object> pagination;
    }

    public class OptionWrapper {
        public String label;
        public String value;
    }
}