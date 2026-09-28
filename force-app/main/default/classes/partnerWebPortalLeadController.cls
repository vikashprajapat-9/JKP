public without sharing class partnerWebPortalLeadController {

    // =========================================================
    // WRAPPER CLASSES
    // =========================================================
    public class LeadsResponse {
        @AuraEnabled public List<LeadRow> leads    { get; set; }
        @AuraEnabled public Integer totalRecords   { get; set; }
        @AuraEnabled public Integer pageSize       { get; set; }
        @AuraEnabled public Integer pageNumber     { get; set; }
        @AuraEnabled public Integer totalPages     { get; set; }
    }

    public class LeadRow {
        @AuraEnabled public Integer rowNo       { get; set; }
        @AuraEnabled public String createdDate  { get; set; }
        @AuraEnabled public String leadNo       { get; set; }
        @AuraEnabled public String leadName     { get; set; }
        @AuraEnabled public String partner      { get; set; }
        @AuraEnabled public String mobile       { get; set; }
        @AuraEnabled public String stage        { get; set; }
    }

    // =========================================================
    // GET LEADS WITH FILTER, SEARCH, PAGINATION
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static LeadsResponse getLeads(
        String stageFilter,
        String searchKey,
        Integer pageNumber,
        Integer pageSize
    ) {
        LeadsResponse response = new LeadsResponse();
        response.pageNumber = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
        response.pageSize   = (pageSize == null || pageSize < 1) ? 10 : pageSize;

        // Count query
        Integer totalRecords;

        if (String.isNotBlank(searchKey) && stageFilter != null && stageFilter != 'All') {
            String likeKey = '%' + searchKey + '%';
            totalRecords = Database.countQuery(
                'SELECT COUNT() FROM Lead WHERE IsConverted = false AND Status = :stageFilter AND (Name LIKE :likeKey OR Company LIKE :likeKey OR Phone LIKE :likeKey)'
            );
        } else if (String.isNotBlank(searchKey)) {
            String likeKey = '%' + searchKey + '%';
            totalRecords = Database.countQuery(
                'SELECT COUNT() FROM Lead WHERE IsConverted = false AND (Name LIKE :likeKey OR Company LIKE :likeKey OR Phone LIKE :likeKey)'
            );
        } else if (String.isNotBlank(stageFilter) && stageFilter != 'All') {
            totalRecords = Database.countQuery(
                'SELECT COUNT() FROM Lead WHERE IsConverted = false AND Status = :stageFilter'
            );
        } else {
            totalRecords = Database.countQuery(
                'SELECT COUNT() FROM Lead WHERE IsConverted = false'
            );
        }

        response.totalRecords = totalRecords;
        response.totalPages = (Integer) Math.ceil((Decimal) totalRecords / response.pageSize);

        // Data query with pagination
        Integer offset = (response.pageNumber - 1) * response.pageSize;

        List<Lead> leads;
        if (String.isNotBlank(searchKey) && stageFilter != null && stageFilter != 'All') {
            String likeKey = '%' + searchKey + '%';
            leads = Database.query(
                'SELECT Id, Name, Company, Phone, Status, CreatedDate FROM Lead WHERE IsConverted = false AND Status = :stageFilter AND (Name LIKE :likeKey OR Company LIKE :likeKey OR Phone LIKE :likeKey) ORDER BY CreatedDate DESC LIMIT :pageSize OFFSET :offset'
            );
        } else if (String.isNotBlank(searchKey)) {
            String likeKey = '%' + searchKey + '%';
            leads = Database.query(
                'SELECT Id, Name, Company, Phone, Status, CreatedDate FROM Lead WHERE IsConverted = false AND (Name LIKE :likeKey OR Company LIKE :likeKey OR Phone LIKE :likeKey) ORDER BY CreatedDate DESC LIMIT :pageSize OFFSET :offset'
            );
        } else if (String.isNotBlank(stageFilter) && stageFilter != 'All') {
            leads = Database.query(
                'SELECT Id, Name, Company, Phone, Status, CreatedDate FROM Lead WHERE IsConverted = false AND Status = :stageFilter ORDER BY CreatedDate DESC LIMIT :pageSize OFFSET :offset'
            );
        } else {
            leads = Database.query(
                'SELECT Id, Name, Company, Phone, Status, CreatedDate FROM Lead WHERE IsConverted = false ORDER BY CreatedDate DESC LIMIT :pageSize OFFSET :offset'
            );
        }

        // Convert to wrapper
        List<LeadRow> rows = new List<LeadRow>();
        Integer rowCounter = offset + 1;

        for (Lead l : leads) {
            LeadRow r = new LeadRow();
            r.rowNo       = rowCounter++;
            r.createdDate = l.CreatedDate != null ? l.CreatedDate.format('dd MMM yyyy') : '';
            r.leadNo      = l.Id;
            r.leadName    = l.Name;
            r.partner     = String.isNotBlank(l.Company) ? l.Company : '-';
            r.mobile      = String.isNotBlank(l.Phone) ? l.Phone : '-';
            r.stage       = String.isNotBlank(l.Status) ? l.Status : '-';
            rows.add(r);
        }

        response.leads = rows;
        return response;
    }

    // =========================================================
    // STAGE FILTER OPTIONS (Lead.Status picklist)
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<String> getStageOptions() {
        List<String> options = new List<String>{ 'All' };
        Schema.DescribeFieldResult f = Lead.Status.getDescribe();
        for (Schema.PicklistEntry entry : f.getPicklistValues()) {
            if (entry.isActive()) {
                options.add(entry.getLabel());
            }
        }
        return options;
    }

    // =========================================================
    // PROJECT OPTIONS (Queries Project__c Lookup Object)
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
    // BUDGET OPTIONS (Lead.Budget_Aligned__c picklist)
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getBudgetOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (Schema.PicklistEntry entry : Lead.Budget_Aligned__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new Map<String, String>{
                    'label' => entry.getLabel(),
                    'value' => entry.getValue()
                });
            }
        }
        return options;
    }

    // =========================================================
    // EXPORT CSV
    // =========================================================
    @AuraEnabled
    public static String exportCSV(String stageFilter, String searchKey) {
        List<Lead> leads;

        if (String.isNotBlank(searchKey) && stageFilter != null && stageFilter != 'All') {
            String likeKey = '%' + searchKey + '%';
            leads = [
                SELECT Name, Company, Phone, Status, CreatedDate
                FROM Lead
                WHERE IsConverted = false AND Status = :stageFilter
                AND (Name LIKE :likeKey OR Company LIKE :likeKey OR Phone LIKE :likeKey)
                ORDER BY CreatedDate DESC LIMIT 1000
            ];
        } else if (String.isNotBlank(searchKey)) {
            String likeKey = '%' + searchKey + '%';
            leads = [
                SELECT Name, Company, Phone, Status, CreatedDate
                FROM Lead
                WHERE IsConverted = false
                AND (Name LIKE :likeKey OR Company LIKE :likeKey OR Phone LIKE :likeKey)
                ORDER BY CreatedDate DESC LIMIT 1000
            ];
        } else if (String.isNotBlank(stageFilter) && stageFilter != 'All') {
            leads = [
                SELECT Name, Company, Phone, Status, CreatedDate
                FROM Lead WHERE IsConverted = false AND Status = :stageFilter
                ORDER BY CreatedDate DESC LIMIT 1000
            ];
        } else {
            leads = [
                SELECT Name, Company, Phone, Status, CreatedDate
                FROM Lead WHERE IsConverted = false
                ORDER BY CreatedDate DESC LIMIT 1000
            ];
        }

        String csv = 'Lead Name,Company,Phone,Stage,Created Date\n';
        for (Lead l : leads) {
            csv += '"' + l.Name + '",'
                + '"' + (String.isNotBlank(l.Company) ? l.Company : '') + '",'
                + '"' + (String.isNotBlank(l.Phone) ? l.Phone : '') + '",'
                + '"' + (String.isNotBlank(l.Status) ? l.Status : '') + '",'
                + '"' + (l.CreatedDate != null ? l.CreatedDate.format('dd MMM yyyy') : '') + '"\n';
        }
        return EncodingUtil.base64Encode(Blob.valueOf(csv));
    }

    // =========================================================
    // CREATE LEAD
    // =========================================================
    @AuraEnabled
    public static Id createLead(
        String fullName,
        String company,
        String leadSource,
        String email,
        String phone,
        String address,
        String project,
        String budget,
        String description
    ) {
        if (String.isBlank(fullName)) {
            throw createHandledException('Full Name is required');
        }
        if (String.isBlank(phone)) {
            throw createHandledException('Mobile Number is required');
        }
        if (String.isBlank(project)) {
            throw createHandledException('Please select an Interested Project');
        }
        if (String.isBlank(budget)) {
            throw createHandledException('Please select a valid Budget Aligned');
        }

        Lead newLead = new Lead();
        newLead.LastName    = fullName.trim();
        newLead.Company     = String.isNotBlank(company) ? company.trim() : 'Individual';
        newLead.LeadSource  = String.isNotBlank(leadSource) ? leadSource.trim() : 'Partner Portal';
        newLead.Email       = String.isNotBlank(email) ? email.trim() : null;
        newLead.Phone       = phone.trim();
        newLead.Street      = String.isNotBlank(address) ? address.trim() : null;

        // Project__c is a LOOKUP (assign Id)
        if (String.isNotBlank(project)) {
            try {
                newLead.Project__c = (Id) project.trim();
            } catch (Exception e) {
                System.debug('>>> Invalid Project Id: ' + project);
            }
        }

        // Budget_Aligned__c is a PICKLIST (assign String value)
        if (String.isNotBlank(budget)) {
            newLead.Budget_Aligned__c = budget.trim();
        }

        newLead.Description = String.isNotBlank(description) ? description.trim() : null;

        System.debug('>>> [LeadPortal] Inserting Lead: ' + JSON.serialize(newLead));

        try {
            insert newLead;
            System.debug('>>> [LeadPortal] Lead created successfully: ' + newLead.Id);
        } catch (DmlException e) {
            System.debug('>>> [LeadPortal] DML Error: ' + e.getDmlMessage(0));
            throw createHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            System.debug('>>> [LeadPortal] Exception: ' + e.getMessage());
            throw createHandledException(e.getMessage());
        }

        return newLead.Id;
    }

    private static AuraHandledException createHandledException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}