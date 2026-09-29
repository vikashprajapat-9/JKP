public without sharing class partnerWebPortalSiteVisit {

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
        @AuraEnabled public String projectName  { get; set; }
        @AuraEnabled public String status       { get; set; }
    }

    // =========================================================
    // 1. GET CUSTOMER OPTIONS (Only Logged-in Partner's Leads)
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCustomerOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        Id currentUserId = UserInfo.getUserId();
        
        Set<Id> visitedLeadIds = new Set<Id>();
        for (Visit__c v : [
            SELECT Lead__c 
            FROM Visit__c 
            WHERE Lead__c != null 
            AND (Lead__r.OwnerId = :currentUserId OR OwnerId = :currentUserId)
        ]) {
            visitedLeadIds.add(v.Lead__c);
        }

        for (Lead l : [
            SELECT Id, Name, Project__c 
            FROM Lead 
            WHERE IsConverted = false 
            AND OwnerId = :currentUserId
            AND Id NOT IN :visitedLeadIds
            ORDER BY Name ASC 
            LIMIT 500
        ]) {
            options.add(new Map<String, String>{
                'label'     => l.Name,
                'value'     => String.valueOf(l.Id),
                'projectId' => String.isNotBlank(String.valueOf(l.Project__c)) ? String.valueOf(l.Project__c) : ''
            });
        }
        return options;
    }

    // =========================================================
    // 2. GET PROJECT OPTIONS
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getProjectOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (Project__c p : [SELECT Id, Name FROM Project__c WITH SYSTEM_MODE ORDER BY Name ASC LIMIT 200]) {
            options.add(new Map<String, String>{
                'label' => p.Name,
                'value' => String.valueOf(p.Id)
            });
        }
        return options;
    }

    // =========================================================
    // 3. FETCH VISITS (Includes Project Name & Status__c)
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
        response.pageSize   = (pageSize   == null || pageSize   < 1) ? 10 : pageSize;

        Id currentUserId = UserInfo.getUserId();
        List<String> conditions = new List<String>{ '(Lead__r.OwnerId = :currentUserId OR CreatedById = :currentUserId OR OwnerId = :currentUserId)' };

        if (String.isNotBlank(stageFilter) && stageFilter != 'All') {
            conditions.add('Status__c = :stageFilter');
        }

        String likeKey;
        if (String.isNotBlank(searchKey)) {
            likeKey = '%' + searchKey.trim() + '%';
            conditions.add('(Name LIKE :likeKey OR Lead__r.Name LIKE :likeKey OR Project__r.Name LIKE :likeKey)');
        }

        String whereClause = ' WHERE ' + String.join(conditions, ' AND ');

        Integer totalRecords = Database.countQuery('SELECT COUNT() FROM Visit__c' + whereClause);
        response.totalRecords = totalRecords;
        response.totalPages   = (Integer) Math.ceil((Decimal) totalRecords / response.pageSize);

        Integer offset = (response.pageNumber - 1) * response.pageSize;
        List<Visit__c> visits = Database.query(
            'SELECT Id, Name, CreatedDate, Status__c, ' +
            'Lead__r.Name, Lead__r.Project__c, Lead__r.Project__r.Name, ' +
            'Project__r.Name ' +
            'FROM Visit__c' + whereClause +
            ' ORDER BY CreatedDate DESC LIMIT :pageSize OFFSET :offset'
        );

        List<VisitRow> rows = new List<VisitRow>();
        Integer rowCounter = offset + 1;

        for (Visit__c v : visits) {
            VisitRow r = new VisitRow();
            r.rowNo       = rowCounter++;
            r.createdDate = v.CreatedDate != null ? v.CreatedDate.format('dd MMM yyyy') : '';
            r.visitName   = String.isNotBlank(v.Name) ? v.Name : '-';
            r.leadName    = (v.Lead__r != null && String.isNotBlank(v.Lead__r.Name)) ? v.Lead__r.Name : '-';
            
            // ✅ Read Project from Visit__r.Project__r OR Lead__r.Project__r
            if (v.Project__r != null && String.isNotBlank(v.Project__r.Name)) {
                r.projectName = v.Project__r.Name;
            } else if (v.Lead__r != null && v.Lead__r.Project__r != null && String.isNotBlank(v.Lead__r.Project__r.Name)) {
                r.projectName = v.Lead__r.Project__r.Name;
            } else {
                r.projectName = '-';
            }

            // ✅ Visit Status
            r.status = String.isNotBlank(v.Status__c) ? v.Status__c : 'Upcoming';
            rows.add(r);
        }

        response.visits = rows;
        return response;
    }

    // =========================================================
    // 4. STATUS FILTER TABS (From Visit__c.Status__c)
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<String> getStageOptions() {
        List<String> options = new List<String>{ 'All' };
        for (Schema.PicklistEntry entry : Visit__c.Status__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(entry.getLabel());
            }
        }
        return options;
    }

    // =========================================================
    // 5. EXPORT CSV
    // =========================================================
    @AuraEnabled
    public static String exportCSV(String stageFilter, String searchKey) {
        Id currentUserId = UserInfo.getUserId();
        List<String> conditions = new List<String>{ '(Lead__r.OwnerId = :currentUserId OR CreatedById = :currentUserId OR OwnerId = :currentUserId)' };

        if (String.isNotBlank(stageFilter) && stageFilter != 'All') {
            conditions.add('Status__c = :stageFilter');
        }

        String likeKey;
        if (String.isNotBlank(searchKey)) {
            likeKey = '%' + searchKey.trim() + '%';
            conditions.add('(Name LIKE :likeKey OR Lead__r.Name LIKE :likeKey OR Project__r.Name LIKE :likeKey)');
        }

        String whereClause = ' WHERE ' + String.join(conditions, ' AND ');
        List<Visit__c> visits = Database.query(
            'SELECT Id, Name, CreatedDate, Status__c, Lead__r.Name, Project__r.Name, Lead__r.Project__r.Name FROM Visit__c' + whereClause + ' ORDER BY CreatedDate DESC LIMIT 1000'
        );

        String csv = 'Visit Name,Customer (Lead),Project,Visit Status,Created Date\n';
        for (Visit__c v : visits) {
            String projName = (v.Project__r != null) ? v.Project__r.Name : ((v.Lead__r != null && v.Lead__r.Project__r != null) ? v.Lead__r.Project__r.Name : '');
            String custName = (v.Lead__r != null) ? v.Lead__r.Name : '';
            String stat     = String.isNotBlank(v.Status__c) ? v.Status__c : 'Upcoming';

            csv += '"' + (String.isNotBlank(v.Name) ? v.Name : '') + '",'
                 + '"' + custName + '",'
                 + '"' + projName + '",'
                 + '"' + stat + '",'
                 + '"' + (v.CreatedDate != null ? v.CreatedDate.format('dd MMM yyyy') : '') + '"\n';
        }
        return EncodingUtil.base64Encode(Blob.valueOf(csv));
    }

    // =========================================================
    // 6. CREATE SITE VISIT (Stamps OwnerId & Links Project)
    // =========================================================
    @AuraEnabled
    public static Id createSiteVisit(
        String leadId,
        String projectId,
        Date visitDate,
        String visitTime,
        String description
    ) {
        if (String.isBlank(leadId)) {
            throw createHandledException('Customer (Lead) is required');
        }

        Visit__c newVisit = new Visit__c();
        newVisit.OwnerId  = UserInfo.getUserId();

        // Assign Lead Lookup
        try {
            newVisit.Lead__c = (Id) leadId.trim();
        } catch (Exception e) {
            System.debug('>>> Invalid Lead Id: ' + leadId);
        }

        // Assign Project Lookup
        if (String.isNotBlank(projectId)) {
            try {
                newVisit.Project__c = (Id) projectId.trim();
            } catch (Exception e) {
                System.debug('>>> Invalid Project Id: ' + projectId);
            }
        }

        if (String.isNotBlank(description)) {
            newVisit.Reason_of_Reschedule__c = description.trim();
        }

        // Default Status if blank
        newVisit.Status__c = 'Upcoming';

        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = true;
        dml.optAllOrNone = true;

        try {
            Database.SaveResult sr = Database.insert(newVisit, dml, AccessLevel.SYSTEM_MODE);
            if (sr.isSuccess()) {
                System.debug('>>> [SiteVisit] Created ID: ' + sr.getId());
                return sr.getId();
            } else {
                String errorMsg = '';
                for (Database.Error err : sr.getErrors()) errorMsg += err.getMessage() + ' ';
                throw createHandledException(errorMsg);
            }
        } catch (DmlException e) {
            throw createHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw createHandledException(e.getMessage());
        }
    }

    private static AuraHandledException createHandledException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}