@RestResource(urlMapping='/api/v1/dashboard')
global without sharing class API_Dashboard {

    private static final String PROJECT_IMAGES_DOCUMENT_NAME = 'Project Images';

    private static final String SUPPORT_KEY      = 'support';
    private static final String SUPPORT_TITLE    = 'Support';
    private static final String SUPPORT_UNIT     = 'count';
    private static final String SUPPORT_LABEL    = 'Pending';
    private static final String SUPPORT_PENDING  = 'Pending';

    private static final String HANDOVER_KEY     = 'handover';
    private static final String HANDOVER_TITLE   = 'Handover';
    private static final String HANDOVER_UNIT    = 'percent';
    private static final String HANDOVER_LABEL   = 'Complete';
    private static final String HANDOVER_STATUS  = 'In Progress';
    private static final Integer HANDOVER_DUMMY_PROGRESS = 27;

    @HttpGet
    global static void getDashboard() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            DashboardData data = buildDashboard(UserInfo.getUserId());
            response.statusCode   = 200;
            response.responseBody = Blob.valueOf(JSON.serialize(
                wrap(200, true, 'Dashboard retrieved successfully', data)
            ));
        } catch (Exception e) {
            System.debug('Error in API_Dashboard.getDashboard ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_Dashboard', 'getDashboard', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(
                wrap(500, false, 'Failed to retrieve dashboard', null)
            ));
        }
    }

    private static DashboardData buildDashboard(Id userId) {
        List<User> users = [SELECT Id, Name, Contact.AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
        Id accountId = (users.isEmpty() || users[0].Contact == null) ? null : users[0].Contact.AccountId;

        DashboardData data = new DashboardData();
        data.customer = new CustomerWrapper();
        data.customer.name  = users.isEmpty() ? null : users[0].Name;
        data.customer.asOf  = String.valueOf(Date.today());
        data.carousel       = new List<CarouselItem>();
        data.progress       = new List<ProgressSection>();

        Map<Id, String> projectNameById        = new Map<Id, String>();
        Map<Id, Set<Id>> unitIdsByProject      = new Map<Id, Set<Id>>();
        Map<Id, Id> projectIdByUnit            = new Map<Id, Id>();
        Set<Id> allUnitIds                     = new Set<Id>();

        if (accountId != null) {
            for (Opportunity opp : [SELECT Id, Unit__c,Unit__r.Floor__r.Block__r.Project__c,Unit__r.Floor__r.Block__r.Project__r.Name FROM Opportunity WHERE AccountId = :accountId AND Unit__c != null WITH SYSTEM_MODE ORDER BY Unit__c ASC, Id ASC]) {
                Id projectId = opp.Unit__r?.Floor__r?.Block__r?.Project__c;
                if (projectId == null) {
                    continue;
                }
                projectNameById.put(projectId, opp.Unit__r.Floor__r.Block__r.Project__r?.Name);
                if (!unitIdsByProject.containsKey(projectId)) {
                    unitIdsByProject.put(projectId, new Set<Id>());
                }
                unitIdsByProject.get(projectId).add(opp.Unit__c);
                projectIdByUnit.put(opp.Unit__c, projectId);
                allUnitIds.add(opp.Unit__c);
            }
        }

        List<String> sortKeys = new List<String>();
        Map<String, Id> projectIdBySortKey = new Map<String, Id>();
        for (Id projectId : projectNameById.keySet()) {
            String name = projectNameById.get(projectId);
            String sortKey = (name == null ? '' : name.toLowerCase()) + '|' + projectId;
            sortKeys.add(sortKey);
            projectIdBySortKey.put(sortKey, projectId);
        }
        sortKeys.sort();
        List<Id> orderedProjectIds = new List<Id>();
        for (String sortKey : sortKeys) {
            orderedProjectIds.add(projectIdBySortKey.get(sortKey));
        }

        Map<Id, String> imageByProject = new Map<Id, String>();
        if (!orderedProjectIds.isEmpty()) {
            for (Sub_Document__c image : [SELECT Id, Name, File_URL__c, Project__c FROM Sub_Document__c WHERE Project__c IN :orderedProjectIds AND Document__r.Name = :PROJECT_IMAGES_DOCUMENT_NAME AND File_URL__c != null WITH SYSTEM_MODE ORDER BY Name ASC, Id ASC]) {
                if (!imageByProject.containsKey(image.Project__c)) {
                    imageByProject.put(image.Project__c, image.File_URL__c);
                }
            }
        }

        Integer totalOpenCases = 0;
        Map<Id, Integer> openCasesByProject  = new Map<Id, Integer>();
        Map<Id, Integer> totalCasesByProject = new Map<Id, Integer>();

        if (accountId != null) {
            for (AggregateResult row : [SELECT Project__c projectKey, Unit__c unitKey, IsClosed closedFlag, COUNT(Id) caseCount FROM Case WHERE AccountId = :accountId OR Unit__c IN :allUnitIds WITH SYSTEM_MODE GROUP BY Project__c, Unit__c, IsClosed]) {
                Boolean isClosed = (Boolean) row.get('closedFlag');
                Integer count    = (Integer) row.get('caseCount');

                Id projectId = (Id) row.get('projectKey');
                if (projectId == null) {
                    Id unitId = (Id) row.get('unitKey');
                    if (unitId != null) {
                        projectId = projectIdByUnit.get(unitId);
                    }
                }

                if (!isClosed) {
                    totalOpenCases += count;
                }
                if (projectId != null && projectNameById.containsKey(projectId)) {
                    totalCasesByProject.put(projectId, getCount(totalCasesByProject, projectId) + count);
                    if (!isClosed) {
                        openCasesByProject.put(projectId, getCount(openCasesByProject, projectId) + count);
                    }
                }
            }
        }

        for (Id projectId : orderedProjectIds) {
            CarouselItem item = new CarouselItem();
            item.projectId = String.valueOf(projectId);
            item.name      = projectNameById.get(projectId);
            item.imageUrl  = imageByProject.get(projectId);
            data.carousel.add(item);
        }

        ProgressSection support = new ProgressSection();
        support.key      = SUPPORT_KEY;
        support.title    = SUPPORT_TITLE;
        support.metric   = newMetric(totalOpenCases, SUPPORT_UNIT, SUPPORT_LABEL);
        support.projects = new List<ProgressProject>();

        for (Id projectId : orderedProjectIds) {
            Integer openCases  = getCount(openCasesByProject, projectId);
            Integer totalCases = getCount(totalCasesByProject, projectId);

            ProgressProject row = newProgressProject(projectId, projectNameById, unitIdsByProject);
            row.progress = totalCases == 0? 0: ((Decimal) openCases * 100 / totalCases).setScale(0, RoundingMode.HALF_UP).intValue();
            row.status   = openCases > 0 ? SUPPORT_PENDING : null;
            support.projects.add(row);
        }
        data.progress.add(support);

        ProgressSection handover = new ProgressSection();
        handover.key      = HANDOVER_KEY;
        handover.title    = HANDOVER_TITLE;
        handover.metric   = newMetric(HANDOVER_DUMMY_PROGRESS, HANDOVER_UNIT, HANDOVER_LABEL);
        handover.projects = new List<ProgressProject>();

        for (Id projectId : orderedProjectIds) {
            ProgressProject row = newProgressProject(projectId, projectNameById, unitIdsByProject);
            row.progress = HANDOVER_DUMMY_PROGRESS;
            row.status   = HANDOVER_STATUS;
            handover.projects.add(row);
        }
        data.progress.add(handover);

        return data;
    }

    private static Integer getCount(Map<Id, Integer> counts, Id key) {
        return counts.containsKey(key) ? counts.get(key) : 0;
    }

    private static MetricWrapper newMetric(Integer value, String unit, String label) {
        MetricWrapper metric = new MetricWrapper();
        metric.value = value;
        metric.unit  = unit;
        metric.label = label;
        return metric;
    }

    private static ProgressProject newProgressProject(Id projectId, Map<Id, String> projectNameById, Map<Id, Set<Id>> unitIdsByProject) {
        ProgressProject row = new ProgressProject();
        row.projectId = String.valueOf(projectId);
        row.name      = projectNameById.get(projectId);
        row.units     = unitIdsByProject.containsKey(projectId) ? unitIdsByProject.get(projectId).size() : 0;
        return row;
    }

    private static ResponseEnvelope wrap(Integer statusCode, Boolean success, String message, DashboardData data) {
        ResponseBody body = new ResponseBody();
        body.success    = success;
        body.statusCode = statusCode;
        body.message    = message;
        body.data       = data;

        ResponseEnvelope envelope = new ResponseEnvelope();
        envelope.response = body;
        return envelope;
    }

    public class ResponseEnvelope {
        public ResponseBody response;
    }

    public class ResponseBody {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public DashboardData data;
    }

    public class DashboardData {
        public CustomerWrapper customer;
        public List<CarouselItem> carousel;
        public List<ProgressSection> progress;
    }

    public class CustomerWrapper {
        public String name;
        public String asOf;
    }

    public class CarouselItem {
        public String projectId;
        public String name;
        public String imageUrl;
    }

    public class ProgressSection {
        public String key;
        public String title;
        public MetricWrapper metric;
        public List<ProgressProject> projects;
    }

    public class MetricWrapper {
        public Integer value;
        public String unit;
        public String label;
    }

    public class ProgressProject {
        public String projectId;
        public String name;
        public Integer units;
        public Integer progress;
        public String status;
    }
}