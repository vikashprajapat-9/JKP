@RestResource(urlMapping='/api/v1/projects/*')
global without sharing class API_ProjectDetails {

    @HttpGet
    global static void getProjectDetails() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            ProjectDetailsResponse result = buildProjectDetailsResponse(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_ProjectDetails.getProjectDetails ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ProjectDetails', 'getProjectDetails', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'An unexpected error occurred while retrieving project details', null)));
        }
    }

    private static ProjectDetailsResponse buildProjectDetailsResponse(RestRequest request) {
        try {
            String projectIdentifier = extractProjectIdentifier(request);
            if (String.isBlank(projectIdentifier)) {
                return createResponse(false, 400, 'Project id is required', null);
            }
            projectIdentifier = projectIdentifier.trim();

            Project__c project = getProjectByIdentifier(projectIdentifier);
            if (project == null) {
                return createResponse(false, 404, 'Project not found', null);
            }
			Address location = project.Project_Location__c;

            ProjectWrapper projectData = new ProjectWrapper();
            projectData.id          = String.valueOf(project.Id);
            projectData.name        = project.Name;
            projectData.city        = location != null ? location.getCity() : null;
            projectData.status      = project.Project_Status__c;
            projectData.media       = getMediaForProject(project.Id);
            projectData.stats       = buildStats(project);
            projectData.description = project.Description__c;
            projectData.specs       = buildSpecs(project);
            projectData.amenities   = getAmenitiesForProject(project.Id);
            projectData.brochureUrl = getBrochureUrlForProject(project.Id);
            // brochureUrl opens the brochure in SharePoint's viewer; brochureDownloadUrl is the direct file link (download)
            projectData.brochureDownloadUrl = SharePointService.directUrl(projectData.brochureUrl);
            projectData.updatedAt   = formatDateTime(project.LastModifiedDate);

            return createResponse(true, 200, 'Project details retrieved successfully', projectData);
        } catch (Exception e) {
            System.debug('Error in API_ProjectDetails.buildProjectDetailsResponse ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ProjectDetails', 'buildProjectDetailsResponse', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'An unexpected error occurred while retrieving project details', null);
        }
    }

    private static String extractProjectIdentifier(RestRequest request) {
        String requestUri = request != null && request.requestURI != null ? request.requestURI : '';
        List<String> uriSegments = requestUri.split('/');
        Integer projectsIndex = uriSegments.indexOf('projects');
        return projectsIndex >= 0 && projectsIndex + 1 < uriSegments.size() ? uriSegments[projectsIndex + 1] : null;
    }

    private static Project__c getProjectByIdentifier(String projectIdentifier) {
        if (!isValidSalesforceId(projectIdentifier)) {
            return null;
        }
        List<Project__c> matchedProjects = [SELECT Id, Name, Project_Status__c, Possession__c, Description__c,Project_Type__c, LastModifiedDate,Project_Location__c FROM Project__c WHERE Id = :projectIdentifier WITH SYSTEM_MODE LIMIT 1];
        return matchedProjects.isEmpty() ? null : matchedProjects[0];
    }

    private static List<MediaWrapper> getMediaForProject(Id projectId) {
        List<MediaWrapper> mediaItems = new List<MediaWrapper>();

        for (Sub_Document__c subDocument : [SELECT Id, Name, File_Url__c FROM Sub_Document__c WHERE Document__r.Project__c = :projectId and Document__r.Name = 'Project Images' WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC]) {
            MediaWrapper mediaItem = new MediaWrapper();
            mediaItem.id    = String.valueOf(subDocument.Id);
            // Direct file link, so the app can show the picture or play the video itself
            mediaItem.url   = SharePointService.directUrl(subDocument.File_Url__c);
            mediaItem.video = isVideoFile(subDocument.Name);
            mediaItems.add(mediaItem);
        }
        return mediaItems;
    }

    private static Boolean isVideoFile(String fileName) {
        if (String.isBlank(fileName) || !fileName.contains('.')) {
            return false;
        }
        String extension = fileName.substringAfterLast('.').toLowerCase();
        Set<String> videoExtensions = new Set<String>{ 'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v' };
        return videoExtensions.contains(extension);
    }

    private static List<StatWrapper> buildStats(Project__c project) {
        List<StatWrapper> stats = new List<StatWrapper>();
        stats.add(buildStat('LKR', null));
        stats.add(buildStat('Possession Date', project.Possession__c));
        stats.add(buildStat('Homes Left', null));
        return stats;
    }

    private static StatWrapper buildStat(String label, Object value) {
        StatWrapper stat = new StatWrapper();
        stat.label = label;
        stat.value = value;
        return stat;
    }

    private static List<SpecWrapper> buildSpecs(Project__c project) {
        List<SpecWrapper> specs = new List<SpecWrapper>();
        specs.add(buildSpec('Area', null));
        specs.add(buildSpec('Slab', null));
        specs.add(buildSpec('Type', project.Project_Type__c));
        specs.add(buildSpec('Type', null));
        specs.add(buildSpec('Tenants', null));
        specs.add(buildSpec('Availability', null));
        return specs;
    }

    private static SpecWrapper buildSpec(String label, Object value) {
        SpecWrapper spec = new SpecWrapper();
        spec.label = label;
        spec.value = value;
        return spec;
    }

    private static List<AmenityWrapper> getAmenitiesForProject(Id projectId) {
        List<AmenityWrapper> amenities = new List<AmenityWrapper>();

        for (Amenties__c amenity : [SELECT Id, Icon__c, Type__c FROM Amenties__c WHERE Project__c = :projectId WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC]) {
            AmenityWrapper amenityItem = new AmenityWrapper();
            amenityItem.icon  = amenity.Icon__c;
            amenityItem.label = amenity.Type__c;
            amenities.add(amenityItem);
        }
        return amenities;
    }

    private static String getBrochureUrlForProject(Id projectId) {
        // List<Document__c> projectDocuments = [
        //     SELECT Id, Name, Project__c
        //     FROM Document__c
        //     WHERE Project__c = :projectId AND Name = 'Project Documents' WITH SYSTEM_MODE
        //     LIMIT 1
        // ];
        // if (projectDocuments.isEmpty()) {
        //     return null;
        // }

        for (Sub_Document__c subDocument : [SELECT Id, Name, File_Url__c FROM Sub_Document__c WHERE Name != null AND File_Url__c != null AND Document__r.Name = 'Project Documents' and Document__r.Project__c = :projectId  WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC]) {
            if (subDocument.Name.toLowerCase().contains('brochure')) {
                return subDocument.File_Url__c;
            }
        }
        return null;
    }

    private static Boolean isValidSalesforceId(String recordId) {
        try {
            Id.valueOf(recordId);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static String formatDateTime(Datetime value) {
        return value == null ? null : value.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'', 'UTC');
    }

    private static ProjectDetailsResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, ProjectWrapper data) {
        ProjectDetailsResponse apiResponse = new ProjectDetailsResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class ProjectDetailsResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public ProjectWrapper data;
    }

    public class ProjectWrapper {
        public String id;
        public String name;
        public String city;
        public String status;
        public List<MediaWrapper> media;
        public List<StatWrapper> stats;
        public String description;
        public List<SpecWrapper> specs;
        public List<AmenityWrapper> amenities;
        public String brochureUrl;
        public String brochureDownloadUrl;
        public String updatedAt;
    }

    public class MediaWrapper {
        public String id;
        public String url;
        public Boolean video;
    }

    public class StatWrapper {
        public String label;
        public Object value;
    }

    public class SpecWrapper {
        public String label;
        public Object value;
    }

    public class AmenityWrapper {
        public String icon;
        public String label;
    }
}