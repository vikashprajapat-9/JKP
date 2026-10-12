// The Site Visits page of the partner portal. A channel head sees the site visits of their team: visits whose Channel
// Partner, or whose lead's Channel Partner, is their account or the account of one of their executives (a channel
// partner account whose Channel Head is theirs). An executive sees only their own visits, in the projects their
// channel head gave them (see PartnerPortalAccess). Partners cannot see their executives' records, so this runs
// without sharing and in system mode, and every visit and lead query is limited by PartnerPortalAccess.
// A new site visit is a request, for the project of its lead, that John Keells Properties approves
// (PartnerSiteVisitService).
public without sharing class partnerWebPortalSiteVisit {

    private static final String SETTINGS_RECORD = 'Default';
    private static final String ALL_FILTER = 'All';
    private static final Integer DEFAULT_PAGE_SIZE = 10;
    private static final Integer MAX_PAGE_SIZE = 200;
    private static final Integer MAX_OFFSET = 2000;
    private static final Integer EXPORT_LIMIT = 10000;
    private static final String VISIT_FIELDS = 'SELECT Id, Name, CreatedDate, Status__c, Visit_Date__c, Visit_Time__c, Lead__r.Name,'
        + ' Lead__r.Project__r.Name, Project__r.Name, Channel_Partner__r.Name, Lead__r.Channel_Partner__r.Name';
    private static final List<String> EXPORT_COLUMNS = new List<String>{
        'Sr.', 'Visit Created Date', 'Visit Name', 'Customer (Lead)', 'Channel Partner', 'Project', 'Visit Date', 'Visit Status'
    };
    // A cell Excel would run as a formula: = @ tab or return first, or + - followed by more than a number
    private static final Pattern FORMULA_START = Pattern.compile('^([=@\\t\\r]|[+-](?![0-9 ()]*$))');
    // The Partner Portal Setting that gives new visits their status; tests set their own
    @TestVisible
    private static Partner_Portal_Setting__mdt setting = Partner_Portal_Setting__mdt.getInstance(SETTINGS_RECORD);

    public class SiteVisitsResponse {
        @AuraEnabled public List<VisitRow> visits  { get; set; }
        @AuraEnabled public Integer totalRecords   { get; set; }
        @AuraEnabled public Integer pageSize       { get; set; }
        @AuraEnabled public Integer pageNumber     { get; set; }
        @AuraEnabled public Integer totalPages     { get; set; }
    }

    public class VisitRow {
        @AuraEnabled public Integer rowNo       { get; set; }
        @AuraEnabled public String createdDate  { get; set; }
        @AuraEnabled public String visitName    { get; set; }
        @AuraEnabled public String leadName     { get; set; }
        @AuraEnabled public String channelPartner { get; set; }
        @AuraEnabled public String projectName  { get; set; }
        @AuraEnabled public String visitDate    { get; set; }
        @AuraEnabled public String status       { get; set; }
    }

    // The conditions of a visit query with their bind values. It always starts with the visits the partner may see.
    private class VisitQuery {
        private final Map<String, Object> binds = new Map<String, Object>();
        private final List<String> conditions = new List<String>();

        private VisitQuery(PartnerPortalAccess access) {
            conditions.add(access.visits(binds));
        }

        private void add(String condition, String bindName, Object value) {
            binds.put(bindName, value);
            conditions.add(condition);
        }

        private String whereClause() {
            return ' WHERE ' + String.join(conditions, ' AND ');
        }
    }

    // =========================================================
    // 1. GET CUSTOMER OPTIONS (the partner's own open leads, not their executives'; an executive's only in their
    //    projects; not one JKP took over, nor one with a request waiting for approval or a visit scheduled). Each comes
    //    with its project, which the form shows read-only (a lead's site visits are for the project it was created
    //    for), and the reason that project cannot have site visits now, if any
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCustomerOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        PartnerPortalAccess access = PartnerPortalAccess.current();
        if (access.accountId == null) {
            return options;
        }
        Map<String, Object> binds = new Map<String, Object>();
        List<Lead> leads = (List<Lead>) Database.queryWithBinds(
            'SELECT Id, Name, Project__c, Project__r.Name, Project__r.Active__c, OwnerId FROM Lead WHERE IsConverted = false AND '
                + access.ownLeads(binds)
                + ' AND Id NOT IN (SELECT Lead__c FROM Visit__c WHERE Lead__c != null AND '
                + PartnerSiteVisitService.openVisitCondition(binds) + ') ORDER BY Name ASC LIMIT 500',
            binds, AccessLevel.SYSTEM_MODE
        );
        Set<Id> ownerIds = new Set<Id>();
        for (Lead l : leads) {
            ownerIds.add(l.OwnerId);
        }
        partnerWebPortalLeadEditController.loadOwners(ownerIds);
        for (Lead l : leads) {
            // Not a lead JKP owns: a queue or an internal user (Owner.Type cannot tell: a partner does not see an internal
            // owner through it)
            if (!partnerWebPortalLeadEditController.isPartnerUser(l.OwnerId)) {
                continue;
            }
            String projectReason = PartnerSiteVisitService.projectNotOpenReason(l.Project__r);
            options.add(new Map<String, String>{
                'label'       => l.Name,
                'value'       => String.valueOf(l.Id),
                'projectId'   => l.Project__c != null ? String.valueOf(l.Project__c) : '',
                'projectName' => l.Project__r != null ? l.Project__r.Name : '',
                'projectUnavailableReason' => projectReason != null ? projectReason : ''
            });
        }
        return options;
    }

    // =========================================================
    // 2. GET PROJECT OPTIONS (active projects; an executive's own projects only)
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getProjectOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        Map<String, Object> binds = new Map<String, Object>();
        String visible = PartnerPortalAccess.current().projects(binds);
        for (Project__c p : (List<Project__c>) Database.queryWithBinds(
                'SELECT Id, Name FROM Project__c WHERE Active__c = true AND ' + visible + ' ORDER BY Name ASC LIMIT 200',
                binds, AccessLevel.SYSTEM_MODE)) {
            options.add(new Map<String, String>{
                'label' => p.Name,
                'value' => String.valueOf(p.Id)
            });
        }
        return options;
    }

    // =========================================================
    // 2b. GET REQUIREMENT TYPE OPTIONS (the visit's Requirement Type picklist)
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getRequirementTypeOptions() {
        return PartnerSiteVisitService.requirementTypes();
    }

    // =========================================================
    // 3. FETCH VISITS (the logged-in partner's team only)
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static SiteVisitsResponse getSiteVisit(
        String stageFilter,
        String searchKey,
        Integer pageNumber,
        Integer pageSize
    ) {
        SiteVisitsResponse response = new SiteVisitsResponse();
        response.pageNumber = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
        response.pageSize   = (pageSize   == null || pageSize   < 1) ? DEFAULT_PAGE_SIZE : Math.min(pageSize, MAX_PAGE_SIZE);
        response.visits = new List<VisitRow>();
        response.totalRecords = 0;
        response.totalPages = 0;
        PartnerPortalAccess access = PartnerPortalAccess.current();
        if (access.accountId == null) {
            return response;
        }

        VisitQuery query = queryFor(access, stageFilter, searchKey);
        response.totalRecords = Database.countQueryWithBinds('SELECT COUNT() FROM Visit__c' + query.whereClause(), query.binds, AccessLevel.SYSTEM_MODE);
        response.totalPages   = (Integer) Math.ceil((Decimal) response.totalRecords / response.pageSize);

        Integer offset = Math.min((response.pageNumber - 1) * response.pageSize, MAX_OFFSET);
        query.binds.put('pageSize', response.pageSize);
        query.binds.put('offsetRows', offset);
        Integer rowNo = offset;
        for (Visit__c visit : (List<Visit__c>) Database.queryWithBinds(VISIT_FIELDS + ' FROM Visit__c' + query.whereClause()
                + ' ORDER BY CreatedDate DESC, Id DESC LIMIT :pageSize OFFSET :offsetRows', query.binds, AccessLevel.SYSTEM_MODE)) {
            response.visits.add(rowOf(visit, ++rowNo));
        }
        return response;
    }

    // =========================================================
    // 4. STATUS FILTER TABS (All, then the Visit Status picklist)
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<String> getStageOptions() {
        List<String> options = new List<String>{ ALL_FILTER };
        for (Schema.PicklistEntry entry : Visit__c.Status__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(entry.getValue());
            }
        }
        return options;
    }

    // =========================================================
    // 5. EXPORT CSV (the chosen filter and search; the page adds the byte-order mark Excel needs)
    // =========================================================
    @AuraEnabled
    public static String exportCSV(String stageFilter, String searchKey) {
        List<String> lines = new List<String>{ csvLine(EXPORT_COLUMNS) };
        PartnerPortalAccess access = PartnerPortalAccess.current();
        if (access.accountId != null) {
            VisitQuery query = queryFor(access, stageFilter, searchKey);
            query.binds.put('exportLimit', EXPORT_LIMIT);
            Integer rowNo = 0;
            for (Visit__c visit : (List<Visit__c>) Database.queryWithBinds(VISIT_FIELDS + ' FROM Visit__c' + query.whereClause()
                    + ' ORDER BY CreatedDate DESC, Id DESC LIMIT :exportLimit', query.binds, AccessLevel.SYSTEM_MODE)) {
                VisitRow row = rowOf(visit, ++rowNo);
                lines.add(csvLine(new List<String>{ String.valueOf(row.rowNo), row.createdDate, row.visitName, row.leadName, row.channelPartner,
                    row.projectName, row.visitDate, row.status }));
            }
        }
        return String.join(lines, '\r\n') + '\r\n';
    }

    // =========================================================
    // 6. REQUEST A SITE VISIT
    // =========================================================
    // For one of the partner's own open leads (not their executives'), for the lead's project; every field of the form is
    // required. The request gets the partner as Channel Partner, the lead's project and the chosen requirement type,
    // date, time and description, and goes to John Keells Properties for approval (PartnerSiteVisitService). Returns
    // the new visit's Id.
    @AuraEnabled
    public static Id createSiteVisit(
        String leadId,
        String projectId,
        String requirementType,
        Date visitDate,
        String visitTime,
        String description
    ) {
        if (String.isBlank(leadId)) {
            throw createHandledException('Choose the customer.');
        }
        PartnerPortalAccess access = PartnerPortalAccess.current();
        Lead customer = ownLead(leadId, access);
        if (customer == null) {
            throw createHandledException('Choose the customer from your own leads.');
        }
        // Not a lead JKP took over, one waiting for the managers' approval, or one another partner won
        String reason = partnerWebPortalLeadEditController.readOnlyReasonOf(customer, access);
        if (reason != null) {
            throw createHandledException(Label.Partner_Visit_Lead_Not_Open);
        }
        Id chosenProject = projectIdOf(projectId);
        if (chosenProject == null) {
            throw createHandledException('Choose the project.');
        }
        // The lead's project, which the form shows read-only: PartnerSiteVisitService refuses another one, and the lead's
        // project while it is not open for site visits. Only an old lead without a project (from before leads needed
        // one) takes the project the partner chose, as before: an active project the partner works in (an executive
        // only in the projects their channel head gave them)
        if (customer.Project__c == null
                && (!access.canSeeProject(chosenProject) || !offeredProjectIds().contains(String.valueOf(chosenProject)))) {
            throw createHandledException('Choose one of your projects.');
        }
        if (String.isBlank(requirementType)) {
            throw createHandledException('Choose the requirement type.');
        }
        if (visitDate == null) {
            throw createHandledException('Choose the visit date.');
        }
        if (String.isBlank(visitTime)) {
            throw createHandledException('Enter the visit time.');
        }
        Time visitAt = timeOf(visitTime);
        if (visitAt == null) {
            throw createHandledException('Enter a valid visit time, for example 10:30 AM.');
        }
        if (String.isBlank(description)) {
            throw createHandledException('Enter a description.');
        }
        try {
            return PartnerSiteVisitService.request(customer, chosenProject, requirementType, visitDate, visitAt, description).Id;
        } catch (PartnerSiteVisitService.VisitException e) {
            throw createHandledException(e.getMessage());
        }
    }

    // =========================================================
    // HELPERS
    // =========================================================

    // The projects the form offers: active, and the partner's (see getProjectOptions)
    public static Set<String> offeredProjectIds() {
        Set<String> ids = new Set<String>();
        for (Map<String, String> option : getProjectOptions()) {
            ids.add(option.get('value'));
        }
        return ids;
    }

    // The status visits without a status are shown and filtered as (the status of a scheduled visit)
    private static String defaultStatus() {
        return setting == null || String.isBlank(setting.Visit_Status__c) ? null : setting.Visit_Status__c.trim();
    }

    // The visits the partner may see with the chosen status that contain the search text in a column of the table
    private static VisitQuery queryFor(PartnerPortalAccess access, String stageFilter, String searchKey) {
        VisitQuery query = new VisitQuery(access);
        String status = stageFilter == null ? '' : stageFilter.trim();
        if (status.length() > 0 && status != ALL_FILTER) {
            if (status.equalsIgnoreCase(defaultStatus())) {
                query.add('(Status__c = :status OR Status__c = null)', 'status', status);
            } else {
                query.add('Status__c = :status', 'status', status);
            }
        }

        String term = searchKey == null ? '' : searchKey.trim();
        if (term.length() > 0) {
            query.add('(Name LIKE :term OR Lead__r.Name LIKE :term OR Project__r.Name LIKE :term OR Lead__r.Project__r.Name LIKE :term'
                + ' OR Status__c LIKE :term OR Channel_Partner__r.Name LIKE :term OR Lead__r.Channel_Partner__r.Name LIKE :term)',
                'term', '%' + escapeLike(term) + '%');
        }
        return query;
    }

    // The lead, when it is an open lead of the partner's own (an executive works their own leads, in their projects),
    // with its project (PartnerSiteVisitService keeps the visit to it)
    private static Lead ownLead(String leadId, PartnerPortalAccess access) {
        Id requested;
        try {
            requested = Id.valueOf(leadId.trim());
        } catch (Exception e) {
            return null;
        }
        if (access.accountId == null || requested.getSObjectType() != Lead.SObjectType) {
            return null;
        }
        Map<String, Object> binds = new Map<String, Object>{ 'requested' => requested };
        List<Lead> leads = (List<Lead>) Database.queryWithBinds(
            'SELECT Id, Status, OwnerId, IsConverted, CP_Approval_Status__c, Channel_Partner__c, Project__c FROM Lead'
                + ' WHERE Id = :requested AND IsConverted = false AND ' + access.ownLeads(binds) + ' LIMIT 1',
            binds, AccessLevel.SYSTEM_MODE
        );
        return leads.isEmpty() ? null : leads[0];
    }

    private static Id projectIdOf(String projectId) {
        if (String.isBlank(projectId)) {
            return null;
        }
        try {
            Id candidate = Id.valueOf(projectId.trim());
            return candidate.getSObjectType() == Project__c.SObjectType ? candidate : null;
        } catch (Exception e) {
            return null;
        }
    }

    // "10:30 AM" as a Time; null when it is not a time of day
    @TestVisible
    private static Time timeOf(String text) {
        return PartnerSiteVisitService.timeOf(text);
    }

    // The search text taken literally: % and _ are not wildcards
    private static String escapeLike(String value) {
        return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    private static VisitRow rowOf(Visit__c visit, Integer rowNo) {
        VisitRow row = new VisitRow();
        row.rowNo       = rowNo;
        row.createdDate = visit.CreatedDate != null ? visit.CreatedDate.format('dd MMM yyyy') : '';
        row.visitName   = String.isNotBlank(visit.Name) ? visit.Name : '-';
        row.leadName    = visit.Lead__r != null && String.isNotBlank(visit.Lead__r.Name) ? visit.Lead__r.Name : '-';
        // The visit's channel partner, or its lead's: the partner or the executive whose visit it is
        if (visit.Channel_Partner__r != null && String.isNotBlank(visit.Channel_Partner__r.Name)) {
            row.channelPartner = visit.Channel_Partner__r.Name;
        } else if (visit.Lead__r != null && visit.Lead__r.Channel_Partner__r != null && String.isNotBlank(visit.Lead__r.Channel_Partner__r.Name)) {
            row.channelPartner = visit.Lead__r.Channel_Partner__r.Name;
        } else {
            row.channelPartner = '-';
        }
        // The visit's project, or its lead's
        if (visit.Project__r != null && String.isNotBlank(visit.Project__r.Name)) {
            row.projectName = visit.Project__r.Name;
        } else if (visit.Lead__r != null && visit.Lead__r.Project__r != null && String.isNotBlank(visit.Lead__r.Project__r.Name)) {
            row.projectName = visit.Lead__r.Project__r.Name;
        } else {
            row.projectName = '-';
        }
        row.visitDate = visit.Visit_Date__c == null ? '-' : PartnerSiteVisitService.dateText(visit.Visit_Date__c)
            + (visit.Visit_Time__c == null ? '' : ', ' + PartnerSiteVisitService.timeText(visit.Visit_Time__c));
        String status = String.isNotBlank(visit.Status__c) ? visit.Status__c : defaultStatus();
        row.status = String.isNotBlank(status) ? status : '-';
        return row;
    }

    // A CSV line: every value quoted with its quotes doubled, and a value Excel would run as a formula kept as text
    private static String csvLine(List<String> values) {
        List<String> cells = new List<String>();
        for (String value : values) {
            String cell = value == null ? '' : value;
            if (FORMULA_START.matcher(cell).find()) {
                cell = '\'' + cell;
            }
            cells.add('"' + cell.replace('"', '""') + '"');
        }
        return String.join(cells, ',');
    }

    private static AuraHandledException createHandledException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}