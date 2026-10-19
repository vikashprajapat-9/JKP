@RestResource(urlMapping='/api/v1/properties/my-properties')
global without sharing class API_MyProperties {

    @HttpGet
    global static void getMyProperties() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            MyPropertiesResponse result = buildMyPropertiesResponse(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_MyProperties.getMyProperties ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_MyProperties', 'getMyProperties', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'An unexpected error occurred while retrieving properties', null)));
        }
    }

    private static MyPropertiesResponse buildMyPropertiesResponse(RestRequest request) {
        try {
            Map<String, String> requestParams = request != null && request.params != null ? request.params : new Map<String, String>();

            String userId          =  UserInfo.getUserId();
            String projectIdFilter = requestParams.get('projectId');

            Integer offsetValue = requestParams.containsKey('offsetValue') && String.isNotBlank(requestParams.get('offsetValue'))? Integer.valueOf(requestParams.get('offsetValue')): 0;
            Integer limitValue = requestParams.containsKey('limitValue') && String.isNotBlank(requestParams.get('limitValue'))? Integer.valueOf(requestParams.get('limitValue')): 20;
            if (offsetValue == null || offsetValue < 0) {
                offsetValue = 0;
            }
            if (limitValue == null || limitValue <= 0) {
                limitValue = 20;
            }

            if (String.isBlank(userId)) {
                return createResponse(false, 400, 'userId is required', null);
            }
            userId = userId.trim();

            if (!isValidSalesforceId(userId)) {
                return createResponse(false, 400, 'userId is invalid', null);
            }

            Boolean isProjectFilterApplied = String.isNotBlank(projectIdFilter) && !projectIdFilter.trim().equalsIgnoreCase('ALL');
            String selectedProjectId = isProjectFilterApplied ? projectIdFilter.trim() : null;
            Id selectedProjectRecordId = null;
            if (isProjectFilterApplied) {
                try {
                    selectedProjectRecordId = Id.valueOf(selectedProjectId);
                } catch (Exception ex) {
                    return createResponse(false, 400, 'projectId is invalid', null);
                }
            }

            PropertiesData propertiesData = new PropertiesData();
            propertiesData.properties = new List<PropertyWrapper>();

            List<User> matchedUsers = [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :userId LIMIT 1];
            if (matchedUsers.isEmpty()) {
                return createResponse(false, 404, 'User not found', null);
            }

            Id accountId = matchedUsers[0].Contact != null ? matchedUsers[0].Contact.AccountId : null;
            if (accountId == null) {
                propertiesData.pagination = buildPagination(0, offsetValue, limitValue, 0);
                return createResponse(true, 200, 'Properties retrieved successfully', propertiesData);
            }

            Map<Id, Opportunity> opportunityByUnitId = new Map<Id, Opportunity>();
            for (Opportunity opportunity : [SELECT Id, Name, Unit__c FROM Opportunity WHERE AccountId = :accountId AND Unit__c != null WITH SYSTEM_MODE ORDER BY CreatedDate DESC]) {
                if (!opportunityByUnitId.containsKey(opportunity.Unit__c)) {
                    opportunityByUnitId.put(opportunity.Unit__c, opportunity);
                }
            }
            if (opportunityByUnitId.isEmpty()) {
                propertiesData.pagination = buildPagination(0, offsetValue, limitValue, 0);
                return createResponse(true, 200, 'Properties retrieved successfully', propertiesData);
            }

            Set<Id> relatedUnitIds = opportunityByUnitId.keySet();

            Integer totalMatchingCount = isProjectFilterApplied
                ? [SELECT COUNT() FROM Unit__c WHERE Id IN :relatedUnitIds AND Floor__r.Block__r.Project__c = :selectedProjectRecordId WITH SYSTEM_MODE]
                : [SELECT COUNT() FROM Unit__c WHERE Id IN :relatedUnitIds WITH SYSTEM_MODE];

            List<Unit__c> pagedUnits = isProjectFilterApplied
                ? [SELECT Id, Unit_Name_Code__c, Status__c, Floor__r.Block__r.Project__c, Floor__r.Block__r.Project__r.Name FROM Unit__c WHERE Id IN :relatedUnitIds AND Floor__r.Block__r.Project__c = :selectedProjectRecordId WITH SYSTEM_MODE ORDER BY Unit_Name_Code__c LIMIT :limitValue OFFSET :offsetValue]
                : [SELECT Id, Unit_Name_Code__c, Status__c, Floor__r.Block__r.Project__c, Floor__r.Block__r.Project__r.Name FROM Unit__c WHERE Id IN :relatedUnitIds WITH SYSTEM_MODE ORDER BY Unit_Name_Code__c LIMIT :limitValue OFFSET :offsetValue];

            propertiesData.pagination = buildPagination(totalMatchingCount, offsetValue, limitValue, pagedUnits.size());

            if (pagedUnits.isEmpty()) {
                return createResponse(true, 200, 'Properties retrieved successfully', propertiesData);
            }

            Set<Id> pagedProjectIds = new Set<Id>();
            for (Unit__c unit : pagedUnits) {
                Project__c project = getProjectFromUnit(unit);
                if (project != null) {
                    pagedProjectIds.add(project.Id);
                }
            }

            Map<Id, List<String>> documentUrlsByProjectId = getDocumentUrlsByProjectId(pagedProjectIds);
            Map<String, String> statusLabelByApiValue     = getUnitStatusLabels();

            for (Unit__c unit : pagedUnits) {
                Project__c project = getProjectFromUnit(unit);
                String projectKey  = project != null ? String.valueOf(project.Id) : null;
                List<String> documentUrls = project != null ? documentUrlsByProjectId.get(project.Id) : null;

                PropertyWrapper propertyItem = new PropertyWrapper();
                propertyItem.projectId     = projectKey;
                propertyItem.projectName   = project != null && project.Name != null ? project.Name : '';
                propertyItem.propertyId    = unit.Id != null ? unit.Id : '';
                propertyItem.unitBlockCode = unit.Unit_Name_Code__c != null ? unit.Unit_Name_Code__c : '';
                propertyItem.imageUrls     = documentUrls != null ? documentUrls : new List<String>();
                propertyItem.status        = resolveStatusLabel(unit.Status__c, statusLabelByApiValue);
                propertiesData.properties.add(propertyItem);
            }

            return createResponse(true, 200, 'Properties retrieved successfully', propertiesData);
        } catch (Exception e) {
            System.debug('Error in API_MyProperties.buildMyPropertiesResponse ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_MyProperties', 'buildMyPropertiesResponse', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'An unexpected error occurred while retrieving properties', null);
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

    private static Map<Id, List<String>> getDocumentUrlsByProjectId(Set<Id> projectIds) {
        Map<Id, List<String>> documentUrlsByProjectId = new Map<Id, List<String>>();
        if (projectIds.isEmpty()) {
            return documentUrlsByProjectId;
        }

        for (Sub_Document__c subDocument : [SELECT Id, Document__r.Project__c, File_Url__c,Document__c FROM Sub_Document__c WHERE Document__r.Project__c IN :projectIds and Document__r.Name = 'Project Images' AND File_Url__c != null WITH SYSTEM_MODE ORDER BY CreatedDate ASC]) {
            if (String.isBlank(subDocument.File_Url__c)) {
                continue;
            }
            if (!documentUrlsByProjectId.containsKey(subDocument.Document__r.Project__c)) {
                documentUrlsByProjectId.put(subDocument.Document__r.Project__c, new List<String>());
            }
            List<String> projectDocumentUrls = documentUrlsByProjectId.get(subDocument.Document__r.Project__c);
            // Project images: direct file link, so the app can show the picture itself (the sharing link opens a SharePoint page)
            String imageUrl = SharePointService.directUrl(subDocument.File_Url__c);
            if (!projectDocumentUrls.contains(imageUrl)) {
                projectDocumentUrls.add(imageUrl);
            }
        }
        System.debug('documentUrlsByProjectId :: ' + documentUrlsByProjectId);
        return documentUrlsByProjectId;
    }

    private static Map<String, String> getUnitStatusLabels() {
        Map<String, String> statusLabelByApiValue = new Map<String, String>();
        for (Schema.PicklistEntry picklistEntry : Unit__c.Status__c.getDescribe().getPicklistValues()) {
            statusLabelByApiValue.put(picklistEntry.getValue(), picklistEntry.getLabel());
        }
        return statusLabelByApiValue;
    }

    private static String resolveStatusLabel(String statusApiValue, Map<String, String> statusLabelByApiValue) {
        if (statusApiValue == null) {
            return '';
        }
        return statusLabelByApiValue.containsKey(statusApiValue) ? statusLabelByApiValue.get(statusApiValue) : statusApiValue;
    }

    private static Project__c getProjectFromUnit(Unit__c unit) {
        if (unit.Floor__r == null || unit.Floor__r.Block__r == null) {
            return null;
        }
        return unit.Floor__r.Block__r.Project__r;
    }

    private static Boolean isValidSalesforceId(String recordId) {
        try {
            Id.valueOf(recordId);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static MyPropertiesResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, PropertiesData data) {
        MyPropertiesResponse apiResponse = new MyPropertiesResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class MyPropertiesResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public PropertiesData data;
    }

    public class PropertiesData {
        public List<PropertyWrapper> properties;
        public Map<String, Object> pagination;
    }

    public class PropertyWrapper {
        public String projectId;
        public String projectName;
        public String propertyId;
        public String unitBlockCode;
        public String salesOrderNo;
        public List<String> imageUrls;
        public String status;
    }
}