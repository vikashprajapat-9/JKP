@RestResource(urlMapping='/api/v1/projects')
global without sharing class API_Projects {

    private static final Integer DEFAULT_OFFSET = 0;
    private static final Integer DEFAULT_LIMIT  = 10;
    private static final Integer MAX_LIMIT      = 100;

    private static final Set<String> VIDEO_EXTENSIONS = new Set<String>{'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'};

    @HttpGet
    global static void getProjects() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            ProjectsResponse result = buildProjectsResponse(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_Projects.getProjects ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_Projects', 'getProjects', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(500, false, 'Failed to retrieve projects', null)));
        }
    }

    private static ProjectsResponse buildProjectsResponse(RestRequest request) {
        Map<String, String> params = request != null && request.params != null ? request.params : new Map<String, String>();

        Integer offsetValue = parseInteger(params.get('offsetValue'), DEFAULT_OFFSET);
        Integer limitValue  = parseInteger(params.get('limitValue'), DEFAULT_LIMIT);
        if (offsetValue == null || limitValue == null || limitValue <= 0) {
            return createResponse(400, false, 'Invalid pagination parameters', null);
        }
        limitValue = Math.min(limitValue, MAX_LIMIT);

        String statusParam = params.get('status');
        if (String.isBlank(statusParam)) {
            return createResponse(400, false, 'status parameter is required', null);
        }
        statusParam = statusParam.trim().toLowerCase();
        if (statusParam != 'upcoming' && statusParam != 'current') {
            return createResponse(400, false, 'Invalid status parameter. Allowed values: upcoming, current', null);
        }

        String upcomingStatusValue = getPicklistValueByName(Project__c.Project_Status__c, 'Upcoming');

        Integer totalCount;
        List<Project__c> projects;

        if (statusParam == 'upcoming') {
            if (upcomingStatusValue == null) {
                totalCount = 0;
                projects   = new List<Project__c>();
            } else {
                totalCount = [SELECT COUNT() FROM Project__c WHERE Project_Status__c = :upcomingStatusValue WITH SYSTEM_MODE];
                projects = [SELECT Id, Name, Project_Location__c, Project_Status__c, Possession__c, Description__c FROM Project__c WHERE Project_Status__c = :upcomingStatusValue WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC LIMIT :limitValue OFFSET :offsetValue];
            }
        } else {
            if (upcomingStatusValue == null) {
                totalCount = [SELECT COUNT() FROM Project__c WITH SYSTEM_MODE];
                projects = [SELECT Id, Name, Project_Location__c, Project_Status__c, Possession__c, Description__c FROM Project__c WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC LIMIT :limitValue OFFSET :offsetValue];
            } else {
                totalCount = [SELECT COUNT() FROM Project__c WHERE Project_Status__c != :upcomingStatusValue WITH SYSTEM_MODE];
                projects = [SELECT Id, Name, Project_Location__c, Project_Status__c, Possession__c, Description__c FROM Project__c WHERE Project_Status__c != :upcomingStatusValue WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC LIMIT :limitValue OFFSET :offsetValue];
            }
        }

        Set<Id> projectIds = new Map<Id, Project__c>(projects).keySet();

        Map<Id, List<MediaWrapper>> mediaByProjectId = new Map<Id, List<MediaWrapper>>();
        for (Sub_Document__c subDocument : [SELECT Id, Name, Document__r.Project__c, File_Url__c FROM Sub_Document__c WHERE Document__r.Project__c IN :projectIds AND Document__r.Name = 'Project Images' AND File_Url__c != null WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC]) {
            if (!mediaByProjectId.containsKey(subDocument.Document__r.Project__c)) {
                mediaByProjectId.put(subDocument.Document__r.Project__c, new List<MediaWrapper>());
            }
            MediaWrapper media = new MediaWrapper();
            media.id    = String.valueOf(subDocument.Id);
            // Direct file link, so the app can show the picture or play the video itself
            media.url   = SharePointService.directUrl(subDocument.File_Url__c);
            media.video = VIDEO_EXTENSIONS.contains(getFileExtension(subDocument.Name));
            mediaByProjectId.get(subDocument.Document__r.Project__c).add(media);
        }

        ProjectsData data = new ProjectsData();
        data.items = new List<ProjectWrapper>();

        for (Project__c project : projects) {
            Address location = project.Project_Location__c;

            StatWrapper possessionStat = new StatWrapper();
            possessionStat.label = 'Possession Date';
            possessionStat.value = project.Possession__c != null ? Datetime.newInstance(project.Possession__c, Time.newInstance(0, 0, 0, 0)).format('MMMM yyyy') : null;

            StatWrapper homesLeftStat = new StatWrapper();
            homesLeftStat.label = 'Homes Left';
            homesLeftStat.value = null;

            ProjectWrapper item = new ProjectWrapper();
            item.id          = String.valueOf(project.Id);
            item.name        = project.Name;
            item.city        = location != null ? location.getCity() : null;
            item.status      = project.Project_Status__c;
            item.media       = mediaByProjectId.containsKey(project.Id) ? mediaByProjectId.get(project.Id) : new List<MediaWrapper>();
           item.stats       = new List<StatWrapper>{ possessionStat, homesLeftStat };
		//    item.stats       = new List<StatWrapper>{ possessionStat };
            item.description = project.Description__c;
            data.items.add(item);
        }

        PaginationWrapper pagination = new PaginationWrapper();
        pagination.hasMore     = (offsetValue + projects.size()) < totalCount;
        pagination.limitValue  = limitValue;
        pagination.offsetValue = offsetValue;
        pagination.totalCount  = totalCount;
        data.pagination = pagination;

        return createResponse(200, true, 'Projects retrieved successfully', data);
    }

    private static Integer parseInteger(String rawValue, Integer defaultValue) {
        if (String.isBlank(rawValue)) {
            return defaultValue;
        }
        String trimmed = rawValue.trim();
        return trimmed.isNumeric() ? Integer.valueOf(trimmed) : null;
    }

    private static String getFileExtension(String fileName) {
        if (String.isBlank(fileName)) {
            return '';
        }
        String trimmed = fileName.trim();
        Integer lastDot = trimmed.lastIndexOf('.');
        if (lastDot <= 0 || lastDot == trimmed.length() - 1) {
            return '';
        }
        return trimmed.substring(lastDot + 1).toLowerCase();
    }

    private static String getPicklistValueByName(Schema.SObjectField field, String targetName) {
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue().equalsIgnoreCase(targetName)) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static ProjectsResponse createResponse(Integer statusCode, Boolean success, String message, ProjectsData data) {
        ProjectsResponse response = new ProjectsResponse();
        response.statusCode = statusCode;
        response.success    = success;
        response.message    = message;
        response.data       = data;
        return response;
    }

    public class ProjectsResponse {
        public Integer statusCode;
        public Boolean success;
        public String message;
        public ProjectsData data;
    }

    public class ProjectsData {
        public List<ProjectWrapper> items;
        public PaginationWrapper pagination;
    }

    public class ProjectWrapper {
        public String id;
        public String name;
        public String city;
        public String status;
        public List<MediaWrapper> media;
        public List<StatWrapper> stats;
        public String description;
    }

    public class MediaWrapper {
        public String id;
        public String url;
        public Boolean video;
    }

    public class StatWrapper {
        public String label;
        public String value;
    }

    public class PaginationWrapper {
        public Boolean hasMore;
        public Integer limitValue;
        public Integer offsetValue;
        public Integer totalCount;
    }
}