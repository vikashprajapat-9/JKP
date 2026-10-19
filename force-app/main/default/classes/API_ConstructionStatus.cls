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
            String userId = UserInfo.getUserId();
            userId = userId != null ? userId.trim() : null;

            if (String.isBlank(userId)) {
                return createResponse(false, 400, 'userId is required', null);
            }

            Map<String, String> requestParams = request != null && request.params != null ? request.params : new Map<String, String>();
            Integer offsetValue = parsePositiveInteger(requestParams.get('offsetValue'), 0, true);
            Integer limitValue  = parsePositiveInteger(requestParams.get('limitValue'), 20, false);

            return getConstructionStatusData(userId, offsetValue, limitValue);
        } catch (Exception e) {
            System.debug('Error in API_ConstructionStatus.buildConstructionStatusResponse ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ConstructionStatus', 'buildConstructionStatusResponse', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'An unexpected error occurred while retrieving construction status', null);
        }
    }

    private static Integer parsePositiveInteger(String rawValue, Integer defaultValue, Boolean allowZero) {
        if (String.isBlank(rawValue) || !rawValue.trim().isNumeric()) {
            return defaultValue;
        }
        Integer parsed = Integer.valueOf(rawValue.trim());
        if (parsed < 0 || (parsed == 0 && !allowZero)) {
            return defaultValue;
        }
        return parsed;
    }

    private static ConstructionStatusResponse getConstructionStatusData(String userId, Integer offsetValue, Integer limitValue) {
        List<User> matchedUsers = [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
        if (matchedUsers.isEmpty()) {
            return createResponse(false, 404, 'User not found', null);
        }

        ConstructionStatusData statusData = new ConstructionStatusData();
        statusData.properties = new List<ConstructionPropertyWrapper>();
        statusData.pagination = buildPagination(0, offsetValue, limitValue, 0);

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

        Set<Id> projectIds = new Set<Id>();
        Map<Id, Unit__c> firstUnitByProjectId = new Map<Id, Unit__c>();
        Map<Id, Set<String>> blockCodesByProjectId = new Map<Id, Set<String>>();

        for (Unit__c unit : [SELECT Id, Unit_Name_Code__c,Floor__r.Block__r.Block_Code__c,Floor__r.Block__r.Project__c FROM Unit__c WHERE Id IN :relatedUnitIds WITH SYSTEM_MODE ORDER BY Unit_Name_Code__c ASC, Id ASC]) {
            Id projectId = getProjectIdFromUnit(unit);
            if (projectId == null) {
                continue; 
            }
            projectIds.add(projectId);

            if (!firstUnitByProjectId.containsKey(projectId)) {
                firstUnitByProjectId.put(projectId, unit);
                blockCodesByProjectId.put(projectId, new Set<String>());
            }

            String blockCode = unit.Floor__r != null && unit.Floor__r.Block__r != null ? unit.Floor__r.Block__r.Block_Code__c : null;
            if (String.isNotBlank(blockCode)) {
                blockCodesByProjectId.get(projectId).add(blockCode.trim()); 
            }
        }
        if (projectIds.isEmpty()) {
            return createResponse(true, 200, 'Construction status list retrieved successfully', statusData);
        }

        Integer totalCount = [SELECT COUNT() FROM Project__c WHERE Id IN :projectIds WITH SYSTEM_MODE];

        List<Project__c> pagedProjects = [SELECT Id, Name, Completion_Percentage__c, Description__c FROM Project__c WHERE Id IN :projectIds WITH SYSTEM_MODE ORDER BY Name ASC, Id ASC LIMIT :limitValue OFFSET :offsetValue];

        statusData.pagination = buildPagination(totalCount, offsetValue, limitValue, pagedProjects.size());

        if (pagedProjects.isEmpty()) {
            return createResponse(true, 200, 'Construction status list retrieved successfully', statusData);
        }

        Map<Id, List<String>> thumbnailUrlsByProjectId = getThumbnailUrlsByProjectId(new Map<Id, Project__c>(pagedProjects).keySet());

        for (Project__c project : pagedProjects) {
            Unit__c firstUnit = firstUnitByProjectId.get(project.Id);
            List<String> thumbnailUrls = thumbnailUrlsByProjectId.get(project.Id);

            ConstructionPropertyWrapper propertyItem = new ConstructionPropertyWrapper();
            propertyItem.id                 = firstUnit != null ? firstUnit.Id : null;                  // first unit of the project
            propertyItem.projectId          = String.valueOf(project.Id);
            propertyItem.propertyName       = project.Name;
            propertyItem.unitNumber         = firstUnit != null ? firstUnit.Unit_Name_Code__c : null;   // first unit of the project
            propertyItem.block              = buildBlockCodes(blockCodesByProjectId.get(project.Id));
            propertyItem.thumbnailUrls      = thumbnailUrls != null ? thumbnailUrls : new List<String>();
            propertyItem.progressPercentage = project.Completion_Percentage__c;
            propertyItem.description        = project.Description__c;
            statusData.properties.add(propertyItem);
        }

        return createResponse(true, 200, 'Construction status list retrieved successfully', statusData);
    }

    private static Map<String, Object> buildPagination(Integer totalCount, Integer offsetValue, Integer limitValue, Integer returnedCount) {
        return new Map<String, Object>{
            'totalCount'  => totalCount,
            'offsetValue' => offsetValue + limitValue,
            'limitValue'  => limitValue,
            'hasMore'     => (offsetValue + returnedCount) < totalCount
        };
    }

    private static String buildBlockCodes(Set<String> blockCodes) {
        if (blockCodes == null || blockCodes.isEmpty()) {
            return null;
        }
        List<String> sortedCodes = new List<String>(blockCodes);
        sortedCodes.sort();
        return String.join(sortedCodes, ', ');
    }

    private static Map<Id, List<String>> getThumbnailUrlsByProjectId(Set<Id> projectIds) {
        Map<Id, List<String>> thumbnailUrlsByProjectId = new Map<Id, List<String>>();
        if (projectIds.isEmpty()) {
            return thumbnailUrlsByProjectId;
        }
        for (Sub_Document__c subDocument : [SELECT Id, Document__r.Project__c, File_Url__c FROM Sub_Document__c WHERE Document__r.Project__c IN :projectIds AND Document__r.Name = 'Project Images' AND File_Url__c != null WITH SYSTEM_MODE ORDER BY CreatedDate ASC]) {
            if (String.isBlank(subDocument.File_Url__c)) {
                continue;
            }
            if (!thumbnailUrlsByProjectId.containsKey(subDocument.Document__r.Project__c)) {
                thumbnailUrlsByProjectId.put(subDocument.Document__r.Project__c, new List<String>());
            }
            List<String> projectThumbnailUrls = thumbnailUrlsByProjectId.get(subDocument.Document__r.Project__c);
            // Direct file link, so the app can show the picture itself (the sharing link opens a SharePoint page)
            String thumbnailUrl = SharePointService.directUrl(subDocument.File_Url__c);
            if (!projectThumbnailUrls.contains(thumbnailUrl)) {
                projectThumbnailUrls.add(thumbnailUrl);
            }
        }
        return thumbnailUrlsByProjectId;
    }

    private static Id getProjectIdFromUnit(Unit__c unit) {
        if (unit.Floor__r == null || unit.Floor__r.Block__r == null) {
            return null;
        }
        return unit.Floor__r.Block__r.Project__c;
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
        public Map<String, Object> pagination;
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