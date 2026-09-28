public without sharing class partnerWebPortalSiteVisit {

    public class SiteVisitsResponse {
        @AuraEnabled public List<VisitRow> visits  { get; set; }
        @AuraEnabled public Integer totalRecords   { get; set; }
        @AuraEnabled public Integer pageSize       { get; set; }
        @AuraEnabled public Integer pageNumber     { get; set; }
        @AuraEnabled public Integer totalPages     { get; set; }
    }

    public class VisitRow {
        @AuraEnabled public Integer rowNo           { get; set; }
        @AuraEnabled public String createdDate      { get; set; }
        @AuraEnabled public String visitName        { get; set; }
        @AuraEnabled public String leadName         { get; set; }
        @AuraEnabled public String projectName      { get; set; }
        @AuraEnabled public String opportunityStage { get; set; }
    }

    // =========================================================
    // 1. GET CUSTOMER OPTIONS (From Lead Object)
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCustomerOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (Lead l : [
            SELECT Id, Name, Project__c 
            FROM Lead 
            WHERE IsConverted = false 
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
    // 2. GET PROJECT OPTIONS (From Project__c Object)
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getProjectOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (Project__c p : [
            SELECT Id, Name 
            FROM Project__c 
            ORDER BY Name ASC 
            LIMIT 200
        ]) {
            options.add(new Map<String, String>{
                'label' => p.Name,
                'value' => String.valueOf(p.Id)
            });
        }
        return options;
    }

    // =========================================================
    // 3. FETCH VISITS (Includes Lead__r.Name & Project__r.Name)
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

        List<String> conditions = new List<String>();
        String likeKey = String.isNotBlank(searchKey) ? '%' + searchKey.trim() + '%' : null;

        if (String.isNotBlank(stageFilter) && stageFilter != 'All') {
            conditions.add('Opportunity__r.StageName = :stageFilter');
        }
        if (likeKey != null) {
            conditions.add('(Name LIKE :likeKey OR Lead__r.Name LIKE :likeKey OR Project__r.Name LIKE :likeKey)');
        }

        String whereClause = conditions.isEmpty()
            ? ''
            : ' WHERE ' + String.join(conditions, ' AND ');

        Integer totalRecords = Database.countQuery(
            'SELECT COUNT() FROM Visit__c' + whereClause
        );
        response.totalRecords = totalRecords;
        response.totalPages = (Integer) Math.ceil((Decimal) totalRecords / response.pageSize);

        Integer offset = (response.pageNumber - 1) * response.pageSize;

        List<Visit__c> visits = Database.query(
            'SELECT Id, Name, CreatedDate, ' +
            'Lead__r.Name, Project__r.Name, Opportunity__r.StageName ' +
            'FROM Visit__c' + whereClause +
            ' ORDER BY CreatedDate DESC LIMIT :pageSize OFFSET :offset'
        );

        List<VisitRow> rows = new List<VisitRow>();
        Integer rowCounter = offset + 1;

        for (Visit__c v : visits) {
            VisitRow r = new VisitRow();
            r.rowNo            = rowCounter++;
            r.createdDate      = v.CreatedDate != null ? v.CreatedDate.format('dd MMM yyyy') : '';
            r.visitName        = String.isNotBlank(v.Name) ? v.Name : '-';
            r.leadName         = v.Lead__r != null ? v.Lead__r.Name : '-';
            r.projectName      = v.Project__r != null ? v.Project__r.Name : '-';
            r.opportunityStage = (v.Opportunity__r != null && String.isNotBlank(v.Opportunity__r.StageName))
                ? v.Opportunity__r.StageName : '-';
            rows.add(r);
        }

        response.visits = rows;
        return response;
    }

    // =========================================================
    // 4. STAGE PICKLIST OPTIONS
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<String> getStageOptions() {
        List<String> options = new List<String>{ 'All' };
        for (Schema.PicklistEntry entry : Opportunity.StageName.getDescribe().getPicklistValues()) {
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
        List<String> conditions = new List<String>();
        String likeKey = String.isNotBlank(searchKey) ? '%' + searchKey.trim() + '%' : null;

        if (String.isNotBlank(stageFilter) && stageFilter != 'All') {
            conditions.add('Opportunity__r.StageName = :stageFilter');
        }
        if (likeKey != null) {
            conditions.add('(Name LIKE :likeKey OR Lead__r.Name LIKE :likeKey OR Project__r.Name LIKE :likeKey)');
        }

        String whereClause = conditions.isEmpty()
            ? ''
            : ' WHERE ' + String.join(conditions, ' AND ');

        List<Visit__c> visits = Database.query(
            'SELECT Id, Name, CreatedDate, ' +
            'Lead__r.Name, Project__r.Name, Opportunity__r.StageName ' +
            'FROM Visit__c' + whereClause +
            ' ORDER BY CreatedDate DESC LIMIT 1000'
        );

        String csv = 'Visit Name,Customer (Lead),Project,Stage,Created Date\n';
        for (Visit__c v : visits) {
            csv += '"' + (String.isNotBlank(v.Name) ? v.Name : '') + '",'
                 + '"' + (v.Lead__r != null ? v.Lead__r.Name : '') + '",'
                 + '"' + (v.Project__r != null ? v.Project__r.Name : '') + '",'
                 + '"' + (v.Opportunity__r != null && String.isNotBlank(v.Opportunity__r.StageName) ? v.Opportunity__r.StageName : '') + '",'
                 + '"' + (v.CreatedDate != null ? v.CreatedDate.format('dd MMM yyyy') : '') + '"\n';
        }
        return EncodingUtil.base64Encode(Blob.valueOf(csv));
    }

    // =========================================================
    // 6. CREATE SITE VISIT
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
            throw new AuraHandledException('Customer (Lead) is required');
        }

        Visit__c newVisit = new Visit__c();
        
        // Link to Lead
        try {
            newVisit.Lead__c = (Id) leadId;
        } catch (Exception e) {
            System.debug('>>> Invalid Lead Id: ' + leadId);
        }

        // Link to Project (if field exists on Visit__c)
        if (String.isNotBlank(projectId)) {
            try {
                newVisit.Project__c = (Id) projectId;
            } catch (Exception e) {
                System.debug('>>> Invalid Project Id: ' + projectId);
            }
        }

        // Description / Reason
        if (String.isNotBlank(description)) {
            newVisit.Reason_of_Reschedule__c = description;
        }

        // Visit Date
        if (visitDate != null) {
            // newVisit.Visit_Date__c = visitDate; // Uncomment if your object has Visit_Date__c
        }

        try {
            insert newVisit;
            System.debug('>>> Site Visit Created ID: ' + newVisit.Id);
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }

        return newVisit.Id;
    }
}