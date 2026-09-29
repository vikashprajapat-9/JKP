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
    // GET LEADS (Filtered to Logged-in Partner Only)
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

        // Filter to logged-in partner user only
        Id currentUserId = UserInfo.getUserId();

        String baseQuery = ' FROM Lead WHERE IsConverted = false AND OwnerId = :currentUserId ';
        List<String> conditions = new List<String>();

        if (String.isNotBlank(stageFilter) && stageFilter != 'All') {
            conditions.add('Status = :stageFilter');
        }

        String likeKey;
        if (String.isNotBlank(searchKey)) {
            likeKey = '%' + searchKey.trim() + '%';
            conditions.add('(Name LIKE :likeKey OR Company LIKE :likeKey OR Phone LIKE :likeKey)');
        }

        String whereClause = conditions.isEmpty() ? '' : ' AND ' + String.join(conditions, ' AND ');

        // Total Count Query
        String countQuery = 'SELECT COUNT()' + baseQuery + whereClause;
        Integer totalRecords = Database.countQuery(countQuery);

        response.totalRecords = totalRecords;
        response.totalPages   = (Integer) Math.ceil((Decimal) totalRecords / response.pageSize);

        // Data Query with Pagination
        Integer offset = (response.pageNumber - 1) * response.pageSize;
        String dataQuery = 'SELECT Id, Name, Company, Phone, Status, CreatedDate ' +
                           baseQuery + whereClause +
                           ' ORDER BY CreatedDate DESC LIMIT :pageSize OFFSET :offset';

        List<Lead> leads = Database.query(dataQuery);

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
    // STAGE OPTIONS
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<String> getStageOptions() {
        List<String> options = new List<String>{ 'All' };
        for (Schema.PicklistEntry entry : Lead.Status.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(entry.getLabel());
            }
        }
        return options;
    }

    // =========================================================
    // PROJECT OPTIONS
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
    // BUDGET OPTIONS
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
    // EXPORT CSV (Logged-in Partner's Leads Only)
    // =========================================================
    @AuraEnabled
    public static String exportCSV(String stageFilter, String searchKey) {
        Id currentUserId = UserInfo.getUserId();
        String baseQuery = 'SELECT Name, Company, Phone, Status, CreatedDate FROM Lead WHERE IsConverted = false AND OwnerId = :currentUserId ';
        List<String> conditions = new List<String>();

        if (String.isNotBlank(stageFilter) && stageFilter != 'All') {
            conditions.add('Status = :stageFilter');
        }

        String likeKey;
        if (String.isNotBlank(searchKey)) {
            likeKey = '%' + searchKey.trim() + '%';
            conditions.add('(Name LIKE :likeKey OR Company LIKE :likeKey OR Phone LIKE :likeKey)');
        }

        String whereClause = conditions.isEmpty() ? '' : ' AND ' + String.join(conditions, ' AND ');
        List<Lead> leads = Database.query(baseQuery + whereClause + ' ORDER BY CreatedDate DESC LIMIT 1000');

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
    // CREATE LEAD (With Strict Mobile Duplicate Check)
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
        if (String.isBlank(fullName)) throw createHandledException('Full Name is required');
        if (String.isBlank(phone))    throw createHandledException('Mobile Number is required');
        if (String.isBlank(project))  throw createHandledException('Please select an Interested Project');
        if (String.isBlank(budget))   throw createHandledException('Please select a valid Budget Aligned');

        String cleanPhone = phone.trim();

        // =====================================================
        // 1. DUPLICATE MOBILE NUMBER CHECK (Across entire org)
        // =====================================================
        List<Lead> existingLeads = [
            SELECT Id, Name 
            FROM Lead 
            WHERE Phone = :cleanPhone 
            AND IsConverted = false 
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (!existingLeads.isEmpty()) {
            throw createHandledException('A lead with this mobile number (' + cleanPhone + ') already exists (' + existingLeads[0].Name + '). Duplicate mobile numbers are not allowed.');
        }

        // =====================================================
        // 2. PREPARE NEW LEAD
        // =====================================================
        Lead newLead = new Lead();
        newLead.LastName    = fullName.trim();
        newLead.Company     = String.isNotBlank(company) ? company.trim() : 'Individual';
        newLead.LeadSource  = String.isNotBlank(leadSource) ? leadSource.trim() : 'Partner Portal';
        newLead.Email       = String.isNotBlank(email) ? email.trim() : null;
        newLead.Phone       = cleanPhone;
        newLead.Street      = String.isNotBlank(address) ? address.trim() : null;

        // Set OwnerId to the logged-in Partner User
        newLead.OwnerId = UserInfo.getUserId();

        if (String.isNotBlank(project)) {
            try { newLead.Project__c = (Id) project.trim(); }
            catch (Exception e) { System.debug('>>> Invalid Project Id: ' + project); }
        }

        if (String.isNotBlank(budget)) {
            newLead.Budget_Aligned__c = budget.trim();
        }

        newLead.Description = String.isNotBlank(description) ? description.trim() : null;

        // =====================================================
        // 3. INSERT LEAD IN SYSTEM MODE
        // =====================================================
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = true;
        dml.optAllOrNone = true;

        try {
            Database.SaveResult sr = Database.insert(newLead, dml, AccessLevel.SYSTEM_MODE);
            if (sr.isSuccess()) {
                System.debug('>>> [LeadPortal] Lead created successfully with Owner: ' + newLead.OwnerId);
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