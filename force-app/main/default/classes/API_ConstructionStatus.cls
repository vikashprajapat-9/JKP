@RestResource(urlMapping='/api/v1/properties/construction-status')
global without sharing class API_ConstructionStatus {

    @HttpGet
    global static void getConstructionStatus() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            ConstructionStatusResponse result = buildConstructionStatusResponse(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_ConstructionStatus.getConstructionStatus ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ConstructionStatus', 'getConstructionStatus', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'An unexpected error occurred while retrieving construction status', null)));
        }
    }

    private static ConstructionStatusResponse buildConstructionStatusResponse(RestRequest request) {
        try {
            String userId = request != null && request.params != null ? request.params.get('userId') : null;
            userId = userId != null ? userId.trim() : null;

            if (String.isBlank(userId)) {
                return createResponse(false, 400, 'userId is required', null);
            }

            return getConstructionStatusData(userId);
        } catch (Exception e) {
            System.debug('Error in API_ConstructionStatus.buildConstructionStatusResponse ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ConstructionStatus', 'buildConstructionStatusResponse', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'An unexpected error occurred while retrieving construction status', null);
        }
    }

    private static ConstructionStatusResponse getConstructionStatusData(String userId) {
        List<User> matchedUsers = [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
        if (matchedUsers.isEmpty()) {
            return createResponse(false, 404, 'User not found', null);
        }

        ConstructionStatusData statusData = new ConstructionStatusData();
        statusData.properties = new List<ConstructionPropertyWrapper>();

        Id accountId = matchedUsers[0].Contact != null ? matchedUsers[0].Contact.AccountId : null;
        if (accountId == null) {
            return createResponse(true, 200, 'Construction status list retrieved successfully', statusData);
        }

        Set<Id> relatedUnitIds = new Set<Id>();
        for (Opportunity opportunity : [SELECT Id, Unit__c FROM Opportunity WHERE AccountId = :accountId AND Unit__c != null WITH SYSTEM_MODE]) {
            relatedUnitIds.add(opportunity.Unit__c);
        }
        if (relatedUnitIds.isEmpty()) {
            return createResponse(true, 200, 'Construction status list retrieved successfully', statusData);
        }

        Map<Id, Unit__c> unitById = new Map<Id, Unit__c>([SELECT Id, Unit_Name_Code__c,Floor__r.Block__r.Block_Code__c,Floor__r.Block__r.Project__r.Id,Floor__r.Block__r.Project__r.Name,Floor__r.Block__r.Project__r.Completion_Percentage__c , Floor__r.Block__r.Project__r.Description__c FROM Unit__c WHERE Id IN :relatedUnitIds WITH SYSTEM_MODE]);
        if (unitById.isEmpty()) {
            return createResponse(true, 200, 'Construction status list retrieved successfully', statusData);
        }

        Set<Id> projectIds = new Set<Id>();
        for (Unit__c unit : unitById.values()) {
            Project__c project = getProjectFromUnit(unit);
            if (project != null) {
                projectIds.add(project.Id);
            }
        }

        Map<Id, List<String>> thumbnailUrlsByProjectId = getThumbnailUrlsByProjectId(projectIds);

        for (Unit__c unit : unitById.values()) {
            Project__c project = getProjectFromUnit(unit);
            List<String> thumbnailUrls = project != null ? thumbnailUrlsByProjectId.get(project.Id) : null;

            ConstructionPropertyWrapper propertyItem = new ConstructionPropertyWrapper();
            propertyItem.id                 = unit.Id;
            propertyItem.projectId          = project != null ? String.valueOf(project.Id) : null;
            propertyItem.propertyName       = project != null ? project.Name : null;
            propertyItem.unitNumber         = unit.Unit_Name_Code__c;
            propertyItem.block              = unit.Floor__r != null && unit.Floor__r.Block__r != null? unit.Floor__r.Block__r.Block_Code__c: null;
            propertyItem.thumbnailUrls      = thumbnailUrls != null ? thumbnailUrls : new List<String>();
            propertyItem.progressPercentage = project != null ? project.Completion_Percentage__c : null;
            propertyItem.description        = project != null ? project.Description__c : null;
            statusData.properties.add(propertyItem);
        }

        return createResponse(true, 200, 'Construction status list retrieved successfully', statusData);
    }

    private static Map<Id, List<String>> getThumbnailUrlsByProjectId(Set<Id> projectIds) {
        Map<Id, List<String>> thumbnailUrlsByProjectId = new Map<Id, List<String>>();
        if (projectIds.isEmpty()) {
            return thumbnailUrlsByProjectId;
        }
        for (Sub_Document__c subDocument : [SELECT Id, Project__c, File_Url__c FROM Sub_Document__c WHERE Project__c IN :projectIds AND File_Url__c != null WITH SYSTEM_MODE ORDER BY CreatedDate ASC]) {
            if (String.isBlank(subDocument.File_Url__c)) {
                continue;
            }
            if (!thumbnailUrlsByProjectId.containsKey(subDocument.Project__c)) {
                thumbnailUrlsByProjectId.put(subDocument.Project__c, new List<String>());
            }
            List<String> projectThumbnailUrls = thumbnailUrlsByProjectId.get(subDocument.Project__c);
            if (!projectThumbnailUrls.contains(subDocument.File_Url__c)) {
                projectThumbnailUrls.add(subDocument.File_Url__c);
            }
        }
        return thumbnailUrlsByProjectId;
    }

    private static Project__c getProjectFromUnit(Unit__c unit) {
        if (unit.Floor__r == null || unit.Floor__r.Block__r == null) {
            return null;
        }
        return unit.Floor__r.Block__r.Project__r;
    }

    private static ConstructionStatusResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, ConstructionStatusData data) {
        ConstructionStatusResponse apiResponse = new ConstructionStatusResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class ConstructionStatusResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public ConstructionStatusData data;
    }

    public class ConstructionStatusData {
        public List<ConstructionPropertyWrapper> properties;
    }

    public class ConstructionPropertyWrapper {
        public String id;
        public String projectId;
        public String propertyName;
        public String unitNumber;
        public String block;
        public List<String> thumbnailUrls;
        public Decimal progressPercentage;
        public String description;
    }
}