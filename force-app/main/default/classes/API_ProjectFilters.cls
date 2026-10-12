@RestResource(urlMapping='/api/v1/project-filters')
global without sharing class API_ProjectFilters {

    @HttpGet
    global static void getProjectFilters() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            ProjectFiltersResponse result = buildProjectFiltersResponse(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_ProjectFilters.getProjectFilters ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ProjectFilters', 'getProjectFilters', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(
                createResponse(false, 500, 'An unexpected error occurred while retrieving project filters', null)
            ));
        }
    }

    private static ProjectFiltersResponse buildProjectFiltersResponse(RestRequest request) {
        try {
            Map<String, String> requestParams = request != null && request.params != null ? request.params : new Map<String, String>();

            String userId = UserInfo.getUserId();

            Integer offsetValue = requestParams.containsKey('offsetValue') && String.isNotBlank(requestParams.get('offsetValue'))? Integer.valueOf(requestParams.get('offsetValue')): 0;
            Integer limitValue = requestParams.containsKey('limitValue') && String.isNotBlank(requestParams.get('limitValue'))? Integer.valueOf(requestParams.get('limitValue')): 20;
            if (offsetValue == null || offsetValue < 0) {
                offsetValue = 0;
            }
            if (limitValue == null || limitValue <= 0) {
                limitValue = 20;
            }

            return getProjectFiltersData(userId, offsetValue, limitValue);
        } catch (Exception e) {
            System.debug('Error in API_ProjectFilters.buildProjectFiltersResponse ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ProjectFilters', 'buildProjectFiltersResponse', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'An unexpected error occurred while retrieving project filters', null);
        }
    }

    private static ProjectFiltersResponse getProjectFiltersData(String userId, Integer offsetValue, Integer limitValue) {
        List<User> matchedUsers = [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :userId LIMIT 1];
        if (matchedUsers.isEmpty()) {
            return createResponse(false, 404, 'User not found', null);
        }

        ProjectFiltersData filtersData = new ProjectFiltersData();
        filtersData.filterOptions = new List<FilterOption>();

        Id accountId = matchedUsers[0].Contact != null ? matchedUsers[0].Contact.AccountId : null;
        if (accountId == null) {
            filtersData.filterOptions.add(new FilterOption('All Projects', 'ALL'));
            filtersData.pagination = buildPagination(0, offsetValue, limitValue, 0);
            return createResponse(true, 200, 'Project filters retrieved successfully', filtersData);
        }

        Set<Id> relatedUnitIds = new Set<Id>();
        for (Opportunity opportunity : [SELECT Id, Unit__c FROM Opportunity WHERE AccountId = :accountId AND Unit__c != null WITH SYSTEM_MODE]) {
            relatedUnitIds.add(opportunity.Unit__c);
        }
        if (relatedUnitIds.isEmpty()) {
            filtersData.filterOptions.add(new FilterOption('All Projects', 'ALL'));
            filtersData.pagination = buildPagination(0, offsetValue, limitValue, 0);
            return createResponse(true, 200, 'Project filters retrieved successfully', filtersData);
        }

        List<Unit__c> relatedUnits = [SELECT Id, Floor__r.Block__r.Project__r.Id, Floor__r.Block__r.Project__r.Name FROM Unit__c WHERE Id IN :relatedUnitIds WITH SYSTEM_MODE];

        Map<String, FilterOption> filterOptionByProjectId = new Map<String, FilterOption>();
        for (Unit__c unit : relatedUnits) {
            Project__c project = getProjectFromUnit(unit);
            if (project == null) {
                continue;
            }
            String projectKey = String.valueOf(project.Id);
            if (!filterOptionByProjectId.containsKey(projectKey)) {
                String projectLabel = String.isNotBlank(project.Name) ? project.Name : projectKey;
                filterOptionByProjectId.put(projectKey, new FilterOption(projectLabel, projectKey));
            }
        }

        List<FilterOption> allProjectOptions = filterOptionByProjectId.values();
        Integer totalCount = allProjectOptions.size();

        List<FilterOption> pagedProjectOptions = new List<FilterOption>();
        for (Integer index = offsetValue; index < allProjectOptions.size() && pagedProjectOptions.size() < limitValue; index++) {
            pagedProjectOptions.add(allProjectOptions[index]);
        }

        if (offsetValue == 0) {
            filtersData.filterOptions.add(new FilterOption('All Projects', 'ALL'));
        }
        filtersData.filterOptions.addAll(pagedProjectOptions);
        filtersData.pagination = buildPagination(totalCount, offsetValue, limitValue, pagedProjectOptions.size());

        return createResponse(true, 200, 'Project filters retrieved successfully', filtersData);
    }

    private static Map<String, Object> buildPagination(Integer totalCount, Integer offsetValue, Integer limitValue, Integer returnedCount) {
        return new Map<String, Object>{
            'totalCount'  => totalCount,
            'offsetValue' => offsetValue + limitValue,
            'limitValue'  => limitValue,
            'hasMore'     => (offsetValue + returnedCount) < totalCount
        };
    }

    private static Project__c getProjectFromUnit(Unit__c unit) {
        if (unit.Floor__r == null || unit.Floor__r.Block__r == null) {
            return null;
        }
        return unit.Floor__r.Block__r.Project__r;
    }

    private static ProjectFiltersResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, ProjectFiltersData data) {
        ProjectFiltersResponse apiResponse = new ProjectFiltersResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class ProjectFiltersResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public ProjectFiltersData data;
    }

    public class ProjectFiltersData {
        public List<FilterOption> filterOptions;
        public Map<String, Object> pagination;
    }

    public class FilterOption {
        public String label;
        public String value;

        public FilterOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}