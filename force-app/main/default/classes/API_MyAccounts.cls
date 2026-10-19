@RestResource(urlMapping='/api/v1/my-accounts')
global without sharing class API_MyAccounts {

    @HttpGet
    global static void getMyAccounts() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            String userId = UserInfo.getUserId();
            MyAccountsResponse result = getMyAccountsData(userId, request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_MyAccounts.getMyAccounts ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_MyAccounts', 'getMyAccounts', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'Failed to retrieve property accounts', null)));
        }
    }

    private static MyAccountsResponse getMyAccountsData(String userId, RestRequest request) {
        try {
            if (String.isBlank(userId)) {
                return createResponse(false, 400, 'Unable to identify the authenticated user', null);
            }

            Map<String, String> requestParams = request != null && request.params != null ? request.params : new Map<String, String>();
            Integer offsetValue = requestParams.containsKey('offsetValue') && String.isNotBlank(requestParams.get('offsetValue'))? Integer.valueOf(requestParams.get('offsetValue')) : 0;
            Integer limitValue = requestParams.containsKey('limitValue') && String.isNotBlank(requestParams.get('limitValue'))? Integer.valueOf(requestParams.get('limitValue')) : 20;
            if (offsetValue == null || offsetValue < 0) {
                offsetValue = 0;
            }
            if (limitValue == null || limitValue <= 0) {
                limitValue = 20;
            }

            Id projectId = null;
            String projectParam = requestParams.get('projectId');
            if (String.isNotBlank(projectParam) && !projectParam.trim().equalsIgnoreCase('ALL')) {
                try {
                    projectId = Id.valueOf(projectParam.trim());
                } catch (Exception e) {
                    return createResponse(false, 400, 'Invalid projectId', null);
                }
                if (projectId.getSObjectType() != Project__c.SObjectType) {
                    return createResponse(false, 400, 'Invalid projectId', null);
                }
            }

            List<User> matchedUsers = [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
            if (matchedUsers.isEmpty()) {
                return createResponse(false, 404, 'User not found', null);
            }

            MyAccountsData accountsData = new MyAccountsData();
            accountsData.projects   = new List<ProjectFilterWrapper>{new ProjectFilterWrapper('All Projects', 'ALL')};
            accountsData.properties = new List<PropertyWrapper>();

            Id accountId = matchedUsers[0].Contact != null ? matchedUsers[0].Contact.AccountId : null;
            if (accountId == null) {
                accountsData.pagination = buildPagination(0, offsetValue, limitValue, 0);
                return createResponse(true, 200, 'Property accounts retrieved successfully', accountsData);
            }

            Set<Id> relatedUnitIds = new Set<Id>();
            for (Opportunity opportunity : [SELECT Id, Unit__c FROM Opportunity WHERE AccountId = :accountId AND Unit__c != null WITH SYSTEM_MODE]) {
                relatedUnitIds.add(opportunity.Unit__c);
            }
            if (relatedUnitIds.isEmpty()) {
                accountsData.pagination = buildPagination(0, offsetValue, limitValue, 0);
                return createResponse(true, 200, 'Property accounts retrieved successfully', accountsData);
            }

            Map<Id, Unit__c> allUnitsById = new Map<Id, Unit__c>([SELECT Id, Unit_Name_Code__c, Floor__r.Block__r.Project__r.Id,Floor__r.Block__r.Project__r.Name, Floor__r.Block__r.Project__r.Project_Code__c FROM Unit__c WHERE Id IN :relatedUnitIds WITH SYSTEM_MODE]);
            if (allUnitsById.isEmpty()) {
                accountsData.pagination = buildPagination(0, offsetValue, limitValue, 0);
                return createResponse(true, 200, 'Property accounts retrieved successfully', accountsData);
            }

            Map<String, ProjectFilterWrapper> filterOptionByProjectCode = new Map<String, ProjectFilterWrapper>();
            for (Unit__c unit : allUnitsById.values()) {
                Project__c project = getProjectFromUnit(unit);
                if (project == null) {
                    continue;
                }
                String projectCode = project.Project_Code__c;
                if (String.isNotBlank(projectCode) && !filterOptionByProjectCode.containsKey(projectCode)) {
                    filterOptionByProjectCode.put(projectCode, new ProjectFilterWrapper(project.Name, projectCode));
                }
            }
            accountsData.projects.addAll(filterOptionByProjectCode.values());

            String whereClause = ' FROM Unit__c WHERE Id IN :relatedUnitIds';
            Map<String, Object> binds = new Map<String, Object>{ 'relatedUnitIds' => relatedUnitIds };
            if (projectId != null) {
                whereClause += ' AND Floor__r.Block__r.Project__c = :projectId';
                binds.put('projectId', projectId);
            }

            Integer totalCount = Database.countQueryWithBinds('SELECT COUNT()' + whereClause, binds, AccessLevel.SYSTEM_MODE);

            binds.put('limitValue', limitValue);
            binds.put('offsetValue', offsetValue);
            List<Unit__c> pagedUnits = (List<Unit__c>) Database.queryWithBinds(
                'SELECT Id, Unit_Name_Code__c, Floor__r.Block__r.Project__r.Id, Floor__r.Block__r.Project__r.Name, Floor__r.Block__r.Project__r.Project_Code__c' +
                whereClause +
                ' ORDER BY Unit_Name_Code__c LIMIT :limitValue OFFSET :offsetValue',
                binds,AccessLevel.SYSTEM_MODE);

            accountsData.pagination = buildPagination(totalCount, offsetValue, limitValue, pagedUnits.size());

            if (pagedUnits.isEmpty()) {
                return createResponse(true, 200, 'Property accounts retrieved successfully', accountsData);
            }

            Set<Id> pagedProjectIds = new Set<Id>();
            for (Unit__c unit : pagedUnits) {
                Project__c project = getProjectFromUnit(unit);
                if (project != null) {
                    pagedProjectIds.add(project.Id);
                }
            }

            Map<Id, List<String>> thumbnailUrlsByProjectId = getThumbnailUrlsByProjectId(pagedProjectIds);

            for (Unit__c unit : pagedUnits) {
                Project__c project = getProjectFromUnit(unit);
                List<String> thumbnailUrls = project != null ? thumbnailUrlsByProjectId.get(project.Id) : null;

                PropertyWrapper propertyItem = new PropertyWrapper();
                propertyItem.id            = accountId;
                propertyItem.projectId     = project != null ? project.Project_Code__c : null;
                propertyItem.propertyName  = project != null ? project.Name : null;
                propertyItem.unitNumber    = unit.Unit_Name_Code__c;
                propertyItem.thumbnailUrls = thumbnailUrls != null ? thumbnailUrls : new List<String>();
                accountsData.properties.add(propertyItem);
            }

            return createResponse(true, 200, 'Property accounts retrieved successfully', accountsData);
        } catch (Exception e) {
            System.debug('Error in API_MyAccounts.getMyAccountsData ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_MyAccounts', 'getMyAccountsData', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'Failed to retrieve property accounts', null);
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

    private static Project__c getProjectFromUnit(Unit__c unit) {
        if (unit.Floor__r == null || unit.Floor__r.Block__r == null) {
            return null;
        }
        return unit.Floor__r.Block__r.Project__r;
    }

    private static MyAccountsResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, MyAccountsData data) {
        MyAccountsResponse apiResponse = new MyAccountsResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class MyAccountsResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public MyAccountsData data;
    }

    public class MyAccountsData {
        public List<ProjectFilterWrapper> projects;
        public List<PropertyWrapper> properties;
        public Map<String, Object> pagination;
    }

    public class ProjectFilterWrapper {
        public String label;
        public String value;

        public ProjectFilterWrapper(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class PropertyWrapper {
        public String id;
        public String projectId;
        public String propertyName;
        public String unitNumber;
        public List<String> thumbnailUrls;
    }
}