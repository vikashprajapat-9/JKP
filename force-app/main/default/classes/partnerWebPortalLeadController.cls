// The Leads page of the partner portal. A channel head sees the leads of their team: those whose Channel Partner is
// their account or the account of one of their executives (a channel partner account whose Channel Head is theirs). An
// executive sees only their own leads, in the projects their channel head gave them (see PartnerPortalAccess). The
// page's filter chips are the Partner Portal Lead Filter records. Partners cannot see their executives' leads, so this
// runs without sharing and in system mode, and every lead query is limited by PartnerPortalAccess.
public without sharing class partnerWebPortalLeadController {

    private static final String SETTINGS_RECORD = 'Default';
    private static final Integer DEFAULT_PAGE_SIZE = 10;
    private static final Integer MAX_PAGE_SIZE = 200;
    private static final Integer MAX_OFFSET = 2000;
    private static final Integer EXPORT_LIMIT = 10000;
    private static final String LEAD_FIELDS = 'SELECT Id, Name, Phone, MobilePhone, Status, CP_Approval_Status__c, CreatedDate, Channel_Partner__c, '
        + 'Channel_Partner__r.Name, Project__c, Project__r.Name, OwnerId, IsConverted';
    private static final List<String> EXPORT_COLUMNS = new List<String>{
        'Sr.', 'Lead Created Date', 'Lead No.', 'Lead Name', 'Channel Partner/Company Name', 'Project Name', 'Lead Mobile No.', 'Lead Stage'
    };
    // A cell Excel would run as a formula: = @ tab or return first, or + - followed by more than a number
    private static final Pattern FORMULA_START = Pattern.compile('^([=@\\t\\r]|[+-](?![0-9 ()]*$))');

    // The Leads page's filters and the portal settings; tests set their own
    @TestVisible
    private static List<Partner_Portal_Lead_Filter__mdt> filterOverride;
    @TestVisible
    private static Partner_Portal_Setting__mdt setting = Partner_Portal_Setting__mdt.getInstance(SETTINGS_RECORD);

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
        // The project the lead is for: the same customer (and mobile number) can be a lead in more than one project
        @AuraEnabled public String project      { get; set; }
        @AuraEnabled public String mobile       { get; set; }
        @AuraEnabled public String stage        { get; set; }
        // Whether the partner may update the lead from the Edit popup (their own open lead), and why not
        @AuraEnabled public Id leadId           { get; set; }
        @AuraEnabled public Boolean canEdit     { get; set; }
        @AuraEnabled public String readOnlyReason { get; set; }
        // Whether the partner may upload the customer's documents (their own lead, also after JKP took it over)
        @AuraEnabled public Boolean canUploadDocuments { get; set; }
    }

    public class LeadFilter {
        @AuraEnabled public String key          { get; set; }
        @AuraEnabled public String label        { get; set; }
    }

    // What createLead did, from the channel partner lead rules (LeadLogicController, run by LeadTrigger):
    // CREATED, CREATED_WITH_NOTICE (another CP has the customer; message = the notice) or APPROVAL_REQUESTED (Direct
    // Sales has the customer: the lead is saved as Pending approval and sent to the managers; message = the notice). A
    // refused lead is an error instead.
    public class CreateLeadResult {
        @AuraEnabled public String outcome      { get; set; }
        @AuraEnabled public Id leadId           { get; set; }
        @AuraEnabled public String message      { get; set; }
    }

    // The conditions of a lead query with their bind values. It always starts with the leads the partner may see.
    private class LeadQuery {
        private final Map<String, Object> binds = new Map<String, Object>();
        private final List<String> conditions = new List<String>();

        private LeadQuery(PartnerPortalAccess access) {
            conditions.add(access.leads(binds));
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
    // FILTER CHIPS (Partner Portal Lead Filter records, in Order)
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static List<LeadFilter> getLeadFilters() {
        List<LeadFilter> chips = new List<LeadFilter>();
        for (Partner_Portal_Lead_Filter__mdt filter : filters()) {
            LeadFilter chip = new LeadFilter();
            chip.key = filter.DeveloperName;
            chip.label = filter.MasterLabel;
            chips.add(chip);
        }
        return chips;
    }

    // =========================================================
    // GET LEADS (the logged-in partner's team only)
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static LeadsResponse getLeads(String filterKey, String searchKey, Integer pageNumber, Integer pageSize) {
        LeadsResponse response = new LeadsResponse();
        response.pageNumber = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
        response.pageSize = (pageSize == null || pageSize < 1) ? DEFAULT_PAGE_SIZE : Math.min(pageSize, MAX_PAGE_SIZE);
        response.leads = new List<LeadRow>();
        response.totalRecords = 0;
        response.totalPages = 0;
        PartnerPortalAccess access = PartnerPortalAccess.current();
        if (access.accountId == null) {
            return response;
        }

        LeadQuery query = queryFor(access, filterKey, searchKey);
        response.totalRecords = Database.countQueryWithBinds('SELECT COUNT() FROM Lead' + query.whereClause(), query.binds, AccessLevel.SYSTEM_MODE);
        response.totalPages = (Integer) Math.ceil((Decimal) response.totalRecords / response.pageSize);

        Integer offset = Math.min((response.pageNumber - 1) * response.pageSize, MAX_OFFSET);
        query.binds.put('pageSize', response.pageSize);
        query.binds.put('offsetRows', offset);
        Integer rowNo = offset;
        List<Lead> page = (List<Lead>) Database.queryWithBinds(LEAD_FIELDS + ' FROM Lead' + query.whereClause()
            + ' ORDER BY CreatedDate DESC, Id DESC LIMIT :pageSize OFFSET :offsetRows', query.binds, AccessLevel.SYSTEM_MODE);
        loadOwners(page);
        for (Lead record : page) {
            response.leads.add(rowOf(record, ++rowNo, access));
        }
        return response;
    }

    // =========================================================
    // PROJECT OPTIONS (active projects; an executive's own projects only)
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
    // EXPORT CSV (the chosen filter and search; the page adds the byte-order mark Excel needs)
    // =========================================================
    @AuraEnabled
    public static String exportCSV(String filterKey, String searchKey) {
        List<String> lines = new List<String>{ csvLine(EXPORT_COLUMNS) };
        PartnerPortalAccess access = PartnerPortalAccess.current();
        if (access.accountId != null) {
            LeadQuery query = queryFor(access, filterKey, searchKey);
            query.binds.put('exportLimit', EXPORT_LIMIT);
            Integer rowNo = 0;
            List<Lead> leads = (List<Lead>) Database.queryWithBinds(LEAD_FIELDS + ' FROM Lead' + query.whereClause()
                + ' ORDER BY CreatedDate DESC, Id DESC LIMIT :exportLimit', query.binds, AccessLevel.SYSTEM_MODE);
            loadOwners(leads);
            for (Lead record : leads) {
                LeadRow row = rowOf(record, ++rowNo, access);
                lines.add(csvLine(new List<String>{ String.valueOf(row.rowNo), row.createdDate, row.leadNo, row.leadName, row.partner, row.project, row.mobile,
                    row.stage }));
            }
        }
        return String.join(lines, '\r\n') + '\r\n';
    }

    // =========================================================
    // CREATE LEAD
    // =========================================================
    // The lead belongs to the logged-in partner's channel partner account and gets the Lead Source of the Partner
    // Portal Setting, which makes it a channel partner lead: LeadTrigger then applies the CP lead rules (mandatory
    // fields, the duplicate check on Phone + Project and its outcomes; see LeadLogicController).
    @AuraEnabled
    public static CreateLeadResult createLead(
        String fullName,
        String company,
        String email,
        String phone,
        String address,
        String project,
        String budget,
        String description
    ) {
        if (String.isBlank(fullName)) throw createHandledException('Full Name is required');
        if (String.isBlank(phone))    throw createHandledException('Mobile Number is required');
        if (String.isBlank(email))    throw createHandledException('Email ID is required');
        if (String.isBlank(project))  throw createHandledException('Please select an Interested Project');
        if (String.isBlank(budget))   throw createHandledException('Please select a valid Budget Aligned');
        if (!LeadLogicController.isPhoneNumber(phone)) throw createHandledException(Label.CP_Lead_Phone_Invalid);
        // Only a partner whose portal access is active adds leads (not after Access Denied or Terminated, nor an
        // internal user previewing the site)
        PartnerPortalAccess access = PartnerPortalAccess.current();
        if (access.accountId == null) {
            throw createHandledException(Label.Partner_Portal_No_Access);
        }
        // An executive works only in the projects their channel head gave them
        if (!access.canSeeProject(projectIdOf(project))) {
            throw createHandledException('Please select one of your projects');
        }

        String cleanPhone = phone.trim();

        // =====================================================
        // 1. PREPARE NEW LEAD
        // =====================================================
        Lead newLead = new Lead();
        newLead.LastName    = fullName.trim();
        newLead.Company     = String.isNotBlank(company) ? company.trim() : 'Individual';
        newLead.LeadSource  = setting == null || String.isBlank(setting.Lead_Source__c) ? null : setting.Lead_Source__c.trim();
        newLead.Email       = String.isNotBlank(email) ? email.trim() : null;
        newLead.Phone       = cleanPhone;
        newLead.Street      = String.isNotBlank(address) ? address.trim() : null;

        // Set OwnerId to the logged-in Partner User, and the Channel Partner to their channel partner account
        newLead.OwnerId = UserInfo.getUserId();
        Account partner = partnerAccount();
        if (partner != null && partner.RecordTypeId == partnerPortalRegistrationController.partnerRecordTypeId()) {
            newLead.Channel_Partner__c = partner.Id;
        }

        if (String.isNotBlank(project)) {
            try { newLead.Project__c = (Id) project.trim(); }
            catch (Exception e) { System.debug('>>> Invalid Project Id: ' + project); }
        }

        if (String.isNotBlank(budget)) {
            newLead.Budget_Aligned__c = budget.trim();
        }

        newLead.Description = String.isNotBlank(description) ? description.trim() : null;

        // =====================================================
        // 2. INSERT LEAD IN SYSTEM MODE (LeadTrigger applies the CP lead rules)
        // =====================================================
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = true;
        dml.optAllOrNone = true;

        try {
            Database.SaveResult sr = Database.insert(newLead, dml, AccessLevel.SYSTEM_MODE);
            LeadLogicController.ChannelPartnerOutcome outcome = channelPartnerOutcome();
            CreateLeadResult result = new CreateLeadResult();
            result.outcome = outcome == null ? LeadLogicController.CP_CREATED : outcome.status;
            result.leadId = sr.getId();
            result.message = outcome == null ? null : outcome.message;
            return result;
        } catch (DmlException e) {
            throw createHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw createHandledException(e.getMessage());
        }
    }

    // The CP lead rules' outcome for the lead just inserted, the only one of its insert (null when they did not run)
    private static LeadLogicController.ChannelPartnerOutcome channelPartnerOutcome() {
        List<LeadLogicController.ChannelPartnerOutcome> outcomes = LeadLogicController.channelPartnerOutcomes;
        return outcomes == null || outcomes.isEmpty() ? null : outcomes[0];
    }

    // =========================================================
    // HELPERS
    // =========================================================

    // The logged-in partner's account; null for anyone else (such as an internal user previewing the site), who has
    // no leads here
    private static Account partnerAccount() {
        User me = [SELECT ContactId, Contact.AccountId, Contact.Account.RecordTypeId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE];
        return me.ContactId == null || me.Contact.AccountId == null ? null : me.Contact.Account;
    }

    // The leads the partner may see that match the filter and contain the search text in any column of the table
    private static LeadQuery queryFor(PartnerPortalAccess access, String filterKey, String searchKey) {
        LeadQuery query = new LeadQuery(access);
        Partner_Portal_Lead_Filter__mdt filter = filterNamed(filterKey);
        if (filter != null) {
            // A chip shows the open leads at its Lead statuses and the booked leads whose opportunity is at its stages
            List<String> statuses = listOf(filter.Lead_Statuses__c);
            List<String> stages = listOf(filter.Opportunity_Stages__c);
            List<String> either = new List<String>();
            if (!statuses.isEmpty()) {
                query.binds.put('statuses', statuses);
                either.add('Status IN :statuses');
            }
            if (!stages.isEmpty()) {
                query.binds.put('opportunityStages', stages);
                either.add('(IsConverted = true AND ConvertedOpportunity.StageName IN :opportunityStages)');
            }
            if (!either.isEmpty()) {
                query.conditions.add('(' + String.join(either, ' OR ') + ')');
            }
            if (filter.Booked__c) {
                query.add('IsConverted = true AND ConvertedOpportunity.StageName IN :bookingStages', 'bookingStages',
                    partnerWebPortalMyTeamController.bookingStages());
            }
        }

        String term = searchKey == null ? '' : searchKey.trim();
        if (term.length() > 0) {
            List<String> matches = new List<String>{
                'Name LIKE :term', 'Company LIKE :term', 'Email LIKE :term', 'Phone LIKE :term', 'MobilePhone LIKE :term',
                'Status LIKE :term', 'Channel_Partner__r.Name LIKE :term', 'Project__r.Name LIKE :term'
            };
            query.binds.put('term', '%' + escapeLike(term) + '%');
            // A phone number typed with spaces or dashes still finds the digits stored on the lead
            String digits = term.replaceAll('[^0-9]', '');
            if (digits.length() >= 4 && digits != term) {
                query.binds.put('digits', '%' + digits + '%');
                matches.add('Phone LIKE :digits');
                matches.add('MobilePhone LIKE :digits');
            }
            // The Lead No. column is the lead's Id
            Id leadId = leadIdOf(term);
            if (leadId != null) {
                query.binds.put('leadId', leadId);
                matches.add('Id = :leadId');
            }
            query.conditions.add('(' + String.join(matches, ' OR ') + ')');
        }
        return query;
    }

    private static List<Partner_Portal_Lead_Filter__mdt> filters() {
        if (filterOverride != null) {
            return filterOverride;
        }
        return [
            SELECT DeveloperName, MasterLabel, Order__c, Lead_Statuses__c, Booked__c, Opportunity_Stages__c
            FROM Partner_Portal_Lead_Filter__mdt
            WITH SYSTEM_MODE
            ORDER BY Order__c ASC NULLS LAST, MasterLabel
        ];
    }

    // The filter with this key; none (so all the team's leads) for a blank or unknown key
    private static Partner_Portal_Lead_Filter__mdt filterNamed(String filterKey) {
        if (String.isBlank(filterKey)) {
            return null;
        }
        for (Partner_Portal_Lead_Filter__mdt filter : filters()) {
            if (filter.DeveloperName == filterKey) {
                return filter;
            }
        }
        return null;
    }

    // The values of a comma-separated setting
    private static List<String> listOf(String text) {
        List<String> values = new List<String>();
        if (String.isNotBlank(text)) {
            for (String value : text.split(',')) {
                if (String.isNotBlank(value)) {
                    values.add(value.trim());
                }
            }
        }
        return values;
    }

    private static Id projectIdOf(String projectId) {
        try {
            Id candidate = Id.valueOf(projectId.trim());
            return candidate.getSObjectType() == Project__c.SObjectType ? candidate : null;
        } catch (Exception e) {
            return null;
        }
    }

    // The search text taken literally: % and _ are not wildcards
    private static String escapeLike(String value) {
        return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    private static Id leadIdOf(String value) {
        if (value.length() != 15 && value.length() != 18) {
            return null;
        }
        try {
            Id candidate = Id.valueOf(value);
            return candidate.getSObjectType() == Lead.SObjectType ? candidate : null;
        } catch (Exception e) {
            return null;
        }
    }

    // Whether the owners of these leads are partner users, in one query (see partnerWebPortalLeadEditController)
    private static void loadOwners(List<Lead> leads) {
        Set<Id> ownerIds = new Set<Id>();
        for (Lead record : leads) {
            ownerIds.add(record.OwnerId);
        }
        partnerWebPortalLeadEditController.loadOwners(ownerIds);
    }

    private static LeadRow rowOf(Lead record, Integer rowNo, PartnerPortalAccess access) {
        LeadRow row = new LeadRow();
        row.leadId      = record.Id;
        row.readOnlyReason = partnerWebPortalLeadEditController.readOnlyReasonOf(record, access);
        row.canEdit     = row.readOnlyReason == null;
        row.canUploadDocuments = partnerWebPortalLeadDocuments.uploadReason(record, access) == null;
        row.rowNo       = rowNo;
        row.createdDate = record.CreatedDate != null ? record.CreatedDate.format('dd MMM yyyy') : '';
        row.leadNo      = record.Id;
        row.leadName    = record.Name;
        row.partner     = record.Channel_Partner__r != null ? record.Channel_Partner__r.Name : '-';
        row.project     = record.Project__r != null ? record.Project__r.Name : '-';
        row.mobile      = String.isNotBlank(record.Phone) ? record.Phone : (String.isNotBlank(record.MobilePhone) ? record.MobilePhone : '-');
        // A CP lead waiting for the managers' approval shows that instead of its stage
        row.stage       = record.CP_Approval_Status__c == LeadLogicController.CP_APPROVAL_PENDING ? Label.CP_Lead_Pending_Stage
            : (String.isNotBlank(record.Status) ? record.Status : '-');
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